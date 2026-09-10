//
//  DepthAnalysisShareCoordinator.swift
//  TAPCamDemo
//

import Combine
import Foundation
import OSLog

nonisolated enum DepthAnalysisShareOption: String, Equatable, Sendable {
    case tapnapPackage
    case image
    case video
}

private extension DepthAnalysisShareMediaKind {
    var diagnosticValue: String {
        switch self {
        case .photo:
            return "photo"
        case .video:
            return "video"
        }
    }
}

@MainActor
enum DepthAnalysisSharePreparationState {
    case idle
    case preparing(option: DepthAnalysisShareOption, progress: Double)
    case failed(option: DepthAnalysisShareOption)
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

/// Owns one frozen Share presentation and its temporary artifact lease. The
/// Viewer, pager, and playback session never observe this object.
@MainActor
class DepthAnalysisShareCoordinator: ObservableObject {
    @Published private(set) var certificationState: DepthAnalysisShareCertificationState?
    @Published private(set) var resourcePreparationFailed = false
    @Published private(set) var preparationState: DepthAnalysisSharePreparationState = .idle
    @Published private(set) var isPopoverPresented = false
    @Published private(set) var activityPresentation: TAPShareActivityPresentation?

    private let recordResolver: DepthAnalysisShareRecordResolver
    private let artifactPreparer: any DepthAnalysisShareArtifactPreparing
    private let localIntegrityValidator: any DepthAnalysisShareLocalIntegrityValidating
    private let activityPresentationBuilder: @MainActor (
        TAPNAPShareArtifact
    ) -> TAPShareActivityPresentation

    private(set) var subject: DepthAnalysisShareSubject?
    private var originalResource: DepthAnalysisShareOriginalResource?
    private var resourceAccess: DepthAnalysisShareResourceAccess?
    private var record: TAPPendingCaptureRecord?
    private var presentationID: UUID?
    private var preparationID: UUID?
    private var preparationTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    private var certificationRefreshID: UUID?
    private var hasDeferredCertificationRefresh = false
    private var popoverHasAppeared = false
    private var pendingHandoffPresentation: TAPShareActivityPresentation?

    init(
        subject: DepthAnalysisShareSubject? = nil,
        originalResource: DepthAnalysisShareOriginalResource? = nil,
        recordResolver: DepthAnalysisShareRecordResolver = DepthAnalysisShareRecordResolver(),
        artifactPreparer: any DepthAnalysisShareArtifactPreparing = DepthAnalysisShareArtifactPreparer(),
        localIntegrityValidator: any DepthAnalysisShareLocalIntegrityValidating =
            DepthAnalysisShareLocalIntegrityValidator(),
        activityPresentationBuilder: @escaping @MainActor (
            TAPNAPShareArtifact
        ) -> TAPShareActivityPresentation = { artifact in
            TAPShareActivityPresentation(artifact: artifact)
        }
    ) {
        self.subject = subject
        self.originalResource = originalResource
        self.recordResolver = recordResolver
        self.artifactPreparer = artifactPreparer
        self.localIntegrityValidator = localIntegrityValidator
        self.activityPresentationBuilder = activityPresentationBuilder
        if let subject,
           let originalResource,
           subject.mediaKind == originalResource.mediaKind,
           originalResource.matches(subject: subject),
           !subject.hasIdentityConflict {
            presentationID = UUID()
            isPopoverPresented = true
            // This initializer is reserved for deterministic tests. Production
            // presents through `present`, whose UIKit appearance callback is the
            // only trigger for local integrity work.
            popoverHasAppeared = true
        }
    }

    var activityPayload: TAPNAPShareArtifact? {
        activityPresentation?.artifact
    }

    var isPackageAvailable: Bool {
        subject?.mediaKind == .photo && certificationState == .localIntegrityPassed
    }

    var isImageAvailable: Bool {
        subject?.mediaKind == .photo && originalResource != nil && certificationState != nil
    }

