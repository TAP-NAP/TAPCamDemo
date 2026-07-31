//
//  CameraControlsUITestHarnessView.swift
//  TAPCamDemo
//

#if DEBUG
import Foundation
import SwiftUI

struct CameraControlsUITestHarnessView: View {
    @State private var selectedMode: CameraCaptureModeOption = .photo
    @State private var activeAdjustmentControl: CameraAdjustmentControl?
    @State private var focusMode: CameraFocusControlMode = .auto
    @State private var exposureMode: CameraAdjustmentControlState.ExposureMode = .auto(globalBias: 0)
    @State private var draft = CameraAdjustmentControlState.defaultDraft(from: Self.capability)
    @State private var isPhotographerModeActive = true
    @State private var status = "Ready"

    var body: some View {
        VStack(spacing: 18) {
            Text("Camera Controls UI Harness")
                .font(.headline)
                .accessibilityIdentifier("camera.controlsHarness.title")

            Text(status)
                .font(.caption.monospaced())
                .accessibilityIdentifier("camera.controlsHarness.status")

            Button("Toggle simulated PRO") {
                isPhotographerModeActive.toggle()
                activeAdjustmentControl = nil
                status = isPhotographerModeActive ? "PRO active" : "Standard active"
            }
            .accessibilityIdentifier("camera.controlsHarness.togglePro")

            Spacer(minLength: 0)

            CameraCaptureControlsView(
                state: CameraCaptureControlsState(
                    isShutterEnabled: true,
                    isLibraryWriteInProgress: false,
                    selectedMode: selectedMode,
                    isRecordingMovie: false,
                    isPreparingMovie: false,
                    isPhotographerModeActive: isPhotographerModeActive,
                    isInteractionLocked: false,
                    adjustmentControlState: adjustmentState,
                    basicEVControlState: CameraBasicEVControlState(bias: 0, isStripVisible: false),
                    contentRotation: .zero
                ),
                highlightColor: CameraViewfinderHighlightPreference.defaultValue.color,
                recentThumbnail: nil,
                onOpenTAPLibrary: { status = "Library opened" },
                onCapture: { status = "Capture tapped" },
                onSwitchCamera: { status = "Camera switched" },
                onSelectMode: selectMode,
                onSelectAdjustmentControl: selectAdjustmentControl,
                onAdjustEV: adjustEV,
                onAdjustISO: adjustISO,
                onAdjustShutterPosition: adjustShutterPosition,
                onAdjustLensPosition: adjustLensPosition,
                onRestoreAutomaticMode: restoreAutomaticMode,
                onBeginAdjustment: { _ in },
                onEndAdjustment: { _ in }
            )
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.ignoresSafeArea())
        .foregroundStyle(.white)
    }

    private var adjustmentState: CameraAdjustmentControlState {
        CameraAdjustmentControlState(
            capability: Self.capability,
            activeControl: activeAdjustmentControl,
            exposureMode: exposureMode,
            focusMode: focusMode,
            draft: draft
        )
    }

    private func selectMode(_ mode: CameraCaptureModeOption) {
        guard mode.isAvailableInStageOne else {
            status = "Coming soon"
            return
        }

        selectedMode = mode
        status = "\(mode.title) selected"
    }

    private func selectAdjustmentControl(_ control: CameraAdjustmentControl) {
        switch control {
        case .ev:
            activeAdjustmentControl = activeAdjustmentControl == .ev ? nil : .ev
            status = activeAdjustmentControl == .ev ? "EV strip shown" : "Controls hidden"
        case .iso:
            activeAdjustmentControl = activeAdjustmentControl == .iso ? nil : .iso
            status = activeAdjustmentControl == .iso ? "ISO strip shown" : "Controls hidden"
        case .shutter:
            activeAdjustmentControl = activeAdjustmentControl == .shutter ? nil : .shutter
            status = activeAdjustmentControl == .shutter ? "Shutter strip shown" : "Controls hidden"
        case .focus:
            activeAdjustmentControl = activeAdjustmentControl == .focus ? nil : .focus
            status = activeAdjustmentControl == .focus ? "Focus strip shown" : "Controls hidden"
        }
    }

