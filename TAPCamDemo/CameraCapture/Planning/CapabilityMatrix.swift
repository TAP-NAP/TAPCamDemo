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
/// The matrix is rebuilt from AVFoundation discovery at launch, then queried as
/// value data when the selected RGB source, depth row, zoom, or crop metadata
/// changes. SwiftUI never makes direct `AVCaptureDevice` decisions.
nonisolated struct CapabilityMatrix: @unchecked Sendable {
    let rgbSources: [CameraProfile]
    let depthCandidates: [DepthDeviceCandidate]

    var defaultRGBSource: CameraProfile? {
        rgbSources
            .filter(\.isEnabled)
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

    func bestCompatibleDepthProfile(for rgbSource: CameraProfile) -> DepthProfile? {
        depthProfiles(for: rgbSource)
            .first(where: \.isSelectable)
    }

    func bestCompatibleDepthProfile(for rgbSource: CameraProfile, preferredZoomFactor: Double) -> DepthProfile? {
        depthProfiles(
            for: rgbSource,
            preferredZoomFactor: preferredZoomFactor
        )
        .first(where: \.isSelectable)
    }

    func debugDepthDeviceOptions() -> [DebugDepthDeviceOption] {
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
        StartupTrace.measure("CapabilityMatrix.focalLengthOptions") {
            var bestBySlot: [String: FocalLengthOption] = [:]

            for rgbSource in rgbSources {
                /*
                 FOV buttons are a rear-camera composition control. Front capture is
                 entered through the dedicated camera-switch button so the selector
                 does not mix "front camera" with rear 35mm-equivalent focal slots.
                 */
                guard rgbSource.device.position == .back else {
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
            StartupTrace.mark("CapabilityMatrix.focalLengthOptions count=\(options.count)")
            return options
        }
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
}
