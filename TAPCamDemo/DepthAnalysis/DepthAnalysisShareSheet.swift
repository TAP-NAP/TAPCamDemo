//
//  DepthAnalysisShareSheet.swift
//  TAPCamDemo
//

import Combine
import Foundation
import SwiftUI

/// Retained for the explicit verification-export surface and its tests. The
/// TAPNAP share sheet itself intentionally does not prepare an export merely
/// to show file metadata.
nonisolated struct DepthAnalysisShareFileInfo: Equatable {
    let fileName: String
    let kind: String
    let fileSize: String
    let warnings: [String]

    init(export: TAPVerificationExport, fileManager: FileManager = .default) {
        fileName = export.fileURL.lastPathComponent
        kind = export.kind.displayName
        fileSize = Self.fileSizeText(for: export.fileURL, fileManager: fileManager)
        warnings = export.warnings
    }

    private static func fileSizeText(for fileURL: URL, fileManager: FileManager) -> String {
        guard let attributes = try? fileManager.attributesOfItem(atPath: fileURL.path),
              let value = attributes[.size] as? NSNumber else {
            return "Unknown"
        }
        return ByteCountFormatter.string(fromByteCount: value.int64Value, countStyle: .file)
    }
}

nonisolated enum DepthAnalysisShareOption: String, Equatable, Sendable {
    case tapnapPackage
    case image
    case video
}

@MainActor
final class DepthAnalysisSharePayload: Identifiable {
    let id: UUID
    let option: DepthAnalysisShareOption
    let artifact: TAPNAPShareArtifact

    init(option: DepthAnalysisShareOption, artifact: TAPNAPShareArtifact) {
        id = artifact.id
        self.option = option
        self.artifact = artifact
    }

    func removeTemporaryDirectory() {
        artifact.removeTemporaryDirectory()
    }
}

@MainActor
enum DepthAnalysisSharePreparationState {
    case idle
    case preparing(option: DepthAnalysisShareOption, progress: Double)
    case failed(option: DepthAnalysisShareOption)
    case ready(option: DepthAnalysisShareOption, payload: DepthAnalysisSharePayload)
}

nonisolated struct DepthAnalysisShareProgressPresentationPolicy: Equatable, Sendable {
    /// Fast work proceeds directly to the system share sheet. Once progress
    /// becomes visible, keep it readable instead of flashing it for one frame.
    static let standard = Self(
        revealDelay: .milliseconds(50),
        minimumVisibleDuration: .milliseconds(200)
    )

    let revealDelay: Duration
    let minimumVisibleDuration: Duration
}

nonisolated protocol DepthAnalysisShareArtifactPreparing: Sendable {
    func preparePackage(
        request: TAPNAPShareResourceRequest,
        progress: @escaping TAPNAPShareArtifactBuilder.ProgressHandler
    ) async throws -> TAPNAPShareArtifact

    func prepareImage(
        request: TAPNAPShareResourceRequest,
        requiresSignedPhoto: Bool,
        progress: @escaping TAPNAPShareArtifactBuilder.ProgressHandler
    ) async throws -> TAPNAPShareArtifact

    func prepareVideo(
        request: TAPVideoShareResourceRequest,
        requiresSignedVideo: Bool,
        progress: @escaping TAPVideoShareArtifactBuilder.ProgressHandler
    ) async throws -> TAPNAPShareArtifact
}

nonisolated extension DepthAnalysisShareArtifactPreparing {
    func prepareVideo(
        request: TAPVideoShareResourceRequest,
        requiresSignedVideo: Bool,
        progress: @escaping TAPVideoShareArtifactBuilder.ProgressHandler
    ) async throws -> TAPNAPShareArtifact {
        throw TAPNAPShareArtifactError.shareResourceUnavailable
    }
}

