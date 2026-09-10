import AVFoundation
import CoreGraphics
import CoreImage
import CoreVideo
import ImageIO
import Testing
import UIKit
@testable import TAPCamDemo

struct TAPVideoPointCloudTests {
    @Test func photoAndVideoPayloadsPreservePixelMappingsAndAllDisplayOrientations() throws {
        let matrix: [Float] = [4, 0, 0, 0, 8, 0, 0.75, 1.25, 1]
        let extrinsic: [Float] = [1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0]
        let photoCalibration = TAPDepthManifest.CameraCalibration(
            intrinsicMatrixReferenceWidth: 4, intrinsicMatrixReferenceHeight: 6,
            pixelSizeMillimeters: 0.001, lensDistortionLookupTablePresent: false,
            inverseLensDistortionLookupTablePresent: false, lensDistortionCenterX: 0.75,
            lensDistortionCenterY: 1.25, intrinsicMatrix: matrix, extrinsicMatrix: extrinsic)
        let videoCalibration = try #require(TAPVideoPointCloudCalibration(.init(
            intrinsicMatrix: matrix, intrinsicMatrixReferenceDimensions: .init(width: 4, height: 6),
            extrinsicMatrix: extrinsic, pixelSizeMillimeters: 0.001,
            lensDistortionCenter: .init(x: 0.75, y: 1.25), lensDistortionLookupTable: nil,
            inverseLensDistortionLookupTable: floatBytes([0, 0]))))
        let image = try TAPDepthRGBAImageRenderer.image(pixels: Array(repeating: 255, count: 4 * 6 * 4), width: 4, height: 6)
        // Expected scene XY for the first pixel at Z = 2, using off-center intrinsics.
        // EXIF mirror names are paired with video rotation followed by a horizontal mirror.
        let orientations: [(exif: CGImagePropertyOrientation, rotation: Int, mirrored: Bool,
                            photoXY: SIMD2<Float>, scaledVideoXY: SIMD2<Float>)] = [
            (.up, 0, false, [-0.375, 0.3125], [-0.125, 0.1875]),
            (.upMirrored, 0, true, [0.375, 0.3125], [0.125, 0.1875]),
            (.right, 90, false, [0.3125, 0.375], [0.1875, 0.125]),
            (.leftMirrored, 90, true, [-0.3125, 0.375], [-0.1875, 0.125]),
            (.down, 180, false, [0.375, -0.3125], [0.125, -0.1875]),
            (.downMirrored, 180, true, [-0.375, -0.3125], [-0.125, -0.1875]),
            (.left, 270, false, [-0.3125, -0.375], [-0.1875, -0.125]),
            (.rightMirrored, 270, true, [0.3125, -0.375], [0.1875, -0.125])
        ]
        for scale in [1, 2] {
            let width = 4 / scale
            let height = 6 / scale
            let depths = Array<Float>(repeating: 2, count: width * height)
            let depthMap = TAPMetricDepthMap(width: width, height: height, samples: depths, calibration: photoCalibration)
            let packed = floatBytes(depths)
            let frame = TAPDecodedDepthVideoFrame(frameIndex: 0, presentationTimeSeconds: 0,
                width: width, height: height, pixelFormat: "fdep", image: UIImage(),
                retainedByteCount: packed.count, packedDepth: packed, calibrationIndex: 0)
            for orientation in orientations {
                let rotated = orientation.rotation == 90 || orientation.rotation == 270
                let encodedWidth = rotated ? 6 : 4
                let encodedHeight = rotated ? 4 : 6
                let scaleValue = Double(scale)
                let offset = (scaleValue - 1) / 2
                let projection = TAPVideoRegistrationProjection(depthWidth: width, depthHeight: height,
                    alignedRGBWidth: 4, alignedRGBHeight: 6, encodedRGBWidth: encodedWidth, encodedRGBHeight: encodedHeight,
                    depthToAlignedRGBPixelCenterAffine: [scaleValue, 0, offset, 0, scaleValue, offset],
                    connectionRotationDegrees: orientation.rotation, isEncodedHorizontallyMirrored: orientation.mirrored,
                    rgbCleanAperture: .init(x: 0, y: 0, width: Double(encodedWidth), height: Double(encodedHeight)))
                let descriptor = TAPVideoDepthRegistrationDescriptor(schemaID: "test",
                    rgbPresentationWidth: encodedWidth, rgbPresentationHeight: encodedHeight,
                    mapping: .avDepthDataWarpedToSynchronizedRGB, projection: projection)
                let videoImage = try TAPDepthRGBAImageRenderer.image(pixels: Array(repeating: 255, count: 4 * 6 * 4),
                    width: encodedWidth, height: encodedHeight)
                let photo = try #require(TAPDepthProjectionScenePayloadBuilder.makePayloadData(image: image,
                    depthMap: depthMap, orientation: orientation.exif, selectedPlaneRegion: nil))
                let video = try #require(try TAPVideoPointCloudProjection.make(frame: frame, history: [],
                    calibration: videoCalibration, descriptor: descriptor, image: videoImage))
                #expect(photo.cameraModel == video.cameraModel)
                #expect(photo.baseVertices.count == width * height && video.vertices.count == width * height)
                #expect(photo.baseVertices[0] == SIMD3(orientation.photoXY.x, orientation.photoXY.y, -2))
                let videoXY = scale == 1 ? orientation.photoXY : orientation.scaledVideoXY
                #expect(video.vertices[0] == SIMD3(videoXY.x, videoXY.y, -2))
                if scale == 1 {
                    #expect(photo.baseVertices == video.vertices)
                }
                // At scale 2, photo pixel (0,0) maps to image (0,0), while video
                // pixel centers map to reference (0.5,0.5); these rays stay distinct.
            }
        }
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

    @Test func smoothingNeverFillsHolesOrBlendsAChangedSurface() {
        #expect(TAPVideoPointCloudSmoothing.depth(current: .nan, history: [(1, 0.02)]).isNaN)
        #expect(TAPVideoPointCloudSmoothing.depth(current: 2, history: [(1, 0.02)]) == 2)
        #expect(TAPVideoPointCloudSmoothing.depth(current: 1, history: [(1.02, 0.2)]) == 1)
        #expect(TAPVideoPointCloudSmoothing.depth(current: 1, history: [(1.02, -0.02)]) == 1)
        let stable = TAPVideoPointCloudSmoothing.depth(current: 1, history: [(1.02, 0.03)])
        #expect(stable > 1 && stable < 1.02)
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
            let payload = try #require(try TAPVideoPointCloudProjection.make(frame: frame, history: [],
                calibration: usableCalibration, descriptor: descriptor, image: image))
            #expect(payload.vertices.count == 4 && payload.colors.count == 4)
            #expect(abs(payload.vertices[0].x + 0.5 / calibrations[index].intrinsicMatrix[0]) < 0.000_001)
        }
        #expect(configuration.calibration(for: historyFrame(index: 40, calibration: nil)) == nil,
                "A legacy frame without CALI must not inherit the last saved calibration")
    }

    @Test func smoothingStopsWhenInlineCalibrationChanges() {
        let first = calibration(inverse: [0, 0])
        let second = calibration(inverse: [0, 0], focalLength: 1.01)
        var frames = (0..<4).map { historyFrame(index: $0, calibration: nil) }
        for index in frames.indices { frames[index].inlineCalibration = index == 1 ? second : first }
        #expect(TAPVideoPointCloudSmoothing.history(before: frames[3], candidates: Array(frames.prefix(3)), gaps: [], after: nil)
            .map(\.frameIndex) == [2], "Equal nil CALI indices cannot bridge changing inline calibration")
    }

    @Test func smoothingKeepsOnlyTheContinuousCalibrationAndLayoutSuffix() {
        let current = historyFrame(index: 3, calibration: 0)
        let frames = [historyFrame(index: 0, calibration: 0),
                      historyFrame(index: 1, calibration: 1),
                      historyFrame(index: 2, calibration: 0)]
        let selected = TAPVideoPointCloudSmoothing.history(before: current, candidates: frames, gaps: [], after: nil)
        #expect(selected.map(\.frameIndex) == [2], "A-B-A must not recover the earlier A history")
        var changedLayout = frames
        changedLayout[1] = historyFrame(index: 1, calibration: 0, width: 2)
        #expect(TAPVideoPointCloudSmoothing.history(before: current, candidates: changedLayout, gaps: [], after: nil)
            .map(\.frameIndex) == [2])
        #expect(TAPVideoPointCloudSmoothing.history(before: current, candidates: [frames[0], frames[2]], gaps: [], after: nil)
            .map(\.frameIndex) == [2], "A missing intermediate frame ends continuity")
    }

    @Test func smoothingCannotBridgeShortDeclaredGapsOrRuntimeFailureCutoffs() {
        let frames = (0..<3).map { historyFrame(index: $0, calibration: 0) }
        let current = historyFrame(index: 3, calibration: 0)
        let gap: ClosedRange<Double> = 0.04...0.05
        #expect(TAPVideoPointCloudSmoothing.crossesGap(from: 0.03, to: 0.06, gaps: [gap]))
        #expect(TAPVideoPointCloudSmoothing.crossesGap(from: 0.06, to: 0.03, gaps: [gap]))
        #expect(!TAPVideoPointCloudSmoothing.crossesGap(from: 0.06, to: 0.07, gaps: [gap]))
        let selected = TAPVideoPointCloudSmoothing.history(before: current, candidates: frames, gaps: [gap], after: nil)
        #expect(selected.map(\.frameIndex) == [2])
        #expect(TAPVideoPointCloudSmoothing.history(before: frames[2], candidates: Array(frames.prefix(2)), gaps: [gap], after: nil).isEmpty)
        #expect(TAPVideoPointCloudSmoothing.history(before: current, candidates: frames, gaps: [], after: 0.075).isEmpty,
                "A warmup read cannot reintroduce history before the runtime failure cutoff")
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
        let payload = try #require(try TAPVideoPointCloudProjection.make(frame: frame, history: [],
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
        let payload = try #require(try TAPVideoPointCloudProjection.make(frame: frame, history: [],
            calibration: usableCalibration, descriptor: descriptor, image: image))
        #expect(payload.colors.count == 2)
        #expect(payload.colors[0].z > 0.95 && payload.colors[0].x < 0.05)
        #expect(payload.colors[1].x > 0.95 && payload.colors[1].y > 0.95 && payload.colors[1].z < 0.05)
    }

    #if DEBUG
    @Test @MainActor func metadataPushAndProbeRenderHeatmapsOnlyForTwoD() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let artifact = try await TAPVideoPlaybackFixtureGenerator.generate(scenario: .pointCloud, outputDirectoryURL: directory)
        let format = try #require(artifact.manifest.payload.depthCoverage.format)
        let trackID = try #require(artifact.manifest.payload.depthCoverage.trackID)
        let pixelCount = Int(format.width) * Int(format.height)
        let packed = Array(repeating: Float16(1), count: pixelCount).withUnsafeBytes { Data($0) }
        let klv = TAPDepthKLVFrame(frameIndex: 0, timestampValue: 0, timestampTimescale: 600,
            compressionCodec: .raw, uncompressedByteCount: packed.count, calibrationIndex: 0, payload: packed)
        let item = AVMutableMetadataItem()
        item.identifier = AVMetadataIdentifier(rawValue: "mdta/com.tapnap.depth.klv")
        item.dataType = kCMMetadataBaseDataType_RawData as String
        item.value = try klv.encodedData() as NSData
        let group = AVTimedMetadataGroup(items: [item], timeRange: CMTimeRange(start: .zero, duration: CMTime(value: 1, timescale: 15)))

        for rendersHeatmap in [false, true] {
            var frames: [TAPDecodedDepthVideoFrame] = []
            var pushWasBackpressured = false
            let onEvent: (TAPVideoDepthPipelineEvent) -> Void = { event in
                switch event.payload {
                case .frame(let frame): frames.append(frame)
                case .decodeFailed(reason: .backpressure, presentationTimeSeconds: _): pushWasBackpressured = true
                default: Issue.record("Metadata push/probe did not produce a depth frame")
                }
            }
            // The 2D caller keeps the default; 3D explicitly opts out.
            let output = rendersHeatmap
                ? TAPVideoDepthMetadataOutput(displayOrientation: .up, depthFormat: format, depthTrackID: trackID, onEvent: onEvent)
                : TAPVideoDepthMetadataOutput(displayOrientation: .up, depthFormat: format, depthTrackID: trackID,
                                              rendersHeatmap: false, onEvent: onEvent)
            defer { output.detach() }
            output.beginNewGeneration()
            output.metadataOutput(AVPlayerItemMetadataOutput(identifiers: nil), didOutputTimedMetadataGroups: [group], from: nil)
            var deadline = ContinuousClock.now.advanced(by: .seconds(8))
            while frames.isEmpty, ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(10))
                if pushWasBackpressured {
                    pushWasBackpressured = false
                    output.metadataOutput(AVPlayerItemMetadataOutput(identifiers: nil), didOutputTimedMetadataGroups: [group], from: nil)
                }
            }
            try #require(frames.count == 1, "Metadata push failed to publish")
            output.probe(fileURL: artifact.fileURL, playbackTimeSeconds: 0,
                         staleToleranceSeconds: 0.2, leadToleranceSeconds: 0.05)
            deadline = ContinuousClock.now.advanced(by: .seconds(8))
            while frames.count < 2, ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(10))
            }
            try #require(frames.count == 2, "Metadata probe failed to publish")
            for frame in frames {
                #expect((frame.image.cgImage != nil) == rendersHeatmap)
                #expect(frame.packedDepth.count == format.uncompressedFrameByteCount)
                #expect(frame.calibrationIndex == 0)
                #expect(frame.retainedByteCount == format.uncompressedFrameByteCount
                    + (rendersHeatmap ? pixelCount * 4 : 0))
            }
        }
    }

    @Test @MainActor func pausedRGBFixtureReentersThreeDWithSmoothingAndClearsOnStop() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let artifact = try await TAPVideoPlaybackFixtureGenerator.generate(scenario: .pointCloud, outputDirectoryURL: directory)
        let session = TAPVideoPlaybackSession(
            source: .fixtureFile(artifact.fileURL, automaticSeekScheduleSeconds: [], autoPlay: false),
            registrationAdapter: TAPVideoManifestDepthRegistrationAdapter(), mediaFetcher: PhotoKitLibraryMediaFetcher())
        await session.startPlaybackSession()
        defer { session.stopPlayback() }
        try #require(session.isThreeDDepthAvailable)
        session.prepareThreeDPlaybackGate(smoothingEnabled: false)
        try await waitForThreeD(session)
        let first = try #require(session.pointCloudStore.presentationTimeSeconds)
        #expect(first == 0)
        session.prepareThreeDPlaybackGate(smoothingEnabled: true)
        try await waitForThreeD(session)
        #expect(session.pointCloudStore.presentationTimeSeconds == first)
        #expect(session.currentPlaybackTimeSeconds == 0)
        let player = try #require(session.player)
        _ = await player.seek(to: CMTime(seconds: 0.8, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        session.prepareThreeDPlaybackGate(smoothingEnabled: false)
        try await waitForThreeD(session, expectedTime: 0.8)
        let afterSeek = try #require(session.pointCloudStore.presentationTimeSeconds)
        #expect(abs(afterSeek - 0.8) < 0.001)
        session.prepareThreeDPlaybackGate(smoothingEnabled: true)
        try await waitForThreeD(session)
        #expect(session.pointCloudStore.presentationTimeSeconds == afterSeek)
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
        playback.begin(on: item, time: 0, smoothingEnabled: false)
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

    @Test func warmupBudgetKeepsNearestWholeFrameWithoutOvershoot() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let artifact = try await TAPVideoPlaybackFixtureGenerator.generate(scenario: .pointCloud, outputDirectoryURL: directory)
        let format = try #require(artifact.manifest.payload.depthCoverage.format)
        let trackID = try #require(artifact.manifest.payload.depthCoverage.trackID)
        let bytes = format.uncompressedFrameByteCount
        let frames = try await TAPVideoDepthMetadataReader.readHistory(fileURL: artifact.fileURL, trackID: trackID,
            through: 0.2, depthFormat: format, maximumRetainedBytes: bytes * 2 - 1, shouldContinue: { true })
        #expect(frames.count == 1)
        #expect(frames.reduce(0) { $0 + $1.retainedByteCount } == bytes)
        #expect(abs((try #require(frames.first)).presentationTimeSeconds - (2.0 / 15.0)) < 0.001)
        let empty = try await TAPVideoDepthMetadataReader.readHistory(fileURL: artifact.fileURL, trackID: trackID,
            through: 0.2, depthFormat: format, maximumRetainedBytes: bytes - 1, shouldContinue: { true })
        #expect(empty.isEmpty)
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
