//
//  StartupGateView.swift
//  TAPCamDemo
//

import Combine
import SwiftUI
import UIKit

struct StartupGateView: View {
    let libraryStore: LibraryMediaStore
    let libraryMediaFetcher: any LibraryMediaFetching
    let videoPosterBackfillService: LibraryVideoPosterBackfillService

    private let setupFactStore: StartupSetupFactStore
    private let initializationStore: StartupInitializationStore

    @StateObject private var startupCoordinator: StartupGateCoordinator
    @State private var setupFact: StartupSetupFact
    @State private var initializationFact: StartupInitializationFact
    @State private var didCompleteExplicitPhotosAction = false
    @State private var pendingSettingsRequirement: StartupGateRequirementKind?
    @State private var didCommitPostPermissionRoute = false
    @State private var didReleaseDeferredWork = false

    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    init(
        libraryStore: LibraryMediaStore,
        libraryMediaFetcher: any LibraryMediaFetching,
        videoPosterBackfillService: LibraryVideoPosterBackfillService,
        userDefaults: UserDefaults = .standard
    ) {
        self.libraryStore = libraryStore
        self.libraryMediaFetcher = libraryMediaFetcher
        self.videoPosterBackfillService = videoPosterBackfillService

        let store = StartupSetupFactStore(userDefaults: userDefaults)
        let initializationStore = StartupInitializationStore(
            userDefaults: userDefaults
        )
        self.setupFactStore = store
        self.initializationStore = initializationStore
        _setupFact = State(
            initialValue: store.load(
                legacyCombinedCompletion: userDefaults.bool(
                    forKey: StartupGateDefaults.legacyCombinedCompletionKey
                )
            )
        )
        _initializationFact = State(initialValue: initializationStore.load())
        _startupCoordinator = StateObject(wrappedValue: StartupGateCoordinator())
    }

