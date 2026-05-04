//
//  StartupGateView.swift
//  TAPCamDemo
//

import SwiftUI

struct StartupGateView: View {
    @AppStorage(StartupGateDefaults.didCompleteFirstInstallPermissionsKey)
    private var didCompleteFirstInstallPermissions = false

    @StateObject private var permissionCoordinator = StartupPermissionCoordinator()
    @State private var phase: StartupGatePhase = .welcome
    @State private var didStartPreparing = false
    @State private var preparedViewModel: CameraViewModel?
    @State private var preparedAppAttestController: AppAttestRuntimeController?

    var body: some View {
        Group {
            if didCompleteFirstInstallPermissions {
                cameraView
            } else {
                switch phase {
                case .welcome:
                    WelcomePermissionsView(coordinator: permissionCoordinator) {
                        beginPreparingIfReady()
                    }
                case .preparing:
                    startupLoadingView
                        .task {
                            await prepareFirstInstall()
                        }
                }
            }
        }
    }

    @ViewBuilder
    private var cameraView: some View {
        if let preparedViewModel,
           let preparedAppAttestController {
            CameraView(
                viewModel: preparedViewModel,
                appAttestController: preparedAppAttestController,
                startsAutomatically: false
            )
        } else {
            CameraView()
        }
    }

    private var startupLoadingView: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 16) {
                ProgressView()
                    .tint(.white)
                    .scaleEffect(1.15)

                Text("First launch needs a little time to finish setup. Please wait.")
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 28)
            }
        }
    }

    private func beginPreparingIfReady() {
        guard permissionCoordinator.hasRequiredPermissions else {
            return
        }
        phase = .preparing
    }

    @MainActor
    private func prepareFirstInstall() async {
        guard !didStartPreparing else {
            return
        }

        guard permissionCoordinator.hasRequiredPermissions else {
            phase = .welcome
            return
        }

        didStartPreparing = true

        let viewModel = CameraViewModel()
        let appAttestController = AppAttestRuntimeController()

        async let cameraStart: Void = viewModel.start()
        async let appAttestPrepare: Void = appAttestController.preparePhotoCredentialAfterFirstInstallLaunch()

        _ = await (cameraStart, appAttestPrepare)

        preparedViewModel = viewModel
        preparedAppAttestController = appAttestController
        didCompleteFirstInstallPermissions = true
    }
}

private enum StartupGatePhase {
    case welcome
    case preparing
}