    var isVideoAvailable: Bool {
        subject?.mediaKind == .video && originalResource != nil && certificationState != nil
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

    var isPreparing: Bool {
        if case .preparing = preparationState {
            return true
        }
        return false
    }

    var visibleProgress: Double? {
        switch preparationState {
        case .preparing(_, let progress):
            return progress
        case .idle, .failed:
            return nil
        }
    }

    func preparationProgress(for option: DepthAnalysisShareOption) -> Double? {
        guard case .preparing(let activeOption, let progress) = preparationState,
              activeOption == option else {
            return nil
        }
        return progress
    }

    var hasActiveActivityPresentation: Bool {
        pendingHandoffPresentation != nil || activityPresentation != nil
    }

    func shareButtonTapped(
        mediaKind: DepthAnalysisShareMediaKind?,
        resourceReady: Bool
    ) {
        #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
        TAPDiagnostics.sharePackaging.info(
            "tap_share_tapped media=\(mediaKind?.diagnosticValue ?? "none", privacy: .public) resourceReady=\(resourceReady, privacy: .public) activityActive=\(self.hasActiveActivityPresentation, privacy: .public)"
        )
        #endif
    }

    func popoverDidAppear() {
        guard isPopoverPresented,
              !popoverHasAppeared else {
            return
        }
        popoverHasAppeared = true
        #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
        TAPDiagnostics.sharePackaging.info(
            "tap_share_popover_appeared media=\(self.subject?.mediaKind.diagnosticValue ?? "none", privacy: .public) pendingRoute=\(self.subject?.usesPendingCaptureResource == true, privacy: .public)"
        )
        #endif
        guard certificationState == nil,
              refreshTask == nil,
              let presentationID,
              let refreshID = certificationRefreshID else {
            return
        }
        refreshTask = Task { [weak self] in
            await self?.refreshCertification(
                presentationID: presentationID,
                refreshID: refreshID
            )
        }
    }

    func togglePresentation(
        for subject: DepthAnalysisShareSubject,
        resourceAccess: DepthAnalysisShareResourceAccess
    ) {
        if isPopoverPresented {
            setPopoverPresented(false)
        } else {
            present(subject: subject, resourceAccess: resourceAccess)
        }
    }

    func present(
        subject: DepthAnalysisShareSubject,
        resource: DepthAnalysisShareOriginalResource
    ) {
        guard resource.matches(subject: subject) else { return }
        present(
            subject: subject,
            resourceAccess: DepthAnalysisShareResourceAccess(isReady: true, acquire: { resource })
        )
    }

    func present(
        subject: DepthAnalysisShareSubject,
        resourceAccess: DepthAnalysisShareResourceAccess
    ) {
        guard !hasActiveActivityPresentation, !subject.hasIdentityConflict else { return }
        let readyResource = resourceAccess.acquire()
        guard readyResource.map({ $0.matches(subject: subject) }) ?? true else { return }
        cancelPreparation(runsDeferredRefresh: false)
        discardPendingHandoff()
        refreshTask?.cancel()
        refreshTask = nil

        presentationID = UUID()
        certificationRefreshID = UUID()
        self.subject = subject
        self.resourceAccess = resourceAccess
        originalResource = readyResource
        record = nil
        certificationState = nil
        resourcePreparationFailed = false
        preparationState = .idle
        popoverHasAppeared = false
        isPopoverPresented = true
    }

    func setPopoverPresented(_ presented: Bool) {
        guard isPopoverPresented != presented else {
            return
        }
        isPopoverPresented = presented
    }

    /// Called by the popover content's disappearance. Promotion happens only
    /// after the app-owned presentation is gone, avoiding nested presentation.
    func popoverDidDisappear() {
        guard !isPopoverPresented else {
            return
        }
        if let presentation = pendingHandoffPresentation {
            let payload = presentation.artifact
            pendingHandoffPresentation = nil
            activityPresentation = presentation
            preparationState = .idle
            #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
            TAPDiagnostics.sharePackaging.info(
                "tap_share_activity_handoff_started kind=\(payload.kind.rawValue, privacy: .public)"
            )
            #endif
        } else {
            dismissPresentation()
        }
    }

    func refreshCertification() async {
        if presentationID == nil {
            presentationID = UUID()
        }
        guard let presentationID else {
            return
        }
        let refreshID = UUID()
        certificationRefreshID = refreshID
        await refreshCertification(
            presentationID: presentationID,
            refreshID: refreshID
        )
    }

    func scheduleCertificationRefresh(
        for change: TAPLibraryPendingCaptureChange? = nil
    ) {
        guard isPopoverPresented,
              pendingHandoffPresentation == nil,
              !hasActiveActivityPresentation else {
            return
        }
        // Photos/iCloud originals and their local verdict are immutable for
        // this frozen presentation. Queue notifications can affect only the
        // exact pending capture shown by this popover.
        guard let subject,
              subject.usesPendingCaptureResource,
              let captureID = subject.captureID,
              change?.captureID == captureID,
              certificationState == .retryPending else {
            return
        }
        guard !isPreparing else {
            hasDeferredCertificationRefresh = true
            return
        }
        guard let presentationID else {
            return
        }
        hasDeferredCertificationRefresh = false
        let refreshID = UUID()
        certificationRefreshID = refreshID
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            await self?.refreshCertification(
                presentationID: presentationID,
                refreshID: refreshID
            )
        }
    }

