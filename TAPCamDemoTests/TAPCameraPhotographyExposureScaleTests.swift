//
//  TAPCameraPhotographyExposureScaleTests.swift
//  TAPCamDemoTests
//

import Testing
@testable import TAPCamDemo

struct TAPCameraPhotographyExposureScaleTests {
    @Test func isoScaleUsesDeviceClippedThirdStopValues() {
        let scale = CameraPhotographyExposureScale.iso(in: 64...1_250)

        #expect(scale.stops.map(\.value) == [
            64, 80, 100, 125, 160, 200, 250,
            320, 400, 500, 640, 800, 1_000, 1_250,
        ])
        #expect(scale.stops.filter(\.isMajor).map(\.value) == [
            100, 200, 400, 800,
        ])
        #expect(scale.snappedValue(for: 118) == 125)
        #expect(scale.label(for: 118) == "125")
        #expect(scale.isAdjustable)
    }

    @Test func shutterScaleUsesConventionalLabelsAndLogarithmicSnapping() {
        let scale = CameraPhotographyExposureScale.shutterDuration(
            in: (1.0 / 8_000.0)...0.5
        )

        #expect(scale.stops.first?.label == "1/8000")
        #expect(scale.stops.last?.label == "0.5\"")
        #expect(abs(scale.snappedValue(for: 1.0 / 120.0) - 1.0 / 125.0) < 0.000_001)
        #expect(scale.label(for: 1.0 / 120.0) == "1/125")

        let position = scale.position(for: 1.0 / 60.0)
        #expect(abs(scale.value(at: position) - 1.0 / 60.0) < 0.000_001)
        #expect(scale.majorTickIndices.contains(Int(position)))
    }

    @Test func narrowUnsupportedRangeDoesNotInventAnAdjustableControl() {
        let scale = CameraPhotographyExposureScale.iso(in: 70...75)

        #expect(scale.stops.isEmpty)
        #expect(scale.positionRange == 0...0)
        #expect(!scale.isAdjustable)
        #expect(scale.label(for: 73) == "--")
        #expect(scale.snappedValue(for: 73) == 73)
    }

    @Test func oneCanonicalStopIsStillNotPresentedAsAnAdjustableScale() {
        let scale = CameraPhotographyExposureScale.iso(in: 99...101)

        #expect(scale.stops.map(\.label) == ["100"])
        #expect(!scale.isAdjustable)
        #expect(scale.label(for: 100) == "--")
        #expect(scale.snappedValue(for: 100.5) == 100.5)
    }

    @Test func riskRangesCoverOnlySelectableStopsAndRemainVisible() {
        let scale = CameraPhotographyExposureScale.iso(in: 64...1_250)

        #expect(scale.positionRanges(for: [110...170]) == [2.5...4.5])
        #expect(scale.positionRanges(for: [120...130]) == [2.5...3.5])
        #expect(scale.positionRanges(for: [101...110]).isEmpty)
        #expect(
            scale.positionRanges(for: [110...130, 150...170])
                == [2.5...4.5]
        )
    }

    @Test func nominalBoundaryStopsSurviveTinyHardwareRoundingDifferences() {
        let nominalMinimum = 1.0 / 8_000.0
        let shutterMinimum = nominalMinimum.nextUp
        let shutterMaximum = 0.5.nextDown
        let shutterScale = CameraPhotographyExposureScale.shutterDuration(
            in: shutterMinimum...shutterMaximum
        )
        let isoMinimum = 64.0.nextUp
        let isoMaximum = 1_250.0.nextDown
        let isoScale = CameraPhotographyExposureScale.iso(
            in: isoMinimum...isoMaximum
        )

        #expect(shutterScale.stops.first?.label == "1/8000")
        #expect(shutterScale.stops.first?.value == shutterMinimum)
        #expect(shutterScale.stops.last?.label == "0.5\"")
        #expect(shutterScale.stops.last?.value == shutterMaximum)
        #expect(isoScale.stops.first?.label == "64")
        #expect(isoScale.stops.first?.value == isoMinimum)
        #expect(isoScale.stops.last?.label == "1250")
        #expect(isoScale.stops.last?.value == isoMaximum)
    }

    @Test func scalesStayStrictlyIncreasingAndUseConventionalSlowShutterLabels() {
        let isoScale = CameraPhotographyExposureScale.iso(in: 6...204_800)
        let shutterScale = CameraPhotographyExposureScale.shutterDuration(
            in: (1.0 / 32_000.0)...1
        )

        #expect(zip(isoScale.stops, isoScale.stops.dropFirst()).allSatisfy { pair in
            pair.0.value < pair.1.value
        })
        #expect(zip(shutterScale.stops, shutterScale.stops.dropFirst()).allSatisfy { pair in
            pair.0.value < pair.1.value
        })
        #expect(Set(isoScale.stops.map(\.value)).count == isoScale.stops.count)
        #expect(Set(shutterScale.stops.map(\.value)).count == shutterScale.stops.count)
        #expect(
            shutterScale.stops
                .filter { $0.value >= 0.25 }
                .prefix(6)
                .map(\.label)
                == ["1/4", "0.3\"", "0.4\"", "0.5\"", "0.6\"", "0.8\""]
        )
    }
}
