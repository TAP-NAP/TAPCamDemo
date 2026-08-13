//
//  DepthAnalysisShareFeedback.swift
//  TAPCamDemo
//

import UIKit

@MainActor
final class DepthAnalysisShareFeedback {
    private let selection = UISelectionFeedbackGenerator()
    private let impact = UIImpactFeedbackGenerator(style: .light)
    private let notification = UINotificationFeedbackGenerator()

    func prepare() {
        selection.prepare()
        impact.prepare()
        notification.prepare()
    }

    func opened() {
        impact.impactOccurred(intensity: 0.72)
        impact.prepare()
    }

    func optionSelected() {
        selection.selectionChanged()
        selection.prepare()
    }

    func failed() {
        notification.notificationOccurred(.error)
        notification.prepare()
    }
}
