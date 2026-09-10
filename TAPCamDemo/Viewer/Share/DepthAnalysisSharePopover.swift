//
//  DepthAnalysisSharePopover.swift
//  TAPCamDemo
//

import SwiftUI
import UIKit

private struct SharePopoverDismissalObserver: UIViewControllerRepresentable {
    let onAppearanceCompleted: () -> Void
    let onDismissalCompleted: () -> Void

    func makeUIViewController(context: Context) -> ObserverViewController {
        ObserverViewController(
            onAppearanceCompleted: onAppearanceCompleted,
            onDismissalCompleted: onDismissalCompleted
        )
    }

    func updateUIViewController(
        _ uiViewController: ObserverViewController,
        context: Context
    ) {
        uiViewController.onAppearanceCompleted = onAppearanceCompleted
        uiViewController.onDismissalCompleted = onDismissalCompleted
    }

    final class ObserverViewController: UIViewController {
        var onAppearanceCompleted: () -> Void
        var onDismissalCompleted: () -> Void
        private var hasAppeared = false

        init(
            onAppearanceCompleted: @escaping () -> Void,
            onDismissalCompleted: @escaping () -> Void
        ) {
            self.onAppearanceCompleted = onAppearanceCompleted
            self.onDismissalCompleted = onDismissalCompleted
            super.init(nibName: nil, bundle: nil)
            view.isUserInteractionEnabled = false
            view.backgroundColor = .clear
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            hasAppeared = true
            onAppearanceCompleted()
        }

        override func viewDidDisappear(_ animated: Bool) {
            super.viewDidDisappear(animated)
            guard hasAppeared else {
                return
            }
            hasAppeared = false
            onDismissalCompleted()
        }
    }
}