    /// Test/explicit refresh entry point for the frozen pending subject. Real
    /// Library notifications must use the identity-carrying overload above.
    func scheduleCertificationRefresh() {
        scheduleCertificationRefresh(
            for: subject?.captureID.map(TAPLibraryPendingCaptureChange.init)
        )
    }

    func prepare(_ option: DepthAnalysisShareOption) {
        guard isPopoverPresented,
              popoverHasAppeared,
              certificationState != nil,
              !isPreparing,
              let subject,
              let presentationID else {
            return
        }

        let photoRequest = resourceRequest(for: subject)
        let videoRequest = videoResourceRequest(for: subject)
        guard option == .video ? videoRequest != nil : photoRequest != nil else {
            preparationState = .failed(option: option)
            return
        }
        if option == .tapnapPackage, certificationState != .localIntegrityPassed {
            return
        }

        discardPendingHandoff()
        let currentPreparationID = UUID()
        preparationID = currentPreparationID
        preparationState = .preparing(option: option, progress: 0)

        preparationTask = Task { [weak self] in
            guard let self else {
                return
            }
            do {
                let artifact: TAPNAPShareArtifact
                let progressHandler = makeProgressHandler(
                    option: option,
                    presentationID: presentationID,
                    preparationID: currentPreparationID
                )
                switch option {
                case .tapnapPackage:
                    guard let photoRequest else {
                        throw TAPNAPShareArtifactError.shareResourceUnavailable
                    }
                    artifact = try await artifactPreparer.preparePackage(
                        request: photoRequest,
                        progress: progressHandler
                    )
                case .image:
                    guard let photoRequest else {
                        throw TAPNAPShareArtifactError.shareResourceUnavailable
                    }
                    artifact = try await artifactPreparer.prepareImage(
                        request: photoRequest,
                        requiresSignedPhoto: certificationState == .localIntegrityPassed,
                        progress: progressHandler
                    )
                case .video:
                    guard let videoRequest else {
                        throw TAPNAPShareArtifactError.shareResourceUnavailable
                    }
                    artifact = try await artifactPreparer.prepareVideo(
                        request: videoRequest,
                        requiresSignedVideo: certificationState == .localIntegrityPassed,
                        progress: progressHandler
                    )
                }

                var ownsArtifact = true
                defer {
                    if ownsArtifact {
                        artifact.removeTemporaryDirectory()
                    }
                }
                try Task.checkCancellation()
                guard let preparedPresentation = makeActivityPresentation(
                    artifact,
                    option: option,
                    presentationID: presentationID,
                    preparationID: currentPreparationID
                ) else {
                    return
                }
                // The presentation owns the artifact before any later await.
                // The system controller is intentionally not constructed until
                // SwiftUI begins presenting the system sheet.
                ownsArtifact = false
                try finishPreparation(
                    preparedPresentation,
                    option: option,
                    presentationID: presentationID,
                    preparationID: currentPreparationID
                )
            } catch is CancellationError {
                finishCancellation(
                    presentationID: presentationID,
                    preparationID: currentPreparationID
                )
            } catch {
                finishFailure(
                    option: option,
                    presentationID: presentationID,
                    preparationID: currentPreparationID
                )
            }
        }
    }

    func cancelPreparation() {
        cancelPreparation(runsDeferredRefresh: true)
    }

    private func cancelPreparation(runsDeferredRefresh: Bool) {
        preparationTask?.cancel()
        preparationTask = nil
        preparationID = nil
        if case .preparing = preparationState {
            preparationState = .idle
        }
        if runsDeferredRefresh {
            runDeferredCertificationRefreshIfNeeded()
        }
    }

    func retryOriginalResource() {
        guard resourcePreparationFailed, isPopoverPresented, !isPreparing,
              let presentationID else { return }
        resourcePreparationFailed = false
        certificationState = nil
        originalResource = nil
        let refreshID = UUID()
        certificationRefreshID = refreshID
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            await self?.refreshCertification(presentationID: presentationID, refreshID: refreshID)
        }
    }

    func cancelFailure() {
        guard case .failed = preparationState else {
            return
        }
        preparationState = .idle
    }

