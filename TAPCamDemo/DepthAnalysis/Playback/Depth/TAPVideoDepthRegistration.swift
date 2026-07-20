//
//  TAPVideoDepthRegistration.swift
//  TAPCamDemo
//

@preconcurrency import AVFoundation
import CoreImage
import ImageIO
import MetalKit
import SwiftUI
import UIKit

nonisolated enum TAPVideoDepthPlaybackBudget {
    static let maximumRetainedFrameBytes = 24 * 1024 * 1024
    static let maximumConcurrentDecodes = 2
    static let metadataAdvanceIntervalSeconds: TimeInterval = 0.5
    static let cacheLookBehindSeconds: TimeInterval = 0.25
    static let cacheLookAheadSeconds: TimeInterval = 0.75
    static let frameLeadToleranceSeconds: TimeInterval = 0.08
    static let failSafeFrameStaleToleranceSeconds: TimeInterval = 0.1
}

/// Pure policy for the bounded metadata probe used when playback is paused or
/// has just jumped. Keeping window selection independent from AVFoundation
/// makes the no-timer readiness contract deterministic and unit-testable.
nonisolated enum TAPVideoDepthMetadataProbePolicy {
    nonisolated struct Window: Equatable, Sendable {
        let startSeconds: TimeInterval
        let endSeconds: TimeInterval
    }

    static let maximumMetadataGroupCount = 256

    static func window(
        playbackTimeSeconds: TimeInterval,
        staleToleranceSeconds: TimeInterval,
        leadToleranceSeconds: TimeInterval,
        assetDurationSeconds: TimeInterval
    ) -> Window? {
        guard playbackTimeSeconds.isFinite,
              staleToleranceSeconds.isFinite,
              leadToleranceSeconds.isFinite,
              assetDurationSeconds.isFinite,
              playbackTimeSeconds >= 0,
              staleToleranceSeconds >= 0,
              leadToleranceSeconds >= 0,
              assetDurationSeconds > 0 else {
            return nil
        }
        let boundedPlayhead = min(playbackTimeSeconds, assetDurationSeconds)
        let start = max(0, boundedPlayhead - staleToleranceSeconds)
        let end = min(assetDurationSeconds, boundedPlayhead + leadToleranceSeconds)
        guard end > start else {
            return nil
        }
        return Window(startSeconds: start, endSeconds: end)
    }

    static func nearestCandidateIndex(
        timestamps: [TimeInterval],
        playbackTimeSeconds: TimeInterval,
        window: Window
    ) -> Int? {
        timestamps.indices
            .filter { index in
                let timestamp = timestamps[index]
                return timestamp.isFinite
                    && timestamp >= window.startSeconds
                    && timestamp <= window.endSeconds
            }
            .min { lhs, rhs in
                let lhsTimestamp = timestamps[lhs]
                let rhsTimestamp = timestamps[rhs]
                let lhsDistance = abs(lhsTimestamp - playbackTimeSeconds)
                let rhsDistance = abs(rhsTimestamp - playbackTimeSeconds)
                if lhsDistance != rhsDistance {
                    return lhsDistance < rhsDistance
                }
                return lhsTimestamp < rhsTimestamp
            }
    }
}

nonisolated enum TAPVideoDepthPipelineGenerationPolicy {
    static func accepts(eventGeneration: UInt64, currentGeneration: UInt64) -> Bool {
        eventGeneration == currentGeneration
    }
}

nonisolated enum TAPVideoDepthGapPolicy {
    static func staleToleranceSeconds(
        nominalDepthFrameIntervalSeconds: TimeInterval?
    ) -> TimeInterval {
        guard let nominalDepthFrameIntervalSeconds,
              nominalDepthFrameIntervalSeconds.isFinite,
              nominalDepthFrameIntervalSeconds > 0 else {
            return TAPVideoDepthPlaybackBudget.failSafeFrameStaleToleranceSeconds
        }
        return max(
            nominalDepthFrameIntervalSeconds * 2,
            TAPVideoDepthPlaybackBudget.failSafeFrameStaleToleranceSeconds
        )
    }
}

/// A transient gap during ordinary playback may reuse the last rendered depth
/// frame to avoid flashing the overlay. Timeline discontinuities must still
/// clear it so depth from an unrelated time is never shown over the RGB frame.
nonisolated enum TAPVideoDepthFrameHoldPolicy {
    nonisolated enum Context: Equatable, Sendable {
        case continuousPlaybackGap
        case discontinuity
    }

    static func shouldHoldLastFrame(
        hasDisplayedFrame: Bool,
        context: Context
    ) -> Bool {
        hasDisplayedFrame && context == .continuousPlaybackGap
    }
}

