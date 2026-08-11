//
//  CameraHapticFeedbackController.swift
//  TAPCamDemo
//

import AVFAudio
import Combine
import OSLog
import SwiftUI
import UIKit

enum CameraAdjustmentHapticStyle: Equatable, Sendable {
    case selection
    case integerTick
    case zeroTick
}

final class CameraHapticFeedbackController: ObservableObject {
    @Published private(set) var hasPreparedCameraInteraction = false
    private(set) var isEnabled = true

    private let shutterImpactGenerator = UIImpactFeedbackGenerator(style: .medium)
    private let selectionGenerator = UISelectionFeedbackGenerator()
    private let integerImpactGenerator = UIImpactFeedbackGenerator(style: .medium)
    private let zeroImpactGenerator = UIImpactFeedbackGenerator(style: .heavy)
    private let enableHapticsDuringAudioInput: () throws -> Void
    private var isCameraAudioInputActive = false
    private var hasEnabledHapticsDuringAudioInput = false
    private var didReportAudioInputAllowanceFailure = false

    init(
        enableHapticsDuringAudioInput: @escaping () throws -> Void = {
            try AVAudioSession.sharedInstance()
                .setAllowHapticsAndSystemSoundsDuringRecording(true)
        }
    ) {
        self.enableHapticsDuringAudioInput = enableHapticsDuringAudioInput
    }

    func setEnabled(_ isEnabled: Bool) {
        guard self.isEnabled != isEnabled else {
            return
        }
        self.isEnabled = isEnabled
        if isEnabled {
            prepareForCameraInteraction()
        }
    }

    func cameraAudioInputDidChange(isActive: Bool) {
        guard isCameraAudioInputActive != isActive else {
            return
        }
        isCameraAudioInputActive = isActive
        hasEnabledHapticsDuringAudioInput = false
        didReportAudioInputAllowanceFailure = false
        if isActive, isEnabled {
            enableRecordingHapticsIfPossible()
        }
    }

    func prepareForCameraInteraction() {
        if isEnabled {
            if isCameraAudioInputActive {
                enableRecordingHapticsIfPossible()
            }
            shutterImpactGenerator.prepare()
            prepareAdjustmentFeedback()
        }
        hasPreparedCameraInteraction = true
    }

    func prepareAdjustmentFeedback() {
        guard isEnabled else {
            return
        }
        selectionGenerator.prepare()
        integerImpactGenerator.prepare()
        zeroImpactGenerator.prepare()
    }

    func shutterAccepted() {
        guard isEnabled else {
            return
        }
        enableRecordingHapticsIfPossible()
        shutterImpactGenerator.impactOccurred()
        shutterImpactGenerator.prepare()
    }

    func adjustmentChanged(style: CameraAdjustmentHapticStyle) {
        guard isEnabled else {
            return
        }
        enableRecordingHapticsIfPossible()
        switch style {
        case .selection:
            selectionGenerator.selectionChanged()
            selectionGenerator.prepare()
        case .integerTick:
            integerImpactGenerator.impactOccurred(intensity: 0.78)
            integerImpactGenerator.prepare()
        case .zeroTick:
            zeroImpactGenerator.impactOccurred(intensity: 1)
            zeroImpactGenerator.prepare()
        }
    }

    private func enableRecordingHapticsIfPossible() {
        guard isCameraAudioInputActive,
              !hasEnabledHapticsDuringAudioInput else {
            return
        }
        do {
            try enableHapticsDuringAudioInput()
            hasEnabledHapticsDuringAudioInput = true
        } catch {
            #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
            if !didReportAudioInputAllowanceFailure {
                TAPDiagnostics.cameraCapture.error(
                    "camera haptics audio-input allowance failed error=\(TAPDiagnostics.describe(error), privacy: .public)"
                )
            }
            #endif
            didReportAudioInputAllowanceFailure = true
        }
    }
}

private struct CameraHapticFeedbackControllerKey: EnvironmentKey {
    static let defaultValue = CameraHapticFeedbackController()
}

extension EnvironmentValues {
    var cameraHapticFeedbackController: CameraHapticFeedbackController {
        get { self[CameraHapticFeedbackControllerKey.self] }
        set { self[CameraHapticFeedbackControllerKey.self] = newValue }
    }
}