nonisolated struct DepthAnalysisShareArtifactPreparer: DepthAnalysisShareArtifactPreparing {
    private let builder: TAPNAPShareArtifactBuilder
    private let videoBuilder: TAPVideoShareArtifactBuilder

    init(
        builder: TAPNAPShareArtifactBuilder = TAPNAPShareArtifactBuilder(),
        videoBuilder: TAPVideoShareArtifactBuilder = TAPVideoShareArtifactBuilder()
    ) {
        self.builder = builder
        self.videoBuilder = videoBuilder
    }

    func preparePackage(
        request: TAPNAPShareResourceRequest,
        progress: @escaping TAPNAPShareArtifactBuilder.ProgressHandler
    ) async throws -> TAPNAPShareArtifact {
        try await builder.prepareTapnapPackage(request: request, progress: progress)
    }

    func prepareImage(
        request: TAPNAPShareResourceRequest,
        requiresSignedPhoto: Bool,
        progress: @escaping TAPNAPShareArtifactBuilder.ProgressHandler
    ) async throws -> TAPNAPShareArtifact {
        try await builder.prepareImage(
            request: request,
            requiresSignedPhoto: requiresSignedPhoto,
            progress: progress
        )
    }

    func prepareVideo(
        request: TAPVideoShareResourceRequest,
        requiresSignedVideo: Bool,
        progress: @escaping TAPVideoShareArtifactBuilder.ProgressHandler
    ) async throws -> TAPNAPShareArtifact {
        try await videoBuilder.prepareVideo(
            request: request,
            requiresSignedVideo: requiresSignedVideo,
            progress: progress
        )
    }
}

struct DepthAnalysisShareSheet: View {
    let subject: DepthAnalysisShareSubject

    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: DepthAnalysisShareSheetModel

