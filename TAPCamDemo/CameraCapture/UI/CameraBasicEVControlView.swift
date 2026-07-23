//
//  CameraBasicEVControlView.swift
//  TAPCamDemo
//

import Foundation
import SwiftUI

nonisolated struct CameraBasicEVControlState: Equatable, Sendable {
    let bias: Double
    let isStripVisible: Bool

    init(
        bias: Double,
        isStripVisible: Bool
    ) {
        self.bias = CameraEVPreferences.clampedBias(bias)
        self.isStripVisible = isStripVisible
    }

    var compactValue: String {
        Self.signedLabel(bias)
    }

    var accessibilityLabel: String {
        "Exposure compensation \(compactValue)"
    }

    private static func signedLabel(_ value: Double) -> String {
        guard value.isFinite, abs(value) >= 0.05 else {
            return "0.0"
        }
        return String(format: "%+0.1f", value)
    }
}

struct CameraBasicEVButton: View {
    let state: CameraBasicEVControlState
    let highlightColor: Color
    let contentRotation: Angle
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            CenterAnchoredChromeRotation(
                rotation: contentRotation,
                width: Metrics.width,
                height: Metrics.height
            ) {
                HStack(spacing: 3) {
                    Text("EV")
                        .font(.system(size: 11, weight: .semibold))
                        .monospaced()
                        .lineLimit(1)
                    Text(state.compactValue)
                        .font(.system(size: 11, weight: .medium))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }
            }
            .foregroundStyle(state.isStripVisible ? highlightColor : Color.white)
            .contentShape(Rectangle())
        }
        .buttonStyle(CameraNoHighlightButtonStyle())
        .accessibilityLabel(state.accessibilityLabel)
        .accessibilityIdentifier("camera.chrome.basicEV")
        .help("Adjust exposure compensation.")
    }

    private enum Metrics {
        static let width: CGFloat = 48
        static let height: CGFloat = 26
    }
}

private struct CameraNoHighlightButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
    }
}

struct CameraBasicEVAdjustmentStrip: View {
    let state: CameraBasicEVControlState
    let highlightColor: Color
    let contentRotation: Angle
    let onAdjustEV: (Double) -> Void

    var body: some View {
        CameraTickedSliderRow(
            title: "EV",
            value: state.compactValue,
            valueBinding: Binding(
                get: { state.bias },
                set: { onAdjustEV(CameraEVPreferences.clampedBias($0)) }
            ),
            range: CameraEVPreferences.minimumGlobalBias...CameraEVPreferences.maximumGlobalBias,
            step: CameraEVPreferences.adjustmentStep,
            isEnabled: true,
            highlightColor: highlightColor,
            contentRotation: contentRotation,
            riskRanges: [],
            tickValueStep: CameraEVPreferences.adjustmentStep,
            isEVIntegerHapticsEnabled: true,
            onEditingBegan: {},
            onEditingEnded: {}
        )
        .accessibilityIdentifier("camera.basicEV.adjustmentStrip")
    }
}
