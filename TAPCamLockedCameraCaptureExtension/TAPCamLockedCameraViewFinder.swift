//
//  TAPCamLockedCameraViewFinder.swift
//  TAPCamDemo
//

import AVKit
import SwiftUI

struct TAPCamLockedCameraViewFinder: View {
    let camera: TAPCamLockedCameraModel

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            TAPCamLockedCameraPreview(source: camera.previewSource)
                .ignoresSafeArea()
                .onCameraCaptureEvent(isEnabled: camera.phase == .live) { event in
                    camera.registerCaptureEvent(event)
                }

            if camera.shouldFlashCaptureProbe {
                Color.white
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }

            TAPCamLockedCameraChrome(phase: camera.phase)
        }
        .accessibilityIdentifier("locked-camera-r1-root")
    }
}

private struct TAPCamLockedCameraChrome: View {
    let phase: TAPCamLockedCameraPhase

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Text("TAPCam R1")
                        .font(.headline)

                    Spacer(minLength: 12)

                    Circle()
                        .fill(phase == .live ? Color.green : Color.orange)
                        .frame(width: 8, height: 8)

                    Text(phase.shortLabel)
                        .font(.caption.weight(.semibold))
                }
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.8), radius: 3)
                .padding(.horizontal, 20)
                .padding(.top, 16)

                Spacer(minLength: 0)
            }

            if phase != .live {
                TAPCamLockedCameraStatusView(phase: phase)
            }
        }
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
        .accessibilityIdentifier("locked-camera-r1-status")
    }
}