    func retryFailedOption() {
        guard case .failed(let option) = preparationState else {
            return
        }
        preparationState = .idle
        prepare(option)
    }

    /// The system sheet's item binding is the primary app-owned lifecycle
    /// signal. SwiftUI `onDismiss` is an exact-ID, idempotent fallback into the
    /// same transition. Only the matching attempt ends, and its temporary file
    /// cleanup does not wait for UIKit to release a cached controller instance.
    func activityPresentationDidEnd(expectedArtifactID: UUID) {
        guard let endedPresentation = activityPresentation,
              endedPresentation.id == expectedArtifactID else {
            return
        }
        let kind = endedPresentation.artifact.kind.rawValue
        #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
        TAPDiagnostics.sharePackaging.info(
            "tap_share_activity_sheet_dismissed kind=\(kind, privacy: .public)"
        )
        #endif
        activityPresentation = nil
        resetPresentationState()
        endedPresentation.scheduleTemporaryDirectoryCleanup()
    }

    func dismissPresentation() {
        guard !hasActiveActivityPresentation else {
            return
        }
        cancelPreparation(runsDeferredRefresh: false)
        refreshTask?.cancel()
        refreshTask = nil
        certificationRefreshID = nil
        discardPendingHandoff()
        resetPresentationState()
    }

    func shutdown() {
        guard !hasActiveActivityPresentation else {
            return
        }
        cancelPreparation(runsDeferredRefresh: false)
        refreshTask?.cancel()
        refreshTask = nil
        certificationRefreshID = nil
        activityPresentation = nil
        discardPendingHandoff()
        resetPresentationState()
    }

    private func refreshCertification(
        presentationID: UUID,
        refreshID: UUID
    ) async {
        guard let subject else {
            return
        }
        let resolvedRecord: TAPPendingCaptureRecord?
        let recordResolutionFailed: Bool
        do {
            resolvedRecord = try await recordResolver.record(for: subject)
            recordResolutionFailed = false
        } catch {
            resolvedRecord = nil
            recordResolutionFailed = true
        }

        guard !Task.isCancelled,
              self.presentationID == presentationID,
              certificationRefreshID == refreshID else {
            return
        }

        // A lookup can already be in flight when the user chooses a format.
        // Freeze certification for that attempt so a late notification cannot
        // replace its preparation state or consume its pending handoff artifact.
        if isPreparing {
            hasDeferredCertificationRefresh = true
            return
        }
        guard pendingHandoffPresentation == nil else {
            return
        }

        var resourceResolutionFailed = false
        var resourceIdentityFailed = false
        if !recordResolutionFailed {
            let requiresSignedOriginal = subject.usesPendingCaptureResource
                && (subject.mediaKind == .photo
                    ? resolvedRecord?.signedPhotoFilename != nil
                    : resolvedRecord?.videoArtifactState == .signed)
            let needsSignedRefresh = requiresSignedOriginal
                && originalResource?.selectedSignedOriginal != true
            if originalResource == nil || needsSignedRefresh {
                do {
                    guard let resourceAccess else {
                        throw TAPNAPShareArtifactError.shareResourceUnavailable
                    }
                    let resource = try await resourceAccess.acquirePrepared(
                        requiresSignedOriginal: requiresSignedOriginal
                    )
                    try Task.checkCancellation()
                    guard self.presentationID == presentationID,
                          certificationRefreshID == refreshID else { return }
                    guard resource.matches(subject: subject) else {
                        throw DepthAnalysisShareRecordResolutionError.identityConflict
                    }
                    guard !requiresSignedOriginal || resource.selectedSignedOriginal == true else {
                        throw TAPNAPShareArtifactError.shareResourceUnavailable
                    }
                    originalResource = resource
                } catch is CancellationError {
                    return
                } catch DepthAnalysisShareRecordResolutionError.identityConflict {
                    resourceIdentityFailed = true
                } catch {
                    resourceResolutionFailed = true
                }
            }
        }
        guard !Task.isCancelled,
              self.presentationID == presentationID,
              certificationRefreshID == refreshID else { return }

        let refreshedState: DepthAnalysisShareCertificationState
        if recordResolutionFailed || resourceResolutionFailed || resourceIdentityFailed {
            // A missing queue record is normalized to nil by the resolver.
            // Every remaining error is corruption, ambiguity, or an identity
            // conflict and must fail closed without touching media validation.
            refreshedState = .failed
        } else {
            refreshedState = await resolvedCertificationState(
                subject: subject,
                record: resolvedRecord
            )
        }
        guard !Task.isCancelled,
              self.presentationID == presentationID,
              certificationRefreshID == refreshID else {
            return
        }
        if let previousState = certificationState,
           previousState != refreshedState {
            cancelPreparation()
            discardPendingHandoff()
        }
        record = resolvedRecord
        resourcePreparationFailed = resourceResolutionFailed
        certificationState = refreshedState
        certificationRefreshID = nil
    }

