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
    private let areHapticsAllowedDuringAudioInput: () -> Bool
    private let enableHapticsDuringAudioInput: () throws -> Void
    private var didReportAudioInputAllowanceFailure = false

    init(
        areHapticsAllowedDuringAudioInput: @escaping () -> Bool = {
            AVAudioSession.sharedInstance().allowHapticsAndSystemSoundsDuringRecording
        },
        enableHapticsDuringAudioInput: @escaping () throws -> Void = {
            try AVAudioSession.sharedInstance()
                .setAllowHapticsAndSystemSoundsDuringRecording(true)
        }
    ) {
        self.areHapticsAllowedDuringAudioInput = areHapticsAllowedDuringAudioInput
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

    func prepareForCameraInteraction() {
        if isEnabled {
            prepareAdjustmentFeedback()
            shutterImpactGenerator.prepare()
        }
        hasPreparedCameraInteraction = true
    }

    func prepareAdjustmentFeedback() {
        guard isEnabled else {
            return
        }
        enableRecordingHapticsIfPossible()
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
        // Audio input can also come from TAP Video, and the shared audio session
        // can change while the photo configuration stays the same.
        guard !areHapticsAllowedDuringAudioInput() else {
            didReportAudioInputAllowanceFailure = false
            return
        }
        do {
            try enableHapticsDuringAudioInput()
            didReportAudioInputAllowanceFailure = false
        } catch {
            #if DEBUG
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