    init(subject: DepthAnalysisShareSubject) {
        self.subject = subject
        _viewModel = StateObject(
            wrappedValue: DepthAnalysisShareSheetModel(subject: subject)
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    statusCard

                    VStack(spacing: 12) {
                        if subject.mediaKind == .video {
                            unavailableOptionButton(
                                titleKey: "share.option.package.title",
                                subtitleKey: "share.option.package.videoComingSoon",
                                systemImage: "shippingbox.fill",
                                badges: ["share.badge.comingSoon"]
                            )
                            .accessibilityIdentifier("tap.share.package")
                        } else {
                            shareOptionButton(
                                option: .tapnapPackage,
                                titleKey: "share.option.package.title",
                                subtitleKey: viewModel.certificationState == .verified
                                    ? "share.option.package.subtitle"
                                    : "share.option.package.locked",
                                systemImage: "shippingbox.fill",
                                badges: ["share.badge.recommended"],
                                isAvailable: viewModel.isPackageAvailable,
                                allowsSelection: viewModel.canPreparePackage
                            )
                            .accessibilityIdentifier("tap.share.package")
                        }

                        if subject.mediaKind == .video {
                            shareOptionButton(
                                option: .video,
                                titleKey: "share.option.video.title",
                                subtitleKey: "share.option.video.subtitle",
                                systemImage: "video.fill",
                                badges: [],
                                isAvailable: viewModel.isVideoAvailable,
                                allowsSelection: viewModel.canPrepareVideo
                            )
                            .accessibilityIdentifier("tap.share.video")
                        } else {
                            shareOptionButton(
                                option: .image,
                                titleKey: "share.option.image.title",
                                subtitleKey: "share.option.image.subtitle",
                                systemImage: "photo.fill",
                                badges: [],
                                isAvailable: viewModel.isImageAvailable,
                                allowsSelection: viewModel.canPrepareImage
                            )
                            .accessibilityIdentifier("tap.share.image")
                        }

                        unavailableOptionButton(
                            titleKey: "share.option.sticker.title",
                            subtitleKey: "share.option.sticker.subtitle",
                            systemImage: "cube.transparent.fill",
                            badges: ["share.badge.comingSoon"]
                        )
                        .accessibilityIdentifier("tap.share.sticker")

                        unavailableOptionButton(
                            titleKey: "share.option.link.title",
                            subtitleKey: "share.option.link.subtitle",
                            systemImage: "link",
                            badges: ["share.badge.members", "share.badge.comingSoon"]
                        )
                        .accessibilityIdentifier("tap.share.link")
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 16)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                preparationStatus
            }
            .navigationTitle("Share")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        viewModel.cancelAndCleanup()
                        dismiss()
                    }
                    .accessibilityIdentifier("tap.share.done")
                }
            }
            .task(id: subject.id) {
                await viewModel.refreshCertification()
            }
            .onReceive(
                NotificationCenter.default.publisher(for: .tapLibraryDidChange)
            ) { _ in
                viewModel.scheduleCertificationRefresh()
            }
            .onDisappear {
                viewModel.cancelAndCleanup()
            }
            .sheet(item: $viewModel.activityPayload, onDismiss: {
                viewModel.finishActivityPresentation()
            }) { payload in
                VerificationExportActivityView(
                    activityItems: [payload.artifact.fileURL]
                )
            }
        }
    }

    @ViewBuilder
    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(String(localized: "share.status.title"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            if let certificationState = viewModel.certificationState {
                HStack(spacing: 12) {
                    Image(systemName: certificationState.systemImage)
                        .font(.title2)
                        .foregroundStyle(certificationState.tint)

                    Text(String(localized: certificationState.localizationKey))
                        .font(.headline)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("tap.share.status")
            } else {
                HStack(spacing: 12) {
                    Circle()
                        .fill(.tertiary)
                        .frame(width: 24, height: 24)
                    Capsule()
                        .fill(.tertiary)
                        .frame(width: 104, height: 18)
                }
                .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func shareOptionButton(
        option: DepthAnalysisShareOption,
        titleKey: String.LocalizationValue,
        subtitleKey: String.LocalizationValue,
        systemImage: String,
        badges: [String.LocalizationValue],
        isAvailable: Bool,
        allowsSelection: Bool
    ) -> some View {
        Button {
            viewModel.prepare(option)
        } label: {
            shareOptionLabel(
                titleKey: titleKey,
                subtitleKey: subtitleKey,
                systemImage: systemImage,
                badges: badges
            )
        }
        .buttonStyle(StableShareOptionButtonStyle())
        .disabled(!allowsSelection)
        // A transient preparation state must not dim and then re-brighten the
        // entire row immediately before the system share sheet appears.
        .opacity(isAvailable ? 1 : 0.52)
    }

    private func unavailableOptionButton(
        titleKey: String.LocalizationValue,
        subtitleKey: String.LocalizationValue,
        systemImage: String,
        badges: [String.LocalizationValue]
    ) -> some View {
        Button {} label: {
            shareOptionLabel(
                titleKey: titleKey,
                subtitleKey: subtitleKey,
                systemImage: systemImage,
                badges: badges
            )
        }
        .buttonStyle(StableShareOptionButtonStyle())
        .disabled(true)
        .opacity(0.52)
    }

    private func shareOptionLabel(
        titleKey: String.LocalizationValue,
        subtitleKey: String.LocalizationValue,
        systemImage: String,
        badges: [String.LocalizationValue]
    ) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: systemImage)
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 42, height: 42)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(String(localized: titleKey))
                        .font(.body.weight(.semibold))

                    ForEach(Array(badges.enumerated()), id: \.offset) { _, badgeKey in
                        Text(String(localized: badgeKey))
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(.quaternary, in: Capsule())
                    }
                }

                Text(String(localized: subtitleKey))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 6)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(.tertiary)
                .padding(.top, 14)
        }
        .multilineTextAlignment(.leading)
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    @ViewBuilder
    private var preparationStatus: some View {
        switch viewModel.preparationState {
        case .idle, .ready:
            EmptyView()
        case .preparing(let option, let progress):
            if viewModel.isPreparationProgressVisible {
                pinnedPreparationFooter {
                    VStack(spacing: 12) {
                        HStack(spacing: 10) {
                            ProgressView(value: progress)
                                .frame(maxWidth: .infinity)

                            Text(
                                progress,
                                format: .percent.precision(.fractionLength(0))
                            )
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                        }
                        .accessibilityIdentifier("tap.share.progress")

                        Text(preparationTitle(option: option, progress: progress))
                            .font(.subheadline.weight(.semibold))
                            .accessibilityIdentifier("tap.share.progress.phase")

                        Button("Cancel") {
                            viewModel.cancelPreparation()
                        }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("tap.share.cancel")
                    }
                }
            }
        case .failed:
            pinnedPreparationFooter {
                VStack(alignment: .leading, spacing: 10) {
                    Label(
                        String(localized: "share.error.title"),
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.orange)

                    Text(String(localized: "share.error.message"))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Button("Retry") {
                        viewModel.retryFailedOption()
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("tap.share.retry")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
            }
        }
    }

    private func pinnedPreparationFooter<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(.regularMaterial)
            .overlay(alignment: .top) {
                Divider()
            }
            .accessibilityIdentifier("tap.share.preparation.footer")
    }

    private func preparationTitle(
        option: DepthAnalysisShareOption,
        progress: Double
    ) -> String {
        if option == .tapnapPackage,
           progress >= TAPNAPShareArtifactBuilder.archiveProgressOffsetForPresentation {
            return String(localized: "share.preparing.package.title")
        }
        return String(localized: "share.preparing.title")
    }
}

