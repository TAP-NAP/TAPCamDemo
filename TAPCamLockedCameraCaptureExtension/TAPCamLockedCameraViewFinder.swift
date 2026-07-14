//
//  TAPCamLockedCameraViewFinder.swift
//  TAPCamDemo
//

import AVKit
import SwiftUI

struct TAPCamLockedCameraViewFinder: View {
    let camera: TAPCamLockedCameraModel
    let sessionContentURL: URL

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            TAPCamLockedCameraPreview(source: camera.previewSource)
                .ignoresSafeArea()
                .onCameraCaptureEvent(isEnabled: camera.phase == .live) { event in
                    guard event.phase == .ended else { return }
                    Task {
                        await camera.captureDepthPhoto(
                            trigger: .hardwareEvent,
                            sessionContentURL: sessionContentURL
                        )
                    }
                }

            if camera.shouldFlashCaptureFeedback {
                Color.white
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }

            TAPCamLockedCameraChrome(
                camera: camera,
                sessionContentURL: sessionContentURL
            )
        }
        .accessibilityIdentifier("locked-camera-r2b-root")
    }
}

private struct TAPCamLockedCameraChrome: View {
    let camera: TAPCamLockedCameraModel
    let sessionContentURL: URL

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Text("TAPCam R2B")
                        .font(.headline)

                    Spacer(minLength: 12)

                    Circle()
                        .fill(camera.phase == .live ? Color.green : Color.orange)
                        .frame(width: 8, height: 8)

                    Text(camera.phase.shortLabel)
                        .font(.caption.weight(.semibold))
                }
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.8), radius: 3)
                .padding(.horizontal, 20)
                .padding(.top, 16)

                Spacer(minLength: 0)

                if camera.phase == .live {
                    TAPCamLockedPhotoControls(
                        camera: camera,
                        sessionContentURL: sessionContentURL
                    )
                        .padding(.bottom, 28)
                }
            }

            if camera.phase != .live {
                TAPCamLockedCameraStatusView(phase: camera.phase)
            }
        }
    }
}

private struct TAPCamLockedPhotoControls: View {
    let camera: TAPCamLockedCameraModel
    let sessionContentURL: URL

    var body: some View {
        VStack(spacing: 10) {
            Button {
                Task {
                    await camera.captureDepthPhoto(
                        trigger: .shutterButton,
                        sessionContentURL: sessionContentURL
                    )
                }
            } label: {
                ZStack {
                    Circle()
                        .stroke(.white, lineWidth: 4)
                    Circle()
                        .fill(.white)
                        .padding(7)
                }
                .frame(width: 72, height: 72)
                .contentShape(Circle())
            }
            .buttonStyle(TAPCamLockedShutterButtonStyle())
            .disabled(!camera.isPhotoCaptureEnabled)
            .accessibilityLabel("Capture depth photo")
            .accessibilityIdentifier("locked-camera-r2b-shutter")

            Text(camera.photoCaptureState.shortLabel)
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(captureStatusColor)
                .frame(height: 18)
                .shadow(color: .black.opacity(0.8), radius: 3)
        }
    }

    private var captureStatusColor: Color {
        if case .failed = camera.photoCaptureState {
            .red
        } else {
            .white
        }
    }
}

private struct TAPCamLockedShutterButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.88 : 1)
            .opacity(configuration.isPressed ? 0.82 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private struct TAPCamLockedCameraStatusView: View {
    let phase: TAPCamLockedCameraPhase

    var body: some View {
        VStack(spacing: 14) {
            if phase == .starting {
                ProgressView()
                    .tint(.white)
                    .controlSize(.large)
            } else {
                Image(systemName: phase.systemImage)
                    .font(.system(size: 30, weight: .medium))
            }

            Text(phase.title)
                .font(.headline)

            if let detail = phase.detail {
                Text(detail)
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.72))
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 32)
        .accessibilityIdentifier("locked-camera-r2b-status")
    }
}
