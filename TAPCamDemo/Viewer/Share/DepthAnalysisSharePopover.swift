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
            activeContent
                .transaction { transaction in
                    // Keep row updates stable without disabling native presentation.
                    transaction.animation = nil
                    transaction.disablesAnimations = true
                }
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

    private enum ContentState {
        case resolvingIntegrity
        case selection
        case failure
    }

    private var contentState: ContentState {
        guard coordinator.certificationState != nil else {
            return .resolvingIntegrity
        }
        switch coordinator.preparationState {
        case .idle:
            return .selection
        case .preparing:
            return .selection
        case .failed:
            return .failure
        }
    }

    @ViewBuilder
    private var activeContent: some View {
        switch contentState {
        case .resolvingIntegrity:
            integrityResolvingContent
        case .selection:
            selectionContent
        case .failure:
            failureContent
        }
    }

    /// Keeps the approved selector footprint stable while the exact frozen
    /// original is checked locally. No credential label or action copy is
    /// exposed until the three-state result is known, so this never reads as a
    /// fourth visible certification state.
    private var integrityResolvingContent: some View {
        VStack(spacing: 0) {
            HStack(spacing: 9) {
                Circle()
                    .fill(.tertiary)
                    .frame(width: 19, height: 19)
                Capsule()
                    .fill(.tertiary)
                    .frame(width: 72, height: 14)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .frame(height: 48)

            Divider()
                .padding(.horizontal, 16)

            integritySkeletonRow(titleWidth: 118, subtitleWidth: 158)
            integritySkeletonRow(titleWidth: 118, subtitleWidth: 82)
            integritySkeletonRow(titleWidth: 82, subtitleWidth: nil)
            integritySkeletonRow(
                titleWidth: 118,
                subtitleWidth: nil,
                drawsDivider: false
            )
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            String(localized: "share.integrity.checking.accessibility")
        )
        .accessibilityIdentifier("tap.share.integrity.resolving")
    }

    private func integritySkeletonRow(
        titleWidth: CGFloat,
        subtitleWidth: CGFloat?,
        drawsDivider: Bool = true
    ) -> some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(.tertiary)
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 8) {
                Capsule()
                    .fill(.tertiary)
                    .frame(width: titleWidth, height: 10)
                if let subtitleWidth {
                    Capsule()
                        .fill(.tertiary)
                        .frame(width: subtitleWidth, height: 8)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .frame(minHeight: 64)
        .overlay(alignment: .bottom) {
            if drawsDivider {
                Divider()
                    .padding(.leading, 55)
            }
        }
        .accessibilityHidden(true)
    }

    private var selectionContent: some View {
        VStack(spacing: 0) {
            credentialHeader
            Divider()
                .padding(.horizontal, 16)

            VStack(spacing: 0) {
                if coordinator.subject?.mediaKind == .video {
                    unavailableOptionRow(
                        titleKey: "share.option.package.title",
                        subtitleKey: "share.option.package.videoComingSoon",
                        systemImage: "shippingbox",
                        badgeKey: "share.badge.comingSoon",
                        identifier: "tap.share.package"
                    )
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
                        identifier: "tap.share.video"
                    )
                } else {
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
                        identifier: "tap.share.image"
                    )
                }

                unavailableOptionRow(
                    titleKey: "share.option.sticker.title",
                    subtitleKey: "share.option.sticker.subtitle",
                    systemImage: "face.smiling",
                    badgeKey: "share.badge.comingSoon",
                    identifier: "tap.share.sticker"
                )
                unavailableOptionRow(
                    titleKey: "share.option.link.title",
                    subtitleKey: "share.option.link.subtitle",
                    systemImage: "link",
                    badgeKey: "share.badge.membersComingSoon",
                    identifier: "tap.share.link",
                    drawsDivider: false
                )
            }
        }
        .accessibilityIdentifier("tap.share.selection")
    }

    @ViewBuilder
    private var credentialHeader: some View {
        if let state = coordinator.certificationState {
            HStack(spacing: 9) {
                Image(systemName: state.systemImage)
                    .foregroundStyle(state.tint)
                Text(String(localized: state.localizationKey))
                    .font(.subheadline)
                    .foregroundStyle(state.tint)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .frame(height: 48)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("tap.share.status")
        } else {
            HStack(spacing: 9) {
                Circle()
                    .fill(.tertiary)
                    .frame(width: 19, height: 19)
                Capsule()
                    .fill(.tertiary)
                    .frame(width: 72, height: 14)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .frame(height: 48)
            .accessibilityHidden(true)
        }
    }

    private var failureContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 13) {
                Image(systemName: "exclamationmark.circle")
                    .font(.title2.weight(.medium))
                    .foregroundStyle(.orange)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 5) {
                    Text(String(localized: "share.error.title"))
                        .font(.headline)
                    Text(String(localized: "share.error.message"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack {
                Spacer(minLength: 0)
                Button("Cancel") {
                    coordinator.cancelFailure()
                }
                .buttonStyle(.plain)
                .foregroundStyle(.blue)
                .accessibilityIdentifier("tap.share.cancel")
                Button("Retry") {
                    coordinator.retryFailedOption()
                }
                .buttonStyle(.plain)
                .fontWeight(.semibold)
                .foregroundStyle(.blue)
                .accessibilityIdentifier("tap.share.retry")
            }
        }
        .padding(16)
        .accessibilityIdentifier("tap.share.failure")
    }

    private func availableOptionRow(
        option: DepthAnalysisShareOption,
        titleKey: String.LocalizationValue,
        subtitleKey: String.LocalizationValue,
        systemImage: String,
        badgeKey: String.LocalizationValue?,
        isAvailable: Bool,
        canPrepare: Bool,
        identifier: String
    ) -> some View {
        let progress = coordinator.preparationProgress(for: option)
        return Button {
            onOptionSelected()
            coordinator.prepare(option)
        } label: {
            optionLabel(
                titleKey: titleKey,
                subtitleKey: subtitleKey,
                systemImage: systemImage,
                badgeKey: badgeKey,
                progress: progress
            )
        }
        .buttonStyle(StableShareOptionButtonStyle())
        .disabled(!canPrepare)
        .opacity(isAvailable ? 1 : 0.38)
        .accessibilityIdentifier(identifier)
    }

    private func unavailableOptionRow(
        titleKey: String.LocalizationValue,
        subtitleKey: String.LocalizationValue,
        systemImage: String,
        badgeKey: String.LocalizationValue,
        identifier: String,
        drawsDivider: Bool = true
    ) -> some View {
        Button {} label: {
            optionLabel(
                titleKey: titleKey,
                subtitleKey: subtitleKey,
                systemImage: systemImage,
                badgeKey: badgeKey,
                drawsDivider: drawsDivider
            )
        }
        .buttonStyle(StableShareOptionButtonStyle())
        .disabled(true)
        .opacity(0.38)
        .accessibilityIdentifier(identifier)
    }

    private func optionLabel(
        titleKey: String.LocalizationValue,
        subtitleKey: String.LocalizationValue,
        systemImage: String,
        badgeKey: String.LocalizationValue?,
        progress: Double? = nil,
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
                    Text(String(localized: subtitleKey))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
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
            "share.status.retry"
        case .failed:
            "share.status.failed"
        }
    }

    var systemImage: String {
        switch self {
        case .localIntegrityPassed:
            "checkmark.circle"
        case .retryPending:
            "arrow.clockwise.circle"
        case .failed:
            "xmark.circle"
        }
    }

    var tint: Color {
        switch self {
        case .localIntegrityPassed:
            .green
        case .retryPending:
            .orange
        case .failed:
            .red
        }
    }
}
