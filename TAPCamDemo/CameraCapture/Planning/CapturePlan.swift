//
//  CapturePlan.swift
//  TAPCamDemo
//
//  Created by Codex on 2026/4/27.
//

@preconcurrency import AVFoundation
import CoreGraphics
import CoreMedia
import Darwin
import Foundation

/// Pairing modes surfaced by SingleCam capture planning.
///
/// Only `rgbWithApplePairedDepth` is executable. Other values remain as
/// diagnostics/manifest facts so unsupported hardware combinations are explicit
/// instead of silently falling back to a different depth source.
nonisolated enum RGBDepthPairingMode: String, Codable, Equatable, Sendable {
    case rgbOnly
    case rgbWithApplePairedDepth
    case requiresMultiCam
    case unsupported
}

/// How the depth-capable SingleCam pipeline was selected.
///
/// These raw values are written into the TAP manifest, so they intentionally
/// keep the existing `auto`, `manual`, and `debugDepthOverride` strings while
/// removing runtime string comparisons from the Swift code.
nonisolated enum DepthSelectionMode: String, Codable, Equatable, Sendable {
    case automatic = "auto"
    case manual
    case debugDepthOverride
}

/// Immutable capture configuration chosen before the session is mutated.
nonisolated struct CaptureConfig: Equatable, Sendable {
    let requestedZoomID: String?
    let requestedZoomFactor: Double?
    let depthDataDeliveryEnabled: Bool
    let embedsDepthDataInPhoto: Bool
}

/// Release crop policy attached to a capture plan.
nonisolated struct CropPolicy: Equatable, Sendable {
    let mode: String
    let cropRectNormalized: CropRectNormalized
    let destructiveFinalCropApplied: Bool
}

/// Captures the user's selected RGB source and depth row as one executable plan.
///
/// This type is the handoff between capability validation and session
/// configuration. It does not mutate AVFoundation; it states which device may be
/// configured, which zoom is legal, and whether still photo + depth capture is
/// allowed.
nonisolated struct CaptureSourcePlan: @unchecked Sendable {
    let rgbSource: CameraProfile
    let depthSource: DepthProfile?
    let selectionMode: DepthSelectionMode
    let pairingMode: RGBDepthPairingMode
    let compatibilityStatus: RGBDepthCompatibilityStatus
    let compatibilityReason: String?
    let sessionMode: CaptureSessionMode
    let resolvedCaptureDevice: AVCaptureDevice
    let formatSelection: PhotoDepthFormatSelection?
    let zoom: ZoomProfile?
    let zoomCapability: ZoomCapability
    var cropPolicy: CropPolicy
    let captureConfig: CaptureConfig

    var canCapturePhotoDepth: Bool {
        pairingMode == .rgbWithApplePairedDepth
            && compatibilityStatus == .compatible
            && captureConfig.depthDataDeliveryEnabled
            && zoom?.isEnabled == true
            && formatSelection != nil
    }

    var requestedFocalLengthLabel: FocalLengthLabelResolver.Label {
        let rawZoomFactor = zoom?.rawVideoZoomFactor ?? 1.0
        let equivalentMillimeters = FocalLengthLabelResolver.equivalentMillimeters(
            for: rgbSource,
            rawVideoZoomFactor: rawZoomFactor,
            formatSelection: formatSelection
        )

        if selectionMode == .debugDepthOverride {
            return FocalLengthLabelResolver.label(
                equivalentMillimeters: equivalentMillimeters,
                source: "\(rgbSource.focalLengthLabelSource)+debugRawVideoZoomFactor"
            )
        }

        return FocalLengthLabelResolver.label(
            equivalentMillimeters: equivalentMillimeters,
            source: "\(rgbSource.focalLengthLabelSource)+releaseRawVideoZoomFactor"
        )
    }

    /// Creates the immutable plan that Runtime is allowed to execute.
    ///
    /// The raw `selectedZoomFactor` is a first-class input so semantic FOV chips
    /// such as `48mm` do not collapse back to a generic `2x`/`3x` zoom ID.
    ///
    /// - Tag: MakeCaptureSourcePlan
    static func make(
        rgbSource: CameraProfile,
        depthSource: DepthProfile?,
        selectionMode: DepthSelectionMode,
        selectedZoomID: String?,
        selectedZoomFactor: Double? = nil,
        cropRectNormalized: CropRectNormalized
    ) -> CaptureSourcePlan {
        let zoomCapability = ZoomCapabilityResolver.resolve(
            rgbSource: rgbSource,
            depthProfile: depthSource,
            selectedZoomID: selectedZoomID,
            selectedZoomFactor: selectedZoomFactor
        )
        /*
         Prefer the selected zoom ID when it names a profile, but keep the raw
         Double as a first-class fallback. Release FOV options can resolve to
         non-catalog raw zoom values such as 4.0; matching the Double here keeps
         those labels from collapsing back to the first enabled depth-safe zoom.
         */
        let selectedZoom = selectedZoomID.flatMap { id in zoomCapability.zoomProfiles.first(where: { $0.id == id }) }
            ?? selectedZoomFactor.flatMap { zoom in zoomCapability.zoomProfiles.first(where: { $0.matchesRawVideoZoomFactor(zoom) }) }
            ?? zoomCapability.zoomProfiles.first(where: \.isEnabled)
        let cropPolicy = CropPolicy(
            mode: "previewOnly",
            cropRectNormalized: cropRectNormalized,
            destructiveFinalCropApplied: false
        )

        let status = depthSource?.compatibility ?? .releasePackagingUnsupported
        let mode: RGBDepthPairingMode
        switch status {
        case .compatible where selectedZoom?.isEnabled == true:
            mode = .rgbWithApplePairedDepth
        case .compatible:
            mode = .unsupported
        case .requiresMultiCam:
            mode = .requiresMultiCam
        case .releasePackagingUnsupported:
            mode = .rgbOnly
        default:
            mode = .unsupported
        }

        let resolvedDevice = depthSource?.compatibility == .compatible
            ? (depthSource?.resolvedDevice ?? rgbSource.device)
            : rgbSource.device
        let depthEnabled = mode == .rgbWithApplePairedDepth

        return CaptureSourcePlan(
            rgbSource: rgbSource,
            depthSource: depthSource,
            selectionMode: selectionMode,
            pairingMode: selectedZoom?.isEnabled == false ? .unsupported : mode,
            compatibilityStatus: selectedZoom?.isEnabled == false ? .unsupportedZoom : status,
            compatibilityReason: selectedZoom?.disabledReason ?? depthSource?.disabledReason,
            sessionMode: .singleCam,
            resolvedCaptureDevice: resolvedDevice,
            formatSelection: depthEnabled ? depthSource?.formatSelection : nil,
            zoom: selectedZoom,
            zoomCapability: zoomCapability,
            cropPolicy: cropPolicy,
            captureConfig: CaptureConfig(
                requestedZoomID: selectedZoom?.id,
                requestedZoomFactor: selectedZoom?.requestedZoomFactor,
                depthDataDeliveryEnabled: depthEnabled,
                embedsDepthDataInPhoto: depthEnabled
            )
        )
    }
}

