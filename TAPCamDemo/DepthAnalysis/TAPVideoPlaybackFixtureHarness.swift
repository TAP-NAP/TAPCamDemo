//
//  TAPVideoPlaybackFixtureHarness.swift
//  TAPCamDemo
//

#if DEBUG
@preconcurrency import AVFoundation
import CoreGraphics
import CoreVideo
import Foundation
import SwiftUI

/// Runtime-authored TAP video fixtures. The encoded H.264 bytes may vary by
/// OS encoder, but the pixels, timestamps, metadata, manifest, and test actions
/// are deterministic for each scenario.
nonisolated enum TAPVideoPlaybackFixtureScenario: String, CaseIterable, Identifiable, Sendable {
    case rotation0 = "rotation-0"
    case rotation90 = "rotation-90"
    case rotation180 = "rotation-180"
    case rotation270 = "rotation-270"
    case mirrored = "mirrored"
    case aspect4x3 = "aspect-4x3"
    case aspect16x9 = "aspect-16x9"
    case cleanAperture = "clean-aperture"
    case depthGap = "depth-gap"
    case seekDiscontinuity = "seek-discontinuity"
    case performancePlayback15Seconds = "performance-playback-15s"
    case metadataStress180Seconds = "metadata-stress-180s"

    var id: String { rawValue }

    var specification: TAPVideoPlaybackFixtureSpecification {
        switch self {
        case .rotation0:
            .standard(scenario: self, rotationDegrees: 0)
        case .rotation90:
            .standard(scenario: self, rotationDegrees: 90)
        case .rotation180:
            .standard(scenario: self, rotationDegrees: 180)
        case .rotation270:
            .standard(scenario: self, rotationDegrees: 270)
        case .mirrored:
            .standard(scenario: self, mirrored: true)
        case .aspect4x3:
            TAPVideoPlaybackFixtureSpecification(
                scenario: self,
                codedWidth: 64,
                codedHeight: 48,
                presentationAperture: .init(x: 0, y: 0, width: 64, height: 48),
                rotationDegrees: 0,
                mirrored: false,
                durationSeconds: 2,
                videoFramesPerSecond: 15,
                depthFramesPerSecond: 15,
                depthGap: nil,
                automaticSeekSeconds: nil
            )
        case .aspect16x9:
            .standard(scenario: self)
        case .cleanAperture:
            TAPVideoPlaybackFixtureSpecification(
                scenario: self,
                codedWidth: 80,
                codedHeight: 48,
                presentationAperture: .init(x: 8, y: 6, width: 64, height: 36),
                rotationDegrees: 0,
                mirrored: false,
                durationSeconds: 2,
                videoFramesPerSecond: 15,
                depthFramesPerSecond: 15,
                depthGap: nil,
                automaticSeekSeconds: nil
            )
        case .depthGap:
            TAPVideoPlaybackFixtureSpecification(
                scenario: self,
                codedWidth: 64,
                codedHeight: 36,
                presentationAperture: .init(x: 0, y: 0, width: 64, height: 36),
                rotationDegrees: 0,
                mirrored: false,
                durationSeconds: 3,
                videoFramesPerSecond: 15,
                depthFramesPerSecond: 15,
                depthGap: .init(startSeconds: 1, endSeconds: 1.6),
                automaticSeekSeconds: 1.3
            )
        case .seekDiscontinuity:
            TAPVideoPlaybackFixtureSpecification(
                scenario: self,
                codedWidth: 64,
                codedHeight: 36,
                presentationAperture: .init(x: 0, y: 0, width: 64, height: 36),
                rotationDegrees: 0,
                mirrored: false,
                durationSeconds: 6,
                videoFramesPerSecond: 15,
                depthFramesPerSecond: 15,
                depthGap: nil,
                automaticSeekSeconds: 4.5
            )
        case .performancePlayback15Seconds:
            TAPVideoPlaybackFixtureSpecification(
                scenario: self,
                codedWidth: 64,
                codedHeight: 36,
                presentationAperture: .init(x: 0, y: 0, width: 64, height: 36),
                rotationDegrees: 0,
                mirrored: false,
                durationSeconds: 15,
                videoFramesPerSecond: 30,
                depthFramesPerSecond: 30,
                depthGap: nil,
                automaticSeekSeconds: nil
            )
        case .metadataStress180Seconds:
            TAPVideoPlaybackFixtureSpecification(
                scenario: self,
                codedWidth: 32,
                codedHeight: 18,
                presentationAperture: .init(x: 0, y: 0, width: 32, height: 18),
                rotationDegrees: 0,
                mirrored: false,
                durationSeconds: 180,
                videoFramesPerSecond: 1,
                depthFramesPerSecond: 30,
                depthGap: nil,
                automaticSeekSeconds: nil
            )
        }
    }
}

