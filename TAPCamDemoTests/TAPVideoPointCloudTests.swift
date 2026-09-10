import AVFoundation
import CoreGraphics
import CoreImage
import CoreVideo
import Testing
import UIKit
import simd
@testable import TAPCamDemo

struct TAPVideoPointCloudTests {
    @Test @MainActor func pauseFreezesDisplayedSceneAndDefersTheCompletedProjectionUntilResume() {
        let playback = TAPVideoPointCloudPlayback()
        defer { playback.cancel() }
        var published = 0
        playback.onStateChange = { if $0 { published += 1 } }
        playback.receiveProjection(pausePayload(at: 0))
        playback.setPlaybackPaused(true)
        playback.receiveProjection(pausePayload(at: 1))
        #expect(playback.store.presentationTimeSeconds == 0 && published == 1)
        playback.setPlaybackPaused(false)
        #expect(playback.store.presentationTimeSeconds == 1 && published == 2)
        playback.setPlaybackPaused(false)
        #expect(published == 2)
    }

    @Test @MainActor func pausedFirstFrameAndSeekCanPublishButDiscardAnEarlierPendingProjection() {
        let playback = TAPVideoPointCloudPlayback()
        defer { playback.cancel() }
        playback.setPlaybackPaused(true)
        playback.receiveProjection(pausePayload(at: 0))
        #expect(playback.store.presentationTimeSeconds == 0)
        playback.receiveProjection(pausePayload(at: 1))
        playback.reset(at: 2)
        playback.setPlaybackPaused(false)
        #expect(playback.store.presentationTimeSeconds == 0, "Seek must discard the old pending result")
        playback.setPlaybackPaused(true)
        playback.receiveProjection(pausePayload(at: 2))
        #expect(playback.store.presentationTimeSeconds == 2, "A paused seek may replace the previous generation's scene once")
        playback.receiveProjection(pausePayload(at: 3))
        playback.cancel()
        playback.setPlaybackPaused(false)
        #expect(playback.store.presentationTimeSeconds == nil, "Leaving this video must discard its pending scene")
    }

    @Test @MainActor func currentGeometryAdvancesBeforeRegistrationAndLateAlignmentCannotRewindIt() {
        let playback = TAPVideoPointCloudPlayback()
        defer { playback.cancel() }
        var map = TAPVideoPointCloudHistory()
        let initial = map.accept(pausePayload(at: 0))
        playback.acceptProjection(initial, spatialHistory: map)
        playback.receiveProjection(pausePayload(at: 2))
        #expect(playback.store.presentationTimeSeconds == 2)
        playback.receiveProjection(pausePayload(at: 3))
        #expect(playback.store.presentationTimeSeconds == 3)
        #expect(playback.spatialHistory.latestTime == 0, "Current geometry must not wait for or overwrite the accepted map")

        let late = map.accept(pausePayload(at: 1))
        playback.acceptProjection(late, spatialHistory: map)
        #expect(playback.spatialHistory.latestTime == 1)
        #expect(playback.store.presentationTimeSeconds == 3, "A late registration can advance the map without rewinding current geometry")

        playback.setPlaybackPaused(true)
        playback.receiveProjection(pausePayload(at: 4))
        let olderThanPending = map.accept(pausePayload(at: 3))
        playback.acceptProjection(olderThanPending, spatialHistory: map)
        #expect(playback.store.presentationTimeSeconds == 3)
        playback.setPlaybackPaused(false)
        #expect(playback.store.presentationTimeSeconds == 4, "Late alignment must not replace the newer paused pending frame")

        playback.setPlaybackPaused(true)
        playback.receiveProjection(pausePayload(at: 5))
        let matchingPending = map.accept(pausePayload(at: 5))
        playback.acceptProjection(matchingPending, spatialHistory: map)
        #expect(playback.store.presentationTimeSeconds == 4)
        playback.setPlaybackPaused(false)
        #expect(playback.store.presentationTimeSeconds == 5)
        playback.reset(at: 0)
        #expect(playback.spatialHistory.frames.isEmpty, "An explicit seek starts a new spatial map")
    }

