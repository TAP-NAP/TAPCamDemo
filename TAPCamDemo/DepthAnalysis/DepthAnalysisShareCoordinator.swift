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
    case ready(option: DepthAnalysisShareOption)
}

nonisolated struct DepthAnalysisShareProgressPresentationPolicy: Equatable, Sendable {
    static let standard = Self(
        revealDelay: .milliseconds(50),
        minimumVisibleDuration: .milliseconds(400)
    )

    let revealDelay: Duration
    let minimumVisibleDuration: Duration
}

nonisolated struct DepthAnalysisShareActivityPresentationPolicy: Equatable, Sendable {
    static let standard = Self(
        appearanceTimeout: .seconds(5),
        dismantleTimeout: .seconds(1)
    )

    let appearanceTimeout: Duration
    let dismantleTimeout: Duration
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
    @Published private(set) var preparationState: DepthAnalysisSharePreparationState = .idle
    @Published private(set) var isPreparationProgressVisible = false
    @Published private(set) var isPopoverPresented = false
    @Published private(set) var activityPresentation: TAPShareActivityPresentation?

    private let recordResolver: DepthAnalysisShareRecordResolver
    private let artifactPreparer: any DepthAnalysisShareArtifactPreparing
    private let localIntegrityValidator: any DepthAnalysisShareLocalIntegrityValidating
    private let progressPresentationPolicy: DepthAnalysisShareProgressPresentationPolicy
    private let activityPresentationPolicy: DepthAnalysisShareActivityPresentationPolicy
    private let activityPresentationBuilder: @MainActor (
        TAPNAPShareArtifact
    ) -> TAPShareActivityPresentation
    private let continuousClock = ContinuousClock()

    private(set) var subject: DepthAnalysisShareSubject?
    private var originalResource: DepthAnalysisShareOriginalResource?
    private var record: TAPPendingCaptureRecord?
    private var presentationID: UUID?
    private var preparationID: UUID?
    private var preparationTask: Task<Void, Never>?
    private var progressRevealTask: Task<Void, Never>?
    private var activityAppearanceWatchdogTask: Task<Void, Never>?
    private var activityDismantleWatchdogTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    private var certificationRefreshID: UUID?
    private var hasDeferredCertificationRefresh = false
    private var popoverHasAppeared = false
    private var preparationStartedAt: ContinuousClock.Instant?
    private var progressVisibleAt: ContinuousClock.Instant?
    private var pendingHandoffPresentation: TAPShareActivityPresentation?
    private var activeActivityLease: TAPNAPShareArtifact?
    private var activitySheetArtifactID: UUID?
    private var activitySheetHasAppeared = false

    init(
        subject: DepthAnalysisShareSubject? = nil,
        originalResource: DepthAnalysisShareOriginalResource? = nil,
        recordResolver: DepthAnalysisShareRecordResolver = DepthAnalysisShareRecordResolver(),
        artifactPreparer: any DepthAnalysisShareArtifactPreparing = DepthAnalysisShareArtifactPreparer(),
        localIntegrityValidator: any DepthAnalysisShareLocalIntegrityValidating =
            DepthAnalysisShareLocalIntegrityValidator(),
        progressPresentationPolicy: DepthAnalysisShareProgressPresentationPolicy = .standard,
        activityPresentationPolicy: DepthAnalysisShareActivityPresentationPolicy = .standard,
        activityPresentationBuilder: @escaping @MainActor (
            TAPNAPShareArtifact
        ) -> TAPShareActivityPresentation = { artifact in
            TAPShareActivityPresentation.prepare(for: artifact)
        }
    ) {
        self.subject = subject
        self.originalResource = originalResource
        self.recordResolver = recordResolver
        self.artifactPreparer = artifactPreparer
        self.localIntegrityValidator = localIntegrityValidator
        self.progressPresentationPolicy = progressPresentationPolicy
        self.activityPresentationPolicy = activityPresentationPolicy
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
        subject?.mediaKind == .photo && certificationState != nil
    }

    var isVideoAvailable: Bool {
        subject?.mediaKind == .video && certificationState != nil
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
        guard isPreparationProgressVisible else {
            return nil
        }
        switch preparationState {
        case .preparing(_, let progress):
            return progress
        case .ready:
            return 1
        case .idle, .failed:
            return nil
        }
    }

    var hasActiveActivityPresentation: Bool {
        activeActivityLease != nil || activitySheetArtifactID != nil
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
        resource: DepthAnalysisShareOriginalResource
    ) {
        if isPopoverPresented {
            setPopoverPresented(false)
        } else {
            present(subject: subject, resource: resource)
        }
    }

    func present(
        subject: DepthAnalysisShareSubject,
        resource: DepthAnalysisShareOriginalResource
    ) {
        guard !hasActiveActivityPresentation,
              !subject.hasIdentityConflict,
              subject.mediaKind == resource.mediaKind,
              resource.matches(subject: subject) else {
            return
        }
        cancelPreparation(runsDeferredRefresh: false)
        discardPendingHandoff()
        refreshTask?.cancel()
        refreshTask = nil

        let currentPresentationID = UUID()
        let currentRefreshID = UUID()
        presentationID = currentPresentationID
        certificationRefreshID = currentRefreshID
        self.subject = subject
        originalResource = resource
        record = nil
        certificationState = nil
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
            activeActivityLease = payload
            activitySheetArtifactID = payload.id
            activitySheetHasAppeared = false
            activityPresentation = presentation
            scheduleActivityAppearanceWatchdog(expectedArtifactID: payload.id)
            #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
            TAPDiagnostics.sharePackaging.info(
                "tap_share_activity_handoff_started kind=\(payload.kind.rawValue, privacy: .public) progressVisible=\(self.isPreparationProgressVisible, privacy: .public) controllerPreconstructed=true"
            )
            #endif
        } else {
            dismissPresentation()
        }
    }

    /// Keeps any already-visible 100% progress on the stable Viewer toolbar
    /// until SwiftUI has mounted the system activity controller. This avoids a
    /// blank handoff interval if controller construction takes noticeable time.
    func activitySheetDidAppear(expectedArtifactID: UUID) {
        guard activitySheetArtifactID == expectedArtifactID,
              activeActivityLease?.id == expectedArtifactID else {
            return
        }
        activitySheetHasAppeared = true
        activityAppearanceWatchdogTask?.cancel()
        activityAppearanceWatchdogTask = nil
        activityDismantleWatchdogTask?.cancel()
        activityDismantleWatchdogTask = nil
        #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
        TAPDiagnostics.sharePackaging.info(
            "tap_share_activity_sheet_appeared kind=\(self.activeActivityLease?.kind.rawValue ?? "none", privacy: .public) progressVisible=\(self.isPreparationProgressVisible, privacy: .public)"
        )
        #endif
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
        preparationStartedAt = continuousClock.now
        preparationState = .preparing(option: option, progress: 0)
        scheduleProgressReveal(
            presentationID: presentationID,
            preparationID: currentPreparationID
        )

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
                ownsArtifact = !(try await finishPreparation(
                    artifact,
                    option: option,
                    presentationID: presentationID,
                    preparationID: currentPreparationID
                ))
            } catch is CancellationError {
                finishCancellation(
                    presentationID: presentationID,
                    preparationID: currentPreparationID
                )
            } catch {
                do {
                    try await finishFailure(
                        option: option,
                        presentationID: presentationID,
                        preparationID: currentPreparationID
                    )
                } catch {
                    finishCancellation(
                        presentationID: presentationID,
                        preparationID: currentPreparationID
                    )
                }
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
        preparationStartedAt = nil
        resetProgressPresentation()
        if case .preparing = preparationState {
            preparationState = .idle
        }
        if runsDeferredRefresh {
            runDeferredCertificationRefreshIfNeeded()
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

    private func endActivityPresentationAfterSystemDismissal(
        expectedArtifactID: UUID
    ) {
        guard activitySheetArtifactID == expectedArtifactID,
              activeActivityLease?.id == expectedArtifactID else {
            return
        }
        // Ending app-owned presentation state must not explicitly delete a
        // file already handed to the system. The activity controller retains
        // the artifact until UIKit releases the controller; the artifact's
        // last-owner lease then performs idempotent cleanup.
        activityPresentation = nil
        activeActivityLease = nil
        activitySheetArtifactID = nil
        activityAppearanceWatchdogTask?.cancel()
        activityAppearanceWatchdogTask = nil
        activityDismantleWatchdogTask?.cancel()
        activityDismantleWatchdogTask = nil
        discardPendingHandoff()
        resetPresentationState()
    }

    /// The system/user dismissal, not destination completion, ends this
    /// app-owned lifecycle. The immutable attempt ID rejects late callbacks
    /// from an older activity controller.
    func activitySheetDidDismiss(expectedArtifactID: UUID) {
        guard activitySheetArtifactID == expectedArtifactID else {
            return
        }
        let appeared = activitySheetHasAppeared
        let kind = activeActivityLease?.kind.rawValue ?? "released"
        #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
        TAPDiagnostics.sharePackaging.info(
            "tap_share_activity_sheet_dismissed kind=\(kind, privacy: .public) appeared=\(appeared, privacy: .public)"
        )
        #endif
        endActivityPresentationAfterSystemDismissal(
            expectedArtifactID: expectedArtifactID
        )
    }

    /// SwiftUI may clear the item binding before its dismissal callback. Stop
    /// advertising a presented sheet without releasing the system controller's
    /// retained file lease; item-scoped dismissal/dismantle owns state cleanup.
    func activityBindingDidDismiss(expectedArtifactID: UUID) {
        guard activitySheetArtifactID == expectedArtifactID,
              activityPresentation?.id == expectedArtifactID else {
            return
        }
        activityPresentation = nil
    }

    func activityControllerDidDismantle(expectedArtifactID: UUID) {
        guard activitySheetArtifactID == expectedArtifactID else {
            return
        }
        #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
        TAPDiagnostics.sharePackaging.info(
            "tap_share_activity_controller_dismantled kind=\(self.activeActivityLease?.kind.rawValue ?? "released", privacy: .public)"
        )
        #endif
        endActivityPresentationAfterSystemDismissal(
            expectedArtifactID: expectedArtifactID
        )
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
        // cancel the 400 ms hold or consume a ready handoff artifact.
        if isPreparing {
            hasDeferredCertificationRefresh = true
            return
        }
        guard pendingHandoffPresentation == nil else {
            return
        }

        let refreshedState: DepthAnalysisShareCertificationState
        if recordResolutionFailed {
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

    private func finishPreparation(
        _ artifact: TAPNAPShareArtifact,
        option: DepthAnalysisShareOption,
        presentationID: UUID,
        preparationID: UUID
    ) async throws -> Bool {
        guard self.presentationID == presentationID,
              self.preparationID == preparationID else {
            return false
        }
        #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
        TAPDiagnostics.sharePackaging.info(
            "tap_share_payload_ready kind=\(artifact.kind.rawValue, privacy: .public) option=\(option.rawValue, privacy: .public) progressVisible=\(self.isPreparationProgressVisible, privacy: .public)"
        )
        #endif

        // Construct while the already-appeared TAP Share popover remains on
        // screen. `VerificationExportActivityView.makeUIViewController` then
        // returns this prepared controller and cannot cold-block the bare
        // Viewer between the app-owned and system-owned presentations.
        let preparedPresentation = activityPresentationBuilder(artifact)
        revealProgressAfterSynchronousColdWorkIfNeeded(
            option: option,
            presentationID: presentationID,
            preparationID: preparationID,
            synchronousDuration: preparedPresentation.constructionDuration
        )
        try Task.checkCancellation()
        guard self.presentationID == presentationID,
              self.preparationID == preparationID else {
            return false
        }
        if isPreparationProgressVisible {
            preparationState = .preparing(option: option, progress: 1)
        }
        try await waitForMinimumProgressVisibility()
        try Task.checkCancellation()
        guard self.presentationID == presentationID,
              self.preparationID == preparationID else {
            return false
        }

        self.preparationID = nil
        preparationStartedAt = nil
        preparationTask = nil
        progressRevealTask?.cancel()
        progressRevealTask = nil
        preparationState = .ready(option: option)
        pendingHandoffPresentation = preparedPresentation
        isPopoverPresented = false
        return true
    }

    private func finishFailure(
        option: DepthAnalysisShareOption,
        presentationID: UUID,
        preparationID: UUID
    ) async throws {
        guard self.presentationID == presentationID,
              self.preparationID == preparationID else {
            return
        }
        try await waitForMinimumProgressVisibility()
        try Task.checkCancellation()
        guard self.presentationID == presentationID,
              self.preparationID == preparationID else {
            return
        }
        self.preparationID = nil
        preparationStartedAt = nil
        preparationTask = nil
        resetProgressPresentation()
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
        preparationStartedAt = nil
        preparationTask = nil
        resetProgressPresentation()
        preparationState = .idle
        runDeferredCertificationRefreshIfNeeded()
    }

    private func scheduleProgressReveal(
        presentationID: UUID,
        preparationID: UUID
    ) {
        resetProgressPresentation()
        let revealDelay = progressPresentationPolicy.revealDelay
        progressRevealTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: revealDelay)
            } catch {
                return
            }
            guard let self,
                  self.presentationID == presentationID,
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

    private func revealProgressAfterSynchronousColdWorkIfNeeded(
        option: DepthAnalysisShareOption,
        presentationID: UUID,
        preparationID: UUID,
        synchronousDuration: Duration
    ) {
        guard !isPreparationProgressVisible,
              popoverHasAppeared,
              self.presentationID == presentationID,
              self.preparationID == preparationID,
              let preparationStartedAt,
              synchronousDuration >= progressPresentationPolicy.revealDelay
                || preparationStartedAt.duration(to: continuousClock.now)
                    >= progressPresentationPolicy.revealDelay else {
            return
        }
        progressRevealTask?.cancel()
        progressRevealTask = nil
        progressVisibleAt = continuousClock.now
        isPreparationProgressVisible = true
        let currentProgress: Double
        if case .preparing(_, let progress) = preparationState {
            currentProgress = progress
        } else {
            currentProgress = 0
        }
        preparationState = .preparing(option: option, progress: currentProgress)
        #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
        TAPDiagnostics.sharePackaging.info(
            "tap_share_activity_wait_feedback_revealed kind=\(self.subject?.mediaKind.diagnosticValue ?? "none", privacy: .public) threshold=over50ms phase=controllerConstruction"
        )
        #endif
    }

    private func scheduleActivityAppearanceWatchdog(expectedArtifactID: UUID) {
        activityAppearanceWatchdogTask?.cancel()
        activityAppearanceWatchdogTask = Task { @MainActor [weak self] in
            do {
                guard let self else {
                    return
                }
                try await Task.sleep(
                    for: self.activityPresentationPolicy.appearanceTimeout
                )
            } catch {
                return
            }
            guard let self,
                  self.activitySheetArtifactID == expectedArtifactID,
                  self.activeActivityLease?.id == expectedArtifactID,
                  !self.activitySheetHasAppeared,
                  self.activityPresentation?.id == expectedArtifactID else {
                return
            }
            self.activityAppearanceWatchdogTask = nil
            #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
            TAPDiagnostics.sharePackaging.info(
                "tap_share_activity_never_appeared kind=\(self.activeActivityLease?.kind.rawValue ?? "none", privacy: .public) outcome=dismantleRequested"
            )
            #endif
            self.activityPresentation = nil
            self.scheduleActivityDismantleWatchdog(
                expectedArtifactID: expectedArtifactID
            )
        }
    }

    private func scheduleActivityDismantleWatchdog(expectedArtifactID: UUID) {
        activityDismantleWatchdogTask?.cancel()
        activityDismantleWatchdogTask = Task { @MainActor [weak self] in
            do {
                guard let self else {
                    return
                }
                try await Task.sleep(
                    for: self.activityPresentationPolicy.dismantleTimeout
                )
            } catch {
                return
            }
            guard let self,
                  self.activitySheetArtifactID == expectedArtifactID,
                  self.activeActivityLease?.id == expectedArtifactID,
                  !self.activitySheetHasAppeared else {
                return
            }
            self.activityDismantleWatchdogTask = nil
            #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
            TAPDiagnostics.sharePackaging.error(
                "tap_share_activity_dismantle_timeout kind=\(self.activeActivityLease?.kind.rawValue ?? "none", privacy: .public) outcome=forcedStateRelease"
            )
            #endif
            self.endActivityPresentationAfterSystemDismissal(
                expectedArtifactID: expectedArtifactID
            )
        }
    }

    private func discardPendingHandoff() {
        let pendingPresentation = pendingHandoffPresentation
        pendingHandoffPresentation = nil
        pendingPresentation?.artifact.removeTemporaryDirectory()
        if !hasActiveActivityPresentation, !isPreparing {
            preparationState = .idle
        }
    }

    private func resetPresentationState() {
        activityAppearanceWatchdogTask?.cancel()
        activityAppearanceWatchdogTask = nil
        activityDismantleWatchdogTask?.cancel()
        activityDismantleWatchdogTask = nil
        activitySheetHasAppeared = false
        presentationID = nil
        preparationID = nil
        preparationStartedAt = nil
        certificationRefreshID = nil
        subject = nil
        originalResource = nil
        record = nil
        certificationState = nil
        preparationState = .idle
        isPopoverPresented = false
        popoverHasAppeared = false
        pendingHandoffPresentation = nil
        activityPresentation = nil
        activeActivityLease = nil
        hasDeferredCertificationRefresh = false
        resetProgressPresentation()
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