    private func resolvedCertificationState(
        subject: DepthAnalysisShareSubject,
        record: TAPPendingCaptureRecord?
    ) async -> DepthAnalysisShareCertificationState {
        guard let originalResource,
              originalResource.mediaKind == subject.mediaKind else {
            return .failed
        }

        if subject.usesPendingCaptureResource {
            switch originalResource {
            case .photo(let resource):
                guard case .pendingCapture(_, let selectedSignedPhoto) = resource.origin else {
                    return .failed
                }
                switch TAPPendingPhotoSharePolicy.disposition(
                    for: record,
                    selectedSignedPhoto: selectedSignedPhoto
                ) {
                case .needsRetry:
                    return .retryPending
                case .failed:
                    return .failed
                case .validateSignedOriginal:
                    break
                }
            case .video(let resource):
                switch TAPPendingVideoSharePolicy.disposition(
                    for: record,
                    selectedSignedVideo: resource.selectedSignedVideo == true
                ) {
                case .needsRetry:
                    return .retryPending
                case .failed:
                    return .failed
                case .validateSignedOriginal:
                    break
                }
            }
        }

        let validationStartedAt = ProcessInfo.processInfo.systemUptime
        #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
        TAPDiagnostics.sharePackaging.info(
            "tap_share_local_integrity_started media=\(subject.mediaKind.diagnosticValue, privacy: .public) route=\(subject.usesPendingCaptureResource ? "pending" : "photos", privacy: .public)"
        )
        #endif
        do {
            try await localIntegrityValidator.validate(
                resource: originalResource,
                expectedCaptureID: record?.captureID ?? subject.captureID,
                expectedPackageID: subject.mediaKind == .video ? record?.packageID : nil
            )
            #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
            TAPDiagnostics.sharePackaging.info(
                "tap_share_local_integrity_finished media=\(subject.mediaKind.diagnosticValue, privacy: .public) outcome=localIntegrityPassed message=本地完整性检查通过 durationBucket=\(Self.durationBucket(since: validationStartedAt), privacy: .public)"
            )
            #endif
            return .localIntegrityPassed
        } catch {
            #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
            TAPDiagnostics.sharePackaging.info(
                "tap_share_local_integrity_finished media=\(subject.mediaKind.diagnosticValue, privacy: .public) outcome=failed durationBucket=\(Self.durationBucket(since: validationStartedAt), privacy: .public)"
            )
            #endif
            return .failed
        }
    }

    private var directShareVerifiabilityWarning: String? {
        guard certificationState == .failed else {
            return nil
        }
        return String(localized: "share.warning.localIntegrityFailed")
    }

    private func resourceRequest(
        for subject: DepthAnalysisShareSubject
    ) -> TAPNAPShareResourceRequest? {
        guard subject.mediaKind == .photo,
              !subject.hasIdentityConflict,
              case .photo(let resourceLease) = originalResource else {
            return nil
        }
        return TAPNAPShareResourceRequest(
            originalResourceLease: resourceLease,
            hasSignatureEvidence: certificationState == .localIntegrityPassed,
            directShareVerifiabilityWarning: directShareVerifiabilityWarning
        )
    }

    private func videoResourceRequest(
        for subject: DepthAnalysisShareSubject
    ) -> TAPVideoShareResourceRequest? {
        guard subject.mediaKind == .video,
              !subject.hasIdentityConflict,
              case .video(let resourceLease) = originalResource else {
            return nil
        }
        return TAPVideoShareResourceRequest(
            originalResourceLease: resourceLease,
            hasSignatureEvidence: certificationState == .localIntegrityPassed,
            directShareVerifiabilityWarning: directShareVerifiabilityWarning
        )
    }

    private func makeProgressHandler(
        option: DepthAnalysisShareOption,
        presentationID: UUID,
        preparationID: UUID
    ) -> TAPNAPShareArtifactBuilder.ProgressHandler {
        { [weak self] progress in
            Task { @MainActor [weak self] in
                self?.updateProgress(
                    progress,
                    option: option,
                    presentationID: presentationID,
                    preparationID: preparationID
                )
            }
        }
    }

