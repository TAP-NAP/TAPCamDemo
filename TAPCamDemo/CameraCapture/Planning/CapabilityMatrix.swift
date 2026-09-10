//
//  CapabilityMatrix.swift
//  TAPCamDemo
//
//  Created by Codex on 2026/4/27.
//

@preconcurrency import AVFoundation
import CoreGraphics
import CoreMedia
import Darwin
import Foundation

/// Complete capability surface consumed by `CameraViewModel`.
///
/// Startup restores or discovers the format candidates and prepares the fixed
/// FOV and PRO choices once. Selection changes query these prepared values;
/// SwiftUI never discovers formats or makes direct device decisions.
nonisolated struct CapabilityMatrix: @unchecked Sendable {
    let rgbSources: [CameraProfile]
    let depthCandidates: [DepthDeviceCandidate]
    private var preparedFocalLengthOptions: [FocalLengthOption] = []
    private var preparedDebugDepthDeviceOptions: [DebugDepthDeviceOption] = []
    private var preparedPhotographerMode: (
        facts: PhotographerModeCapabilityFacts,
        rgbSource: CameraProfile?,
        depthProfile: DepthProfile?
    ) = (CapabilityMatrix.unavailablePhotographerModeFacts(), nil, nil)

    init(
        rgbSources: [CameraProfile],
        depthCandidates: [DepthDeviceCandidate],
        photographerModeFacts: PhotographerModeCapabilityFacts? = nil
    ) {
        self.rgbSources = rgbSources
        self.depthCandidates = depthCandidates
        preparedFocalLengthOptions = makeFocalLengthOptions()
        preparedDebugDepthDeviceOptions = makeDebugDepthDeviceOptions()
        preparedPhotographerMode = makePhotographerModeResolution(cachedFacts: photographerModeFacts)
    }

    var photographerModeFacts: PhotographerModeCapabilityFacts {
        preparedPhotographerMode.facts
    }

    func bestDepthFormatSelection(
        for device: AVCaptureDevice,
        preferredZoomFactor: Double? = nil,
        requiresPreferredZoomSupport: Bool = false
    ) -> PhotoDepthFormatSelection? {
        depthCandidates.first { $0.device.uniqueID == device.uniqueID }?
            .bestFormatSelection(
                preferredZoomFactor: preferredZoomFactor,
                requiresPreferredZoomSupport: requiresPreferredZoomSupport
            )
    }

    var defaultRGBSource: CameraProfile? {
        rgbSources
            .filter {
                $0.isEnabled
                    && $0.device.deviceType != .builtInLiDARDepthCamera
            }
            .max { lhs, rhs in
                CameraCapabilityResolver.automaticPriority(for: lhs.device.deviceType) < CameraCapabilityResolver.automaticPriority(for: rhs.device.deviceType)
            }
    }

    func rgbSource(id: String?) -> CameraProfile? {
        guard let id else {
            return defaultRGBSource
        }
        return rgbSources.first(where: { $0.id == id })
    }

    /// Resolves a source for the Standard product path. A stale explicit ID
    /// left by a failed PRO transition must never make LiDAR look like a valid
    /// Standard RGB selection.
    func standardRGBSource(id: String?) -> CameraProfile? {
        guard let source = rgbSource(id: id),
              source.device.deviceType != .builtInLiDARDepthCamera else {
            return defaultRGBSource
        }
        return source
    }

    func depthProfiles(
        for rgbSource: CameraProfile,
        preferredZoomFactor: Double? = nil
    ) -> [DepthProfile] {
        DepthProfileKind.allCases.map { kind in
            let candidate = depthCandidates.first(where: { $0.kind == kind })
            let availability = availability(for: kind, candidate: candidate)
            let pairing = RGBDepthCompatibilityMatrix.evaluate(
                rgbSource: rgbSource,
                depthKind: kind,
                candidate: candidate,
                preferredZoomFactor: preferredZoomFactor
            )

            return DepthProfile(
                id: kind.id,
                kind: kind,
                displayName: kind.displayName,
                iconName: kind.iconName,
                fixedOrder: kind.fixedOrder,
                availability: availability,
                compatibility: pairing.status,
                disabledReason: pairing.reason,
                resolvedDevice: pairing.resolvedDevice,
                formatSelection: pairing.formatSelection
            )
        }
        .sorted { $0.fixedOrder < $1.fixedOrder }
    }

    /// Depth profiles available to the Standard product path. LiDAR is
    /// intentionally reserved for Photographer mode even when AVFoundation can
    /// pair it with a Standard RGB source.
    func standardDepthProfiles(
        for rgbSource: CameraProfile,
        preferredZoomFactor: Double? = nil
    ) -> [DepthProfile] {
        depthProfiles(
            for: rgbSource,
            preferredZoomFactor: preferredZoomFactor
        )
        .filter { $0.kind != .lidarDepth }
    }

    func bestCompatibleDepthProfile(for rgbSource: CameraProfile) -> DepthProfile? {
        standardDepthProfiles(for: rgbSource)
            .first(where: \.isSelectable)
    }

    func bestCompatibleDepthProfile(for rgbSource: CameraProfile, preferredZoomFactor: Double) -> DepthProfile? {
        standardDepthProfiles(
            for: rgbSource,
            preferredZoomFactor: preferredZoomFactor
        )
        .first(where: \.isSelectable)
    }

    /// Release eligibility for the LiDAR-only photographer workflow.
    ///
    /// This deliberately resolves the explicit `builtInLiDARDepthCamera`
    /// candidate instead of reusing the automatic 24mm FOV option, which may
    /// point at Triple or Dual Wide on the same phone.
    var photographerModeAvailability: PhotographerModeAvailability {
        let resolution = preparedPhotographerMode
        return PhotographerModeAvailability.resolve(resolution.facts)
    }

    /// Builds the fixed 24mm/1x LiDAR plan used by Photographer mode.
    /// Returning nil means the complete Release eligibility contract failed;
    /// callers must keep or restore a standard camera path.
    func photographerModeCapturePlan(
        cropRectNormalized: CropRectNormalized = .fullFrame
    ) -> CaptureSourcePlan? {
        let resolution = preparedPhotographerMode
        guard PhotographerModeAvailability.resolve(resolution.facts).isAvailable,
              let rgbSource = resolution.rgbSource,
              let depthProfile = resolution.depthProfile else {
            return nil
        }

        let plan = CaptureSourcePlan.make(
            rgbSource: rgbSource,
            depthSource: depthProfile,
            selectionMode: .manual,
            selectedZoomID: nil,
            selectedZoomFactor: 1.0,
            cropRectNormalized: cropRectNormalized
        )
        guard plan.canCapturePhotoDepth,
              plan.zoom?.matchesRawVideoZoomFactor(1.0) == true else {
            return nil
        }
        return plan
    }

    func debugDepthDeviceOptions() -> [DebugDepthDeviceOption] {
        preparedDebugDepthDeviceOptions
    }

    private func makeDebugDepthDeviceOptions() -> [DebugDepthDeviceOption] {
        DepthProfileKind.allCases
            .map { kind in
            let candidate = depthCandidates.first(where: { $0.kind == kind })
            let availability = availability(for: kind, candidate: candidate)
            let rgbSource = candidate.map { candidate in
                rgbSources.first(where: { $0.id == candidate.device.uniqueID })
                    ?? CameraCapabilityResolver.debugCameraProfile(for: candidate.device, depthCandidates: depthCandidates)
            }

            return DebugDepthDeviceOption(
                id: kind.id,
                kind: kind,
                displayName: kind.displayName,
                iconName: kind.iconName,
                fixedOrder: kind.fixedOrder,
                availability: availability,
                disabledReason: debugDepthDeviceDisabledReason(
                    availability: availability,
                    rgbSource: rgbSource
                ),
                deviceName: candidate?.device.localizedName,
                deviceTypeRawValue: candidate?.device.deviceType.rawValue,
                device: candidate?.device,
                rgbSource: rgbSource,
                formatSelection: candidate?.formatSelection
            )
        }
        .sorted { $0.fixedOrder < $1.fixedOrder }
    }

    /// Builds the Release FOV chips from compatible photo-depth capabilities.
    ///
    /// Each enabled option carries a resolved RGB source, compatible depth row,
    /// and raw `videoZoomFactor`; Release UI does not infer those values again.
    ///
    /// - Tag: BuildReleaseFOVOptions
    func focalLengthOptions() -> [FocalLengthOption] {
        preparedFocalLengthOptions
    }

    private func makeFocalLengthOptions() -> [FocalLengthOption] {
        var bestBySlot: [String: FocalLengthOption] = [:]

        for rgbSource in rgbSources {
            /*
             FOV buttons are a rear-camera composition control. Front capture is
             entered through the dedicated camera-switch button so the selector
             does not mix "front camera" with rear 35mm-equivalent focal slots.
             */
            guard rgbSource.device.position == .back,
                  rgbSource.device.deviceType != .builtInLiDARDepthCamera else {
                continue
            }

            for targetFOV in FocalLengthLabelResolver.releaseFOVTargets() {
                /*
                 Depth support is format-specific. A virtual device may expose
                 one active format whose depth delivery is safe only at 2x/3x
                 and another format that works at 1x. Release FOV options must
                 therefore resolve the Apple-paired depth source for each target
                 FOV instead of reusing the single "best" depth format selected
                 during discovery. Otherwise the 24mm slot can be incorrectly
                 filled by LiDAR while Triple/Dual Wide are marked unavailable
                 at 1x, making 24mm and 48mm look visually too similar.
                 */
                let seedDepthSource = bestCompatibleDepthProfile(for: rgbSource)
                let requestedZoomFactor = FocalLengthLabelResolver.releaseVideoZoomFactor(
                    for: rgbSource,
                    targetEquivalentMillimeters: targetFOV,
                    formatSelection: seedDepthSource?.formatSelection
                )
                let depthSource = bestCompatibleDepthProfile(
                    for: rgbSource,
                    preferredZoomFactor: requestedZoomFactor
                )
                let zoomCapability = ZoomCapabilityResolver.resolve(
                    rgbSource: rgbSource,
                    depthProfile: depthSource,
                    selectedZoomID: nil,
                    selectedZoomFactor: requestedZoomFactor
                )
                guard let zoom = zoomCapability.zoomProfiles.first(where: { $0.matchesRawVideoZoomFactor(requestedZoomFactor) }) else {
                    continue
                }
                let label = FocalLengthLabelResolver.label(
                    equivalentMillimeters: targetFOV,
                    source: "\(rgbSource.focalLengthLabelSource)+releaseFOVTarget"
                )
                let isEnabled = rgbSource.isEnabled && depthSource?.isSelectable == true && zoom.isEnabled
                let option = FocalLengthOption(
                    id: "\(rgbSource.id)-\(zoom.id)-\(label.label)",
                    displayName: label.label,
                    numericLabel: label.numericLabel,
                    unitLabel: label.unitLabel,
                    equivalentFocalLength35mmMillimeters: label.equivalentMillimeters ?? 0,
                    labelSource: label.source,
                    rgbSource: rgbSource,
                    depthSource: depthSource,
                    zoom: zoom,
                    isEnabled: isEnabled,
                    disabledReason: isEnabled
                        ? nil
                        : zoom.disabledReason ?? depthSource?.disabledReason ?? rgbSource.disabledReason ?? "Depth capture unavailable"
                )

                #if !DEBUG
                guard option.isEnabled else {
                    continue
                }
                #endif

                let slotKey = "\(rgbSource.positionDescription)-\(option.displayName)"
                if let existing = bestBySlot[slotKey],
                   focalOptionPriority(existing) >= focalOptionPriority(option) {
                    continue
                }
                bestBySlot[slotKey] = option
            }
        }

        let options = bestBySlot.values.sorted { lhs, rhs in
            if lhs.rgbSource.device.position != rhs.rgbSource.device.position {
                return lhs.rgbSource.device.position == .back
            }
            if lhs.equivalentFocalLength35mmMillimeters == rhs.equivalentFocalLength35mmMillimeters {
                return focalOptionPriority(lhs) > focalOptionPriority(rhs)
            }
            return lhs.equivalentFocalLength35mmMillimeters < rhs.equivalentFocalLength35mmMillimeters
        }
        return options
    }

    var defaultFocalLengthOption: FocalLengthOption? {
        let options = focalLengthOptions()
        return bestOption(nearEquivalentMillimeters: 24, in: options)
            ?? options.first(where: \.isEnabled)
    }

    func bestOption(nearEquivalentMillimeters target: Double, in options: [FocalLengthOption]? = nil) -> FocalLengthOption? {
        let candidates = (options ?? focalLengthOptions()).filter(\.isEnabled)
        return candidates.min { lhs, rhs in
            let lhsDistance = abs(lhs.equivalentFocalLength35mmMillimeters - target)
            let rhsDistance = abs(rhs.equivalentFocalLength35mmMillimeters - target)
            if abs(lhsDistance - rhsDistance) > 0.001 {
                return lhsDistance < rhsDistance
            }
            return focalOptionPriority(lhs) > focalOptionPriority(rhs)
        }
    }

    private func focalOptionPriority(_ option: FocalLengthOption) -> Int {
        let enabledScore = option.isEnabled ? 10_000 : 0
        let sourceScore = CameraCapabilityResolver.releaseDisplayPriority(for: option.rgbSource)
        return enabledScore + sourceScore
    }

    private func availability(for kind: DepthProfileKind, candidate: DepthDeviceCandidate?) -> DepthProfileAvailability {
        guard let candidate else {
            return .unavailable
        }
        return candidate.formatSelection == nil ? .unsupportedFormat : .available
    }

    private func debugDepthDeviceDisabledReason(
        availability: DepthProfileAvailability,
        rgbSource: CameraProfile?
    ) -> String? {
        switch availability {
        case .available where rgbSource == nil:
            return "Debug RGB source unavailable"
        case .available:
            return nil
        case .unavailable:
            return "Depth device unavailable"
        case .unsupportedFormat:
            return "No depth-capable format"
        }
    }

    private func makePhotographerModeResolution(cachedFacts: PhotographerModeCapabilityFacts?) -> (
        facts: PhotographerModeCapabilityFacts,
        rgbSource: CameraProfile?,
        depthProfile: DepthProfile?
    ) {
        guard let candidate = depthCandidates.first(where: { $0.kind == .lidarDepth }) else {
            return (
                Self.unavailablePhotographerModeFacts(),
                nil,
                nil
            )
        }

        let device = candidate.device
        let isRearLiDARDevice = device.deviceType == .builtInLiDARDepthCamera
            && device.position == .back
        let formatSelection = candidate.bestFormatSelection(
            preferredZoomFactor: 1.0,
            requiresPreferredZoomSupport: true
        )
        let rgbSource = rgbSources.first(where: { $0.id == device.uniqueID })
            ?? CameraCapabilityResolver.cameraProfile(
                for: device,
                depthCandidates: depthCandidates
            )
        let depthProfile = formatSelection.map { selection in
            DepthProfile(
                id: DepthProfileKind.lidarDepth.id,
                kind: .lidarDepth,
                displayName: DepthProfileKind.lidarDepth.displayName,
                iconName: DepthProfileKind.lidarDepth.iconName,
                fixedOrder: DepthProfileKind.lidarDepth.fixedOrder,
                availability: .available,
                compatibility: .compatible,
                disabledReason: nil,
                resolvedDevice: device,
                formatSelection: selection
            )
        }
        if let cachedFacts {
            return (cachedFacts, rgbSource, depthProfile)
        }
        let plan = depthProfile.map { profile in
            CaptureSourcePlan.make(
                rgbSource: rgbSource,
                depthSource: profile,
                selectionMode: .manual,
                selectedZoomID: nil,
                selectedZoomFactor: 1.0,
                cropRectNormalized: .fullFrame
            )
        }
        let controlCapabilities = formatSelection.map { selection in
            CameraControlCapabilitySnapshot.make(
                device: device,
                activeFormat: selection.videoFormat
            )
        }

        return (
            PhotographerModeCapabilityFacts(
                isRearLiDARDevice: isRearLiDARDevice,
                hasOneXDepthFormat: formatSelection != nil,
                supportsPhotoDepthDelivery: plan?.canCapturePhotoDepth == true,
                supportsCustomExposure: controlCapabilities?.exposure.supportsCustomExposure == true,
                hasAdjustableISORange: controlCapabilities?.exposure.isoRange.isAdjustable == true,
                hasAdjustableShutterRange: controlCapabilities?.exposure.shutterDurationRangeSeconds.isAdjustable == true,
                supportsLockedFocus: controlCapabilities?.focus.supportsLockedFocus == true,
                supportsCustomLensPosition: controlCapabilities?.focus.supportsCustomLensPosition == true
            ),
            rgbSource,
            depthProfile
        )
    }

    private static func unavailablePhotographerModeFacts() -> PhotographerModeCapabilityFacts {
        PhotographerModeCapabilityFacts(
            isRearLiDARDevice: false,
            hasOneXDepthFormat: false,
            supportsPhotoDepthDelivery: false,
            supportsCustomExposure: false,
            hasAdjustableISORange: false,
            hasAdjustableShutterRange: false,
            supportsLockedFocus: false,
            supportsCustomLensPosition: false
        )
    }
}
