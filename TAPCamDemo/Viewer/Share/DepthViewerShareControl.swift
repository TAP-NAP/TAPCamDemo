//
//  DepthViewerShareControl.swift
//  TAPCamDemo
//

import Foundation
import SwiftUI

/// Stable Share leaf shared by photo, Live Photo, and TAP Video. The popover
/// and the one system activity sheet are siblings owned outside either
/// presentation, so payload preparation cannot remount the Viewer.
struct DepthViewerShareControl: View {
    let subject: DepthAnalysisShareSubject?
    let resourceAccess: DepthAnalysisShareResourceAccess?
    let accessibilityLabel: String

    @StateObject private var coordinator = DepthAnalysisShareCoordinator()
    @State private var feedback = DepthAnalysisShareFeedback()
    @AppStorage(CameraFeedbackPreferences.shutterHapticsEnabledKey)
    private var interactionHapticsEnabled = CameraFeedbackPreferences.defaultShutterHapticsEnabled

    var body: some View {
        ViewerToolbarIconButton(
            icon: .shareNetwork,
            accessibilityLabel: accessibilityLabel,
            accessibilityIdentifier: "tap.viewer.share",
            foregroundStyle: .primary,
            isEnabled: subject != nil
                && resourceAccess != nil
                && subject?.hasIdentityConflict == false
                && !coordinator.hasActiveActivityPresentation,
            accessibilityValue: accessibilityValue,
            progress: coordinator.visibleProgress,
            action: presentShare
        )
        .popover(
            isPresented: popoverBinding,
            attachmentAnchor: .rect(.bounds),
            arrowEdge: .bottom
        ) {
            DepthAnalysisSharePopover(
                coordinator: coordinator,
                onOptionSelected: selectionFeedback,
                onAppearanceCompleted: coordinator.popoverDidAppear,
                onDismissalCompleted: coordinator.popoverDidDisappear
            )
        }
        .background {
            DepthViewerSystemSharePresenter(
                coordinator: coordinator,
                expectedPresentationID: coordinator.activityPresentation?.id
            )
        }
        .onReceive(
            NotificationCenter.default.publisher(for: .tapLibraryDidChange)
        ) { notification in
            coordinator.scheduleCertificationRefresh(
                for: notification.object as? TAPLibraryPendingCaptureChange
            )
        }
        .onDisappear {
            if !coordinator.hasActiveActivityPresentation {
                coordinator.shutdown()
            }
        }
        .onAppear {
            if interactionHapticsEnabled {
                feedback.prepare()
            }
        }
        .onChange(of: coordinator.preparationState.isFailure) { wasFailure, isFailure in
            if interactionHapticsEnabled, !wasFailure, isFailure {
                feedback.failed()
            }
        }
    }

    private var popoverBinding: Binding<Bool> {
        Binding(
            get: { coordinator.isPopoverPresented },
            set: { coordinator.setPopoverPresented($0) }
        )
    }

    private var accessibilityValue: String? {
        guard let progress = coordinator.visibleProgress else {
            return nil
        }
        return String(
            format: String(localized: "share.progress.accessibilityValue"),
            Int((progress * 100).rounded())
        )
    }

    private func presentShare() {
        coordinator.shareButtonTapped(
            mediaKind: subject?.mediaKind,
            resourceReady: resourceAccess?.isReady == true
        )
        guard let subject,
              let resourceAccess else {
            return
        }
        if interactionHapticsEnabled {
            feedback.opened()
        }
        coordinator.togglePresentation(for: subject, resourceAccess: resourceAccess)
    }

    private func selectionFeedback() {
        if interactionHapticsEnabled {
            feedback.optionSelected()
        }
    }
}

/// Gives every system sheet an immutable attempt ID. The item binding is the
/// primary end signal; SwiftUI `onDismiss` is an exact-ID, idempotent fallback.
/// Neither path uses UIKit controller release as a resource-lifetime protocol.
private struct DepthViewerSystemSharePresenter: View {
    @ObservedObject var coordinator: DepthAnalysisShareCoordinator
    let expectedPresentationID: UUID?

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .sheet(
                item: presentationBinding,
                onDismiss: activitySheetDidDismiss
            ) { presentation in
                VerificationExportActivityView(
                    sharePresentation: presentation
                )
            }
    }

    private func activitySheetDidDismiss() {
        guard let expectedPresentationID else {
            return
        }
        coordinator.activityPresentationDidEnd(
            expectedArtifactID: expectedPresentationID
        )
    }

    private var presentationBinding: Binding<TAPShareActivityPresentation?> {
        Binding(
            get: {
                guard coordinator.activityPresentation?.id == expectedPresentationID else {
                    return nil
                }
                return coordinator.activityPresentation
            },
            set: { newPresentation in
                if newPresentation == nil, let expectedPresentationID {
                    coordinator.activityPresentationDidEnd(
                        expectedArtifactID: expectedPresentationID
                    )
                }
            }
        )
    }
}

private extension DepthAnalysisSharePreparationState {
    var isFailure: Bool {
        if case .failed = self {
            return true
        }
        return false
    }
}