nonisolated enum TAPVideoDepthRegistrationMapping: String, Sendable {
    /// Debug fixture pixels are authored in the pre-transform RGB aperture.
    case preRegisteredRGBPresentation

    /// AVDepthData was delivered in the synchronized, lens-warped RGB grid;
    /// the signed descriptor fully defines scale, connection rotation, and
    /// clean-aperture projection into presentation coordinates.
    case avDepthDataWarpedToSynchronizedRGB
}

nonisolated enum TAPVideoRegisteredDepthAvailability: Equatable, Sendable {
    case checking
    case available(TAPVideoDepthRegistrationDescriptor)
    case unavailable

    var isAvailable: Bool {
        if case .available(let descriptor) = self {
            return descriptor.supportsRegisteredOverlay
        }
        return false
    }
}

nonisolated struct TAPVideoDepthRegistrationDescriptor: Equatable, Sendable {
    let schemaID: String
    let rgbPresentationWidth: Int
    let rgbPresentationHeight: Int
    let mapping: TAPVideoDepthRegistrationMapping
    let nominalDepthFrameIntervalSeconds: TimeInterval?
    let projection: TAPVideoRegistrationProjection?

    init(
        schemaID: String,
        rgbPresentationWidth: Int,
        rgbPresentationHeight: Int,
        mapping: TAPVideoDepthRegistrationMapping,
        nominalDepthFrameIntervalSeconds: TimeInterval? = nil,
        projection: TAPVideoRegistrationProjection? = nil
    ) {
        self.schemaID = schemaID
        self.rgbPresentationWidth = rgbPresentationWidth
        self.rgbPresentationHeight = rgbPresentationHeight
        self.mapping = mapping
        self.nominalDepthFrameIntervalSeconds = nominalDepthFrameIntervalSeconds
        self.projection = projection
    }

    var supportsRegisteredOverlay: Bool {
        guard rgbPresentationWidth > 0,
              rgbPresentationHeight > 0 else {
            return false
        }
        switch mapping {
        case .preRegisteredRGBPresentation:
            return projection == nil
        case .avDepthDataWarpedToSynchronizedRGB:
            return projection != nil
        }
    }
}

nonisolated struct TAPVideoRegistrationRect: Equatable, Sendable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double
}

nonisolated protocol TAPVideoDepthRegistrationAdapting: Sendable {
    func registrationDescriptor(
        for manifest: TAPVideoManifest
    ) -> TAPVideoDepthRegistrationDescriptor?
}

