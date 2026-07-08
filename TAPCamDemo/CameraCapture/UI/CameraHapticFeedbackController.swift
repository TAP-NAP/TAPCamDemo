//
//  CameraHapticFeedbackController.swift
//  TAPCamDemo
//

import Combine
import SwiftUI
import UIKit

enum CameraAdjustmentHapticStyle: Equatable, Sendable {
    case selection
    case integerTick
    case zeroTick
}

final class CameraHapticFeedbackController: ObservableObject {
    @Published private(set) var hasPreparedCameraInteraction = false

    private let shutterImpactGenerator = UIImpactFeedbackGenerator(style: .medium)
    private let selectionGenerator = UISelectionFeedbackGenerator()
    private let integerImpactGenerator = UIImpactFeedbackGenerator(style: .medium)
    private let zeroImpactGenerator = UIImpactFeedbackGenerator(style: .heavy)

    func prepareForCameraInteraction() {
        shutterImpactGenerator.prepare()
        prepareAdjustmentFeedback()
        hasPreparedCameraInteraction = true
    }

    func prepareAdjustmentFeedback() {
        selectionGenerator.prepare()
        integerImpactGenerator.prepare()
        zeroImpactGenerator.prepare()
    }

    func shutterAccepted() {
        shutterImpactGenerator.impactOccurred()
        shutterImpactGenerator.prepare()
    }

    func adjustmentChanged(style: CameraAdjustmentHapticStyle) {
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
