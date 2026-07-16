//
//  TAPVideoPlaybackFixtureSpecification.swift
//  TAPCamDemo
//

#if DEBUG
import CoreGraphics
import Foundation

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
#endif
