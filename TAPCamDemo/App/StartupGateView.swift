//
//  StartupGateView.swift
//  TAPCamDemo
//

import LockedCameraCapture
import OSLog
import SwiftUI

struct StartupGateView: View {
    @AppStorage(StartupGateDefaults.didCompleteFirstInstallSetupKey)
    private var didCompleteFirstInstallSetup = false

    @StateObject private var startupCoordinator = StartupGateCoordinator()

    var body: some View {
        Group {
            if didCompleteFirstInstallSetup {
                CameraView()
            } else {
                WelcomeStartupSetupView(coordinator: startupCoordinator) {
                    completeFirstInstallSetupIfReady()
                }
            }
        }
        .task {
            await LockedCameraAppContextPublisher.publishCurrentContextIfAvailable()
        }
        .onContinueUserActivity(TAPCamLockedCameraHandoff.activityType) { activity in
            handleLockedCameraHandoff(activity)
        }
    }

    private func completeFirstInstallSetupIfReady() {
        guard startupCoordinator.hasCompletedRequiredStartupChecks else {
            return
        }
        didCompleteFirstInstallSetup = true
    }

    private func handleLockedCameraHandoff(_ activity: NSUserActivity) {
        guard let handoff = TAPCamIntentHandoff(lockedCameraActivity: activity) else {
            return
        }
        LockedCameraDiagnostics.logger.info(
            "locked_camera_handoff_received destination=\(handoff.destination.rawValue, privacy: .public) tapAction=\(handoff.tapAction ?? "none", privacy: .public) reason=\(handoff.reason ?? "none", privacy: .public) managerSessionCount=\(LockedCameraCaptureManager.shared.sessionContentURLs.count, privacy: .public)"
        )

        let delaysAppearance = beginLockedCameraTransitionDelayIfNeeded(for: handoff)

        TAPCamIntentHandoffStore().saveHandoff(handoff)
        NotificationCenter.default.post(name: .tapCamIntentHandoffDidChange, object: nil)

        if delaysAppearance {
            Task {
                let summary = await LockedCaptureSessionContentImportCoordinator.shared
                    .importAvailableSessionContentAfterSessionContentSettles(reason: "locked_camera_transition")
                await MainActor.run {
                    endLockedCameraTransitionDelay(
                        for: handoff,
                        importedCount: summary.importedCount,
                        sessionCount: summary.scannedSessionCount
                    )
                }
            }
        }

        guard handoff.shouldRegenerateLockedCameraContext else {
            LockedCameraDiagnostics.logger.info(
                "locked_camera_handoff_route_no_context_refresh destination=\(handoff.destination.rawValue, privacy: .public) tapAction=\(handoff.tapAction ?? "none", privacy: .public) reason=\(handoff.reason ?? "none", privacy: .public)"
            )
            return
        }

        Task {
            await LockedCameraAppContextPublisher.publishCurrentContextIfAvailable()
        }
    }

    private func beginLockedCameraTransitionDelayIfNeeded(for handoff: TAPCamIntentHandoff) -> Bool {
        guard handoff.shouldDelayAppearanceForLockedContent else {
            LockedCameraDiagnostics.logger.info(
                "locked_camera_transition_delay_skipped destination=\(handoff.destination.rawValue, privacy: .public) tapAction=\(handoff.tapAction ?? "none", privacy: .public) reason=\(handoff.reason ?? "none", privacy: .public)"
            )
            return false
        }

        if #available(iOS 18.1, *) {
            LockedCameraCaptureManager.shared.beginDelayingAppearance()
            LockedCameraDiagnostics.logger.info(
                "locked_camera_transition_delay_begin destination=\(handoff.destination.rawValue, privacy: .public) tapAction=\(handoff.tapAction ?? "none", privacy: .public) reason=\(handoff.reason ?? "none", privacy: .public)"
            )
            return true
        }

        LockedCameraDiagnostics.logger.info(
            "locked_camera_transition_delay_unavailable destination=\(handoff.destination.rawValue, privacy: .public) tapAction=\(handoff.tapAction ?? "none", privacy: .public)"
        )
        return false
    }

    private func endLockedCameraTransitionDelay(
        for handoff: TAPCamIntentHandoff,
        importedCount: Int,
        sessionCount: Int
    ) {
        if #available(iOS 18.1, *) {
            LockedCameraCaptureManager.shared.endDelayingAppearance()
            LockedCameraDiagnostics.logger.info(
                "locked_camera_transition_delay_end destination=\(handoff.destination.rawValue, privacy: .public) imported=\(importedCount, privacy: .public) sessions=\(sessionCount, privacy: .public)"
            )
        }
    }
}