    @Test func metricDecodePreservesCALIAndUsesReciprocalDisparity() throws {
        let packed = floatBytes([0.5, 0, .nan, 2])
        let klv = TAPDepthKLVFrame(frameIndex: 7, timestampValue: 600, timestampTimescale: 600,
            compressionCodec: .raw, uncompressedByteCount: packed.count, calibrationIndex: 3, payload: packed)
        let format = TAPVideoManifest.DepthFormat(kind: "disparity", pixelFormat: "fdis", width: 2, height: 2,
            packedRowStride: 8, bytesPerSample: 4, uncompressedFrameByteCount: packed.count)
        let frame = try TAPDepthFrameDecoder.decode(klv.encodedData(), presentationTimeSeconds: 1,
            depthFormat: format, displayOrientation: .up, rendersHeatmap: false)
        #expect(frame.calibrationIndex == 3)
        #expect(frame.retainedByteCount == packed.count)
        #expect(TAPVideoPointCloudProjection.metricSample(frame, index: 0) == 2)
        #expect(TAPVideoPointCloudProjection.metricSample(frame, index: 1).isNaN)
        #expect(TAPVideoPointCloudProjection.metricSample(frame, index: 2).isNaN)
        #expect(TAPVideoPointCloudProjection.metricSample(frame, index: 3) == 0.5)
        #expect(TAPVideoPointCloudProjection.metricSample(frame, index: Int.max).isNaN)
        #expect(TAPVideoPointCloudProjection.metricSample(frame, index: Int.min).isNaN)
    }