/// Share rows intentionally keep identical pixels for pressed and temporarily
/// disabled states. Preparation progress provides persistent feedback without
/// flashing the row while asynchronous model state changes.
private struct StableShareOptionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
    }
}

private extension DepthAnalysisShareCertificationState {
    var localizationKey: String.LocalizationValue {
        switch self {
        case .verified:
            "share.status.verified"
        case .retryPending:
            "share.status.retry"
        case .failed:
            "share.status.failed"
        }
    }

    var systemImage: String {
        switch self {
        case .verified:
            "checkmark.seal.fill"
        case .retryPending:
            "arrow.clockwise.circle.fill"
        case .failed:
            "xmark.octagon.fill"
        }
    }

    var tint: Color {
        switch self {
        case .verified:
            .green
        case .retryPending:
            .orange
        case .failed:
            .red
        }
    }
}

@MainActor
final class DepthAnalysisShareSheetModel: ObservableObject {
    @Published private(set) var certificationState: DepthAnalysisShareCertificationState?
    @Published private(set) var preparationState: DepthAnalysisSharePreparationState = .idle
    @Published private(set) var isPreparationProgressVisible = false
    @Published var activityPayload: DepthAnalysisSharePayload?

    private let subject: DepthAnalysisShareSubject
    private let recordResolver: DepthAnalysisShareRecordResolver
    private let artifactPreparer: any DepthAnalysisShareArtifactPreparing
    private let progressPresentationPolicy: DepthAnalysisShareProgressPresentationPolicy
    private let continuousClock = ContinuousClock()
    private var record: TAPPendingCaptureRecord?
    private var preparationTask: Task<Void, Never>?
    private var progressRevealTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    private var preparationID: UUID?
    private var progressVisibleAt: ContinuousClock.Instant?
    /// SwiftUI clears an item-driven sheet binding before invoking onDismiss.
    /// Keep cleanup ownership independent from that presentation binding so a
    /// certification refresh cannot either delete an active attachment early
    /// or leak it after the system activity controller closes.
    private var activityPayloadPendingCleanup: DepthAnalysisSharePayload?

    init(
        subject: DepthAnalysisShareSubject,
        recordResolver: DepthAnalysisShareRecordResolver = DepthAnalysisShareRecordResolver(),
        artifactPreparer: any DepthAnalysisShareArtifactPreparing = DepthAnalysisShareArtifactPreparer(),
        progressPresentationPolicy: DepthAnalysisShareProgressPresentationPolicy = .standard
    ) {
        self.subject = subject
        self.recordResolver = recordResolver
        self.artifactPreparer = artifactPreparer
        self.progressPresentationPolicy = progressPresentationPolicy
    }

    var isPackageAvailable: Bool {
        subject.mediaKind == .photo && certificationState == .verified
    }

    var isImageAvailable: Bool {
        subject.mediaKind == .photo && certificationState != nil
    }

    var isVideoAvailable: Bool {
        subject.mediaKind == .video && certificationState != nil
    }

    var canPreparePackage: Bool {
        isPackageAvailable && !isPreparing
    }

    var canPrepareImage: Bool {
        isImageAvailable && !isPreparing
    }

    var canPrepareVideo: Bool {
        isVideoAvailable && !isPreparing
    }

    private var isPreparing: Bool {
        if case .preparing = preparationState {
            return true
        }
        return false
    }

    func refreshCertification() async {
        let resolvedRecord: TAPPendingCaptureRecord?
        do {
            resolvedRecord = try await recordResolver.record(for: subject)
        } catch {
            resolvedRecord = nil
        }

        guard !Task.isCancelled else {
            return
        }

        let refreshedState = DepthAnalysisShareCertificationPolicy.state(
            for: resolvedRecord,
            mediaKind: subject.mediaKind
        )
        if let previousState = certificationState, previousState != refreshedState {
            cancelPreparation()
            invalidatePreparedPayloadForCertificationChange()
        }
        record = resolvedRecord
        certificationState = refreshedState
    }

