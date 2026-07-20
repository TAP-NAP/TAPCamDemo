//
//  StartupGateView.swift
//  TAPCamDemo
//

import LockedCameraCapture
import Combine
import OSLog
import Photos
import SwiftUI
import UIKit

struct StartupGateView: View {
    let libraryStore: LibraryMediaStore
    let libraryMediaFetcher: any LibraryMediaFetching
    let videoPosterBackfillService: LibraryVideoPosterBackfillService

    @AppStorage(StartupGateDefaults.didCompleteFirstInstallSetupKey)
    private var didCompleteFirstInstallSetup = false

    @StateObject private var startupCoordinator = StartupGateCoordinator()
    @State private var neutralLockedCameraHandoff: TAPCamIntentHandoff?
    @State private var isPreparingFirstInstallCameraReadiness = false

    var body: some View {
        Group {
            if let neutralLockedCameraHandoff {
                LockedCameraNeutralHandoffView(
                    handoff: neutralLockedCameraHandoff,
                    onOpenCamera: {
                        self.neutralLockedCameraHandoff = nil
                    },
                    onOpenLibrary: {
                        self.neutralLockedCameraHandoff = nil
                        TAPCamIntentHandoffStore().saveHandoff(TAPCamIntentHandoff(
                            destination: .tapLibrary,
                            tapAction: TAPCamLockedCameraHandoff.openTAPLibrary,
                            reason: "e1d_manual_library"
                        ))
                        NotificationCenter.default.post(name: .tapCamIntentHandoffDidChange, object: nil)
                    }
                )
            } else if isPreparingFirstInstallCameraReadiness {
                CameraView(
                    libraryStore: libraryStore,
                    libraryMediaFetcher: libraryMediaFetcher,
                    initialReadinessGate: .firstInstall {
                    completeFirstInstallSetupAfterCameraReadiness()
                    }
                )
            } else if didCompleteFirstInstallSetup {
                CameraView(
                    libraryStore: libraryStore,
                    libraryMediaFetcher: libraryMediaFetcher
                )
            } else {
                WelcomeStartupSetupView(coordinator: startupCoordinator) {
                    beginFirstInstallCameraReadinessIfReady()
                }
            }
        }
        .task {
            await LockedCameraAppContextPublisher.publishCurrentContextIfAvailable()
            do {
                try await videoPosterBackfillService.run()
                await refreshLibraryIfPhotoAccessIsGranted()
            } catch is CancellationError {
                return
            } catch {
                // Poster backfill is a derivative-only maintenance task. A
                // missing/corrupt poster must never gate camera readiness.
            }
        }
        .onChange(of: startupCoordinator.photoLibraryStatus) { _, status in
            guard status == .granted else {
                return
            }
            Task {
                await refreshLibraryIfPhotoAccessIsGranted()
            }
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: UIApplication.didReceiveMemoryWarningNotification
            )
        ) { _ in
            DepthAlbumThumbnailMemoryCache.shared.removeAll()
        }
        .onContinueUserActivity(TAPCamLockedCameraHandoff.activityType) { activity in
            handleLockedCameraHandoff(activity)
        }
        .onContinueUserActivity(TAPCamLockedCameraHandoff.openOnlyActivityType) { activity in
            handleLockedCameraOpenOnlyActivity(activity)
        }
        .onOpenURL { url in
            handleLockedCameraOpenURL(url)
        }
    }

    private func beginFirstInstallCameraReadinessIfReady() {
        guard StartupGatePolicy.firstInstallContinueAction(
            for: startupCoordinator.statusSnapshot
        ) == .enterCameraReadiness else {
            return
        }
        isPreparingFirstInstallCameraReadiness = true
    }

    private func refreshLibraryIfPhotoAccessIsGranted() async {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard status == .authorized || status == .limited else {
            return
        }
        await libraryStore.refresh()
    }

    private func completeFirstInstallSetupAfterCameraReadiness() {
        didCompleteFirstInstallSetup = true
    }

    private func handleLockedCameraHandoff(_ activity: NSUserActivity) {
        guard let handoff = TAPCamIntentHandoff(lockedCameraActivity: activity) else {
            let keys = activity.userInfo?.keys
                .compactMap { $0 as? String }
                .sorted()
                .joined(separator: "|") ?? "none"
            let title = activity.title ?? "none"
            LockedCameraDiagnostics.logger.info(
                "locked_camera_handoff_ignored activityType=\(activity.activityType, privacy: .public) activityTitle=\(title, privacy: .public) userInfoKeys=\(keys, privacy: .public) managerSessionCount=\(LockedCameraCaptureManager.shared.sessionContentURLs.count, privacy: .public)"
            )
            return
        }
        LockedCameraDiagnostics.logger.info(
            "locked_camera_handoff_received destination=\(handoff.destination.rawValue, privacy: .public) tapAction=\(handoff.tapAction ?? "none", privacy: .public) reason=\(handoff.reason ?? "none", privacy: .public) managerSessionCount=\(LockedCameraCaptureManager.shared.sessionContentURLs.count, privacy: .public)"
        )

        let delaysAppearance = beginLockedCameraTransitionDelayIfNeeded(for: handoff)

        if handoff.destination == .lockedImportNeutral {
            neutralLockedCameraHandoff = handoff
            LockedCameraDiagnostics.logger.info(
                "locked_camera_neutral_handoff_presented tapAction=\(handoff.tapAction ?? "none", privacy: .public) reason=\(handoff.reason ?? "none", privacy: .public) managerSessionCount=\(LockedCameraCaptureManager.shared.sessionContentURLs.count, privacy: .public)"
            )
            return
        }

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

    private func handleLockedCameraOpenOnlyActivity(_ activity: NSUserActivity) {
        let keys = activity.userInfo?.keys
            .compactMap { $0 as? String }
            .sorted()
            .joined(separator: "|") ?? "none"
        let title = activity.title ?? "none"
        LockedCameraDiagnostics.logger.info(
            "locked_camera_open_only_handoff_ignored activityType=\(activity.activityType, privacy: .public) activityTitle=\(title, privacy: .public) userInfoKeys=\(keys, privacy: .public) managerSessionCount=\(LockedCameraCaptureManager.shared.sessionContentURLs.count, privacy: .public)"
        )
    }

    private func handleLockedCameraOpenURL(_ url: URL) {
        guard let route = TAPCamLockedCameraHandoff.lockedCameraRoute(from: url) else {
            LockedCameraDiagnostics.logger.info(
                "locked_camera_url_open_ignored scheme=\(url.scheme ?? "none", privacy: .public) host=\(url.host ?? "none", privacy: .public) path=\(url.path, privacy: .public)"
            )
            return
        }

        LockedCameraDiagnostics.logger.info(
            "locked_camera_url_open_received route=\(route, privacy: .public) managerSessionCount=\(LockedCameraCaptureManager.shared.sessionContentURLs.count, privacy: .public)"
        )
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

private struct LockedCameraNeutralHandoffView: View {
    let handoff: TAPCamIntentHandoff
    let onOpenCamera: () -> Void
    let onOpenLibrary: () -> Void

    @State private var didImportLockedCapture = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 18) {
                Text("TAPCam")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white)

                Text(didImportLockedCapture ? "Locked capture imported" : "Waiting for locked capture")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.72))

                HStack(spacing: 12) {
                    Button("Camera", action: onOpenCamera)
                        .buttonStyle(.borderedProminent)
                    Button("Library", action: onOpenLibrary)
                        .buttonStyle(.bordered)
                }
            }
            .padding(24)
        }
        .onAppear {
            LockedCameraDiagnostics.logger.info(
                "locked_camera_neutral_handoff_appear tapAction=\(handoff.tapAction ?? "none", privacy: .public) reason=\(handoff.reason ?? "none", privacy: .public) managerSessionCount=\(LockedCameraCaptureManager.shared.sessionContentURLs.count, privacy: .public)"
            )
        }
        .onReceive(NotificationCenter.default.publisher(for: .tapCamLockedCaptureImportDidAddPendingCaptures).receive(on: RunLoop.main)) { _ in
            didImportLockedCapture = true
            LockedCameraDiagnostics.logger.info(
                "locked_camera_neutral_handoff_import_notification managerSessionCount=\(LockedCameraCaptureManager.shared.sessionContentURLs.count, privacy: .public)"
            )
        }
    }
}