nonisolated struct TAPVideoPlaybackFixtureRect: Equatable, Sendable {
    let x: Int
    let y: Int
    let width: Int
    let height: Int
}

nonisolated struct TAPVideoPlaybackFixtureGap: Equatable, Sendable {
    let startSeconds: Double
    let endSeconds: Double

    func contains(_ seconds: Double) -> Bool {
        seconds >= startSeconds && seconds < endSeconds
    }
}

nonisolated struct TAPVideoPlaybackFixtureSpecification: Equatable, Sendable {
    let scenario: TAPVideoPlaybackFixtureScenario
    let codedWidth: Int
    let codedHeight: Int
    let presentationAperture: TAPVideoPlaybackFixtureRect
    let rotationDegrees: Int
    let mirrored: Bool
    let durationSeconds: Double
    let videoFramesPerSecond: Int
    let depthFramesPerSecond: Int
    let depthGap: TAPVideoPlaybackFixtureGap?
    let automaticSeekSeconds: Double?

    var transformDescription: String {
        mirrored
            ? "rotation:\(rotationDegrees);mirrored"
            : "rotation:\(rotationDegrees);not-mirrored"
    }

    var expectedVideoFrameCount: Int {
        Int((durationSeconds * Double(videoFramesPerSecond)).rounded(.down))
    }

    var expectedDepthFrameCount: Int {
        let candidateCount = Int((durationSeconds * Double(depthFramesPerSecond)).rounded(.down))
        return (0..<candidateCount).reduce(into: 0) { count, index in
            let seconds = Double(index) / Double(depthFramesPerSecond)
            if depthGap?.contains(seconds) != true {
                count += 1
            }
        }
    }

    var maxObservedStoredDepthIntervalSeconds: Double? {
        let candidateCount = Int((durationSeconds * Double(depthFramesPerSecond)).rounded(.down))
        var previousSeconds: Double?
        var maximumInterval: Double?
        for index in 0..<candidateCount {
            let seconds = Double(index) / Double(depthFramesPerSecond)
            guard depthGap?.contains(seconds) != true else {
                continue
            }
            if let previousSeconds {
                maximumInterval = max(maximumInterval ?? 0, seconds - previousSeconds)
            }
            previousSeconds = seconds
        }
        return maximumInterval
    }

    var preferredTransform: CGAffineTransform {
        let width = CGFloat(codedWidth)
        let height = CGFloat(codedHeight)
        if mirrored {
            return CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: width, ty: 0)
        }
        switch rotationDegrees {
        case 90:
            return CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: height, ty: 0)
        case 180:
            return CGAffineTransform(a: -1, b: 0, c: 0, d: -1, tx: width, ty: height)
        case 270:
            return CGAffineTransform(a: 0, b: -1, c: 1, d: 0, tx: 0, ty: width)
        default:
            return .identity
        }
    }

    fileprivate static func standard(
        scenario: TAPVideoPlaybackFixtureScenario,
        rotationDegrees: Int = 0,
        mirrored: Bool = false
    ) -> Self {
        Self(
            scenario: scenario,
            codedWidth: 64,
            codedHeight: 36,
            presentationAperture: .init(x: 0, y: 0, width: 64, height: 36),
            rotationDegrees: rotationDegrees,
            mirrored: mirrored,
            durationSeconds: 2,
            videoFramesPerSecond: 15,
            depthFramesPerSecond: 15,
            depthGap: nil,
            automaticSeekSeconds: nil
        )
    }
}