    func scheduleCertificationRefresh() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            await self?.refreshCertification()
        }
    }

    func prepare(_ option: DepthAnalysisShareOption) {
        guard !isPreparing else {
            return
        }

        if case .ready(let readyOption, let payload) = preparationState,
           readyOption == option {
            activityPayloadPendingCleanup = payload
            activityPayload = payload
            return
        }

        let photoRequest = resourceRequest
        let videoRequest = videoResourceRequest
        guard option == .video ? videoRequest != nil : photoRequest != nil else {
            preparationState = .failed(option: option)
            return
        }
        if option == .tapnapPackage, certificationState != .verified {
            return
        }

        clearPreparedPayload()
        let currentPreparationID = UUID()
        preparationID = currentPreparationID
        preparationState = .preparing(option: option, progress: 0)
        scheduleProgressReveal(preparationID: currentPreparationID)

        preparationTask = Task { [weak self] in
            guard let self else {
                return
            }

            do {
                let artifact: TAPNAPShareArtifact
                switch option {
                case .tapnapPackage:
                    guard let request = photoRequest else {
                        throw TAPNAPShareArtifactError.shareResourceUnavailable
                    }
                    artifact = try await artifactPreparer.preparePackage(
                        request: request,
                        progress: { [weak self] progress in
                            Task { @MainActor [weak self] in
                                self?.updateProgress(
                                    progress,
                                    option: option,
                                    preparationID: currentPreparationID
                                )
                            }
                        }
                    )
                case .image:
                    guard let request = photoRequest else {
                        throw TAPNAPShareArtifactError.shareResourceUnavailable
                    }
                    artifact = try await artifactPreparer.prepareImage(
                        request: request,
                        requiresSignedPhoto: certificationState == .verified,
                        progress: { [weak self] progress in
                            Task { @MainActor [weak self] in
                                self?.updateProgress(
                                    progress,
                                    option: option,
                                    preparationID: currentPreparationID
                                )
                            }
                        }
                    )
                case .video:
                    guard let request = videoRequest else {
                        throw TAPNAPShareArtifactError.shareResourceUnavailable
                    }
                    artifact = try await artifactPreparer.prepareVideo(
                        request: request,
                        requiresSignedVideo: certificationState == .verified,
                        progress: { [weak self] progress in
                            Task { @MainActor [weak self] in
                                self?.updateProgress(
                                    progress,
                                    option: option,
                                    preparationID: currentPreparationID
                                )
                            }
                        }
                    )
                }

                var ownsArtifact = true
                defer {
                    if ownsArtifact {
                        artifact.removeTemporaryDirectory()
                    }
                }
                try Task.checkCancellation()
                ownsArtifact = !(try await finishPreparation(
                    artifact,
                    option: option,
                    preparationID: currentPreparationID
                ))
            } catch is CancellationError {
                finishCancellation(preparationID: currentPreparationID)
            } catch {
                finishFailure(option: option, preparationID: currentPreparationID)
            }
        }
    }

    func cancelPreparation() {
        preparationTask?.cancel()
        preparationTask = nil
        preparationID = nil
        resetProgressPresentation()
        if case .preparing = preparationState {
            preparationState = .idle
        }
    }

    func retryFailedOption() {
        guard case .failed(let option) = preparationState else {
            return
        }
        preparationState = .idle
        prepare(option)
    }

    func cancelAndCleanup() {
        refreshTask?.cancel()
        refreshTask = nil
        cancelPreparation()
        clearPreparedPayload()
    }

    /// The system activity controller has finished or was cancelled. The
    /// generated artifact is session-temporary and must not become a cache.
    func finishActivityPresentation() {
        clearPreparedPayload()
    }

    private var resourceRequest: TAPNAPShareResourceRequest? {
        guard subject.mediaKind == .photo else {
            return nil
        }
        if let record {
            return TAPNAPShareResourceRequest(
                record: record,
                expectsPairedVideo: subject.expectsPairedVideo
            )
        }
        if let assetID = subject.assetID {
            return TAPNAPShareResourceRequest(assetLocalIdentifier: assetID)
        }
        return nil
    }

    private var videoResourceRequest: TAPVideoShareResourceRequest? {
        guard subject.mediaKind == .video, !subject.hasIdentityConflict else {
            return nil
        }
        if let record {
            guard record.artifactKind == .tapVideo else {
                return nil
            }
            return TAPVideoShareResourceRequest(record: record)
        }
        guard subject.captureID != nil || subject.assetID != nil else {
            return nil
        }
        return TAPVideoShareResourceRequest(
            captureID: subject.captureID,
            assetLocalIdentifier: subject.assetID,
            prefersPhotoLibraryResource: subject.captureID == nil,
            hasSignatureEvidence: false
        )
    }

    private func updateProgress(
        _ progress: Double?,
        option: DepthAnalysisShareOption,
        preparationID: UUID
    ) {
        guard self.preparationID == preparationID else {
            return
        }
        guard let progress, progress.isFinite else {
            return
        }
        preparationState = .preparing(
            option: option,
            progress: min(max(progress, 0), 1)
        )
    }

    private func finishPreparation(
        _ artifact: TAPNAPShareArtifact,
        option: DepthAnalysisShareOption,
        preparationID: UUID
    ) async throws -> Bool {
        guard self.preparationID == preparationID else {
            return false
        }

        if isPreparationProgressVisible {
            preparationState = .preparing(option: option, progress: 1)
        }
        try await waitForMinimumProgressVisibility()
        try Task.checkCancellation()
        guard self.preparationID == preparationID else {
            return false
        }

        self.preparationID = nil
        preparationTask = nil
        resetProgressPresentation()
        let payload = DepthAnalysisSharePayload(option: option, artifact: artifact)
        preparationState = .ready(option: option, payload: payload)
        activityPayloadPendingCleanup = payload
        activityPayload = payload
        return true
    }

    private func finishFailure(
        option: DepthAnalysisShareOption,
        preparationID: UUID
    ) {
        guard self.preparationID == preparationID else {
            return
        }
        self.preparationID = nil
        preparationTask = nil
        resetProgressPresentation()
        preparationState = .failed(option: option)
    }

    private func finishCancellation(preparationID: UUID) {
        guard self.preparationID == preparationID else {
            return
        }
        self.preparationID = nil
        preparationTask = nil
        resetProgressPresentation()
        preparationState = .idle
    }

    private func scheduleProgressReveal(preparationID: UUID) {
        resetProgressPresentation()
        let revealDelay = progressPresentationPolicy.revealDelay
        progressRevealTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: revealDelay)
            } catch {
                return
            }

            guard let self,
                  self.preparationID == preparationID,
                  self.isPreparing else {
                return
            }
            self.progressRevealTask = nil
            self.progressVisibleAt = self.continuousClock.now
            self.isPreparationProgressVisible = true
        }
    }

    private func waitForMinimumProgressVisibility() async throws {
        guard let progressVisibleAt else {
            return
        }

        let elapsed = progressVisibleAt.duration(to: continuousClock.now)
        let remaining = progressPresentationPolicy.minimumVisibleDuration - elapsed
        if remaining > .zero {
            try await Task.sleep(for: remaining)
        }
    }

    private func resetProgressPresentation() {
        progressRevealTask?.cancel()
        progressRevealTask = nil
        progressVisibleAt = nil
        isPreparationProgressVisible = false
    }

    private func clearPreparedPayload() {
        let readyPayload: DepthAnalysisSharePayload?
        if case .ready(_, let payload) = preparationState {
            readyPayload = payload
        } else {
            readyPayload = nil
        }
        let payloads = [
            readyPayload,
            activityPayload,
            activityPayloadPendingCleanup
        ].compactMap { $0 }
        activityPayload = nil
        activityPayloadPendingCleanup = nil
        var removedPayloadIDs: Set<UUID> = []
        for payload in payloads where removedPayloadIDs.insert(payload.id).inserted {
            payload.removeTemporaryDirectory()
        }
        if !isPreparing {
            preparationState = .idle
        }
    }

    /// UIActivityViewController may not open a file URL until the user picks
    /// a destination. A library notification can invalidate the prepared
    /// option while that controller is still presented, but it must never
    /// remove the active attachment. The normal activity dismissal path owns
    /// final cleanup.
    private func invalidatePreparedPayloadForCertificationChange() {
        guard activityPayload != nil else {
            clearPreparedPayload()
            return
        }
        if !isPreparing {
            preparationState = .idle
        }
    }
}
