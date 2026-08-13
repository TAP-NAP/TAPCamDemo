//
//  DepthViewerShareControl.swift
//  TAPCamDemo
//

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
                && resourceAccess?.isReady == true
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
        .sheet(
            item: activityPresentationBinding,
            onDismiss: coordinator.activitySheetDidDismiss
        ) { presentation in
            VerificationExportActivityView(
                preparedSharePresentation: presentation,
                onAppeared: {
                    coordinator.activitySheetDidAppear(
                        expectedArtifactID: presentation.id
                    )
                },
                onFinished: {
                    coordinator.finishActivityPresentation(
                        expectedArtifactID: presentation.id
                    )
                },
                onDismantled: {
                    coordinator.activityControllerDidDismantle(
                        expectedArtifactID: presentation.id
                    )
                }
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

    private var activityPresentationBinding: Binding<TAPShareActivityPresentation?> {
        Binding(
            get: { coordinator.activityPresentation },
            set: { presentation in
                if presentation == nil {
                    coordinator.activityBindingDidDismiss()
                }
            }
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
        let resource = resourceAccess?.acquire()
        guard let subject,
              let resource else {
            return
        }
        if interactionHapticsEnabled {
            feedback.opened()
        }
        coordinator.togglePresentation(for: subject, resource: resource)
    }

    private func selectionFeedback() {
        if interactionHapticsEnabled {
            feedback.optionSelected()
        }
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
