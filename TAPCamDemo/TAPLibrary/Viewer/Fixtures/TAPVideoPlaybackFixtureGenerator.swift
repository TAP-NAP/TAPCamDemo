//
//  TAPVideoPlaybackFixtureGenerator.swift
//  TAPCamDemo
//

#if DEBUG
@preconcurrency import AVFoundation
import CoreGraphics
import CoreVideo
import Foundation

nonisolated struct TAPVideoPlaybackFixtureArtifact: Identifiable, Sendable {
    let fileURL: URL
    let scenario: TAPVideoPlaybackFixtureScenario
    let specification: TAPVideoPlaybackFixtureSpecification
    let manifest: TAPVideoManifest

    var id: URL { fileURL }
}

nonisolated enum TAPVideoPlaybackFixtureGenerator {
    private static let timeScale: Int32 = 600
    private static let metadataIdentifier = AVMetadataIdentifier(
        rawValue: "mdta/com.tapnap.depth.klv"
    )

    static func generate(
        scenario: TAPVideoPlaybackFixtureScenario,
        outputDirectoryURL: URL? = nil
    ) async throws -> TAPVideoPlaybackFixtureArtifact {
        let specification = scenario.specification
        let encodedFixture = try await Task.detached(priority: .userInitiated) {
            try await generateContainer(
                specification: specification,
                outputDirectoryURL: outputDirectoryURL
            )
        }.value
        do {
            let recordedFacts = try await TAPMediaTrackFactsReader.read(
                from: encodedFixture.fileURL
            )
            let manifest = try manifest(
                specification: specification,
                videoFrameCount: encodedFixture.videoFrameCount,
                depthFrameCount: encodedFixture.depthFrameCount,
                recordedFacts: recordedFacts
            )
            try await Task.detached(priority: .userInitiated) {
                try TAPVideoManifestBox.appendManifest(
                    manifest,
                    toFileAt: encodedFixture.fileURL
                )
            }.value
            return TAPVideoPlaybackFixtureArtifact(
                fileURL: encodedFixture.fileURL,
                scenario: specification.scenario,
                specification: specification,
                manifest: manifest
            )
        } catch {
            try? FileManager.default.removeItem(at: encodedFixture.fileURL)
            if encodedFixture.ownsDirectory {
                try? FileManager.default.removeItem(at: encodedFixture.directoryURL)
            }
            throw error
        }
    }

    private static func generateContainer(
        specification: TAPVideoPlaybackFixtureSpecification,
        outputDirectoryURL: URL?
    ) async throws -> TAPVideoPlaybackEncodedFixture {
        let fileManager = FileManager.default
        let ownsDirectory = outputDirectoryURL == nil
        let directoryURL = outputDirectoryURL
            ?? fileManager.temporaryDirectory.appendingPathComponent(
                "TAPVideoPlaybackFixture-\(specification.scenario.rawValue)-\(UUID().uuidString)",
                isDirectory: true
            )
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let fileURL = directoryURL.appendingPathComponent("artifact.mp4")
        if fileManager.fileExists(atPath: fileURL.path) {
            try fileManager.removeItem(at: fileURL)
        }

        do {
            let writer = try AVAssetWriter(outputURL: fileURL, fileType: .mp4)
            writer.movieTimeScale = CMTimeScale(timeScale)
            writer.shouldOptimizeForNetworkUse = true

            let videoInput = AVAssetWriterInput(
                mediaType: .video,
                outputSettings: videoSettings(for: specification)
            )
            videoInput.expectsMediaDataInRealTime = false
            videoInput.transform = specification.preferredTransform
            guard writer.canAdd(videoInput) else {
                throw fixtureError("asset writer rejected fixture video input")
            }
            writer.add(videoInput)
            let pixelAdaptor = AVAssetWriterInputPixelBufferAdaptor(
                assetWriterInput: videoInput,
                sourcePixelBufferAttributes: [
                    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                    kCVPixelBufferWidthKey as String: specification.codedWidth,
                    kCVPixelBufferHeightKey as String: specification.codedHeight,
                    kCVPixelBufferIOSurfacePropertiesKey as String: [:]
                ]
            )

            let metadataInput = AVAssetWriterInput(
                mediaType: .metadata,
                outputSettings: nil,
                sourceFormatHint: try depthMetadataFormatDescription()
            )
            metadataInput.expectsMediaDataInRealTime = false
            guard writer.canAdd(metadataInput) else {
                throw fixtureError("asset writer rejected fixture depth metadata input")
            }
            writer.add(metadataInput)
            let metadataAdaptor = AVAssetWriterInputMetadataAdaptor(
                assetWriterInput: metadataInput
            )

            guard writer.startWriting() else {
                throw fixtureError(writer.error?.localizedDescription ?? "fixture writer failed to start")
            }
            writer.startSession(atSourceTime: .zero)

            let videoStep = Int64(timeScale) / Int64(specification.videoFramesPerSecond)
            let depthStep = Int64(timeScale) / Int64(specification.depthFramesPerSecond)
            let endValue = Int64((specification.durationSeconds * Double(timeScale)).rounded())
            var nextVideoValue: Int64 = 0
            var nextDepthValue: Int64 = 0
            var videoFrameIndex = 0
            var appendedDepthFrameCount = 0

            while nextVideoValue < endValue || nextDepthValue < endValue {
                try Task.checkCancellation()
                if nextVideoValue <= nextDepthValue, nextVideoValue < endValue {
                    try waitUntilReady(videoInput, writer: writer)
                    let pixelBuffer = try makeRGBPixelBuffer(
                        specification: specification,
                        frameIndex: videoFrameIndex
                    )
                    guard pixelAdaptor.append(
                        pixelBuffer,
                        withPresentationTime: CMTime(value: nextVideoValue, timescale: timeScale)
                    ) else {
                        throw fixtureError(writer.error?.localizedDescription ?? "fixture video append failed")
                    }
                    videoFrameIndex += 1
                    nextVideoValue += videoStep
                } else if nextDepthValue < endValue {
                    let seconds = Double(nextDepthValue) / Double(timeScale)
                    if specification.depthGap?.contains(seconds) != true {
                        try waitUntilReady(metadataInput, writer: writer)
                        let timestamp = CMTime(value: nextDepthValue, timescale: timeScale)
                        let group = try depthMetadataGroup(
                            specification: specification,
                            frameIndex: appendedDepthFrameCount,
                            timestamp: timestamp,
                            durationValue: depthStep
                        )
                        guard metadataAdaptor.append(group) else {
                            throw fixtureError(writer.error?.localizedDescription ?? "fixture metadata append failed")
                        }
                        appendedDepthFrameCount += 1
                    }
                    nextDepthValue += depthStep
                }
            }

            writer.endSession(atSourceTime: CMTime(value: endValue, timescale: timeScale))
            videoInput.markAsFinished()
            metadataInput.markAsFinished()
            try await finish(writer)

            return TAPVideoPlaybackEncodedFixture(
                fileURL: fileURL,
                directoryURL: directoryURL,
                ownsDirectory: ownsDirectory,
                videoFrameCount: videoFrameIndex,
                depthFrameCount: appendedDepthFrameCount
            )
        } catch {
            try? fileManager.removeItem(at: fileURL)
            if ownsDirectory {
                try? fileManager.removeItem(at: directoryURL)
            }
            throw error
        }
    }

    private static func videoSettings(
        for specification: TAPVideoPlaybackFixtureSpecification
    ) -> [String: Any] {
        var settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: specification.codedWidth,
            AVVideoHeightKey: specification.codedHeight,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 180_000,
                AVVideoMaxKeyFrameIntervalKey: max(1, specification.videoFramesPerSecond)
            ]
        ]
        let aperture = specification.presentationAperture
        if aperture.x != 0
            || aperture.y != 0
            || aperture.width != specification.codedWidth
            || aperture.height != specification.codedHeight {
            // AVVideoCleanAperture*OffsetKey is expressed relative to the
            // coded image center, not as a top-left pixel coordinate.
            let horizontalOffset = Double(aperture.x)
                + Double(aperture.width) / 2
                - Double(specification.codedWidth) / 2
            let verticalOffset = Double(specification.codedHeight) / 2
                - Double(aperture.y)
                - Double(aperture.height) / 2
            settings[AVVideoCleanApertureKey] = [
                AVVideoCleanApertureWidthKey: aperture.width,
                AVVideoCleanApertureHeightKey: aperture.height,
                AVVideoCleanApertureHorizontalOffsetKey: horizontalOffset,
                AVVideoCleanApertureVerticalOffsetKey: verticalOffset
            ]
        }
        return settings
    }

    private static func makeRGBPixelBuffer(
        specification: TAPVideoPlaybackFixtureSpecification,
        frameIndex: Int
    ) throws -> CVPixelBuffer {
        var pixelBuffer: CVPixelBuffer?
        let result = CVPixelBufferCreate(
            kCFAllocatorDefault,
            specification.codedWidth,
            specification.codedHeight,
            kCVPixelFormatType_32BGRA,
            [kCVPixelBufferIOSurfacePropertiesKey as String: [:]] as CFDictionary,
            &pixelBuffer
        )
        guard result == kCVReturnSuccess, let pixelBuffer else {
            throw fixtureError("unable to allocate fixture RGB pixel buffer")
        }

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }
        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            throw fixtureError("fixture RGB pixel buffer has no base address")
        }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let aperture = specification.presentationAperture
        for y in 0..<specification.codedHeight {
            let row = baseAddress.advanced(by: y * bytesPerRow).assumingMemoryBound(to: UInt8.self)
            for x in 0..<specification.codedWidth {
                let offset = x * 4
                let insideAperture = x >= aperture.x
                    && x < aperture.x + aperture.width
                    && y >= aperture.y
                    && y < aperture.y + aperture.height
                let blue: UInt8
                let green: UInt8
                let red: UInt8
                if !insideAperture {
                    blue = 190
                    green = 0
                    red = 190
                } else {
                    let localX = x - aperture.x
                    let localY = y - aperture.y
                    let isMovingMarker = localX == frameIndex % max(1, aperture.width)
                    if isMovingMarker {
                        blue = 255
                        green = 255
                        red = 255
                    } else if localX < aperture.width / 2, localY < aperture.height / 2 {
                        blue = 0
                        green = 0
                        red = 255
                    } else if localY < aperture.height / 2 {
                        blue = 0
                        green = 255
                        red = 0
                    } else if localX < aperture.width / 2 {
                        blue = 255
                        green = 0
                        red = 0
                    } else {
                        blue = 0
                        green = 255
                        red = 255
                    }
                }
                row[offset] = blue
                row[offset + 1] = green
                row[offset + 2] = red
                row[offset + 3] = 255
            }
        }
        return pixelBuffer
    }

    private static func depthMetadataGroup(
        specification: TAPVideoPlaybackFixtureSpecification,
        frameIndex: Int,
        timestamp: CMTime,
        durationValue: Int64
    ) throws -> AVTimedMetadataGroup {
        let packedBytes = packedDepthBytes(
            width: specification.presentationAperture.width,
            height: specification.presentationAperture.height,
            frameIndex: frameIndex
        )
        let frame = TAPDepthKLVFrame(
            frameIndex: UInt32(frameIndex),
            timestampValue: timestamp.value,
            timestampTimescale: timestamp.timescale,
            compressionCodec: .raw,
            uncompressedByteCount: packedBytes.count,
            calibrationIndex: 0,
            payload: packedBytes
        )
        let item = AVMutableMetadataItem()
        item.identifier = metadataIdentifier
        item.dataType = kCMMetadataBaseDataType_RawData as String
        item.value = try frame.encodedData() as NSData
        return AVTimedMetadataGroup(
            items: [item],
            timeRange: CMTimeRange(
                start: timestamp,
                duration: CMTime(value: durationValue, timescale: timeScale)
            )
        )
    }

    private static func packedDepthBytes(
        width: Int,
        height: Int,
        frameIndex: Int
    ) -> Data {
        var data = Data(count: width * height * 2)
        data.withUnsafeMutableBytes { bytes in
            guard let baseAddress = bytes.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                return
            }
            for y in 0..<height {
                for x in 0..<width {
                    let normalizedX = Float(x) / Float(max(1, width - 1))
                    let normalizedY = Float(y) / Float(max(1, height - 1))
                    let motion = Float(frameIndex % 30) / 300
                    let value = Float16(0.5 + normalizedX * 2.5 + normalizedY + motion)
                    let bits = value.bitPattern.littleEndian
                    let offset = (y * width + x) * 2
                    baseAddress[offset] = UInt8(bits & 0xff)
                    baseAddress[offset + 1] = UInt8((bits >> 8) & 0xff)
                }
            }
        }
        return data
    }

    private static func depthMetadataFormatDescription() throws -> CMMetadataFormatDescription {
        let item = AVMutableMetadataItem()
        item.identifier = metadataIdentifier
        item.dataType = kCMMetadataBaseDataType_RawData as String
        item.value = Data([0]) as NSData
        let group = AVTimedMetadataGroup(
            items: [item],
            timeRange: CMTimeRange(
                start: .zero,
                duration: CMTime(value: 1, timescale: timeScale)
            )
        )
        guard let formatDescription = group.copyFormatDescription() else {
            throw fixtureError("unable to create fixture depth metadata format")
        }
        return formatDescription
    }

    private static func waitUntilReady(
        _ input: AVAssetWriterInput,
        writer: AVAssetWriter
    ) throws {
        let deadline = Date().addingTimeInterval(5)
        while !input.isReadyForMoreMediaData {
            try Task.checkCancellation()
            guard writer.status == .writing else {
                throw fixtureError(writer.error?.localizedDescription ?? "fixture writer stopped")
            }
            guard Date() < deadline else {
                throw fixtureError("fixture writer input readiness timed out")
            }
            Thread.sleep(forTimeInterval: 0.001)
        }
    }

    private static func finish(_ writer: AVAssetWriter) async throws {
        await withCheckedContinuation { continuation in
            writer.finishWriting {
                continuation.resume()
            }
        }
        try Task.checkCancellation()
        guard writer.status == .completed else {
            throw fixtureError(writer.error?.localizedDescription ?? "fixture writer did not complete")
        }
    }

    private static func manifest(
        specification: TAPVideoPlaybackFixtureSpecification,
        videoFrameCount: Int,
        depthFrameCount: Int,
        recordedFacts: TAPMediaTrackFacts
    ) throws -> TAPVideoManifest {
        guard recordedFacts.videoTrackCount == 1,
              recordedFacts.audioTrackCount == 0,
              recordedFacts.metadataTrackCount == 1,
              recordedFacts.trackCount == 2,
              let metadata = recordedFacts.metadata,
              let metadataCodec = metadata.codec else {
            throw fixtureError(
                "runtime fixture must contain exactly one video track, one metadata track, and no audio track"
            )
        }
        let aperture = specification.presentationAperture
        let gap = specification.depthGap.map {
            TAPVideoManifest.DepthGap(
                reason: .silentCadence,
                startPTS: .init(
                    value: Int64(($0.startSeconds * Double(timeScale)).rounded()),
                    timescale: timeScale
                ),
                endPTS: .init(
                    value: Int64(($0.endSeconds * Double(timeScale)).rounded()),
                    timescale: timeScale
                ),
                nearestStartRGBFrame: Int($0.startSeconds * Double(specification.videoFramesPerSecond)),
                nearestEndRGBFrame: Int($0.endSeconds * Double(specification.videoFramesPerSecond))
            )
        }
        let depthFormat = TAPVideoManifest.DepthFormat(
            kind: "depth",
            pixelFormat: "hdep",
            width: Int32(aperture.width),
            height: Int32(aperture.height),
            packedRowStride: aperture.width * 2,
            sourceRowStride: aperture.width * 2,
            bytesPerSample: 2,
            uncompressedFrameByteCount: aperture.width * aperture.height * 2,
            compressionPolicy: "per-frame:raw"
        )
        let registration = TAPVideoManifest.SpatialRegistration(
            status: .registered,
            mapping: specification.scenario == .pointCloud
                ? TAPVideoManifest.RegistrationDescriptor.schemaID
                : TAPVideoFixtureIdentityRegistrationAdapter.mappingIdentifier,
            rgbReferenceDimensions: .init(
                width: Double(aperture.width),
                height: Double(aperture.height)
            ),
            depthReferenceDimensions: .init(
                width: Double(aperture.width),
                height: Double(aperture.height)
            ),
            rgbCleanAperture: .init(
                x: Double(aperture.x),
                y: Double(aperture.y),
                width: Double(aperture.width),
                height: Double(aperture.height)
            ),
            recordedTransform: specification.transformDescription,
            calibration: TAPVideoManifest.CameraCalibration(
                intrinsicMatrix: [
                    Float(aperture.width), 0, 0,
                    0, Float(aperture.height), 0,
                    Float(aperture.width) / 2, Float(aperture.height) / 2, 1
                ],
                intrinsicMatrixReferenceDimensions: .init(
                    width: Double(aperture.width),
                    height: Double(aperture.height)
                ),
                extrinsicMatrix: [
                    1, 0, 0,
                    0, 1, 0,
                    0, 0, 1,
                    0, 0, 0
                ],
                pixelSizeMillimeters: 0.001,
                lensDistortionCenter: .init(
                    x: Double(aperture.width) / 2,
                    y: Double(aperture.height) / 2
                ),
                lensDistortionLookupTable: specification.scenario == .pointCloud ? Data(count: 8) : nil,
                inverseLensDistortionLookupTable: specification.scenario == .pointCloud ? Data(count: 8) : nil
            ),
            calibrationCoverage: .init(
                indexedSampleCount: depthFrameCount,
                missingCalibrationSampleCount: 0,
                overflowUnindexedSampleCount: 0,
                tableOverflowed: false
            ),
            descriptor: specification.scenario == .pointCloud ? .init(
                alignedRGBCodedDimensions: .init(width: Double(aperture.width), height: Double(aperture.height)),
                encodedRGBCodedDimensions: .init(width: Double(aperture.width), height: Double(aperture.height)),
                depthDimensions: .init(width: Double(aperture.width), height: Double(aperture.height)),
                depthToAlignedRGBPixelCenterAffine: [1, 0, 0, 0, 1, 0],
                connectionTransform: "rotation:0;not-mirrored",
                rgbCleanAperture: .init(x: 0, y: 0, width: Double(aperture.width), height: Double(aperture.height))
            ) : nil
        )
        return TAPVideoManifest(
            payload: TAPVideoManifest.Payload(
                id: "fixture-\(specification.scenario.rawValue)",
                packageID: "debug-runtime-fixture",
                capturedAt: "2026-07-11T00:00:00.000Z",
                selectedCameraPlan: .init(
                    deviceUniqueID: nil,
                    deviceType: "DebugRuntimeFixture",
                    localizedName: "TAP Video Fixture",
                    position: "back",
                    requestedFocalLengthLabel: nil,
                    resolvedFocalLengthLabel: nil,
                    resolvedZoomFactor: 1,
                    depthCapable: true
                ),
                container: .init(
                    fileType: "mp4",
                    mediaType: "video/mp4",
                    durationSeconds: recordedFacts.durationSeconds,
                    timeScale: recordedFacts.timeScale,
                    trackCount: recordedFacts.trackCount
                ),
                rgbTrack: .init(
                    trackID: recordedFacts.video.trackID,
                    codec: recordedFacts.video.codec,
                    width: recordedFacts.video.width,
                    height: recordedFacts.video.height,
                    durationSeconds: recordedFacts.video.timing.durationSeconds,
                    timeScale: recordedFacts.video.timing.timeScale,
                    nominalFrameRate: recordedFacts.video.nominalFrameRate,
                    frameCount: videoFrameCount,
                    transform: specification.transformDescription
                ),
                audioTrack: .init(
                    status: .notCaptured,
                    trackID: nil,
                    codec: nil,
                    durationSeconds: nil,
                    timeScale: nil,
                    sampleRate: nil,
                    channelCount: nil
                ),
                depthCoverage: .init(
                    trackID: metadata.trackID,
                    trackCodec: metadataCodec,
                    trackDurationSeconds: metadata.timing.durationSeconds,
                    trackTimeScale: metadata.timing.timeScale,
                    sampleCount: depthFrameCount,
                    deliveredSampleCount: depthFrameCount,
                    gaps: gap.map { [$0] } ?? [],
                    format: depthFormat
                ),
                spatialRegistration: registration,
                synchronization: .init(
                    timing: "sample-timestamps",
                    rgbToDepthMapping: "fixture-pre-registered-presentation-grid",
                    maxObservedDeltaSeconds: 0,
                    maxObservedDepthIntervalSeconds: specification
                        .maxObservedStoredDepthIntervalSeconds,
                    nominalDepthIntervalSeconds: 1 / Double(specification.depthFramesPerSecond)
                ),
                stop: .init(
                    reason: .userStop,
                    recordedDurationSeconds: specification.durationSeconds
                ),
                software: .init(
                    appIdentifier: "net.tapcam.demo.debug-fixture",
                    appVersion: "debug",
                    buildNumber: "1",
                    schemaWriter: "TAPVideoPlaybackFixtureGenerator"
                )
            )
        )
    }

    private static func fixtureError(_ message: String) -> TAPDepthCaptureError {
        .videoRecordingFailed(message)
    }
}

nonisolated private struct TAPVideoPlaybackEncodedFixture: Sendable {
    let fileURL: URL
    let directoryURL: URL
    let ownsDirectory: Bool
    let videoFrameCount: Int
    let depthFrameCount: Int
}
#endif