nonisolated struct TAPVideoPlaybackFixtureLaunchConfiguration: Equatable, Sendable {
    static let enableArgument = "--tap-video-playback-fixture"
    static let scenarioArgument = "--tap-video-fixture-scenario"
    static let enableEnvironmentKey = "TAPCAM_UI_TEST_VIDEO_FIXTURE"
    static let scenarioEnvironmentKey = "TAPCAM_UI_TEST_VIDEO_FIXTURE_SCENARIO"
    static let autoPlayEnvironmentKey = "TAPCAM_UI_TEST_VIDEO_FIXTURE_AUTOPLAY"
    static let seekScheduleEnvironmentKey = "TAPCAM_UI_TEST_VIDEO_FIXTURE_SEEK_SCHEDULE"
    static let accessibilityDynamicTypeEnvironmentKey =
        "TAPCAM_UI_TEST_VIDEO_FIXTURE_ACCESSIBILITY_DYNAMIC_TYPE"

    let scenario: TAPVideoPlaybackFixtureScenario
    let autoPlay: Bool
    let seekScheduleSeconds: [Double]?
    let usesAccessibilityDynamicType: Bool

    static var current: Self? {
        parse(
            arguments: ProcessInfo.processInfo.arguments,
            environment: ProcessInfo.processInfo.environment
        )
    }

    static func parse(
        arguments: [String],
        environment: [String: String]
    ) -> Self? {
        let argumentValue = scenarioValue(in: arguments)
        let environmentValue = environment[scenarioEnvironmentKey]
        let autoPlay = environment[autoPlayEnvironmentKey] == "1"
        let usesAccessibilityDynamicType =
            environment[accessibilityDynamicTypeEnvironmentKey] == "1"
        let seekScheduleSeconds: [Double]?
        if let rawSchedule = environment[seekScheduleEnvironmentKey] {
            guard let parsedSchedule = parseSeekSchedule(rawSchedule) else {
                return nil
            }
            seekScheduleSeconds = parsedSchedule
        } else {
            seekScheduleSeconds = nil
        }
        let isEnabled = arguments.contains(enableArgument)
            || environment[enableEnvironmentKey] == "1"
            || argumentValue != nil
            || environmentValue != nil
        guard isEnabled else {
            return nil
        }
        let rawScenario = argumentValue ?? environmentValue
        guard let rawScenario else {
            return Self(
                scenario: .rotation0,
                autoPlay: autoPlay,
                seekScheduleSeconds: seekScheduleSeconds,
                usesAccessibilityDynamicType: usesAccessibilityDynamicType
            )
        }
        guard let scenario = TAPVideoPlaybackFixtureScenario(rawValue: rawScenario) else {
            return nil
        }
        return Self(
            scenario: scenario,
            autoPlay: autoPlay,
            seekScheduleSeconds: seekScheduleSeconds,
            usesAccessibilityDynamicType: usesAccessibilityDynamicType
        )
    }

    private static func scenarioValue(in arguments: [String]) -> String? {
        if let inline = arguments.first(where: { $0.hasPrefix("\(scenarioArgument)=") }) {
            return String(inline.dropFirst(scenarioArgument.count + 1))
        }
        guard let index = arguments.firstIndex(of: scenarioArgument),
              arguments.indices.contains(index + 1) else {
            return nil
        }
        return arguments[index + 1]
    }

    private static func parseSeekSchedule(_ rawValue: String) -> [Double]? {
        let components = rawValue.split(separator: ",", omittingEmptySubsequences: false)
        guard !components.isEmpty else {
            return nil
        }
        var values: [Double] = []
        values.reserveCapacity(components.count)
        for component in components {
            guard let value = Double(component.trimmingCharacters(in: .whitespaces)),
                  value.isFinite,
                  value >= 0 else {
                return nil
            }
            values.append(value)
        }
        return values
    }
}

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
            let recordedFacts = try await TAPVideoPlaybackFixtureRecordedFacts.load(
                from: encodedFixture.fileURL
            )
            let manifest = manifest(
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
        recordedFacts: TAPVideoPlaybackFixtureRecordedFacts
    ) -> TAPVideoManifest {
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
            mapping: TAPVideoFixtureIdentityRegistrationAdapter.mappingIdentifier,
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
                lensDistortionLookupTable: nil,
                inverseLensDistortionLookupTable: nil
            ),
            calibrationCoverage: .init(
                indexedSampleCount: depthFrameCount,
                missingCalibrationSampleCount: 0,
                overflowUnindexedSampleCount: 0,
                tableOverflowed: false
            )
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
                    trackID: recordedFacts.videoTrackID,
                    codec: recordedFacts.videoCodec,
                    width: recordedFacts.videoWidth,
                    height: recordedFacts.videoHeight,
                    durationSeconds: recordedFacts.videoDurationSeconds,
                    timeScale: recordedFacts.videoTimeScale,
                    nominalFrameRate: recordedFacts.nominalFrameRate,
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
                    trackID: recordedFacts.depthMetadataTrackID,
                    trackCodec: recordedFacts.depthMetadataCodec,
                    trackDurationSeconds: recordedFacts.depthMetadataDurationSeconds,
                    trackTimeScale: recordedFacts.depthMetadataTimeScale,
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