    private func restoreAutomaticMode(_ control: CameraAdjustmentControl) {
        switch control {
        case .iso:
            switch exposureMode {
            case .isoPriority(let globalBias):
                exposureMode = .auto(globalBias: globalBias)
            case .custom:
                exposureMode = .shutterPriority(globalBias: 0)
            case .auto, .shutterPriority:
                return
            }
            activeAdjustmentControl = .iso
            status = "ISO Auto restored"
        case .shutter:
            switch exposureMode {
            case .shutterPriority(let globalBias):
                exposureMode = .auto(globalBias: globalBias)
            case .custom:
                exposureMode = .isoPriority(globalBias: 0)
            case .auto, .isoPriority:
                return
            }
            activeAdjustmentControl = .shutter
            status = "Shutter Auto restored"
        case .focus:
            guard focusMode == .manual else {
                return
            }
            focusMode = .auto
            activeAdjustmentControl = .focus
            status = "Focus Auto restored"
        case .ev:
            return
        }
    }

    private func adjustEV(_ value: Double) {
        let clamped = CameraEVPreferences.clampedBias(value)
        switch exposureMode {
        case .auto:
            exposureMode = .auto(globalBias: clamped)
        case .isoPriority:
            exposureMode = .isoPriority(globalBias: clamped)
        case .shutterPriority:
            exposureMode = .shutterPriority(globalBias: clamped)
        case .custom:
            break
        }
        status = "EV \(Self.signedLabel(clamped))"
    }

    private func adjustISO(_ value: Double) {
        let state = adjustmentState
        let snappedISO = state.exposure.isoScale.snappedValue(for: value)
        draft = draft.replacingISO(snappedISO).clamped(to: state)
        switch exposureMode {
        case .auto(let globalBias), .isoPriority(let globalBias):
            exposureMode = .isoPriority(globalBias: globalBias)
        case .shutterPriority, .custom:
            exposureMode = .custom(meterOffset: 0)
        }
        activeAdjustmentControl = .iso
        status = "ISO \(state.exposure.isoScale.label(for: draft.iso))"
    }

    private func adjustShutterPosition(_ position: Double) {
        let state = adjustmentState
        draft = draft.replacingShutterDuration(
            state.exposure.shutterDuration(forPosition: position)
        ).clamped(to: state)
        switch exposureMode {
        case .auto(let globalBias), .shutterPriority(let globalBias):
            exposureMode = .shutterPriority(globalBias: globalBias)
        case .isoPriority, .custom:
            exposureMode = .custom(meterOffset: 0)
        }
        activeAdjustmentControl = .shutter
        status = "Shutter \(state.exposure.shutterScale.label(for: draft.shutterDurationSeconds))"
    }

    private func adjustLensPosition(_ value: Double) {
        let state = adjustmentState
        draft = draft.replacingLensPosition(state.focus.clampedLensPosition(value)).clamped(to: state)
        focusMode = .manual
        activeAdjustmentControl = .focus
        status = "MF \(state.focus.lensPositionLabel(for: draft.lensPosition))"
    }

    private static func signedLabel(_ value: Double) -> String {
        guard value.isFinite, abs(value) >= 0.05 else {
            return "0.0"
        }
        return String(format: "%+0.1f", value)
    }

    private static let capability = CameraControlCapabilitySnapshot(
        deviceID: "camera-controls-ui-harness",
        deviceDisplayName: "UI Harness Camera",
        deviceTypeRawValue: "harness",
        exposure: CameraControlCapabilitySnapshot.Exposure(
            supportsContinuousAutoExposure: true,
            supportsLockedExposure: true,
            supportsCustomExposure: true,
            exposureBiasRange: CameraControlCapabilitySnapshot.DoubleRange(minimum: -2, maximum: 2),
            isoRange: CameraControlCapabilitySnapshot.DoubleRange(minimum: 64, maximum: 1_250),
            shutterDurationRangeSeconds: CameraControlCapabilitySnapshot.DoubleRange(
                minimum: 1.0 / 8_000.0,
                maximum: 0.5
            ),
            currentISO: 200,
            currentShutterDurationSeconds: 1.0 / 120.0,
            currentExposureTargetOffset: 0
        ),
        focus: CameraControlCapabilitySnapshot.Focus(
            supportsAutoFocus: true,
            supportsContinuousAutoFocus: true,
            supportsLockedFocus: true,
            supportsCustomLensPosition: true,
            supportsFocusPointOfInterest: true,
            supportsSmoothAutoFocus: true,
            minimumFocusDistanceMillimeters: 125,
            currentLensPosition: 0.5
        ),
        whiteBalance: CameraControlCapabilitySnapshot.WhiteBalance(
            supportsContinuousAutoWhiteBalance: true,
            supportsLockedWhiteBalance: true,
            maximumGain: 8
        ),
        aperture: CameraControlCapabilitySnapshot.Aperture(fixedLensAperture: 1.8),
        zoom: CameraControlCapabilitySnapshot.Zoom(
            range: CameraControlCapabilitySnapshot.DoubleRange(minimum: 1, maximum: 5)
        )
    )
}
#endif
