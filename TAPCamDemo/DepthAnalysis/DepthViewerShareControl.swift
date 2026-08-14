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
        .background {
            DepthViewerSystemSharePresenter(
                coordinator: coordinator,
                presentation: coordinator.activityPresentation
            )
            .id(coordinator.activityPresentation?.id)
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

/// Gives every system sheet an immutable attempt ID. SwiftUI may deliver the
/// old sheet's binding and dismissal callbacks after a newer attempt begins;
/// routing through this item-scoped presenter lets the coordinator reject
/// those stale callbacks instead of closing the new sheet.
private struct DepthViewerSystemSharePresenter: View {
    @ObservedObject var coordinator: DepthAnalysisShareCoordinator
    let presentation: TAPShareActivityPresentation?

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .sheet(
                item: presentationBinding,
                onDismiss: sheetDidDismiss
            ) { presentation in
                VerificationExportActivityView(
                    preparedSharePresentation: presentation,
                    onAppeared: { [presentationID = presentation.id] in
                        coordinator.activitySheetDidAppear(
                            expectedArtifactID: presentationID
                        )
                    },
                    onDismantled: { [presentationID = presentation.id] in
                        coordinator.activityControllerDidDismantle(
                            expectedArtifactID: presentationID
                        )
                    }
                )
            }
    }

    private var presentationBinding: Binding<TAPShareActivityPresentation?> {
        Binding(
            get: { presentation },
            set: { newPresentation in
                if newPresentation == nil, let presentation {
                    coordinator.activityBindingDidDismiss(
                        expectedArtifactID: presentation.id
                    )
                }
            }
        )
    }

    private func sheetDidDismiss() {
        if let presentation {
            coordinator.activitySheetDidDismiss(
                expectedArtifactID: presentation.id
            )
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