nonisolated private struct TAPVideoPlaybackFixtureRecordedFacts: Sendable {
    let durationSeconds: Double
    let timeScale: Int32
    let trackCount: Int
    let videoTrackID: Int32
    let videoCodec: String
    let videoWidth: Int32
    let videoHeight: Int32
    let videoDurationSeconds: Double
    let videoTimeScale: Int32
    let nominalFrameRate: Double?
    let depthMetadataTrackID: Int32
    let depthMetadataCodec: String
    let depthMetadataDurationSeconds: Double
    let depthMetadataTimeScale: Int32

    static func load(from fileURL: URL) async throws -> Self {
        let asset = AVURLAsset(url: fileURL)
        async let allTracks = asset.load(.tracks)
        async let videoTracks = asset.loadTracks(withMediaType: .video)
        async let audioTracks = asset.loadTracks(withMediaType: .audio)
        async let metadataTracks = asset.loadTracks(withMediaType: .metadata)
        async let duration = asset.load(.duration)

        let resolvedTracks = try await allTracks
        let resolvedVideoTracks = try await videoTracks
        let resolvedAudioTracks = try await audioTracks
        let resolvedMetadataTracks = try await metadataTracks
        guard resolvedVideoTracks.count == 1,
              resolvedAudioTracks.isEmpty,
              resolvedMetadataTracks.count == 1,
              let videoTrack = resolvedVideoTracks.first,
              let metadataTrack = resolvedMetadataTracks.first else {
            throw TAPDepthCaptureError.videoRecordingFailed(
                "runtime fixture must contain exactly one video track, one metadata track, and no audio track"
            )
        }

        let resolvedDuration = try await duration
        let videoDescriptions = try await videoTrack.load(.formatDescriptions)
        guard let videoDescription = videoDescriptions.first else {
            throw TAPDepthCaptureError.videoRecordingFailed(
                "runtime fixture video format is unavailable"
            )
        }
        let dimensions = CMVideoFormatDescriptionGetDimensions(videoDescription)
        let videoTiming = try await trackTiming(videoTrack)
        let nominalFrameRate = Double(try await videoTrack.load(.nominalFrameRate))
        let metadataDescriptions = try await metadataTrack.load(.formatDescriptions)
        guard let metadataDescription = metadataDescriptions.first else {
            throw TAPDepthCaptureError.videoRecordingFailed(
                "runtime fixture metadata format is unavailable"
            )
        }
        let metadataTiming = try await trackTiming(metadataTrack)
        return Self(
            durationSeconds: max(0, CMTimeGetSeconds(resolvedDuration)),
            timeScale: resolvedDuration.timescale,
            trackCount: resolvedTracks.count,
            videoTrackID: videoTrack.trackID,
            videoCodec: TAPFourCharCode.string(
                from: CMFormatDescriptionGetMediaSubType(videoDescription)
            ),
            videoWidth: dimensions.width,
            videoHeight: dimensions.height,
            videoDurationSeconds: videoTiming.durationSeconds,
            videoTimeScale: videoTiming.timeScale,
            nominalFrameRate: nominalFrameRate > 0 ? nominalFrameRate : nil,
            depthMetadataTrackID: metadataTrack.trackID,
            depthMetadataCodec: TAPFourCharCode.string(
                from: CMFormatDescriptionGetMediaSubType(metadataDescription)
            ),
            depthMetadataDurationSeconds: metadataTiming.durationSeconds,
            depthMetadataTimeScale: metadataTiming.timeScale
        )
    }

    private static func trackTiming(_ track: AVAssetTrack) async throws -> TAPVideoPlaybackFixtureTrackTiming {
        async let loadedTimeRange = track.load(.timeRange)
        async let loadedNaturalTimeScale = track.load(.naturalTimeScale)
        let timeRange = try await loadedTimeRange
        let naturalTimeScale = try await loadedNaturalTimeScale
        let durationSeconds = CMTimeGetSeconds(timeRange.duration)
        let timeScale = naturalTimeScale > 0 ? naturalTimeScale : timeRange.duration.timescale
        guard durationSeconds.isFinite,
              durationSeconds >= 0,
              timeScale > 0 else {
            throw TAPDepthCaptureError.videoRecordingFailed(
                "runtime fixture track timing is invalid"
            )
        }
        return TAPVideoPlaybackFixtureTrackTiming(
            durationSeconds: durationSeconds,
            timeScale: timeScale
        )
    }
}