/// Immutable request to configure the managed capture session.
///
/// UI and the photo provider never add/remove inputs or outputs directly. The
/// view model creates this request after pairing validation and hands it to
/// `CaptureSessionController`, which serializes all AVFoundation mutation on
/// its session queue.
nonisolated enum CameraAuxiliaryPreviewPolicy: Equatable, Sendable {
    case none
    case manualFocusLoupe
}

nonisolated struct SessionConfigurationRequest: @unchecked Sendable {
    let capturePlan: CaptureSourcePlan
    let outputProfile: CaptureOutputProfile
    let auxiliaryPreviewPolicy: CameraAuxiliaryPreviewPolicy

    init(
        capturePlan: CaptureSourcePlan,
        outputProfile: CaptureOutputProfile = CaptureOutputProfileCatalog.releaseDefaultProfile,
        auxiliaryPreviewPolicy: CameraAuxiliaryPreviewPolicy = .none
    ) {
        self.capturePlan = capturePlan
        self.outputProfile = outputProfile
        self.auxiliaryPreviewPolicy = auxiliaryPreviewPolicy
    }
}

/// Stable metadata for the configured SingleCam capture path.
///
/// This value crosses the session boundary into capture/package/manifest code.
/// It records both the user's requested source rows and the resolved
/// AVFoundation device so readers can see where Apple paired depth came from.
nonisolated struct CaptureSelectionContext: Codable, Equatable, Sendable {
    let sessionMode: String
    let selectionMode: DepthSelectionMode
    let pairingMode: String
    let compatibilityStatus: String
    let compatibilityReason: String?
    let alignmentStatus: String
    let rgbSourceID: String
    let rgbSourceDisplayName: String
    let rgbSourceDeviceType: String
    let rgbSourceDeviceName: String
    let rgbSourcePosition: String
    let rgbSourceKind: String
    let depthSourceID: String?
    let depthSourceDisplayName: String?
    let depthSourceKind: String?
    let selectedFocalLengthLabel: String
    let selectedFocalLengthLabelSource: String
    let selectedEquivalentFocalLength35mmMillimeters: Double?
    let selectedZoomID: String?
    let selectedZoomDisplayName: String?
    let selectedZoomFactor: Double?
    let cropRectNormalized: CropRectNormalized
    let resolvedCaptureDeviceID: String
    let resolvedCaptureDeviceType: String
    let resolvedCaptureDeviceName: String
}

