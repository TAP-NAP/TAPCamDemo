//
//  TAPVideoDepthPlaybackSupport.swift
//  TAPCamDemo
//

@preconcurrency import AVFoundation
import AVKit
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

/// A validated, renderer-reproducible projection. Coordinates are pixel-center
/// coordinates with a top-left origin, matching AVDepthData and clean aperture
/// metadata. The production adapter is the sole constructor from a manifest.
nonisolated struct TAPVideoRegistrationProjection: Equatable, Sendable {
    let depthWidth: Int
    let depthHeight: Int
    let alignedRGBWidth: Int
    let alignedRGBHeight: Int
    let encodedRGBWidth: Int
    let encodedRGBHeight: Int
    let depthToAlignedRGBPixelCenterAffine: [Double]
    let connectionRotationDegrees: Int
    let isEncodedHorizontallyMirrored: Bool
    let rgbCleanAperture: TAPVideoRegistrationRect

    func projectDepthPixelCenter(x: Double, y: Double) -> CGPoint? {
        guard x.isFinite,
              y.isFinite,
              depthToAlignedRGBPixelCenterAffine.count == 6 else {
            return nil
        }
        let affine = depthToAlignedRGBPixelCenterAffine
        let alignedX = affine[0] * x + affine[1] * y + affine[2]
        let alignedY = affine[3] * x + affine[4] * y + affine[5]
        let rotatedPoint: CGPoint
        switch connectionRotationDegrees {
        case 0:
            rotatedPoint = CGPoint(x: alignedX, y: alignedY)
        case 90:
            rotatedPoint = CGPoint(
                x: Double(alignedRGBHeight - 1) - alignedY,
                y: alignedX
            )
        case 180:
            rotatedPoint = CGPoint(
                x: Double(alignedRGBWidth - 1) - alignedX,
                y: Double(alignedRGBHeight - 1) - alignedY
            )
        case 270:
            rotatedPoint = CGPoint(
                x: alignedY,
                y: Double(alignedRGBWidth - 1) - alignedX
            )
        default:
            return nil
        }
        let encodedPoint = isEncodedHorizontallyMirrored
            ? CGPoint(
                x: Double(encodedRGBWidth - 1) - rotatedPoint.x,
                y: rotatedPoint.y
            )
            : rotatedPoint
        return CGPoint(
            x: encodedPoint.x - rgbCleanAperture.x,
            y: encodedPoint.y - rgbCleanAperture.y
        )
    }
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
    func registrationDescriptor(
        for manifest: TAPVideoManifest
    ) -> TAPVideoDepthRegistrationDescriptor? {
        let registration = manifest.payload.spatialRegistration
        guard registration.status == .registered,
              registration.mapping == TAPVideoManifest.RegistrationDescriptor.schemaID,
              let signedDescriptor = registration.descriptor,
              signedDescriptor.schema == TAPVideoManifest.RegistrationDescriptor.schemaID,
              signedDescriptor.version == 1,
              signedDescriptor.model == TAPVideoManifest.RegistrationDescriptor.mappingModel,
              signedDescriptor.videoStabilizationMode == "off",
              registration.rgbReferenceDimensions == signedDescriptor.alignedRGBCodedDimensions,
              registration.depthReferenceDimensions == signedDescriptor.depthDimensions,
              registration.rgbCleanAperture == signedDescriptor.rgbCleanAperture,
              registration.recordedTransform == signedDescriptor.connectionTransform,
              registration.calibrationTable.count
                <= TAPVideoManifest.SpatialRegistration.maximumCalibrationCount,
              registration.calibrationTable.allSatisfy(Self.isValidCalibration),
              let connection = Self.connectionTransform(
                  from: signedDescriptor.connectionTransform
              ),
              connection.isMirrored == signedDescriptor.isEncodedHorizontallyMirrored,
              Self.rgbTrackTransform(
                  manifest.payload.rgbTrack.transform,
                  matchesRotation: connection.rotationDegrees,
                  isMirrored: connection.isMirrored
              ),
              let depthWidth = Self.integerDimension(signedDescriptor.depthDimensions.width),
              let depthHeight = Self.integerDimension(signedDescriptor.depthDimensions.height),
              let alignedRGBWidth = Self.integerDimension(
                  signedDescriptor.alignedRGBCodedDimensions.width
              ),
              let alignedRGBHeight = Self.integerDimension(
                  signedDescriptor.alignedRGBCodedDimensions.height
              ),
              let encodedRGBWidth = Self.integerDimension(
                  signedDescriptor.encodedRGBCodedDimensions.width
              ),
              let encodedRGBHeight = Self.integerDimension(
                  signedDescriptor.encodedRGBCodedDimensions.height
              ),
              manifest.payload.depthCoverage.format?.width == Int32(depthWidth),
              manifest.payload.depthCoverage.format?.height == Int32(depthHeight),
              manifest.payload.rgbTrack.width == Int32(encodedRGBWidth),
              manifest.payload.rgbTrack.height == Int32(encodedRGBHeight),
              Self.rotationMatchesDimensions(
                  connection.rotationDegrees,
                  alignedWidth: alignedRGBWidth,
                  alignedHeight: alignedRGBHeight,
                  encodedWidth: encodedRGBWidth,
                  encodedHeight: encodedRGBHeight
              ),
              Self.isValidAperture(
                  signedDescriptor.rgbCleanAperture,
                  encodedWidth: encodedRGBWidth,
                  encodedHeight: encodedRGBHeight
              ),
              Self.isCanonicalScaleAffine(
                  signedDescriptor.depthToAlignedRGBPixelCenterAffine,
                  depthWidth: depthWidth,
                  depthHeight: depthHeight,
                  alignedWidth: alignedRGBWidth,
                  alignedHeight: alignedRGBHeight
              ),
              Self.hasMatchingAspectRatio(
                  width: depthWidth,
                  height: depthHeight,
                  otherWidth: alignedRGBWidth,
                  otherHeight: alignedRGBHeight
              ),
              let presentationWidth = Self.integerDimension(
                  signedDescriptor.rgbCleanAperture.width
              ),
              let presentationHeight = Self.integerDimension(
                  signedDescriptor.rgbCleanAperture.height
              ) else {
            return nil
        }
        let projection = TAPVideoRegistrationProjection(
            depthWidth: depthWidth,
            depthHeight: depthHeight,
            alignedRGBWidth: alignedRGBWidth,
            alignedRGBHeight: alignedRGBHeight,
            encodedRGBWidth: encodedRGBWidth,
            encodedRGBHeight: encodedRGBHeight,
            depthToAlignedRGBPixelCenterAffine: signedDescriptor.depthToAlignedRGBPixelCenterAffine,
            connectionRotationDegrees: connection.rotationDegrees,
            isEncodedHorizontallyMirrored: connection.isMirrored,
            rgbCleanAperture: TAPVideoRegistrationRect(
                x: signedDescriptor.rgbCleanAperture.x,
                y: signedDescriptor.rgbCleanAperture.y,
                width: signedDescriptor.rgbCleanAperture.width,
                height: signedDescriptor.rgbCleanAperture.height
            )
        )
        return TAPVideoDepthRegistrationDescriptor(
            schemaID: signedDescriptor.schema,
            rgbPresentationWidth: presentationWidth,
            rgbPresentationHeight: presentationHeight,
            mapping: .avDepthDataWarpedToSynchronizedRGB,
            nominalDepthFrameIntervalSeconds: Self.nominalDepthInterval(manifest),
            projection: projection
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
    ) -> (rotationDegrees: Int, isMirrored: Bool)? {
        let components = transform.split(separator: ";", omittingEmptySubsequences: false)
            .map(String.init)
        guard components.count == 2,
              components[1] == "not-mirrored" || components[1] == "mirrored",
              components[0].hasPrefix("rotation:"),
              let rotation = Int(components[0].dropFirst("rotation:".count)),
              [0, 90, 180, 270].contains(rotation) else {
            return nil
        }
        return (rotation, components[1] == "mirrored")
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

@MainActor
struct TAPVideoRegisteredDepthOverlay {
    let image: UIImage
    let registrationDescriptor: TAPVideoDepthRegistrationDescriptor
}

@MainActor
protocol TAPVideoDepthOverlaySink: AnyObject {
    func setRegisteredDepthOverlay(_ overlay: TAPVideoRegisteredDepthOverlay?)
}

@MainActor
final class TAPVideoDepthOverlayStore {
    private weak var sink: (any TAPVideoDepthOverlaySink)?
    private(set) var overlay: TAPVideoRegisteredDepthOverlay?

    func attach(_ sink: any TAPVideoDepthOverlaySink) {
        self.sink = sink
        sink.setRegisteredDepthOverlay(overlay)
    }

    func detach(_ sink: any TAPVideoDepthOverlaySink) {
        guard self.sink === sink else {
            return
        }
        self.sink = nil
    }

    func present(
        _ image: UIImage,
        registrationDescriptor: TAPVideoDepthRegistrationDescriptor
    ) {
        let overlay = TAPVideoRegisteredDepthOverlay(
            image: image,
            registrationDescriptor: registrationDescriptor
        )
        self.overlay = overlay
        sink?.setRegisteredDepthOverlay(overlay)
    }

    func clear() {
        overlay = nil
        sink?.setRegisteredDepthOverlay(nil)
    }
}

@MainActor
final class TAPVideoDepthFrameCache {
    let maximumRetainedBytes: Int
    let lookBehindSeconds: TimeInterval
    let lookAheadSeconds: TimeInterval

    private(set) var frames: [TAPDecodedDepthVideoFrame] = []
    private(set) var retainedByteCount = 0

    init(
        maximumRetainedBytes: Int = TAPVideoDepthPlaybackBudget.maximumRetainedFrameBytes,
        lookBehindSeconds: TimeInterval = TAPVideoDepthPlaybackBudget.cacheLookBehindSeconds,
        lookAheadSeconds: TimeInterval = TAPVideoDepthPlaybackBudget.cacheLookAheadSeconds
    ) {
        self.maximumRetainedBytes = min(
            max(0, maximumRetainedBytes),
            TAPVideoDepthPlaybackBudget.maximumRetainedFrameBytes
        )
        self.lookBehindSeconds = max(0, lookBehindSeconds)
        self.lookAheadSeconds = max(0, lookAheadSeconds)
    }

    @discardableResult
    func insert(_ frame: TAPDecodedDepthVideoFrame, around playbackTimeSeconds: Double) -> Bool {
        guard frame.retainedByteCount > 0,
              frame.retainedByteCount <= maximumRetainedBytes else {
            return false
        }

        if let duplicateIndex = frames.firstIndex(where: { $0.cacheMatches(frame) }) {
            retainedByteCount -= frames[duplicateIndex].retainedByteCount
            frames.remove(at: duplicateIndex)
        }
        frames.append(frame)
        retainedByteCount += frame.retainedByteCount
        prune(around: playbackTimeSeconds)

        while retainedByteCount > maximumRetainedBytes,
              let evictionIndex = farthestFrameIndex(from: playbackTimeSeconds) {
            retainedByteCount -= frames[evictionIndex].retainedByteCount
            frames.remove(at: evictionIndex)
        }
        frames.sort { $0.presentationTimeSeconds < $1.presentationTimeSeconds }
        return frames.contains(where: { $0.cacheMatches(frame) })
    }

    func nearestFrame(
        to playbackTimeSeconds: Double,
        staleToleranceSeconds: TimeInterval = TAPVideoDepthPlaybackBudget.failSafeFrameStaleToleranceSeconds,
        leadToleranceSeconds: TimeInterval = TAPVideoDepthPlaybackBudget.frameLeadToleranceSeconds
    ) -> TAPDecodedDepthVideoFrame? {
        let earliest = playbackTimeSeconds - max(0, staleToleranceSeconds)
        let latest = playbackTimeSeconds + max(0, leadToleranceSeconds)
        return frames
            .filter { frame in
                frame.presentationTimeSeconds >= earliest
                    && frame.presentationTimeSeconds <= latest
            }
            .min { lhs, rhs in
                abs(lhs.presentationTimeSeconds - playbackTimeSeconds)
                    < abs(rhs.presentationTimeSeconds - playbackTimeSeconds)
            }
    }

    func prune(around playbackTimeSeconds: Double) {
        guard playbackTimeSeconds.isFinite else {
            clear()
            return
        }
        let earliest = playbackTimeSeconds - lookBehindSeconds
        let latest = playbackTimeSeconds + lookAheadSeconds
        frames.removeAll { frame in
            let shouldRemove = frame.presentationTimeSeconds < earliest
                || frame.presentationTimeSeconds > latest
            if shouldRemove {
                retainedByteCount -= frame.retainedByteCount
            }
            return shouldRemove
        }
        retainedByteCount = max(0, retainedByteCount)
    }

    func clear() {
        frames.removeAll(keepingCapacity: false)
        retainedByteCount = 0
    }

    private func farthestFrameIndex(from playbackTimeSeconds: Double) -> Int? {
        frames.indices.max { lhs, rhs in
            abs(frames[lhs].presentationTimeSeconds - playbackTimeSeconds)
                < abs(frames[rhs].presentationTimeSeconds - playbackTimeSeconds)
        }
    }
}

nonisolated final class TAPVideoDepthDecodeAdmission: @unchecked Sendable {
    nonisolated struct Owner: Hashable, Sendable {
        fileprivate let id: UUID
    }

    nonisolated struct Token: Hashable, Sendable {
        fileprivate let id: UUID
        fileprivate let owner: Owner
        let generation: UInt64
    }

    private struct Waiter {
        let id: UUID
        let owner: Owner
        let expectedGeneration: UInt64
        let continuation: CheckedContinuation<Token?, Never>
    }

    private let maximumConcurrentDecodes: Int
    private let lock = NSLock()
    private var ownerGenerations: [Owner: UInt64] = [:]
    private var activeTokens: [UUID: Token] = [:]
    private var waiters: [Waiter] = []

    init(maximumConcurrentDecodes: Int = TAPVideoDepthPlaybackBudget.maximumConcurrentDecodes) {
        self.maximumConcurrentDecodes = min(
            max(1, maximumConcurrentDecodes),
            TAPVideoDepthPlaybackBudget.maximumConcurrentDecodes
        )
    }

    func makeOwner() -> Owner {
        let owner = Owner(id: UUID())
        lock.lock()
        ownerGenerations[owner] = 1
        lock.unlock()
        return owner
    }

    @discardableResult
    func beginNewGeneration(for owner: Owner) -> UInt64 {
        lock.lock()
        let current = (ownerGenerations[owner] ?? 1) &+ 1
        ownerGenerations[owner] = current
        let staleWaiters = removeWaitersLocked(for: owner)
        lock.unlock()
        resume(staleWaiters, with: nil)
        return current
    }

    func admit(for owner: Owner) -> Token? {
        lock.lock()
        defer {
            lock.unlock()
        }
        guard let generation = ownerGenerations[owner],
              activeTokens.count < maximumConcurrentDecodes else {
            return nil
        }
        let token = Token(id: UUID(), owner: owner, generation: generation)
        activeTokens[token.id] = token
        return token
    }

    func admitWhenAvailable(
        for owner: Owner,
        expectedGeneration: UInt64
    ) async -> Token? {
        let waiterID = UUID()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                lock.lock()
                if Task.isCancelled
                    || ownerGenerations[owner] != expectedGeneration {
                    lock.unlock()
                    continuation.resume(returning: nil)
                    return
                }
                if activeTokens.count < maximumConcurrentDecodes {
                    let token = Token(
                        id: UUID(),
                        owner: owner,
                        generation: expectedGeneration
                    )
                    activeTokens[token.id] = token
                    lock.unlock()
                    continuation.resume(returning: token)
                    return
                }
                waiters.append(Waiter(
                    id: waiterID,
                    owner: owner,
                    expectedGeneration: expectedGeneration,
                    continuation: continuation
                ))
                lock.unlock()
            }
        } onCancel: {
            cancelWaiter(waiterID)
        }
    }

    func isCurrent(_ token: Token) -> Bool {
        lock.lock()
        defer {
            lock.unlock()
        }
        return ownerGenerations[token.owner] == token.generation
            && activeTokens[token.id] == token
    }

    func finish(_ token: Token) {
        lock.lock()
        activeTokens[token.id] = nil
        let resumptions = admitWaitingTasksLocked()
        lock.unlock()
        for (waiter, admittedToken) in resumptions {
            waiter.continuation.resume(returning: admittedToken)
        }
    }

    func invalidate(_ owner: Owner) {
        lock.lock()
        ownerGenerations[owner] = nil
        let staleWaiters = removeWaitersLocked(for: owner)
        lock.unlock()
        resume(staleWaiters, with: nil)
    }

    var activeDecodeCount: Int {
        lock.lock()
        defer {
            lock.unlock()
        }
        return activeTokens.count
    }

    func currentGeneration(for owner: Owner) -> UInt64? {
        lock.lock()
        defer {
            lock.unlock()
        }
        return ownerGenerations[owner]
    }

    var waitingAdmissionCount: Int {
        lock.lock()
        defer {
            lock.unlock()
        }
        return waiters.count
    }

    private func cancelWaiter(_ waiterID: UUID) {
        lock.lock()
        guard let index = waiters.firstIndex(where: { $0.id == waiterID }) else {
            lock.unlock()
            return
        }
        let waiter = waiters.remove(at: index)
        lock.unlock()
        waiter.continuation.resume(returning: nil)
    }

    private func removeWaitersLocked(for owner: Owner) -> [Waiter] {
        var removed: [Waiter] = []
        waiters.removeAll { waiter in
            guard waiter.owner == owner else {
                return false
            }
            removed.append(waiter)
            return true
        }
        return removed
    }

    private func admitWaitingTasksLocked() -> [(Waiter, Token?)] {
        var resumptions: [(Waiter, Token?)] = []
        var index = 0
        while index < waiters.count {
            let waiter = waiters[index]
            guard ownerGenerations[waiter.owner] == waiter.expectedGeneration else {
                waiters.remove(at: index)
                resumptions.append((waiter, nil))
                continue
            }
            guard activeTokens.count < maximumConcurrentDecodes else {
                index += 1
                continue
            }
            waiters.remove(at: index)
            let token = Token(
                id: UUID(),
                owner: waiter.owner,
                generation: waiter.expectedGeneration
            )
            activeTokens[token.id] = token
            resumptions.append((waiter, token))
        }
        return resumptions
    }

    private func resume(_ waiters: [Waiter], with token: Token?) {
        for waiter in waiters {
            waiter.continuation.resume(returning: token)
        }
    }
}

private extension TAPVideoDepthRegistrationDescriptor {
    func registeredCIImage(from image: UIImage) -> CIImage? {
        guard let cgImage = image.cgImage else {
            return nil
        }
        let source = CIImage(cgImage: cgImage)
        switch mapping {
        case .preRegisteredRGBPresentation:
            return source.oriented(forExifOrientation: image.imageOrientation.exifOrientation)
        case .avDepthDataWarpedToSynchronizedRGB:
            guard let projection,
                  cgImage.width == projection.depthWidth,
                  cgImage.height == projection.depthHeight else {
                return nil
            }
            let orientation: CGImagePropertyOrientation
            switch projection.connectionRotationDegrees {
            case 0:
                orientation = .up
            case 90:
                orientation = .right
            case 180:
                orientation = .down
            case 270:
                orientation = .left
            default:
                return nil
            }
            let oriented = source.oriented(forExifOrientation: Int32(orientation.rawValue))
            let encodedImage: CIImage
            if projection.isEncodedHorizontallyMirrored {
                encodedImage = oriented.transformed(by: CGAffineTransform(
                    a: -1,
                    b: 0,
                    c: 0,
                    d: 1,
                    tx: oriented.extent.minX + oriented.extent.maxX,
                    ty: 0
                ))
            } else {
                encodedImage = oriented
            }
            let extent = encodedImage.extent
            guard extent.width > 0,
                  extent.height > 0 else {
                return nil
            }
            let aperture = projection.rgbCleanAperture
            let cropRect = CGRect(
                x: extent.minX
                    + aperture.x / Double(projection.encodedRGBWidth) * extent.width,
                y: extent.minY
                    + (1 - (aperture.y + aperture.height)
                        / Double(projection.encodedRGBHeight)) * extent.height,
                width: aperture.width / Double(projection.encodedRGBWidth) * extent.width,
                height: aperture.height / Double(projection.encodedRGBHeight) * extent.height
            ).intersection(extent)
            guard !cropRect.isNull,
                  cropRect.width > 0,
                  cropRect.height > 0 else {
                return nil
            }
            return encodedImage
                .cropped(to: cropRect)
                .transformed(by: CGAffineTransform(
                    translationX: -cropRect.minX,
                    y: -cropRect.minY
                ))
        }
    }
}

@MainActor
private final class TAPVideoDepthMetalOverlayView: MTKView, MTKViewDelegate {
    private let imageContext: CIContext
    private let commandQueue: any MTLCommandQueue
    private let outputColorSpace = CGColorSpace(name: CGColorSpace.sRGB)
        ?? CGColorSpaceCreateDeviceRGB()
    private var image: CIImage?

    static func makeIfSupported() -> TAPVideoDepthMetalOverlayView? {
        guard let device = MTLCreateSystemDefaultDevice(),
              let commandQueue = device.makeCommandQueue() else {
            return nil
        }
        return TAPVideoDepthMetalOverlayView(
            device: device,
            commandQueue: commandQueue
        )
    }

    private init(
        device: any MTLDevice,
        commandQueue: any MTLCommandQueue
    ) {
        self.imageContext = CIContext(mtlDevice: device)
        self.commandQueue = commandQueue
        super.init(frame: .zero, device: device)
        framebufferOnly = false
        colorPixelFormat = .bgra8Unorm
        clearColor = MTLClearColorMake(0, 0, 0, 0)
        isOpaque = false
        backgroundColor = .clear
        isPaused = true
        enableSetNeedsDisplay = true
        autoResizeDrawable = true
        delegate = self
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func present(_ overlay: TAPVideoRegisteredDepthOverlay?) {
        self.image = overlay.flatMap {
            $0.registrationDescriptor.registeredCIImage(from: $0.image)
        }
        setNeedsDisplay()
    }

    func draw(in view: MTKView) {
        guard let image,
              let drawable = currentDrawable,
              let commandBuffer = commandQueue.makeCommandBuffer() else {
            return
        }
        let targetBounds = CGRect(origin: .zero, size: drawableSize)
        guard targetBounds.width > 0,
              targetBounds.height > 0,
              image.extent.width > 0,
              image.extent.height > 0 else {
            return
        }
        let normalizedImage = image.transformed(
            by: CGAffineTransform(
                translationX: -image.extent.minX,
                y: -image.extent.minY
            )
        )
        let presentationImage = normalizedImage.transformed(
            by: CGAffineTransform(
                scaleX: targetBounds.width / normalizedImage.extent.width,
                y: targetBounds.height / normalizedImage.extent.height
            )
        )
        imageContext.render(
            presentationImage,
            to: drawable.texture,
            commandBuffer: commandBuffer,
            bounds: targetBounds,
            colorSpace: outputColorSpace
        )
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        _ = view
        _ = size
    }
}

private extension UIImage.Orientation {
    var exifOrientation: Int32 {
        switch self {
        case .up:
            Int32(CGImagePropertyOrientation.up.rawValue)
        case .upMirrored:
            Int32(CGImagePropertyOrientation.upMirrored.rawValue)
        case .down:
            Int32(CGImagePropertyOrientation.down.rawValue)
        case .downMirrored:
            Int32(CGImagePropertyOrientation.downMirrored.rawValue)
        case .left:
            Int32(CGImagePropertyOrientation.left.rawValue)
        case .leftMirrored:
            Int32(CGImagePropertyOrientation.leftMirrored.rawValue)
        case .right:
            Int32(CGImagePropertyOrientation.right.rawValue)
        case .rightMirrored:
            Int32(CGImagePropertyOrientation.rightMirrored.rawValue)
        @unknown default:
            Int32(CGImagePropertyOrientation.up.rawValue)
        }
    }
}

@MainActor
private final class TAPVideoDepthOverlaySurfaceView: UIView {
    private let metalView: TAPVideoDepthMetalOverlayView?
    private let fallbackImageView: UIImageView?
    private let fallbackImageContext = CIContext(options: [.cacheIntermediates: false])
    private(set) var hasImage = false

    override init(frame: CGRect) {
        let metalView = TAPVideoDepthMetalOverlayView.makeIfSupported()
        self.metalView = metalView
        if metalView == nil {
            let imageView = UIImageView()
            imageView.contentMode = .scaleToFill
            imageView.isUserInteractionEnabled = false
            self.fallbackImageView = imageView
        } else {
            self.fallbackImageView = nil
        }
        super.init(frame: frame)
        isOpaque = false
        backgroundColor = .clear
        isUserInteractionEnabled = false
        clipsToBounds = true
        if let metalView {
            addSubview(metalView)
        } else if let fallbackImageView {
            addSubview(fallbackImageView)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        metalView?.frame = bounds
        fallbackImageView?.frame = bounds
        if hasImage {
            metalView?.setNeedsDisplay()
        }
    }

    func present(_ overlay: TAPVideoRegisteredDepthOverlay?) {
        metalView?.present(overlay)
        if let fallbackImageView {
            let registeredImage = overlay.flatMap {
                $0.registrationDescriptor.registeredCIImage(from: $0.image)
            }
            if let registeredImage,
               let cgImage = fallbackImageContext.createCGImage(
                   registeredImage,
                   from: registeredImage.extent
               ) {
                fallbackImageView.image = UIImage(cgImage: cgImage)
                hasImage = true
            } else {
                fallbackImageView.image = nil
                hasImage = false
            }
        } else {
            hasImage = overlay != nil
        }
    }
}

@MainActor
final class TAPVideoPlayerSurfaceUIView: UIView {
    override class var layerClass: AnyClass {
        AVPlayerLayer.self
    }

    var playerLayer: AVPlayerLayer {
        guard let playerLayer = layer as? AVPlayerLayer else {
            preconditionFailure("TAPVideoPlayerSurfaceUIView requires AVPlayerLayer backing")
        }
        return playerLayer
    }

    private let overlaySurfaceView = TAPVideoDepthOverlaySurfaceView()
    private var showsRegisteredDepth = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = true
        backgroundColor = .black
        clipsToBounds = true
        isUserInteractionEnabled = false
        playerLayer.videoGravity = .resizeAspect
        playerLayer.backgroundColor = UIColor.black.cgColor
        overlaySurfaceView.isHidden = true
        addSubview(overlaySurfaceView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        UIView.performWithoutAnimation {
            overlaySurfaceView.frame = playerLayer.videoRect
            overlaySurfaceView.layoutIfNeeded()
        }
        updateOverlayVisibility()
    }

    func setPlayer(_ player: AVPlayer?) {
        guard playerLayer.player !== player else {
            return
        }
        playerLayer.player = player
        setNeedsLayout()
    }

    func update(showsRegisteredDepth: Bool, overlayOpacity: Double) {
        self.showsRegisteredDepth = showsRegisteredDepth
        overlaySurfaceView.alpha = CGFloat(min(max(overlayOpacity, 0), 1))
        updateOverlayVisibility()
    }

    func present(_ overlay: TAPVideoRegisteredDepthOverlay?) {
        overlaySurfaceView.present(overlay)
        setNeedsLayout()
        updateOverlayVisibility()
    }

    func refreshVideoGeometry() {
        setNeedsLayout()
        layoutIfNeeded()
    }

    func reset() {
        showsRegisteredDepth = false
        overlaySurfaceView.present(nil)
        overlaySurfaceView.frame = .zero
        overlaySurfaceView.isHidden = true
        playerLayer.player = nil
    }

    private func updateOverlayVisibility() {
        let videoRect = playerLayer.videoRect
        let hasUsableVideoRect = videoRect.width > 0 && videoRect.height > 0
        overlaySurfaceView.isHidden = !showsRegisteredDepth
            || !overlaySurfaceView.hasImage
            || !hasUsableVideoRect
    }
}

/// A presentation-only video surface. SwiftUI owns every interactive control;
/// this view owns only AVPlayerLayer, the registered-depth overlay, and the PiP
/// bridge required to switch back to RGB for system playback surfaces.
@MainActor
struct TAPVideoPlayerSurfaceView: UIViewRepresentable {
    let player: AVPlayer
    let overlayStore: TAPVideoDepthOverlayStore
    let showsRegisteredDepth: Bool
    let overlayOpacity: Double
    let onSystemPlaybackRequiresRGB: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            overlayStore: overlayStore,
            onSystemPlaybackRequiresRGB: onSystemPlaybackRequiresRGB
        )
    }

    func makeUIView(context: Context) -> TAPVideoPlayerSurfaceUIView {
        let surfaceView = TAPVideoPlayerSurfaceUIView()
        surfaceView.setPlayer(player)
        context.coordinator.bind(to: surfaceView, player: player)
        context.coordinator.update(
            showsRegisteredDepth: showsRegisteredDepth,
            overlayOpacity: overlayOpacity
        )
        return surfaceView
    }

    func updateUIView(
        _ surfaceView: TAPVideoPlayerSurfaceUIView,
        context: Context
    ) {
        if surfaceView.playerLayer.player !== player {
            surfaceView.setPlayer(player)
            context.coordinator.observeExternalPlayback(on: player)
        }
        context.coordinator.update(
            showsRegisteredDepth: showsRegisteredDepth,
            overlayOpacity: overlayOpacity
        )
        surfaceView.refreshVideoGeometry()
    }

    static func dismantleUIView(
        _ surfaceView: TAPVideoPlayerSurfaceUIView,
        coordinator: Coordinator
    ) {
        coordinator.unbind()
        surfaceView.reset()
    }

    @MainActor
    final class Coordinator: NSObject,
        AVPictureInPictureControllerDelegate,
        TAPVideoDepthOverlaySink {
        private let overlayStore: TAPVideoDepthOverlayStore
        private let onSystemPlaybackRequiresRGB: () -> Void
        private weak var surfaceView: TAPVideoPlayerSurfaceUIView?
        private weak var observedPlayer: AVPlayer?
        private var externalPlaybackObservation: NSKeyValueObservation?
        private var playerLayerReadyObservation: NSKeyValueObservation?
        private var pictureInPictureController: AVPictureInPictureController?
        private var showsRegisteredDepth = false
        private var overlayOpacity = 1.0
        private var isPictureInPictureActive = false

        init(
            overlayStore: TAPVideoDepthOverlayStore,
            onSystemPlaybackRequiresRGB: @escaping () -> Void
        ) {
            self.overlayStore = overlayStore
            self.onSystemPlaybackRequiresRGB = onSystemPlaybackRequiresRGB
            super.init()
        }

        func bind(to surfaceView: TAPVideoPlayerSurfaceUIView, player: AVPlayer) {
            self.surfaceView = surfaceView
            overlayStore.attach(self)
            observeExternalPlayback(on: player)
            observeReadiness(of: surfaceView.playerLayer)
            configurePictureInPicture(for: surfaceView.playerLayer)
            surfaceView.refreshVideoGeometry()
        }

        func unbind() {
            externalPlaybackObservation?.invalidate()
            externalPlaybackObservation = nil
            playerLayerReadyObservation?.invalidate()
            playerLayerReadyObservation = nil
            observedPlayer = nil

            if let pictureInPictureController {
                if pictureInPictureController.isPictureInPictureActive {
                    pictureInPictureController.stopPictureInPicture()
                }
                pictureInPictureController.delegate = nil
            }
            pictureInPictureController = nil
            isPictureInPictureActive = false

            overlayStore.detach(self)
            surfaceView?.present(nil)
            surfaceView = nil
        }

        func update(showsRegisteredDepth: Bool, overlayOpacity: Double) {
            self.showsRegisteredDepth = showsRegisteredDepth
            self.overlayOpacity = overlayOpacity
            surfaceView?.update(
                showsRegisteredDepth: showsRegisteredDepth,
                overlayOpacity: overlayOpacity
            )
            if showsRegisteredDepth
                && (observedPlayer?.isExternalPlaybackActive == true
                    || isPictureInPictureActive) {
                requireRGBForSystemPlayback()
            }
        }

        func setRegisteredDepthOverlay(_ overlay: TAPVideoRegisteredDepthOverlay?) {
            surfaceView?.present(overlay)
        }

        func observeExternalPlayback(on player: AVPlayer) {
            externalPlaybackObservation?.invalidate()
            observedPlayer = player
            externalPlaybackObservation = player.observe(
                \.isExternalPlaybackActive,
                options: [.initial, .new]
            ) { [weak self] player, _ in
                guard player.isExternalPlaybackActive else {
                    return
                }
                Task { @MainActor [weak self, weak player] in
                    guard let self,
                          let player,
                          self.observedPlayer === player else {
                        return
                    }
                    self.requireRGBForSystemPlayback()
                }
            }
        }

        func pictureInPictureControllerWillStartPictureInPicture(
            _ pictureInPictureController: AVPictureInPictureController
        ) {
            guard self.pictureInPictureController === pictureInPictureController else {
                return
            }
            isPictureInPictureActive = true
            requireRGBForSystemPlayback()
        }

        func pictureInPictureControllerDidStopPictureInPicture(
            _ pictureInPictureController: AVPictureInPictureController
        ) {
            guard self.pictureInPictureController === pictureInPictureController else {
                return
            }
            isPictureInPictureActive = false
        }

        func pictureInPictureController(
            _ pictureInPictureController: AVPictureInPictureController,
            failedToStartPictureInPictureWithError error: any Error
        ) {
            guard self.pictureInPictureController === pictureInPictureController else {
                return
            }
            _ = error
            isPictureInPictureActive = false
        }

        private func observeReadiness(of playerLayer: AVPlayerLayer) {
            playerLayerReadyObservation?.invalidate()
            playerLayerReadyObservation = playerLayer.observe(
                \.isReadyForDisplay,
                options: [.initial, .new]
            ) { [weak self] _, _ in
                Task { @MainActor [weak self] in
                    self?.surfaceView?.refreshVideoGeometry()
                }
            }
        }

        private func configurePictureInPicture(for playerLayer: AVPlayerLayer) {
            guard AVPictureInPictureController.isPictureInPictureSupported(),
                  let controller = AVPictureInPictureController(playerLayer: playerLayer) else {
                pictureInPictureController = nil
                return
            }
            controller.delegate = self
            controller.canStartPictureInPictureAutomaticallyFromInline = true
            pictureInPictureController = controller
        }

        private func requireRGBForSystemPlayback() {
            guard showsRegisteredDepth else {
                return
            }
            showsRegisteredDepth = false
            surfaceView?.update(
                showsRegisteredDepth: false,
                overlayOpacity: overlayOpacity
            )
            onSystemPlaybackRequiresRGB()
        }
    }
}