nonisolated private struct TAPVideoPlaybackFixtureTrackTiming: Sendable {
    let durationSeconds: Double
    let timeScale: Int32
}

@MainActor
struct TAPVideoPlaybackFixtureHarnessView: View {
    let configuration: TAPVideoPlaybackFixtureLaunchConfiguration

    @State private var phase = Phase.generating
    @State private var presentedArtifact: TAPVideoPlaybackFixtureArtifact?

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .generating:
                    ProgressView("Generating \(configuration.scenario.rawValue)")
                        .tint(.white)
                        .foregroundStyle(.white)
                        .accessibilityIdentifier("tap.video.fixture.generating")
                case .ready(let artifact):
                    VStack(spacing: 18) {
                        Label("Fixture ready", systemImage: "checkmark.circle.fill")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .accessibilityIdentifier("tap.video.fixture.ready")

                        Text(artifact.scenario.rawValue)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)

                        Button("Open fixture") {
                            presentedArtifact = artifact
                        }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("tap.video.fixture.open")
                    }
                case .failed(let message):
                    ContentUnavailableView(
                        "Fixture generation failed",
                        systemImage: "video.slash",
                        description: Text(message)
                    )
                    .foregroundStyle(.white)
                    .accessibilityIdentifier("tap.video.fixture.failed")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black.ignoresSafeArea())
            .navigationDestination(isPresented: isArtifactPresented) {
                if let presentedArtifact {
                    TAPVideoDepthPlaybackView(
                        source: .fixtureFile(
                            presentedArtifact.fileURL,
                            automaticSeekScheduleSeconds: configuration.seekScheduleSeconds
                                ?? presentedArtifact.specification.automaticSeekSeconds.map { [$0] }
                                ?? [],
                            autoPlay: configuration.autoPlay
                        ),
                        registrationAdapter: TAPVideoFixtureIdentityRegistrationAdapter()
                    )
                }
            }
        }
        .dynamicTypeSize(
            configuration.usesAccessibilityDynamicType ? .accessibility3 : .large
        )
        .task(id: configuration.scenario) {
            phase = .generating
            do {
                phase = .ready(
                    try await TAPVideoPlaybackFixtureGenerator.generate(
                        scenario: configuration.scenario
                    )
                )
            } catch is CancellationError {
                return
            } catch {
                phase = .failed("\((error as NSError).domain)(\((error as NSError).code))")
            }
        }
    }

    private var isArtifactPresented: Binding<Bool> {
        Binding(
            get: { presentedArtifact != nil },
            set: { isPresented in
                if !isPresented {
                    presentedArtifact = nil
                }
            }
        )
    }

    private enum Phase {
        case generating
        case ready(TAPVideoPlaybackFixtureArtifact)
        case failed(String)
    }
}
#endif
