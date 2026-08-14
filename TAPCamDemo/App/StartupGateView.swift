//
//  StartupGateView.swift
//  TAPCamDemo
//

import Combine
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
    @State private var isPreparingFirstInstallCameraReadiness = false

    var body: some View {
        Group {
            if isPreparingFirstInstallCameraReadiness {
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
        await libraryStore.cachedSnapshotOrRefresh()
    }

    private func completeFirstInstallSetupAfterCameraReadiness() {
        didCompleteFirstInstallSetup = true
    }
}