    @Test func inlineCalibrationKeepsProjectingAfterTheSixteenEntryTableFills() throws {
        let projection = TAPVideoRegistrationProjection(depthWidth: 2, depthHeight: 2,
            alignedRGBWidth: 2, alignedRGBHeight: 2, encodedRGBWidth: 2, encodedRGBHeight: 2,
            depthToAlignedRGBPixelCenterAffine: [1, 0, 0, 0, 1, 0], connectionRotationDegrees: 0,
            isEncodedHorizontallyMirrored: false, rgbCleanAperture: .init(x: 0, y: 0, width: 2, height: 2))
        let descriptor = TAPVideoDepthRegistrationDescriptor(schemaID: "test", rgbPresentationWidth: 2,
            rgbPresentationHeight: 2, mapping: .avDepthDataWarpedToSynchronizedRGB, projection: projection)
        let format = TAPVideoManifest.DepthFormat(kind: "depth", pixelFormat: "fdep", width: 2, height: 2,
            packedRowStride: 8, bytesPerSample: 4, uncompressedFrameByteCount: 16)
        let calibrations = (0..<40).map { calibration(inverse: [0, 0], focalLength: 1 + Float($0) / 100) }
        let configuration = TAPVideoPointCloudConfiguration(fileURL: URL(fileURLWithPath: "/unused"),
            descriptor: descriptor, format: format, trackID: 2, calibrations: Array(calibrations.prefix(16)))
        let colorData = Data(repeating: 255, count: 16)
        let provider = try #require(CGDataProvider(data: colorData as CFData))
        let image = try #require(CGImage(width: 2, height: 2, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: 8, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
        let packed = floatBytes([1, 1, 1, 1])
        for index in calibrations.indices {
            let usesInline = index >= 16
            let klv = TAPDepthKLVFrame(frameIndex: UInt32(index), timestampValue: Int64(index * 20), timestampTimescale: 600,
                compressionCodec: .raw, uncompressedByteCount: packed.count,
                calibrationIndex: usesInline ? nil : UInt32(index), payload: packed,
                inlineCalibration: usesInline ? calibrations[index] : nil)
            let frame = try TAPDepthFrameDecoder.decode(klv.encodedData(), presentationTimeSeconds: Double(index) / 30,
                depthFormat: format, displayOrientation: .up, rendersHeatmap: false)
            #expect(configuration.calibration(for: frame) == calibrations[index])
            #expect(frame.inlineCalibration == (usesInline ? calibrations[index] : nil))
            #expect(frame.retainedByteCount >= packed.count + (usesInline ? 16 : 0))
            let savedCalibration = try #require(configuration.calibration(for: frame))
            let usableCalibration = try #require(TAPVideoPointCloudCalibration(savedCalibration))
            let payload = try #require(try TAPVideoPointCloudProjection.make(frame: frame,
                calibration: usableCalibration, descriptor: descriptor, image: image))
            #expect(payload.vertices.count == 4 && payload.colors.count == 4)
            #expect(abs(payload.vertices[0].x + 0.5 / calibrations[index].intrinsicMatrix[0]) < 0.000_001)
        }
        #expect(configuration.calibration(for: historyFrame(index: 40, calibration: nil)) == nil,
                "A legacy frame without CALI must not inherit the last saved calibration")
    }

    @Test func depthSelectionCannotCrossAShortDeclaredGap() {
        let gap = 0.045...0.055
        #expect(TAPVideoDepthGapPolicy.crossesGap(from: 0.03, to: 0.06, gaps: [gap]))
        #expect(TAPVideoDepthGapPolicy.crossesGap(from: 0.06, to: 0.03, gaps: [gap]))
        #expect(!TAPVideoDepthGapPolicy.crossesGap(from: 0.06, to: 0.07, gaps: [gap]))
    }

    @Test func distortionUsesInverseTableAndMissingCalibrationFailsClosed() throws {
        let corrected = try #require(TAPVideoPointCloudCalibration(calibration(inverse: [0.1, 0.1])))
        let point = corrected.rectifiedPoint(x: 0, y: 0, width: 2, height: 2)
        #expect(abs(point.x + 0.05) < 0.000_001)
        #expect(abs(point.y + 0.05) < 0.000_001)
        #expect(TAPVideoPointCloudCalibration(calibration(inverse: nil)) == nil)
        #expect(TAPVideoPointCloudCalibration(calibration(inverse: [.nan, 0])) == nil)
    }

    @Test func recordedTripleCameraLUTFoldUsesPinholeForTheWholeFrame() throws {
        // Exact inverse LUT and intrinsics from the recorded 24 mm triple-camera sample.
        let inverse = try #require(Data(base64Encoded: "AAAAAPemqriyrLK5N6FXukUU0booxzO7NcGOuzKK1bttFBi8lqVPvKB/iLyZXq289U3VvMTd/ryjSxS9HrwovW/bPL1g9lG9iGdrvUPkh72iMaW9tDDWvdQUE77wY1C+TSyTvksjyb64hQK/fuIfvzyZOb+yI06/E3hdv75kaL8h9W+/Jxx1v6GXeL/G8Hq/pYZ8v6CZfb/VVH6/AdV+v0wtf7+Can+/"))
        let saved = TAPVideoManifest.CameraCalibration(
            intrinsicMatrix: [5916.6953, 0, 0, 0, 5916.6953, 0, 4224.5303, 3027.435, 1],
            intrinsicMatrixReferenceDimensions: .init(width: 8448, height: 6034),
            extrinsicMatrix: [1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0], pixelSizeMillimeters: 0.001,
            lensDistortionCenter: .init(x: 4224.02294921875, y: 3021.939453125),
            lensDistortionLookupTable: nil, inverseLensDistortionLookupTable: inverse)
        let projector = try #require(TAPVideoPointCloudCalibration(saved))
        #expect(projector.inverseDistortion.isEmpty)
        for x in [160, 240, 280, 319] {
            let point = projector.rectifiedPoint(x: Double(x), y: 120, width: 320, height: 240)
            #expect(abs(point.x - ((Double(x) + 0.5) * 8448 / 320 - 0.5)) < 0.000_001)
        }
        let edge = projector.vertex(x: 0, y: 120, width: 320, height: 240, depth: 2.0345, rotation: 0, mirrored: false)
        #expect(abs(edge.x + 1.4483) < 0.000_1, "The old fold incorrectly collapsed this ray to X = -0.0569 m")
        let corner = projector.vertex(x: 0, y: 0, width: 320, height: 240, depth: 0.3554, rotation: 0, mirrored: false)
        #expect(abs(corner.x + 0.2530) < 0.000_1 && abs(corner.y - 0.1811) < 0.000_1)
    }

    @Test func distortionMonotonicityChecksInsideSegmentsAndKeepsTheRecordedLiDARTable() throws {
        // The mapped knot radii increase, but the last segment's derivative becomes negative.
        let folded = try #require(TAPVideoPointCloudCalibration(calibration(inverse: [0, -0.1, -0.45])))
        #expect(folded.inverseDistortion.isEmpty)
        let inverse = try #require(Data(base64Encoded: "AAAAABSB7zhU2+05skGEOidS5zpo7zA7VzR4O0azozs2F847Pv75O6cGEzwJcCg8G4o8PN+qTjzrNV482aJqPFyDczyViHg8RYd5PG16djwIhG88pOtkPKQaVzxMlkY8q/czPNfhHzz19go8lZnrO1rDwTujJZk7HVRkOz/EGTvXJKQ66DhCOf4IZrqzbAC7H99Jux82i7vCzbK7Rtzau0X+ALzxTRO8"))
        let values = inverse.withUnsafeBytes { bytes in
            stride(from: 0, to: inverse.count, by: 4).map {
                Float(bitPattern: UInt32(littleEndian: bytes.loadUnaligned(fromByteOffset: $0, as: UInt32.self)))
            }
        }
        let corrected = try #require(TAPVideoPointCloudCalibration(calibration(inverse: values)))
        #expect(corrected.inverseDistortion == values)
        #expect(corrected.rectifiedPoint(x: 0, y: 0, width: 2, height: 2) != CGPoint.zero)
    }

    @Test func projectionKeepsRGBPixelIdentityAndSkipsInvalidGeometry() throws {
        let calibration = try #require(TAPVideoPointCloudCalibration(calibration(inverse: [0, 0])))
        let projection = TAPVideoRegistrationProjection(depthWidth: 2, depthHeight: 2,
            alignedRGBWidth: 2, alignedRGBHeight: 2, encodedRGBWidth: 2, encodedRGBHeight: 2,
            depthToAlignedRGBPixelCenterAffine: [1, 0, 0, 0, 1, 0], connectionRotationDegrees: 0,
            isEncodedHorizontallyMirrored: false, rgbCleanAperture: .init(x: 0, y: 0, width: 2, height: 2))
        let descriptor = TAPVideoDepthRegistrationDescriptor(schemaID: "test", rgbPresentationWidth: 2,
            rgbPresentationHeight: 2, mapping: .avDepthDataWarpedToSynchronizedRGB, projection: projection)
        let data = Data([255, 0, 0, 255, 0, 255, 0, 255, 0, 0, 255, 255, 255, 255, 0, 255])
        let provider = try #require(CGDataProvider(data: data as CFData))
        let image = try #require(CGImage(width: 2, height: 2, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: 8, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
        let packed = floatBytes([1, 2, .nan, 4])
        let frame = TAPDecodedDepthVideoFrame(frameIndex: 0, presentationTimeSeconds: 0, width: 2, height: 2,
            pixelFormat: "fdep", image: UIImage(), retainedByteCount: packed.count, packedDepth: packed, calibrationIndex: 0)
        let payload = try #require(try TAPVideoPointCloudProjection.make(frame: frame,
            calibration: calibration, descriptor: descriptor, image: image))
        #expect(payload.vertices.count == 3)
        #expect(payload.vertices[0] == SIMD3<Float>(-0.5, 0.5, -1))
        #expect(payload.vertices[1] == SIMD3<Float>(1, 1, -2))
        #expect(payload.colors[0] == SIMD4<Float>(1, 0, 0, 1))
        #expect(payload.colors[1] == SIMD4<Float>(0, 1, 0, 1))
        #expect(payload.colors[2] == SIMD4<Float>(1, 1, 0, 1))
    }

    @Test func videoRGBBufferCropPreservesTopLeftPixelCoordinates() throws {
        var buffer: CVPixelBuffer?
        try #require(CVPixelBufferCreate(kCFAllocatorDefault, 2, 2, kCVPixelFormatType_32BGRA,
            [kCVPixelBufferIOSurfacePropertiesKey as String: [:]] as CFDictionary, &buffer) == kCVReturnSuccess)
        let pixelBuffer = try #require(buffer)
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        let address = try #require(CVPixelBufferGetBaseAddress(pixelBuffer))
        let stride = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let bgra: [[UInt8]] = [[0, 0, 255, 255, 0, 255, 0, 255], [255, 0, 0, 255, 0, 255, 255, 255]]
        for row in 0..<2 { bgra[row].withUnsafeBytes { address.advanced(by: row * stride).copyMemory(from: $0.baseAddress!, byteCount: 8) } }
        CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
        let projection = TAPVideoRegistrationProjection(depthWidth: 2, depthHeight: 2,
            alignedRGBWidth: 2, alignedRGBHeight: 2, encodedRGBWidth: 2, encodedRGBHeight: 2,
            depthToAlignedRGBPixelCenterAffine: [1, 0, 0, 0, 1, 0], connectionRotationDegrees: 0,
            isEncodedHorizontallyMirrored: false, rgbCleanAperture: .init(x: 0, y: 1, width: 2, height: 1))
        let descriptor = TAPVideoDepthRegistrationDescriptor(schemaID: "test", rgbPresentationWidth: 2,
            rgbPresentationHeight: 1, mapping: .avDepthDataWarpedToSynchronizedRGB, projection: projection)
        let format = TAPVideoManifest.DepthFormat(kind: "depth", pixelFormat: "fdep", width: 2, height: 2,
            packedRowStride: 8, bytesPerSample: 4, uncompressedFrameByteCount: 16)
        let rawCalibration = calibration(inverse: [0, 0])
        let configuration = TAPVideoPointCloudConfiguration(fileURL: URL(fileURLWithPath: "/unused"),
            descriptor: descriptor, format: format, trackID: 2, calibrations: [rawCalibration])
        let image = try #require(TAPVideoPointCloudRGB(pixelBuffer: pixelBuffer).image(
            configuration: configuration, context: CIContext(options: [.useSoftwareRenderer: true])))
        #expect(image.width == 2 && image.height == 1)
        let packed = floatBytes([1, 2, 3, 4])
        let frame = TAPDecodedDepthVideoFrame(frameIndex: 0, presentationTimeSeconds: 0, width: 2, height: 2,
            pixelFormat: "fdep", image: UIImage(), retainedByteCount: packed.count, packedDepth: packed, calibrationIndex: 0)
        let usableCalibration = try #require(TAPVideoPointCloudCalibration(rawCalibration))
        let payload = try #require(try TAPVideoPointCloudProjection.make(frame: frame,
            calibration: usableCalibration, descriptor: descriptor, image: image))
        #expect(payload.colors.count == 2)
        #expect(payload.colors[0].z > 0.95 && payload.colors[0].x < 0.05)
        #expect(payload.colors[1].x > 0.95 && payload.colors[1].y > 0.95 && payload.colors[1].z < 0.05)
    }

    #if DEBUG
    @Test @MainActor func pausedRGBFixtureSeeksToRequestedPTSAndClearsOnStop() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let artifact = try await TAPVideoPlaybackFixtureGenerator.generate(scenario: .pointCloud, outputDirectoryURL: directory)
        let session = TAPVideoPlaybackSession(
            source: .fixtureFile(artifact.fileURL, automaticSeekScheduleSeconds: [], autoPlay: false),
            registrationAdapter: TAPVideoManifestDepthRegistrationAdapter(), mediaFetcher: PhotoKitLibraryMediaFetcher())
        await session.startPlaybackSession()
        defer { session.stopPlayback() }
        try #require(session.isThreeDDepthAvailable)
        session.prepareThreeDPlaybackGate()
        try await waitForThreeD(session)
        let first = try #require(session.pointCloudStore.presentationTimeSeconds)
        #expect(first == 0)
        #expect(session.currentPlaybackTimeSeconds == 0)
        let player = try #require(session.player)
        _ = await player.seek(to: CMTime(seconds: 0.8, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        session.playbackIntentState.onSeek?(session.currentPlaybackTimeSeconds)
        try await waitForThreeD(session, expectedTime: 0.8)
        let afterSeek = try #require(session.pointCloudStore.presentationTimeSeconds)
        #expect(abs(afterSeek - 0.8) < 0.001)
        session.stopPlayback()
        #expect(session.pointCloudStore.presentationTimeSeconds == nil)
    }

    @Test @MainActor func gapsHoldTheLastFrameUntilRecoveryAndNeverCrossMedia() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let artifact = try await TAPVideoPlaybackFixtureGenerator.generate(scenario: .pointCloud, outputDirectoryURL: directory)
        var presentation = await TAPVideoDepthMetadataReader.presentation(
            for: artifact.fileURL, registrationAdapter: TAPVideoManifestDepthRegistrationAdapter())
        presentation.depthGaps = [.init(reason: .outputDrop, startPTS: .init(value: 1, timescale: 2),
            endPTS: .init(value: 6, timescale: 5), nearestStartRGBFrame: nil, nearestEndRGBFrame: nil)]
        let playback = TAPVideoPointCloudPlayback()
        playback.configure(fileURL: artifact.fileURL, presentation: presentation)
        let item = AVPlayerItem(url: artifact.fileURL)
        playback.begin(on: item, time: 0)
        defer { playback.cancel() }
        var deadline = ContinuousClock.now.advanced(by: .seconds(8))
        while playback.store.presentationTimeSeconds == nil, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(try #require(playback.store.presentationTimeSeconds) == 0)
        var ready = false
        playback.onStateChange = { ready = $0 }
        playback.update(at: 1)
        #expect(playback.store.presentationTimeSeconds == 0 && ready)
        playback.reset(at: 1)
        playback.update(at: 1)
        #expect(playback.store.presentationTimeSeconds == 0 && ready)
        playback.reset(at: 1.6)
        deadline = ContinuousClock.now.advanced(by: .seconds(8))
        while playback.store.presentationTimeSeconds == 0, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(abs((try #require(playback.store.presentationTimeSeconds)) - 1.6) < 0.001)
        playback.configure(fileURL: artifact.fileURL, presentation: presentation)
        #expect(playback.store.presentationTimeSeconds == nil && !ready)
    }

    @MainActor private func waitForThreeD(_ session: TAPVideoPlaybackSession, expectedTime: Double? = nil) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(8))
        while (!session.isThreeDPlaybackReady || expectedTime.map {
            abs((session.pointCloudStore.presentationTimeSeconds ?? -.infinity) - $0) > 0.001
        } == true), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        try #require(session.isThreeDPlaybackReady, "RGB/metric frame failed to become ready")
    }
    #endif

    private func pausePayload(at time: Double) -> TAPVideoPointCloudPayload {
        .init(presentationTimeSeconds: time, vertices: [SIMD3<Float>(0, 0, -2)], colors: [SIMD4<Float>(1, 0, 0, 1)],
              cameraModel: .init(fx: 300, fy: 300, cx: 160, cy: 240, imageWidth: 320, imageHeight: 480))
    }

    private func historyFrame(index: Int, calibration: UInt32?, width: Int = 1) -> TAPDecodedDepthVideoFrame {
        TAPDecodedDepthVideoFrame(frameIndex: index, presentationTimeSeconds: Double(index) / 30,
            width: width, height: 1, pixelFormat: "fdep", image: UIImage(), retainedByteCount: 4,
            calibrationIndex: calibration)
    }

    private func floatBytes(_ values: [Float]) -> Data {
        values.flatMap { value -> [UInt8] in
            let bits = value.bitPattern
            return [UInt8(truncatingIfNeeded: bits), UInt8(truncatingIfNeeded: bits >> 8),
                    UInt8(truncatingIfNeeded: bits >> 16), UInt8(truncatingIfNeeded: bits >> 24)]
        }.withUnsafeBytes { Data($0) }
    }

    private func calibration(inverse: [Float]?, focalLength: Float = 1) -> TAPVideoManifest.CameraCalibration {
        .init(intrinsicMatrix: [focalLength, 0, 0, 0, focalLength, 0, 0.5, 0.5, 1],
              intrinsicMatrixReferenceDimensions: .init(width: 2, height: 2),
              extrinsicMatrix: [1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0],
              pixelSizeMillimeters: 0.001, lensDistortionCenter: .init(x: 0.5, y: 0.5),
              lensDistortionLookupTable: floatBytes([0, 0]), inverseLensDistortionLookupTable: inverse.map(floatBytes))
    }
}