/// Result of applying a `SessionConfigurationRequest` to AVFoundation.
///
/// The view model stores this as the active capture context. A shutter press is
/// valid only when `depthDeliverySupported` and `capturePlan.canCapturePhotoDepth`
/// are both true.
nonisolated struct SessionConfigurationResult: @unchecked Sendable {
    let depthDeliverySupported: Bool
    let cameraDisplayName: String
    let nativePreviewAspectRatio: Double
    let capturePlan: CaptureSourcePlan
    let outputProfile: CaptureOutputProfile
    let resolvedOutput: ResolvedCaptureOutputProfile
    let device: AVCaptureDevice
    let livePhotoAudioInputConfigured: Bool
    let controlCapabilities: CameraControlCapabilitySnapshot
    let selectionContext: CaptureSelectionContext
    let auxiliaryPreviewPolicy: CameraAuxiliaryPreviewPolicy

    init(
        depthDeliverySupported: Bool,
        cameraDisplayName: String,
        nativePreviewAspectRatio: Double,
        capturePlan: CaptureSourcePlan,
        outputProfile: CaptureOutputProfile,
        resolvedOutput: ResolvedCaptureOutputProfile,
        device: AVCaptureDevice,
        livePhotoAudioInputConfigured: Bool,
        controlCapabilities: CameraControlCapabilitySnapshot,
        selectionContext: CaptureSelectionContext,
        auxiliaryPreviewPolicy: CameraAuxiliaryPreviewPolicy = .none
    ) {
        self.depthDeliverySupported = depthDeliverySupported
        self.cameraDisplayName = cameraDisplayName
        self.nativePreviewAspectRatio = nativePreviewAspectRatio
        self.capturePlan = capturePlan
        self.outputProfile = outputProfile
        self.resolvedOutput = resolvedOutput
        self.device = device
        self.livePhotoAudioInputConfigured = livePhotoAudioInputConfigured
        self.controlCapabilities = controlCapabilities
        self.selectionContext = selectionContext
        self.auxiliaryPreviewPolicy = auxiliaryPreviewPolicy
    }
}

extension SessionConfigurationRequest {
    nonisolated var selectionContext: CaptureSelectionContext {
        let plan = capturePlan
        let focalLabel = plan.requestedFocalLengthLabel
        return CaptureSelectionContext(
            sessionMode: plan.sessionMode.rawValue,
            selectionMode: plan.selectionMode,
            pairingMode: plan.pairingMode.rawValue,
            compatibilityStatus: plan.compatibilityStatus.rawValue,
            compatibilityReason: plan.compatibilityReason,
            alignmentStatus: plan.canCapturePhotoDepth ? "sameCapturePipeline" : "notCaptured",
            rgbSourceID: plan.rgbSource.id,
            rgbSourceDisplayName: plan.rgbSource.displayName,
            rgbSourceDeviceType: plan.rgbSource.deviceTypeRawValue,
            rgbSourceDeviceName: plan.rgbSource.deviceName,
            rgbSourcePosition: plan.rgbSource.positionDescription,
            rgbSourceKind: plan.rgbSource.sourceKind.rawValue,
            depthSourceID: plan.depthSource?.id,
            depthSourceDisplayName: plan.depthSource?.displayName,
            depthSourceKind: plan.depthSource?.kind.rawValue,
            selectedFocalLengthLabel: focalLabel.label,
            selectedFocalLengthLabelSource: focalLabel.source,
            selectedEquivalentFocalLength35mmMillimeters: focalLabel.equivalentMillimeters,
            selectedZoomID: plan.zoom?.id,
            selectedZoomDisplayName: plan.zoom?.displayName,
            selectedZoomFactor: plan.zoom?.rawVideoZoomFactor,
            cropRectNormalized: plan.cropPolicy.cropRectNormalized,
            resolvedCaptureDeviceID: plan.resolvedCaptureDevice.uniqueID,
            resolvedCaptureDeviceType: plan.resolvedCaptureDevice.deviceType.rawValue,
            resolvedCaptureDeviceName: plan.resolvedCaptureDevice.localizedName
        )
    }
}
