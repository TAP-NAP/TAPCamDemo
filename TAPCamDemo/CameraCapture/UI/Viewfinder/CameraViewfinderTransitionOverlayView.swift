//
//  CameraViewfinderTransitionOverlayView.swift
//  TAPCamDemo
//

import SwiftUI

/// Presentation-only state for camera-path transitions.
///
/// Camera/session readiness remains owned by `CameraView`. The overlay only
/// describes what is already happening and never advances a transition itself.
nonisolated enum CameraViewfinderTransitionPresentation: Equatable, Sendable {
    static let duration = 0.2

    case hidden
    case switchingCaptureMode
    case switchingFocalLength
    case presented(message: String)
    case failed(message: String)

    static var activatingProMode: Self {
        .presented(message: "Starting Pro mode…")
    }

    static var deactivatingProMode: Self {
        .presented(message: "Returning to standard mode…")
    }

    static var switchingToFrontCamera: Self {
        .presented(message: "Switching to front camera…")
    }

    static var switchingToRearCamera: Self {
        .presented(message: "Switching to rear camera…")
    }

    static var restoringProMode: Self {
        .presented(message: "Restoring Pro mode…")
    }

    var isPresented: Bool {
        switch self {
        case .hidden:
            false
        case .switchingCaptureMode, .switchingFocalLength, .presented, .failed:
            true
        }
    }

    var message: String? {
        switch self {
        case .hidden, .switchingCaptureMode, .switchingFocalLength:
            nil
        case .presented(let message), .failed(let message):
            message
        }
    }

    var showsProgressIndicator: Bool {
        guard case .presented = self else {
            return false
        }
        return true
    }

    var keepsFocalLengthSelector: Bool {
        switch self {
        case .hidden, .switchingCaptureMode, .switchingFocalLength:
            true
        case .presented, .failed:
            false
        }
    }
}

/// Frosts the current viewfinder while its camera path is being reconfigured.
///
/// The native preview view retains its rendered appearance during input swaps.
struct CameraViewfinderTransitionOverlayView: View {
    let presentation: CameraViewfinderTransitionPresentation
    var recoveryActionTitle: String? = nil
    var onRecoveryAction: (() -> Void)? = nil

    var body: some View {
        ZStack {
            if presentation.isPresented {
                Rectangle()
                    .fill(.regularMaterial)

                Color.black.opacity(0.18)

                if presentation.message != nil {
                    status
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .allowsHitTesting(presentation.isPresented)
        .accessibilityElement(children: recoveryActionTitle == nil ? .combine : .contain)
        .accessibilityHidden(!presentation.isPresented)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityIdentifier("camera.viewfinder.transitionOverlay")
        .animation(.easeInOut(duration: CameraViewfinderTransitionPresentation.duration), value: presentation.isPresented)
    }

    private var status: some View {
        VStack(spacing: 12) {
            if presentation.showsProgressIndicator && recoveryActionTitle == nil {
                ProgressView()
                    .controlSize(.regular)
                    .tint(.white)
            } else {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.white)
            }

            if let message = presentation.message {
                CameraViewfinderTransitionCopy.text(for: message)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .accessibilityIdentifier("camera.viewfinder.transitionMessage")
            }

            if let recoveryActionTitle, let onRecoveryAction {
                Button(action: onRecoveryAction) {
                    CameraViewfinderTransitionCopy.text(for: recoveryActionTitle)
                }
                .buttonStyle(.borderedProminent)
                .tint(.white)
                .foregroundStyle(.black)
                .accessibilityIdentifier("camera.viewfinder.transitionRetry")
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(.black.opacity(0.28), in: Capsule())
    }

    private var accessibilityLabel: Text {
        guard let message = presentation.message else {
            return Text(verbatim: "")
        }
        return CameraViewfinderTransitionCopy.text(for: message)
    }
}

private enum CameraViewfinderTransitionCopy {
    private static let localizedMessages: Set<String> = [
        "Starting Pro mode…",
        "Returning to standard mode…",
        "Switching to front camera…",
        "Switching to rear camera…",
        "Restoring Pro mode…",
        "Restoring standard camera…",
        "Unable to restore the camera.",
        "Camera service is not responding. Reopen TAP-NAP if it does not recover.",
        "Retry"
    ]

    static func text(for message: String) -> Text {
        guard localizedMessages.contains(message) else {
            // Presentation cases may carry a future runtime value; keep it verbatim.
            return Text(verbatim: message)
        }
        return Text(LocalizedStringKey(message))
    }
}
