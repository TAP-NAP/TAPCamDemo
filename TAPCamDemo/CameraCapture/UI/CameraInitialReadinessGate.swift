//
//  CameraInitialReadinessGate.swift
//  TAPCamDemo
//

@preconcurrency import AVFoundation
import SwiftUI

struct CameraInitialReadinessGate {
    let isEnabled: Bool
    let onReady: () -> Void

    static let disabled = CameraInitialReadinessGate(isEnabled: false, onReady: {})

    static func firstInstall(onReady: @escaping () -> Void) -> CameraInitialReadinessGate {
        CameraInitialReadinessGate(isEnabled: true, onReady: onReady)
    }
}

nonisolated enum CameraInteractiveReadinessState: Equatable {
    case inactive
    case preparing(message: String)
    case ready
    case failed(message: String, canOpenSettings: Bool)

    var blocksInteraction: Bool {
        switch self {
        case .inactive, .ready:
            false
        case .preparing, .failed:
            true
        }
    }

    static func resolve(
        isGateEnabled: Bool,
        didCompleteGate: Bool,
        cameraAuthorizationStatus: AVAuthorizationStatus,
        isConfiguringSession: Bool,
        hasActiveSessionConfiguration: Bool,
        isDepthCaptureReady: Bool,
        hasPreparedHaptics: Bool,
        statusMessage: String
    ) -> CameraInteractiveReadinessState {
        guard isGateEnabled, !didCompleteGate else {
            return .inactive
        }

        switch cameraAuthorizationStatus {
        case .authorized:
            if hasActiveSessionConfiguration, isDepthCaptureReady, hasPreparedHaptics {
                return .ready
            }

            if isConfiguringSession || isPreparingStatusMessage(statusMessage) || !hasPreparedHaptics {
                return .preparing(message: nonEmptyStatusMessage(statusMessage))
            }

            return .failed(message: nonEmptyStatusMessage(statusMessage), canOpenSettings: false)
        case .notDetermined:
            return .preparing(message: nonEmptyStatusMessage(statusMessage))
        case .denied, .restricted:
            return .failed(message: nonEmptyStatusMessage(statusMessage), canOpenSettings: true)
        @unknown default:
            return .failed(message: nonEmptyStatusMessage(statusMessage), canOpenSettings: true)
        }
    }

    private static func nonEmptyStatusMessage(_ statusMessage: String) -> String {
        statusMessage.isEmpty ? "Preparing camera..." : statusMessage
    }

    private static func isPreparingStatusMessage(_ statusMessage: String) -> Bool {
        let normalized = statusMessage.lowercased()
        return normalized.isEmpty
            || normalized.contains("preparing")
            || normalized.contains("waiting")
    }
}

struct CameraInitialReadinessOverlayView: View {
    let state: CameraInteractiveReadinessState
    let onRetry: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            switch state {
            case .inactive, .ready:
                EmptyView()
            case .preparing(let message):
                VStack(spacing: 16) {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(1.08)

                    Text("Preparing camera")
                        .font(.headline)
                        .foregroundStyle(.white)

                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.68))
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .padding(.horizontal, 34)
                }
            case .failed(let message, let canOpenSettings):
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundStyle(.yellow)

                    Text("Camera setup needs attention")
                        .font(.headline)
                        .foregroundStyle(.white)

                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.68))
                        .multilineTextAlignment(.center)
                        .lineLimit(4)
                        .padding(.horizontal, 34)

                    HStack(spacing: 12) {
                        Button {
                            onRetry()
                        } label: {
                            Label("Retry", systemImage: "arrow.clockwise")
                                .font(.headline)
                                .frame(minWidth: 108, minHeight: 44)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.white)
                        .foregroundStyle(.black)

                        if canOpenSettings {
                            Button {
                                onOpenSettings()
                            } label: {
                                Label("Settings", systemImage: "gearshape")
                                    .font(.headline)
                                    .frame(minWidth: 108, minHeight: 44)
                            }
                            .buttonStyle(.bordered)
                            .tint(.white)
                        }
                    }
                }
            }
        }
        .accessibilityIdentifier("camera.initialReadiness.overlay")
    }
}
