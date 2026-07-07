//
//  LockedCaptureRootView.swift
//  TAPCamDemo
//

import LockedCameraCapture
import OSLog
import SwiftUI

struct LockedCaptureRootView: View {
    private static let logger = TAPCamLockedCameraDiagnostics.logger()

    let session: LockedCameraCaptureSession

    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var controller = LockedCaptureCameraController()
    @State private var showsBootDiagnostics = true

    init(session: LockedCameraCaptureSession) {
        self.session = session
        Self.logger.info("locked_camera_root_init contentURL=\(session.sessionContentURL.path, privacy: .private(mask: .hash))")
    }

    var body: some View {
        ZStack {
            Color(red: 0.025, green: 0.027, blue: 0.032)
                .ignoresSafeArea()

            if controller.isPreviewHostVisible {
                LockedCapturePreviewHost(
                    session: controller.captureSession,
                    onCapture: { controller.capturePhoto(into: session.sessionContentURL) },
                    onLayerStateChanged: { inWindow, hasSuperlayer in
                        controller.recordPreviewLayerState(
                            inWindow: inWindow,
                            hasSuperlayer: hasSuperlayer
                        )
                    }
                )
                .ignoresSafeArea()
                .opacity(controller.state.showsPreview ? 1 : 0.28)
            }

            if controller.state.showsStatusOverlay {
                statusOverlay
            }

            VStack {
                topBar
                if !controller.availableLenses.isEmpty {
                    lensSelector
                        .padding(.top, 8)
                }
                if showsBootDiagnostics || controller.state.showsStatusOverlay {
                    diagnosticBadge
                        .padding(.top, 8)
                }
                Spacer()
                bottomBar
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 22)
        }
        .task {
            await controller.start()
        }
        .task {
            try? await Task.sleep(for: .seconds(12))
            showsBootDiagnostics = false
            Self.logger.info("locked_camera_root_boot_diagnostics_hidden")
        }
        .onAppear {
            logRootLifecycle("appear")
        }
        .onChange(of: scenePhase) { _, phase in
            Self.logger.info(
                "locked_camera_root_scene_phase_changed phase=\(String(describing: phase), privacy: .public) state=\(controller.state.title, privacy: .public) message=\(controller.state.message, privacy: .public)"
            )
            controller.handleScenePhase(phase)
        }
        .onDisappear {
            logRootLifecycle("disappear")
            controller.stop()
        }
    }

    private func logRootLifecycle(_ event: String) {
        Self.logger.info(
            "locked_camera_root_lifecycle event=\(event, privacy: .public) scenePhase=\(String(describing: scenePhase), privacy: .public) state=\(controller.state.title, privacy: .public) message=\(controller.state.message, privacy: .public)"
        )
    }

    private var topBar: some View {
        HStack {
            Text("TAPCam")
                .font(.headline)
                .foregroundStyle(.white)

            Spacer()

            if let lensLabel = controller.activeLensLabel {
                Text(lensLabel)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.82))
            }
        }
    }

    private var lensSelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(controller.availableLenses) { lens in
                    let isSelected = controller.selectedLensID == lens.id
                    Button {
                        controller.selectLens(lens)
                    } label: {
                        Text("\(lens.numericLabel)\(lens.unitLabel)")
                            .font(.caption.weight(.semibold).monospacedDigit())
                            .foregroundStyle(isSelected ? .black : .white)
                            .frame(minWidth: 44, minHeight: 32)
                            .padding(.horizontal, 6)
                            .background(
                                isSelected ? .white : .black.opacity(0.48),
                                in: RoundedRectangle(cornerRadius: 8)
                            )
                            .overlay {
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(.white.opacity(isSelected ? 0 : 0.28), lineWidth: 1)
                            }
                    }
                    .buttonStyle(.plain)
                    .disabled(isSelected || !controller.state.canCapture)
                    .accessibilityLabel("Lens \(lens.displayName)")
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private var diagnosticBadge: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Lock POC • \(controller.state.title)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
            Text(controller.state.message)
                .font(.caption2)
                .lineLimit(2)
                .foregroundStyle(.white.opacity(0.76))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.black.opacity(0.68), in: RoundedRectangle(cornerRadius: 8))
    }

    private var statusOverlay: some View {
        VStack(spacing: 12) {
            ProgressView()
                .tint(.white)
                .opacity(controller.state.isRecovering ? 1 : 0)

            Text(controller.state.title)
                .font(.headline)
                .foregroundStyle(.white)

            Text(controller.state.message)
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.72))
                .frame(maxWidth: 280)

            if controller.state.isUnavailable {
                Button {
                    controller.openHostApplication(
                        session: session,
                        tapAction: TAPCamLockedCameraHandoff.regenerateLockedCameraContext,
                        reason: controller.state.message
                    )
                } label: {
                    Label("Unlock", systemImage: "lock.open")
                        .font(.headline)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
                .tint(.white)
                .foregroundStyle(.black)
            }
        }
        .padding(24)
        .background(.black.opacity(0.56), in: RoundedRectangle(cornerRadius: 8))
    }

    private var bottomBar: some View {
        HStack(alignment: .center) {
            Button {
                controller.openHostApplication(
                    session: session,
                    tapAction: TAPCamLockedCameraHandoff.openTAPCameraRuntimeImport,
                    reason: controller.lastCaptureSucceeded
                        ? "e1c_light_route_after_saved_capture"
                        : "e1c_light_route_placeholder"
                )
            } label: {
                Image(systemName: lockedAlbumPlaceholderIcon)
                    .font(.system(size: 22, weight: .semibold))
                    .frame(width: 52, height: 52)
                    .background(.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 8))
                    .foregroundStyle(controller.lastCaptureSucceeded ? .green : .white)
            }
            .buttonStyle(.plain)
            .disabled(!controller.state.canCapture)
            .accessibilityLabel(
                Text(controller.lastCaptureSucceeded ? "Open TAP Library" : "Open TAPCam")
            )

            Spacer()

            Button {
                controller.capturePhoto(into: session.sessionContentURL)
            } label: {
                ZStack {
                    Circle()
                        .stroke(.white, lineWidth: 4)
                        .frame(width: 78, height: 78)
                    Circle()
                        .fill(controller.state.canCapture ? .white : .white.opacity(0.38))
                        .frame(width: 62, height: 62)
                }
            }
            .buttonStyle(.plain)
            .disabled(!controller.state.canCapture)
            .accessibilityLabel("Capture")

            Spacer()

            Color.clear
                .frame(width: 52, height: 52)
                .accessibilityHidden(true)
        }
    }

    private var lockedAlbumPlaceholderIcon: String {
        controller.lastCaptureSucceeded ? "checkmark.circle.fill" : "photo.stack"
    }
}