/// Production accepts only the versioned mapping emitted by the recorder and
/// revalidates every dimension, affine, transform, and aperture invariant.
/// The signed descriptor enables 2D registration. Per-frame metric camera
/// calibration is validated independently because it is optional for this
/// YUV-space overlay mapping.
nonisolated struct TAPVideoManifestDepthRegistrationAdapter: TAPVideoDepthRegistrationAdapting {
    private struct ConnectionTransform {
        let rotationDegrees: Int
        let isMirrored: Bool
    }

    private struct ValidatedDimensions {
        let depthWidth: Int
        let depthHeight: Int
        let alignedRGBWidth: Int
        let alignedRGBHeight: Int
        let encodedRGBWidth: Int
        let encodedRGBHeight: Int
        let presentationWidth: Int
        let presentationHeight: Int
    }

    func registrationDescriptor(
        for manifest: TAPVideoManifest
    ) -> TAPVideoDepthRegistrationDescriptor? {
        guard let signedDescriptor = Self.validatedSignedDescriptor(for: manifest),
              let connection = Self.validatedConnection(
                  descriptor: signedDescriptor,
                  rgbTrackTransform: manifest.payload.rgbTrack.transform
              ),
              let dimensions = Self.validatedDimensions(
                  descriptor: signedDescriptor,
                  manifest: manifest
              ),
              Self.hasValidProjectionGeometry(
                  descriptor: signedDescriptor,
                  connection: connection,
                  dimensions: dimensions
              ) else {
            return nil
        }
        return TAPVideoDepthRegistrationDescriptor(
            schemaID: signedDescriptor.schema,
            rgbPresentationWidth: dimensions.presentationWidth,
            rgbPresentationHeight: dimensions.presentationHeight,
            mapping: .avDepthDataWarpedToSynchronizedRGB,
            nominalDepthFrameIntervalSeconds: Self.nominalDepthInterval(manifest),
            projection: Self.makeProjection(
                descriptor: signedDescriptor,
                connection: connection,
                dimensions: dimensions
            )
        )
    }

    private static func validatedSignedDescriptor(
        for manifest: TAPVideoManifest
    ) -> TAPVideoManifest.RegistrationDescriptor? {
        let registration = manifest.payload.spatialRegistration
        guard registration.status == .registered,
              registration.mapping == TAPVideoManifest.RegistrationDescriptor.schemaID,
              let descriptor = registration.descriptor,
              descriptor.schema == TAPVideoManifest.RegistrationDescriptor.schemaID,
              descriptor.version == 1,
              descriptor.model == TAPVideoManifest.RegistrationDescriptor.mappingModel,
              descriptor.videoStabilizationMode == "off",
              registration.rgbReferenceDimensions == descriptor.alignedRGBCodedDimensions,
              registration.depthReferenceDimensions == descriptor.depthDimensions,
              registration.rgbCleanAperture == descriptor.rgbCleanAperture,
              registration.recordedTransform == descriptor.connectionTransform,
              registration.calibrationTable.count
                <= TAPVideoManifest.SpatialRegistration.maximumCalibrationCount,
              registration.calibrationTable.allSatisfy(Self.isValidCalibration) else {
            return nil
        }
        return descriptor
    }

    private static func validatedConnection(
        descriptor: TAPVideoManifest.RegistrationDescriptor,
        rgbTrackTransform: String?
    ) -> ConnectionTransform? {
        guard let connection = connectionTransform(
            from: descriptor.connectionTransform
        ),
        connection.isMirrored == descriptor.isEncodedHorizontallyMirrored,
        Self.rgbTrackTransform(
            rgbTrackTransform,
            matchesRotation: connection.rotationDegrees,
            isMirrored: connection.isMirrored
        ) else {
            return nil
        }
        return connection
    }

    private static func validatedDimensions(
        descriptor: TAPVideoManifest.RegistrationDescriptor,
        manifest: TAPVideoManifest
    ) -> ValidatedDimensions? {
        guard let depthWidth = integerDimension(descriptor.depthDimensions.width),
              let depthHeight = integerDimension(descriptor.depthDimensions.height),
              let alignedRGBWidth = integerDimension(
                  descriptor.alignedRGBCodedDimensions.width
              ),
              let alignedRGBHeight = integerDimension(
                  descriptor.alignedRGBCodedDimensions.height
              ),
              let encodedRGBWidth = integerDimension(
                  descriptor.encodedRGBCodedDimensions.width
              ),
              let encodedRGBHeight = integerDimension(
                  descriptor.encodedRGBCodedDimensions.height
              ),
              let presentationWidth = integerDimension(descriptor.rgbCleanAperture.width),
              let presentationHeight = integerDimension(descriptor.rgbCleanAperture.height),
              manifest.payload.depthCoverage.format?.width == Int32(depthWidth),
              manifest.payload.depthCoverage.format?.height == Int32(depthHeight),
              manifest.payload.rgbTrack.width == Int32(encodedRGBWidth),
              manifest.payload.rgbTrack.height == Int32(encodedRGBHeight) else {
            return nil
        }
        return ValidatedDimensions(
            depthWidth: depthWidth,
            depthHeight: depthHeight,
            alignedRGBWidth: alignedRGBWidth,
            alignedRGBHeight: alignedRGBHeight,
            encodedRGBWidth: encodedRGBWidth,
            encodedRGBHeight: encodedRGBHeight,
            presentationWidth: presentationWidth,
            presentationHeight: presentationHeight
        )
    }

    private static func hasValidProjectionGeometry(
        descriptor: TAPVideoManifest.RegistrationDescriptor,
        connection: ConnectionTransform,
        dimensions: ValidatedDimensions
    ) -> Bool {
        rotationMatchesDimensions(
            connection.rotationDegrees,
            alignedWidth: dimensions.alignedRGBWidth,
            alignedHeight: dimensions.alignedRGBHeight,
            encodedWidth: dimensions.encodedRGBWidth,
            encodedHeight: dimensions.encodedRGBHeight
        ) && isValidAperture(
            descriptor.rgbCleanAperture,
            encodedWidth: dimensions.encodedRGBWidth,
            encodedHeight: dimensions.encodedRGBHeight
        ) && isCanonicalScaleAffine(
            descriptor.depthToAlignedRGBPixelCenterAffine,
            depthWidth: dimensions.depthWidth,
            depthHeight: dimensions.depthHeight,
            alignedWidth: dimensions.alignedRGBWidth,
            alignedHeight: dimensions.alignedRGBHeight
        ) && hasMatchingAspectRatio(
            width: dimensions.depthWidth,
            height: dimensions.depthHeight,
            otherWidth: dimensions.alignedRGBWidth,
            otherHeight: dimensions.alignedRGBHeight
        )
    }

    private static func makeProjection(
        descriptor: TAPVideoManifest.RegistrationDescriptor,
        connection: ConnectionTransform,
        dimensions: ValidatedDimensions
    ) -> TAPVideoRegistrationProjection {
        TAPVideoRegistrationProjection(
            depthWidth: dimensions.depthWidth,
            depthHeight: dimensions.depthHeight,
            alignedRGBWidth: dimensions.alignedRGBWidth,
            alignedRGBHeight: dimensions.alignedRGBHeight,
            encodedRGBWidth: dimensions.encodedRGBWidth,
            encodedRGBHeight: dimensions.encodedRGBHeight,
            depthToAlignedRGBPixelCenterAffine:
                descriptor.depthToAlignedRGBPixelCenterAffine,
            connectionRotationDegrees: connection.rotationDegrees,
            isEncodedHorizontallyMirrored: connection.isMirrored,
            rgbCleanAperture: TAPVideoRegistrationRect(
                x: descriptor.rgbCleanAperture.x,
                y: descriptor.rgbCleanAperture.y,
                width: descriptor.rgbCleanAperture.width,
                height: descriptor.rgbCleanAperture.height
            )
        )
    }

    private static func nominalDepthInterval(_ manifest: TAPVideoManifest) -> TimeInterval? {
        manifest.payload.synchronization.nominalDepthIntervalSeconds.flatMap {
            $0.isFinite && $0 > 0 ? $0 : nil
        } ?? manifest.payload.rgbTrack.nominalFrameRate.flatMap {
            $0.isFinite && $0 > 0 ? 1 / $0 : nil
        }
    }

    private static func integerDimension(_ value: Double) -> Int? {
        guard value.isFinite,
              value > 0,
              value <= Double(Int32.max) else {
            return nil
        }
        let rounded = value.rounded()
        guard abs(value - rounded) <= 0.001 else {
            return nil
        }
        return Int(rounded)
    }

    private static func connectionTransform(
        from transform: String
    ) -> ConnectionTransform? {
        let components = transform.split(separator: ";", omittingEmptySubsequences: false)
            .map(String.init)
        guard components.count == 2,
              components[1] == "not-mirrored" || components[1] == "mirrored",
              components[0].hasPrefix("rotation:"),
              let rotation = Int(components[0].dropFirst("rotation:".count)),
              [0, 90, 180, 270].contains(rotation) else {
            return nil
        }
        return ConnectionTransform(
            rotationDegrees: rotation,
            isMirrored: components[1] == "mirrored"
        )
    }

    private static func rgbTrackTransform(
        _ transform: String?,
        matchesRotation expectedRotation: Int,
        isMirrored expectedMirroring: Bool
    ) -> Bool {
        guard let transform else {
            return expectedRotation == 0 && !expectedMirroring
        }
        if transform == "identity" {
            return expectedRotation == 0 && !expectedMirroring
        }
        let components = transform.split(separator: ";", omittingEmptySubsequences: false)
        let expectedCount = expectedMirroring ? 2 : 1
        guard components.count == expectedCount,
              let rotationComponent = components.first,
              rotationComponent.hasPrefix("rotation:"),
              let rotation = Int(rotationComponent.dropFirst("rotation:".count)) else {
            return false
        }
        if expectedMirroring,
           components[1] != "mirrored" {
            return false
        }
        return ((rotation % 360) + 360) % 360 == expectedRotation
    }

    private static func rotationMatchesDimensions(
        _ rotation: Int,
        alignedWidth: Int,
        alignedHeight: Int,
        encodedWidth: Int,
        encodedHeight: Int
    ) -> Bool {
        if rotation == 90 || rotation == 270 {
            return alignedWidth == encodedHeight && alignedHeight == encodedWidth
        }
        return alignedWidth == encodedWidth && alignedHeight == encodedHeight
    }

    private static func isValidAperture(
        _ aperture: TAPVideoManifest.Rect,
        encodedWidth: Int,
        encodedHeight: Int
    ) -> Bool {
        aperture.x.isFinite
            && aperture.y.isFinite
            && aperture.width.isFinite
            && aperture.height.isFinite
            && aperture.x >= 0
            && aperture.y >= 0
            && aperture.width > 0
            && aperture.height > 0
            && aperture.x + aperture.width <= Double(encodedWidth) + 0.001
            && aperture.y + aperture.height <= Double(encodedHeight) + 0.001
    }

    private static func isCanonicalScaleAffine(
        _ affine: [Double],
        depthWidth: Int,
        depthHeight: Int,
        alignedWidth: Int,
        alignedHeight: Int
    ) -> Bool {
        guard affine.count == 6,
              affine.allSatisfy(\.isFinite) else {
            return false
        }
        let scaleX = Double(alignedWidth) / Double(depthWidth)
        let scaleY = Double(alignedHeight) / Double(depthHeight)
        let expected = [
            scaleX, 0, 0.5 * scaleX - 0.5,
            0, scaleY, 0.5 * scaleY - 0.5
        ]
        return zip(affine, expected).allSatisfy { actual, expected in
            abs(actual - expected) <= max(1, abs(expected)) * 0.000_001
        }
    }

    private static func hasMatchingAspectRatio(
        width: Int,
        height: Int,
        otherWidth: Int,
        otherHeight: Int
    ) -> Bool {
        let lhs = Double(width) / Double(height)
        let rhs = Double(otherWidth) / Double(otherHeight)
        return abs(lhs - rhs) / max(lhs, rhs) <= 0.005
    }

    private static func isValidCalibration(
        _ calibration: TAPVideoManifest.CameraCalibration
    ) -> Bool {
        calibration.intrinsicMatrix.count == 9
            && calibration.extrinsicMatrix.count == 12
            && calibration.intrinsicMatrix.allSatisfy(\.isFinite)
            && calibration.extrinsicMatrix.allSatisfy(\.isFinite)
            && calibration.pixelSizeMillimeters.isFinite
            && calibration.pixelSizeMillimeters > 0
            && calibration.intrinsicMatrixReferenceDimensions.width.isFinite
            && calibration.intrinsicMatrixReferenceDimensions.height.isFinite
            && calibration.intrinsicMatrixReferenceDimensions.width > 0
            && calibration.intrinsicMatrixReferenceDimensions.height > 0
            && calibration.lensDistortionCenter.x.isFinite
            && calibration.lensDistortionCenter.y.isFinite
    }
}

