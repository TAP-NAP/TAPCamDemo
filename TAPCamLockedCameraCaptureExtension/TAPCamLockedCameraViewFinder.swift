//
//  TAPCamLockedCameraViewFinder.swift
//  TAPCamDemo
//

import AVKit
import LockedCameraCapture
import OSLog
import SwiftUI

struct TAPCamLockedCameraViewFinder: View {
    let camera: TAPCamLockedCameraModel
    let session: LockedCameraCaptureSession
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
                session: session,
                sessionContentURL: sessionContentURL
            )
        }
        .accessibilityIdentifier("locked-camera-r4-root")
        .onAppear {
            TAPCamLockedCameraDiagnostics.logger(category: "LockedCameraR4B")
                .notice("r4b_extension_root_appear")
        }
        .onDisappear {
            TAPCamLockedCameraDiagnostics.logger(category: "LockedCameraR4B")
                .notice("r4b_extension_root_disappear")
        }
    }
}

private struct TAPCamLockedCameraChrome: View {
    let camera: TAPCamLockedCameraModel
    let session: LockedCameraCaptureSession
    let sessionContentURL: URL

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Text("TAPCam R4")
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

                TAPCamLockedBottomControls(
                    camera: camera,
                    session: session,
                    sessionContentURL: sessionContentURL
                )
                .padding(.bottom, 28)
            }

            if camera.phase != .live {
                TAPCamLockedCameraStatusView(phase: camera.phase)
            }
        }
    }
}

private struct TAPCamLockedBottomControls: View {
    let camera: TAPCamLockedCameraModel
    let session: LockedCameraCaptureSession
    let sessionContentURL: URL

    var body: some View {
        ZStack(alignment: .bottom) {
            if camera.phase == .live {
                TAPCamLockedPhotoControls(
                    camera: camera,
                    sessionContentURL: sessionContentURL
                )
            }

            HStack {
                TAPCamLockedCameraOpenControl(session: session)

                Spacer(minLength: 0)

                Color.clear
                    .frame(width: 72, height: 78)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 28)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 104)
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
            .accessibilityIdentifier("locked-camera-r4-shutter")

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
        .accessibilityIdentifier("locked-camera-r4-status")
    }
}
