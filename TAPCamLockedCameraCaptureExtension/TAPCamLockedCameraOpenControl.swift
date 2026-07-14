//
//  TAPCamLockedCameraOpenControl.swift
//  TAPCamDemo
//

import LockedCameraCapture
import OSLog
import SwiftUI

struct TAPCamLockedCameraOpenControl: View {
    let session: LockedCameraCaptureSession

    @State private var state = OpenState.idle

    var body: some View {
        Button(action: requestOpen) {
            VStack(spacing: 5) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(.black.opacity(0.46))
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(.white.opacity(0.9), lineWidth: 1.5)

                    if state == .requesting {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: state == .failed ? "exclamationmark.triangle" : "photo.on.rectangle")
                            .font(.system(size: 22, weight: .semibold))
                    }
                }
                .frame(width: 56, height: 56)

                Text(state.label)
                    .font(.caption2.weight(.bold))
                    .frame(width: 72, height: 14)
            }
            .foregroundStyle(state == .failed ? Color.red : Color.white)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(state == .requesting)
        .frame(width: 72, height: 78)
        .accessibilityLabel(state == .failed ? "Retry opening TAP Library" : "Open TAP Library")
        .accessibilityIdentifier("locked-camera-r4-open-library")
    }

    private func requestOpen() {
        guard state != .requesting else {
            return
        }

        let requestID = UUID().uuidString
        state = .requesting
        TAPCamLockedCameraDiagnostics.logger(category: "LockedCameraR4")
            .notice("r4_open_tap_received requestID=\(requestID, privacy: .public)")

        let activity = TAPCamLockedCameraOpenActivity.makeTapLibraryActivity()
        Task { @MainActor in
            TAPCamLockedCameraDiagnostics.logger(category: "LockedCameraR4")
                .notice("r4_open_request_begin requestID=\(requestID, privacy: .public)")
            do {
                try await session.openApplication(for: activity)
                state = .accepted
                TAPCamLockedCameraDiagnostics.logger(category: "LockedCameraR4")
                    .notice("r4_open_request_accepted requestID=\(requestID, privacy: .public)")
            } catch {
                state = .failed
                let nsError = error as NSError
                TAPCamLockedCameraDiagnostics.logger(category: "LockedCameraR4")
                    .error("r4_open_request_failed requestID=\(requestID, privacy: .public) domain=\(nsError.domain, privacy: .public) code=\(nsError.code, privacy: .public)")
            }
        }
    }
}

private extension TAPCamLockedCameraOpenControl {
    enum OpenState {
        case idle
        case requesting
        case accepted
        case failed

        var label: String {
            switch self {
            case .idle:
                "OPEN"
            case .requesting:
                "OPENING"
            case .accepted:
                "OPENED"
            case .failed:
                "TRY AGAIN"
            }
        }
    }
}