    private func updateProgress(
        _ progress: Double?,
        option: DepthAnalysisShareOption,
        presentationID: UUID,
        preparationID: UUID
    ) {
        guard self.presentationID == presentationID,
              self.preparationID == preparationID,
              let progress,
              progress.isFinite else {
            return
        }
        let currentProgress: Double
        if case .preparing(_, let current) = preparationState {
            currentProgress = current
        } else {
            currentProgress = 0
        }
        preparationState = .preparing(
            option: option,
            progress: max(currentProgress, min(max(progress, 0), 1))
        )
    }

    private func makeActivityPresentation(
        _ artifact: TAPNAPShareArtifact,
        option: DepthAnalysisShareOption,
        presentationID: UUID,
        preparationID: UUID
    ) -> TAPShareActivityPresentation? {
        guard self.presentationID == presentationID,
              self.preparationID == preparationID else {
            return nil
        }
        #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
        TAPDiagnostics.sharePackaging.info(
            "tap_share_payload_ready kind=\(artifact.kind.rawValue, privacy: .public) option=\(option.rawValue, privacy: .public)"
        )
        #endif

        // Only create an attempt-scoped artifact owner here. UIKit construction
        // belongs to the later system-sheet presentation boundary; doing it in
        // this app-owned popover would make LaunchServices inspect the file too
        // early.
        return activityPresentationBuilder(artifact)
    }

    private func finishPreparation(
        _ preparedPresentation: TAPShareActivityPresentation,
        option: DepthAnalysisShareOption,
        presentationID: UUID,
        preparationID: UUID
    ) throws {
        var transferredToPendingHandoff = false
        defer {
            if !transferredToPendingHandoff {
                preparedPresentation.scheduleTemporaryDirectoryCleanup()
            }
        }
        try Task.checkCancellation()
        guard self.presentationID == presentationID,
              self.preparationID == preparationID else {
            return
        }
        preparationState = .preparing(option: option, progress: 1)
        self.preparationID = nil
        preparationTask = nil
        pendingHandoffPresentation = preparedPresentation
        transferredToPendingHandoff = true
        isPopoverPresented = false
    }

    private func finishFailure(
        option: DepthAnalysisShareOption,
        presentationID: UUID,
        preparationID: UUID
    ) {
        guard self.presentationID == presentationID,
              self.preparationID == preparationID else {
            return
        }
        self.preparationID = nil
        preparationTask = nil
        preparationState = .failed(option: option)
        runDeferredCertificationRefreshIfNeeded()
    }

    private func finishCancellation(
        presentationID: UUID,
        preparationID: UUID
    ) {
        guard self.presentationID == presentationID,
              self.preparationID == preparationID else {
            return
        }
        self.preparationID = nil
        preparationTask = nil
        preparationState = .idle
        runDeferredCertificationRefreshIfNeeded()
    }

    private func discardPendingHandoff() {
        let discardedPresentation = pendingHandoffPresentation
        pendingHandoffPresentation = nil
        discardedPresentation?.scheduleTemporaryDirectoryCleanup()
        if !hasActiveActivityPresentation, !isPreparing {
            preparationState = .idle
        }
    }

    private func resetPresentationState() {
        presentationID = nil
        preparationID = nil
        certificationRefreshID = nil
        subject = nil
        originalResource = nil
        resourceAccess = nil
        record = nil
        certificationState = nil
        resourcePreparationFailed = false
        preparationState = .idle
        isPopoverPresented = false
        popoverHasAppeared = false
        pendingHandoffPresentation = nil
        activityPresentation = nil
        hasDeferredCertificationRefresh = false
    }

    nonisolated private static func durationBucket(
        since startedAt: TimeInterval
    ) -> String {
        let milliseconds = max(
            0,
            Int(((ProcessInfo.processInfo.systemUptime - startedAt) * 1_000).rounded())
        )
        switch milliseconds {
        case ..<50:
            return "under50ms"
        case ..<200:
            return "50to199ms"
        case ..<1_000:
            return "200to999ms"
        default:
            return "over1s"
        }
    }

    private func runDeferredCertificationRefreshIfNeeded() {
        guard hasDeferredCertificationRefresh else {
            return
        }
        hasDeferredCertificationRefresh = false
        scheduleCertificationRefresh(
            for: subject?.captureID.map(TAPLibraryPendingCaptureChange.init)
        )
    }
}