struct DepthAnalysisSharePopover: View {
    @ObservedObject var coordinator: DepthAnalysisShareCoordinator
    let onOptionSelected: () -> Void
    let onAppearanceCompleted: () -> Void
    let onDismissalCompleted: () -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            selectionContent
        }
        .frame(width: 288)
        .background(.regularMaterial)
        .presentationCompactAdaptation(.popover)
        .presentationSizing(.fitted)
        .interactiveDismissDisabled(coordinator.isPreparing)
        .background(
            SharePopoverDismissalObserver(
                onAppearanceCompleted: onAppearanceCompleted,
                onDismissalCompleted: onDismissalCompleted
            )
            .frame(width: 0, height: 0)
        )
    }

    private var selectionContent: some View {
        VStack(spacing: 0) {
            credentialHeader
            Divider().padding(.horizontal, 16)
            formatRows
                .transaction { transaction in
                    transaction.animation = nil
                    transaction.disablesAnimations = true
                }
        }
        .accessibilityIdentifier("tap.share.selection")
    }

    private var formatRows: some View {
        VStack(spacing: 0) {
            availableOptionRow(
                option: .tapnapPackage,
                titleKey: "share.option.package.title",
                subtitleKey: coordinator.certificationState == .localIntegrityPassed
                    ? "share.option.package.subtitle"
                    : "share.option.package.locked",
                systemImage: "shippingbox",
                badgeKey: "share.badge.recommended",
                isAvailable: coordinator.isPackageAvailable,
                canPrepare: coordinator.canPreparePackage,
                identifier: "tap.share.package"
            )
            if coordinator.subject?.mediaKind == .video {
                availableOptionRow(
                    option: .video,
                    titleKey: "share.option.video.title",
                    subtitleKey: coordinator.certificationState == .failed
                        ? "share.option.media.unverifiable"
                        : "share.option.video.subtitle",
                    systemImage: "video",
                    badgeKey: nil,
                    isAvailable: coordinator.isVideoAvailable,
                    canPrepare: coordinator.canPrepareVideo,
                    identifier: "tap.share.video",
                    drawsDivider: false
                )
            } else {
                availableOptionRow(
                    option: .image,
                    titleKey: "share.option.image.title",
                    subtitleKey: coordinator.certificationState == .failed
                        ? "share.option.media.unverifiable"
                        : "share.option.image.subtitle",
                    systemImage: "photo.on.rectangle",
                    badgeKey: nil,
                    isAvailable: coordinator.isImageAvailable,
                    canPrepare: coordinator.canPrepareImage,
                    identifier: "tap.share.image",
                    drawsDivider: false
                )
            }
        }
    }

    private var credentialHeader: some View {
        let state = coordinator.certificationState ?? .retryPending
        let isPreparing = coordinator.certificationState == nil || state == .retryPending
        return HStack(spacing: 9) {
            ZStack {
                if let systemImage = state.systemImage {
                    Image(systemName: systemImage)
                        .opacity(isPreparing ? 0 : 1)
                        .transition(.opacity)
                }
                ProgressView()
                    .controlSize(.small)
                    .opacity(isPreparing ? 1 : 0)
            }
            .frame(width: 19, height: 19)
            Text(String(localized: coordinator.resourcePreparationFailed
                ? "share.status.originalPreparationFailed" : state.localizationKey))
                .font(.subheadline)
                .contentTransition(.opacity)
            Spacer(minLength: 0)
            Button("Retry") { coordinator.retryOriginalResource() }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.blue)
                .opacity(coordinator.resourcePreparationFailed ? 1 : 0)
                .disabled(!coordinator.resourcePreparationFailed)
                .accessibilityHidden(!coordinator.resourcePreparationFailed)
                .accessibilityIdentifier("tap.share.resource.retry")
        }
        .foregroundStyle(state.tint)
        .padding(.horizontal, 16)
        .frame(height: 48)
        .animation(.easeInOut(duration: 0.16), value: coordinator.certificationState)
        .accessibilityIdentifier("tap.share.status")
    }

    private func availableOptionRow(
        option: DepthAnalysisShareOption,
        titleKey: String.LocalizationValue,
        subtitleKey: String.LocalizationValue,
        systemImage: String,
        badgeKey: String.LocalizationValue?,
        isAvailable: Bool,
        canPrepare: Bool,
        identifier: String,
        drawsDivider: Bool = true
    ) -> some View {
        let progress = coordinator.preparationProgress(for: option)
        let failed: Bool = if case .failed(let failedOption) = coordinator.preparationState {
            failedOption == option
        } else { false }
        return Button {
            onOptionSelected()
            if failed {
                coordinator.retryFailedOption()
            } else {
                coordinator.prepare(option)
            }
        } label: {
            optionLabel(
                titleKey: titleKey,
                subtitleKey: subtitleKey,
                systemImage: systemImage,
                badgeKey: badgeKey,
                progress: progress,
                failed: failed,
                drawsDivider: drawsDivider
            )
        }
        .buttonStyle(StableShareOptionButtonStyle())
        .disabled(!canPrepare)
        .opacity(isAvailable || coordinator.certificationState == nil
            || coordinator.certificationState == .retryPending ? 1 : 0.38)
        .accessibilityIdentifier(identifier)
    }

    private func optionLabel(
        titleKey: String.LocalizationValue,
        subtitleKey: String.LocalizationValue,
        systemImage: String,
        badgeKey: String.LocalizationValue?,
        progress: Double? = nil,
        failed: Bool = false,
        drawsDivider: Bool = true
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.title3.weight(.medium))
                .frame(width: 29)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(String(localized: titleKey))
                        .font(.subheadline.weight(.semibold))
                    if let badgeKey {
                        Text(String(localized: badgeKey))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.blue)
                    }
                }
                ZStack(alignment: .leading) {
                    HStack(spacing: 8) {
                        Text(String(localized: failed ? "share.error.message" : subtitleKey))
                            .font(.caption2)
                            .foregroundStyle(failed ? .orange : .secondary)
                            .lineLimit(2)
                        if failed {
                            Text("Retry")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.blue)
                        }
                    }
                    .opacity(progress == nil ? 1 : 0)
                    .accessibilityHidden(progress != nil)

                    ProgressView(value: progress ?? 0)
                        .progressViewStyle(.linear)
                        .tint(.blue)
                        .frame(maxWidth: .infinity)
                        .frame(height: 2)
                        .opacity(progress == nil ? 0 : 1)
                        .accessibilityHidden(progress == nil)
                        .accessibilityIdentifier("tap.share.progress")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: 28, alignment: .leading)
            }
            Spacer(minLength: 0)
        }
        .multilineTextAlignment(.leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .frame(minHeight: 64)
        .overlay(alignment: .bottom) {
            if drawsDivider {
                Divider()
                    .padding(.leading, 55)
            }
        }
        .contentShape(Rectangle())
    }
}

private struct StableShareOptionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
    }
}

private extension DepthAnalysisShareCertificationState {
    var localizationKey: String.LocalizationValue {
        switch self {
        case .localIntegrityPassed:
            "share.status.verified"
        case .retryPending:
            "share.status.preparing"
        case .failed:
            "share.status.failed"
        }
    }

    var systemImage: String? {
        switch self {
        case .localIntegrityPassed:
            "checkmark.circle"
        case .retryPending:
            nil
        case .failed:
            "xmark.circle"
        }
    }

    var tint: Color {
        switch self {
        case .localIntegrityPassed:
            .green
        case .retryPending:
            .secondary
        case .failed:
            .red
        }
    }
}