#if DEBUG
/// Debug fixtures may opt into the playback pipeline only when their depth
/// frames were authored directly in the RGB presentation pixel grid.
nonisolated struct TAPVideoFixtureIdentityRegistrationAdapter: TAPVideoDepthRegistrationAdapting {
    static let mappingIdentifier = "fixture:pre-registered-rgb-presentation:v1"

    func registrationDescriptor(
        for manifest: TAPVideoManifest
    ) -> TAPVideoDepthRegistrationDescriptor? {
        let registration = manifest.payload.spatialRegistration
        guard registration.status == .registered,
              registration.mapping == Self.mappingIdentifier,
              let rgbDimensions = registration.rgbReferenceDimensions,
              let depthDimensions = registration.depthReferenceDimensions,
              let cleanAperture = registration.rgbCleanAperture,
              let recordedTransform = registration.recordedTransform,
              !recordedTransform.isEmpty,
              rgbDimensions.width.isFinite,
              rgbDimensions.height.isFinite,
              rgbDimensions.width > 0,
              rgbDimensions.height > 0,
              rgbDimensions == depthDimensions,
              cleanAperture.width == rgbDimensions.width,
              cleanAperture.height == rgbDimensions.height,
              let depthFormat = manifest.payload.depthCoverage.format,
              Double(depthFormat.width) == depthDimensions.width,
              Double(depthFormat.height) == depthDimensions.height else {
            return nil
        }
        let nominalDepthInterval = manifest.payload.synchronization
            .nominalDepthIntervalSeconds
            .flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
            ?? manifest.payload.rgbTrack.nominalFrameRate.flatMap {
                $0.isFinite && $0 > 0 ? 1 / $0 : nil
            }
        return TAPVideoDepthRegistrationDescriptor(
            schemaID: "urn:tapnap:tapcam:video-depth-registration:fixture-identity",
            rgbPresentationWidth: Int(rgbDimensions.width),
            rgbPresentationHeight: Int(rgbDimensions.height),
            mapping: .preRegisteredRGBPresentation,
            nominalDepthFrameIntervalSeconds: nominalDepthInterval
        )
    }
}
#endif