    var body: some View {
        Group {
            switch route {
            case .firstInstallSetup(let mode):
                WelcomeStartupSetupView(
                    mode: mode,
                    coordinator: startupCoordinator,
                    onContinue: recordFrozenSetupCompletionIfReady,
                    onRequestPhotoLibraryAccess: requestPhotoLibraryAccess,
                    onOpenSettings: openAppSettings(for:)
                )
            case .requiredPermissionCheck:
                RequiredPermissionCheckView(
                    coordinator: startupCoordinator,
                    onRequestPhotoLibraryAccess: requestPhotoLibraryAccess,
                    onOpenSettings: openAppSettings(for:)
                )
            case .resourceInitialization, .viewfinder:
                postPermissionCameraRoute
            }
        }
        .task(id: didReleaseDeferredWork) {
            guard didReleaseDeferredWork else { return }
            do {
                try await videoPosterBackfillService.run()
            } catch is CancellationError {
                return
            } catch {
                // Poster backfill is derivative-only maintenance. It never
                // changes startup routing or camera readiness.
            }
        }
        .onChange(of: setupFact) {
            Task { await synchronizeLibraryObservationAndCatalog() }
        }
        .onChange(of: startupCoordinator.photoLibraryStatus) {
            Task { await synchronizeLibraryObservationAndCatalog() }
        }
        .onChange(of: route) { _, newRoute in
            switch newRoute {
            case .resourceInitialization, .viewfinder:
                break
            case .firstInstallSetup, .requiredPermissionCheck:
                // A later recovery must commit a fresh post-permission shell
                // before constructing a replacement CameraView graph.
                didCommitPostPermissionRoute = false
            }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            refreshFactsAfterActivation()
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: UIApplication.didReceiveMemoryWarningNotification
            )
        ) { _ in
            DepthAlbumThumbnailMemoryCache.shared.removeAll()
        }
    }

    private var route: StartupRoute {
        StartupGatePolicy.route(
            for: StartupRouteFacts(
                setup: setupFact,
                requiredPermissions: startupCoordinator.requiredPermissionSnapshot,
                initialization: initializationFact
            )
        )
    }

    private var postPermissionCameraRoute: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if didCommitPostPermissionRoute {
                CameraView(
                    libraryStore: libraryStore,
                    libraryMediaFetcher: libraryMediaFetcher,
                    initialReadinessGate: route == .resourceInitialization
                        ? .resourceInitialization(
                            prepareCommit: prepareInitializationCommitIfReady
                        )
                        : .disabled,
                    onViewfinderInteractive: releaseDeferredWorkIfNeeded
                )
            } else if route == .resourceInitialization {
                ResourceInitializationLaunchView()
            }
        }
        .task {
            guard !didCommitPostPermissionRoute else { return }
            await Task.yield()
            didCommitPostPermissionRoute = true
            await synchronizeLibraryObservationAndCatalog()
        }
    }

    private func recordFrozenSetupCompletionIfReady() {
        guard StartupGatePolicy.firstInstallContinueAction(
            for: startupCoordinator.statusSnapshot
        ) == .enterResourceInitialization,
        case .firstInstallSetup(.initial) = route,
        let completedFact = setupFactStore.recordFrozenLegacyCompletion(
            statusSnapshot: startupCoordinator.statusSnapshot
        ) else {
            return
        }

        // This is deliberately not a canonical SetupReceipt. The frozen
        // Network row cannot supply credential binding evidence.
        setupFact = completedFact
    }

    private func requestPhotoLibraryAccess() async {
        await startupCoordinator.requestPhotoLibraryAccess()
        let status = startupCoordinator.requiredPermissionSnapshot.photoLibrary
        didCompleteExplicitPhotosAction = status == .authorized || status == .limited
        await synchronizeLibraryObservationAndCatalog()
    }

    private func openAppSettings(for requirement: StartupGateRequirementKind) {
        guard requirement != .securityPreflight,
              let url = URL(string: UIApplication.openSettingsURLString) else {
            return
        }
        pendingSettingsRequirement = requirement
        openURL(url)
    }

    private func refreshFactsAfterActivation() {
        let routeBeforeRefresh = route

        if let pendingSettingsRequirement {
            startupCoordinator.refreshAuthorizationStatus(
                for: pendingSettingsRequirement
            )
            self.pendingSettingsRequirement = nil

            // The Setup page's existing legacy Network refresh semantics are
            // frozen. Required Permission Check never enters this branch.
            if case .firstInstallSetup = routeBeforeRefresh {
                startupCoordinator.refreshSecurityPreflightStatus()
            }
        } else {
            switch routeBeforeRefresh {
            case .firstInstallSetup:
                startupCoordinator.refreshAuthorizationStatuses()
            case .requiredPermissionCheck, .resourceInitialization, .viewfinder:
                startupCoordinator.refreshRequiredPermissionStatuses()
            }
        }

        Task { await synchronizeLibraryObservationAndCatalog() }
    }

    @MainActor
    private func synchronizeLibraryObservationAndCatalog() async {
        let shouldObserve = StartupGatePolicy.shouldActivatePhotoLibraryObservation(
            setup: setupFact,
            didCompleteExplicitPhotosAction: didCompleteExplicitPhotosAction,
            photoLibraryStatus: startupCoordinator.requiredPermissionSnapshot.photoLibrary
        )

        guard shouldObserve,
              didCommitPostPermissionRoute || didCompleteExplicitPhotosAction else {
            libraryStore.stopObservingChangesIfNeeded()
            return
        }

        libraryStore.startObservingChangesIfNeeded()

        // An explicit Photos action may activate observation while Setup is
        // still open, but scalable catalog work waits until Setup completion.
        guard setupFact.permitsPostSetupRouting,
              didCommitPostPermissionRoute else {
            return
        }
        await libraryStore.cachedSnapshotOrRefresh()
    }

    @MainActor
    private func prepareInitializationCommitIfReady() async ->
        CameraInitialReadinessCommit? {
        let store = initializationStore
        let worker = Task.detached(priority: .userInitiated) {
            store.prepareCurrent { _ in
                try Task.checkCancellation()
            }
        }
        let completion = await withTaskCancellationHandler {
            await worker.value
        } onCancel: {
            worker.cancel()
        }
        guard !Task.isCancelled, let prepared = completion else {
            completion?.discard()
            return nil
        }
        return CameraInitialReadinessCommit(
            commit: {
                guard route == .resourceInitialization else {
                    prepared.discard()
                    return false
                }
                guard prepared.commit() else { return false }
                initializationFact = .current(prepared.completion)
                return true
            },
            discard: {
                prepared.discard()
            }
        )
    }

    private func releaseDeferredWorkIfNeeded() {
        guard !didReleaseDeferredWork else { return }
        didReleaseDeferredWork = true
    }
}
