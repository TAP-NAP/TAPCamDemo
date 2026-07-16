//
//  TAPVideoSpatialRegistrationAssembler.swift
//  TAPCamDemo
//

@preconcurrency import AVFoundation
import CoreGraphics
import CoreMedia
import Foundation

nonisolated enum TAPVideoRecordingTransform {
    static func description(
        metrics: TAPVideoRecordingMetrics,
        request: TAPVideoRecordingRequest
    ) -> String? {
        let angle = metrics.appliedVideoRotationAngle ?? request.videoRotationAngle
        guard let angle else {
            return nil
        }
        return metrics.appliedVideoMirrored
            ? "rotation:\(Int(angle));mirrored"
            : "rotation:\(Int(angle))"
    }

    static func normalizedQuarterTurn(_ angle: CGFloat?) -> Int {
        guard let angle, angle.isFinite else {
            return 0
        }
        let normalized = ((Int(angle.rounded()) % 360) + 360) % 360
        return [0, 90, 180, 270].contains(normalized) ? normalized : -1
    }
}

/// Pure spatial-registration policy over immutable recording facts.
nonisolated enum TAPVideoSpatialRegistrationAssembler {
    static func make(
        fileFacts: TAPMediaTrackFacts,
        metrics: TAPVideoRecordingMetrics,
        request: TAPVideoRecordingRequest
    ) -> TAPVideoManifest.SpatialRegistration {
        guard metrics.depthSampleCount > 0,
              let depthFormat = metrics.firstDepthFormat,
              let videoFormat = metrics.firstVideoFormatDescription else {
            return .unavailable
        }
        let calibration = metrics.depthCalibrationTable.entries.first
        let calibrationCoverage = TAPVideoManifest.CalibrationCoverage(
            indexedSampleCount: metrics.depthSamplesWithCalibrationIndex,
            missingCalibrationSampleCount: metrics.depthSamplesMissingCalibration,
            overflowUnindexedSampleCount: metrics.depthSamplesWithUnindexedCalibration,
            tableOverflowed: metrics.depthCalibrationTable.didOverflow
        )
        let cleanAperture = CMVideoFormatDescriptionGetCleanAperture(
            videoFormat,
            originIsAtTopLeft: true
        )
        let encodedDimensions = TAPVideoManifest.Dimensions(
            width: Double(fileFacts.video.width),
            height: Double(fileFacts.video.height)
        )
        let normalizedRotation = TAPVideoRecordingTransform.normalizedQuarterTurn(
            metrics.appliedVideoRotationAngle
        )
        let alignedDimensions = alignedDimensions(
            encodedDimensions,
            rotation: normalizedRotation
        )
        let depthDimensions = TAPVideoManifest.Dimensions(
            width: Double(depthFormat.width),
            height: Double(depthFormat.height)
        )
        let cleanApertureValue = TAPVideoManifest.Rect(
            x: cleanAperture.origin.x,
            y: cleanAperture.origin.y,
            width: cleanAperture.width,
            height: cleanAperture.height
        )
        let connectionTransform = metrics.appliedVideoMirrored
            ? "rotation:\(normalizedRotation);mirrored"
            : "rotation:\(normalizedRotation);not-mirrored"
        let failures = registrationFailures(
            metrics: metrics,
            normalizedRotation: normalizedRotation,
            encodedDimensions: encodedDimensions,
            alignedDimensions: alignedDimensions,
            depthDimensions: depthDimensions,
            cleanAperture: cleanApertureValue
        )
        guard failures.isEmpty else {
            return unavailableRegistration(
                failures: failures,
                metrics: metrics,
                request: request,
                alignedDimensions: alignedDimensions,
                depthDimensions: depthDimensions,
                cleanAperture: cleanApertureValue,
                connectionTransform: connectionTransform,
                calibration: calibration,
                calibrationCoverage: calibrationCoverage
            )
        }
        return registeredRegistration(
            metrics: metrics,
            encodedDimensions: encodedDimensions,
            alignedDimensions: alignedDimensions,
            depthDimensions: depthDimensions,
            cleanAperture: cleanApertureValue,
            connectionTransform: connectionTransform,
            calibration: calibration,
            calibrationCoverage: calibrationCoverage
        )
    }

    private static func alignedDimensions(
        _ encoded: TAPVideoManifest.Dimensions,
        rotation: Int
    ) -> TAPVideoManifest.Dimensions {
        guard rotation == 90 || rotation == 270 else {
            return encoded
        }
        return TAPVideoManifest.Dimensions(
            width: encoded.height,
            height: encoded.width
        )
    }

    private static func registrationFailures(
        metrics: TAPVideoRecordingMetrics,
        normalizedRotation: Int,
        encodedDimensions: TAPVideoManifest.Dimensions,
        alignedDimensions: TAPVideoManifest.Dimensions,
        depthDimensions: TAPVideoManifest.Dimensions,
        cleanAperture: TAPVideoManifest.Rect
    ) -> [String] {
        synchronizationFailures(metrics: metrics)
            + connectionFailures(
                metrics: metrics,
                normalizedRotation: normalizedRotation
            )
            + geometryFailures(
                encodedDimensions: encodedDimensions,
                alignedDimensions: alignedDimensions,
                depthDimensions: depthDimensions,
                cleanAperture: cleanAperture
            )
    }

    private static func synchronizationFailures(
        metrics: TAPVideoRecordingMetrics
    ) -> [String] {
        var failures: [String] = []
        if !metrics.usesSynchronizedRGBDepthOutput { failures.append("not-synchronized") }
        if !metrics.observedSynchronizedRGBDepthPair { failures.append("no-rgb-depth-pair") }
        if metrics.maxObservedRGBDepthDeltaSeconds == nil { failures.append("missing-sync-delta") }
        if metrics.depthFormatChanged { failures.append("depth-format-changed") }
        return failures
    }

    private static func connectionFailures(
        metrics: TAPVideoRecordingMetrics,
        normalizedRotation: Int
    ) -> [String] {
        var failures: [String] = []
        if !metrics.observedDepthConnectionConfiguration {
            failures.append("depth-connection-unobserved")
        }
        if normalizedRotation < 0 { failures.append("unsupported-rgb-rotation") }
        if metrics.appliedDepthMirrored { failures.append("depth-mirrored") }
        if TAPVideoRecordingTransform.normalizedQuarterTurn(metrics.appliedDepthRotationAngle) != 0 {
            failures.append("depth-rotated")
        }
        if metrics.appliedVideoStabilizationMode != .off { failures.append("rgb-stabilized") }
        return failures
    }

    private static func geometryFailures(
        encodedDimensions: TAPVideoManifest.Dimensions,
        alignedDimensions: TAPVideoManifest.Dimensions,
        depthDimensions: TAPVideoManifest.Dimensions,
        cleanAperture: TAPVideoManifest.Rect
    ) -> [String] {
        var failures: [String] = []
        if cleanAperture.width <= 0 || cleanAperture.height <= 0 {
            failures.append("invalid-clean-aperture")
        }
        if !isValid(encodedDimensions) { failures.append("invalid-encoded-dimensions") }
        if !isValid(alignedDimensions) { failures.append("invalid-aligned-dimensions") }
        if !isValid(depthDimensions) { failures.append("invalid-depth-dimensions") }
        if !isContained(cleanAperture, in: encodedDimensions) {
            failures.append("clean-aperture-outside-rgb")
        }
        if !hasMatchingAspectRatio(depthDimensions, alignedDimensions) {
            failures.append("rgb-depth-aspect-mismatch")
        }
        return failures
    }

    private static func unavailableRegistration(
        failures: [String],
        metrics: TAPVideoRecordingMetrics,
        request: TAPVideoRecordingRequest,
        alignedDimensions: TAPVideoManifest.Dimensions,
        depthDimensions: TAPVideoManifest.Dimensions,
        cleanAperture: TAPVideoManifest.Rect,
        connectionTransform: String,
        calibration: TAPVideoManifest.CameraCalibration?,
        calibrationCoverage: TAPVideoManifest.CalibrationCoverage
    ) -> TAPVideoManifest.SpatialRegistration {
        TAPVideoManifest.SpatialRegistration(
            status: .unavailable,
            mapping: "avdepthdata-registration-prerequisites-unavailable:"
                + failures.joined(separator: ","),
            rgbReferenceDimensions: alignedDimensions,
            depthReferenceDimensions: depthDimensions,
            rgbCleanAperture: cleanAperture,
            recordedTransform: TAPVideoRecordingTransform.description(
                metrics: metrics,
                request: request
            ) ?? connectionTransform,
            calibration: calibration,
            calibrationTable: metrics.depthCalibrationTable.entries,
            calibrationCoverage: calibrationCoverage,
            descriptor: nil
        )
    }

    private static func registeredRegistration(
        metrics: TAPVideoRecordingMetrics,
        encodedDimensions: TAPVideoManifest.Dimensions,
        alignedDimensions: TAPVideoManifest.Dimensions,
        depthDimensions: TAPVideoManifest.Dimensions,
        cleanAperture: TAPVideoManifest.Rect,
        connectionTransform: String,
        calibration: TAPVideoManifest.CameraCalibration?,
        calibrationCoverage: TAPVideoManifest.CalibrationCoverage
    ) -> TAPVideoManifest.SpatialRegistration {
        let scaleX = alignedDimensions.width / depthDimensions.width
        let scaleY = alignedDimensions.height / depthDimensions.height
        let descriptor = TAPVideoManifest.RegistrationDescriptor(
            alignedRGBCodedDimensions: alignedDimensions,
            encodedRGBCodedDimensions: encodedDimensions,
            depthDimensions: depthDimensions,
            depthToAlignedRGBPixelCenterAffine: [
                scaleX, 0, 0.5 * scaleX - 0.5,
                0, scaleY, 0.5 * scaleY - 0.5
            ],
            connectionTransform: connectionTransform,
            isEncodedHorizontallyMirrored: metrics.appliedVideoMirrored,
            rgbCleanAperture: cleanAperture,
            videoStabilizationMode: "off"
        )
        return TAPVideoManifest.SpatialRegistration(
            status: .registered,
            mapping: TAPVideoManifest.RegistrationDescriptor.schemaID,
            rgbReferenceDimensions: alignedDimensions,
            depthReferenceDimensions: depthDimensions,
            rgbCleanAperture: cleanAperture,
            recordedTransform: connectionTransform,
            calibration: calibration,
            calibrationTable: metrics.depthCalibrationTable.entries,
            calibrationCoverage: calibrationCoverage,
            descriptor: descriptor
        )
    }

    private static func isValid(
        _ dimensions: TAPVideoManifest.Dimensions
    ) -> Bool {
        dimensions.width.isFinite
            && dimensions.height.isFinite
            && dimensions.width > 0
            && dimensions.height > 0
    }

    private static func isContained(
        _ rect: TAPVideoManifest.Rect,
        in dimensions: TAPVideoManifest.Dimensions
    ) -> Bool {
        rect.x.isFinite
            && rect.y.isFinite
            && rect.width.isFinite
            && rect.height.isFinite
            && rect.x >= 0
            && rect.y >= 0
            && rect.width > 0
            && rect.height > 0
            && rect.x + rect.width <= dimensions.width + 0.001
            && rect.y + rect.height <= dimensions.height + 0.001
    }

    private static func hasMatchingAspectRatio(
        _ lhs: TAPVideoManifest.Dimensions,
        _ rhs: TAPVideoManifest.Dimensions
    ) -> Bool {
        let lhsAspect = lhs.width / lhs.height
        let rhsAspect = rhs.width / rhs.height
        return abs(lhsAspect - rhsAspect) / max(lhsAspect, rhsAspect) <= 0.005
    }
}
