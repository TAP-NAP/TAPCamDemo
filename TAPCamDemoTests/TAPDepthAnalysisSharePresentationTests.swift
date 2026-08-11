//
//  TAPDepthAnalysisSharePresentationTests.swift
//  TAPCamDemoTests
//

import Foundation
import Testing
@testable import TAPCamDemo

@Suite("Depth Analysis share presentation")
struct TAPDepthAnalysisSharePresentationTests {
    @Test func builtAppExportsTapnapCapturePackageTypeWithoutDocumentImportRoute() throws {
        let declarations = try #require(
            Bundle.main.object(forInfoDictionaryKey: "UTExportedTypeDeclarations")
                as? [[String: Any]]
        )
        let declaration = try #require(declarations.first(where: { value in
            value["UTTypeIdentifier"] as? String == "net.tapnap.capture-package"
        }))
        let tags = try #require(declaration["UTTypeTagSpecification"] as? [String: Any])

        #expect(
            declaration["UTTypeConformsTo"] as? [String]
                == ["public.zip-archive"]
        )
        #expect(tags["public.filename-extension"] as? [String] == ["tapnap"])
        #expect(
            tags["public.mime-type"] as? [String]
                == ["application/vnd.tapnap.capture-package+zip"]
        )
        #expect(Bundle.main.object(forInfoDictionaryKey: "CFBundleDocumentTypes") == nil)
    }

    @Test func certificationPolicyMapsEveryPersistedStatusToThreeProductStates() {
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        let cases: [(TAPPendingCaptureStatus, DepthAnalysisShareCertificationState)] = [
            (.pending, .retryPending),
            (.waitingNetwork, .retryPending),
            (.signing, .retryPending),
            (.signed, .verified),
            (.exporting, .verified),
            (.exported, .verified),
            (.failedRetryable, .retryPending),
            (.failedTerminal, .failed)
        ]

        for (status, expected) in cases {
            let record = TAPCamDemoTestFixtures.samplePendingRecord(
                captureID: "status-\(status.rawValue)",
                capturedAt: now,
                status: status,
                signedHEICFilename: nil,
                assetLocalIdentifier: status == .exported ? "asset-exported" : nil
            )
            #expect(DepthAnalysisShareCertificationPolicy.state(for: record) == expected)
        }
    }

    @Test func durableSignatureEvidenceWinsOverRetryAndTerminalStates() {
        let now = Date(timeIntervalSince1970: 1_750_000_000)

        for status in [TAPPendingCaptureStatus.failedRetryable, .failedTerminal, .waitingNetwork] {
            let record = TAPCamDemoTestFixtures.samplePendingRecord(
                captureID: "signed-\(status.rawValue)",
                capturedAt: now,
                status: status,
                signedHEICFilename: "signed.heic"
            )
            #expect(DepthAnalysisShareCertificationPolicy.state(for: record) == .verified)
        }
    }

    @Test func videoCertificationPolicyMapsUnsignedRecordsToRetryOrFailure() {
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        let cases: [(TAPPendingCaptureStatus, DepthAnalysisShareCertificationState)] = [
            (.pending, .retryPending),
            (.waitingNetwork, .retryPending),
            (.signing, .retryPending),
            (.signed, .failed),
            (.exporting, .failed),
            (.exported, .failed),
            (.failedRetryable, .retryPending),
            (.failedTerminal, .failed)
        ]

        for (status, expected) in cases {
            let record = TAPCamDemoTestFixtures.samplePendingVideoRecord(
                captureID: "video-status-\(status.rawValue)",
                capturedAt: now,
                status: status,
                videoArtifactState: .unsigned,
                assetLocalIdentifier: status == .exported ? "video-exported" : nil
            )

            #expect(
                DepthAnalysisShareCertificationPolicy.state(
                    for: record,
                    mediaKind: .video
                ) == expected
            )
        }
    }

    @Test func persistedSignedVideoEvidenceWinsOverRetryAndTerminalStates() {
        let now = Date(timeIntervalSince1970: 1_750_000_000)

        for status in [
            TAPPendingCaptureStatus.pending,
            .waitingNetwork,
            .failedRetryable,
            .failedTerminal
        ] {
            let record = TAPCamDemoTestFixtures.samplePendingVideoRecord(
                captureID: "signed-video-\(status.rawValue)",
                capturedAt: now,
                status: status,
                videoArtifactState: .signed
            )

            #expect(
                DepthAnalysisShareCertificationPolicy.state(
                    for: record,
                    mediaKind: .video
                ) == .verified
            )
        }
    }

    @Test func videoShareSubjectMapsPendingOwnedAndPhotosIdentities() {
        let pending = DepthAnalysisShareSubject(
            videoSource: .pendingCapture("pending-video"),
            itemID: "pending-item"
        )
        #expect(pending.id == "pending-item")
        #expect(pending.mediaID == .tapCapture("pending-video"))
        #expect(pending.captureID == "pending-video")
        #expect(pending.assetID == nil)
        #expect(pending.mediaKind == .video)
        #expect(!pending.hasIdentityConflict)

        let owned = DepthAnalysisShareSubject(
            videoSource: .ownedCapture(
                captureID: "owned-video",
                assetLocalIdentifier: "owned-asset"
            ),
            itemID: "owned-item"
        )
        #expect(owned.id == "owned-item")
        #expect(owned.mediaID == .tapCapture("owned-video"))
        #expect(owned.captureID == "owned-video")
        #expect(owned.assetID == "owned-asset")
        #expect(owned.mediaKind == .video)
        #expect(!owned.hasIdentityConflict)

        let photos = DepthAnalysisShareSubject(
            videoSource: .photosAsset("photos-video"),
            itemID: "photos-item"
        )
        #expect(photos.id == "photos-item")
        #expect(photos.mediaID == .photosAsset("photos-video"))
        #expect(photos.captureID == nil)
        #expect(photos.assetID == "photos-video")
        #expect(photos.mediaKind == .video)
        #expect(!photos.hasIdentityConflict)
    }

    @Test func missingOrNonPhotoRecordIsFailed() {
        #expect(DepthAnalysisShareCertificationPolicy.state(for: nil) == .failed)

        let now = Date(timeIntervalSince1970: 1_750_000_000)
        let videoRecord = TAPPendingCaptureRecord(
            captureID: "video-record",
            packageID: UUID(),
            capturedAt: now,
            createdAt: now,
            updatedAt: now,
            status: .exported,
            artifactKind: .tapVideo,
            videoArtifactFilename: "artifact.mp4",
            videoArtifactState: .signed,
            thumbnailFilename: nil,
            assetLocalIdentifier: "video-asset",
            failureReason: nil,
            retryCount: 0,
            location: nil
        )
        #expect(DepthAnalysisShareCertificationPolicy.state(for: videoRecord) == .failed)
    }

    @Test func recordResolverUsesCaptureIdentityAndRequiresMatchingAsset() async throws {
        let record = TAPCamDemoTestFixtures.samplePendingRecord(
            captureID: "owned-capture",
            capturedAt: Date(timeIntervalSince1970: 1_750_000_000),
            status: .exported,
            signedHEICFilename: "signed.heic",
            assetLocalIdentifier: "owned-asset"
        )
        let resolver = DepthAnalysisShareRecordResolver(
            captureLoader: { _ in record },
            assetLoader: { _ in nil }
        )

        let resolved = try await resolver.record(for: DepthAnalysisShareSubject(
            id: "owned",
            mediaID: .tapCapture("owned-capture"),
            captureID: "owned-capture",
            assetID: "owned-asset"
        ))
        #expect(resolved?.captureID == record.captureID)

        await #expect(throws: DepthAnalysisShareRecordResolutionError.identityConflict) {
            _ = try await resolver.record(for: DepthAnalysisShareSubject(
                id: "mismatch",
                mediaID: .tapCapture("owned-capture"),
                captureID: "owned-capture",
                assetID: "another-asset"
            ))
        }

        let wrongRecord = TAPCamDemoTestFixtures.samplePendingRecord(
            captureID: "different-capture",
            capturedAt: record.capturedAt,
            status: .exported,
            assetLocalIdentifier: "owned-asset"
        )
        let wrongCaptureResolver = DepthAnalysisShareRecordResolver(
            captureLoader: { _ in wrongRecord },
            assetLoader: { _ in nil }
        )
        await #expect(throws: DepthAnalysisShareRecordResolutionError.identityConflict) {
            _ = try await wrongCaptureResolver.record(for: DepthAnalysisShareSubject(
                id: "wrong-capture",
                mediaID: .tapCapture("owned-capture"),
                captureID: "owned-capture",
                assetID: "owned-asset"
            ))
        }
    }

    @Test func captureIdentityFailureNeverFallsBackToAssetLookup() async {
        let resolver = DepthAnalysisShareRecordResolver(
            captureLoader: { _ in throw TestError.missingCapture },
            assetLoader: { _ in throw TestError.unexpectedAssetLookup }
        )

        await #expect(throws: TestError.missingCapture) {
            _ = try await resolver.record(for: DepthAnalysisShareSubject(
                id: "owned-missing",
                mediaID: .tapCapture("owned-capture"),
                captureID: "owned-capture",
                assetID: "owned-asset"
            ))
        }
    }

    @Test func recordResolverFallsBackToAssetForLegacyEntry() async throws {
        let record = TAPCamDemoTestFixtures.samplePendingRecord(
            captureID: "legacy-capture",
            capturedAt: Date(timeIntervalSince1970: 1_750_000_000),
            status: .exported,
            signedHEICFilename: nil,
            assetLocalIdentifier: "legacy-asset"
        )
        let resolver = DepthAnalysisShareRecordResolver(
            captureLoader: { _ in throw TestError.missingCapture },
            assetLoader: { assetID in
                assetID == "legacy-asset" ? record : nil
            }
        )

        let resolved = try await resolver.record(for: DepthAnalysisShareSubject(
            id: "legacy",
            mediaID: .photosAsset("legacy-asset"),
            captureID: nil,
            assetID: "legacy-asset"
        ))
        #expect(resolved?.captureID == "legacy-capture")
    }

    @MainActor
    @Test func libraryChangeRefreshCanPromoteNeedsRetryToVerifiedWithoutValidation() async {
        let pendingRecord = TAPCamDemoTestFixtures.samplePendingRecord(
            captureID: "refresh-capture",
            capturedAt: Date(timeIntervalSince1970: 1_750_000_000),
            status: .waitingNetwork,
            signedHEICFilename: nil
        )
        let signedRecord = TAPCamDemoTestFixtures.samplePendingRecord(
            captureID: "refresh-capture",
            capturedAt: Date(timeIntervalSince1970: 1_750_000_000),
            status: .signed,
            signedHEICFilename: "signed.heic"
        )
        let box = ShareRecordBox(pendingRecord)
        let resolver = DepthAnalysisShareRecordResolver(
            captureLoader: { _ in await box.current() },
            assetLoader: { _ in nil }
        )
        let model = DepthAnalysisShareSheetModel(
            subject: DepthAnalysisShareSubject(
                id: "refresh",
                mediaID: .tapCapture("refresh-capture"),
                captureID: "refresh-capture",
                assetID: nil
            ),
            recordResolver: resolver
        )

        await model.refreshCertification()
        #expect(model.certificationState == .retryPending)

        await box.replace(with: signedRecord)
        model.scheduleCertificationRefresh()
        for _ in 0..<50 where model.certificationState != .verified {
            await Task.yield()
        }

        #expect(model.certificationState == .verified)
    }

    @MainActor
    @Test func certificationRefreshKeepsActiveSystemShareAttachmentUntilDismissal() async throws {
        let capturedAt = Date(timeIntervalSince1970: 1_750_000_000)
        let pendingRecord = TAPCamDemoTestFixtures.samplePendingRecord(
            captureID: "active-refresh",
            capturedAt: capturedAt,
            status: .waitingNetwork,
            signedHEICFilename: nil
        )
        let signedRecord = TAPCamDemoTestFixtures.samplePendingRecord(
            captureID: "active-refresh",
            capturedAt: capturedAt,
            status: .signed,
            signedHEICFilename: "signed.heic"
        )
        let recordBox = ShareRecordBox(pendingRecord)
        let resolver = DepthAnalysisShareRecordResolver(
            captureLoader: { _ in await recordBox.current() },
            assetLoader: { _ in nil }
        )
        let artifactDirectoryURL = try TAPCamDemoTestFixtures.makeTemporaryDirectory()
        let artifactURL = artifactDirectoryURL.appendingPathComponent("TAPNAP-Photo.heic")
        try Data("active-unsigned-image".utf8).write(to: artifactURL)
        let artifact = TAPNAPShareArtifact(
            id: UUID(),
            kind: .image,
            fileURL: artifactURL,
            temporaryDirectoryURL: artifactDirectoryURL,
            warnings: []
        )
        let preparer = ShareArtifactPreparerStub(
            packageOperation: { _ in
                throw TestError.unexpectedPackagePreparation
            },
            imageOperation: { _, requiresSignedPhoto in
                guard !requiresSignedPhoto else {
                    throw TestError.unexpectedSignedImagePolicy
                }
                return artifact
            }
        )
        let model = DepthAnalysisShareSheetModel(
            subject: DepthAnalysisShareSubject(
                id: "active-refresh",
                mediaID: .tapCapture(pendingRecord.captureID),
                captureID: pendingRecord.captureID,
                assetID: nil
            ),
            recordResolver: resolver,
            artifactPreparer: preparer
        )

        await model.refreshCertification()
        #expect(model.certificationState == .retryPending)
        model.prepare(.image)
        for _ in 0..<100 where model.activityPayload == nil {
            await Task.yield()
        }
        #expect(model.activityPayload != nil)
        #expect(FileManager.default.fileExists(atPath: artifactURL.path))

        await recordBox.replace(with: signedRecord)
        await model.refreshCertification()

        #expect(model.certificationState == .verified)
        #expect(model.activityPayload != nil)
        #expect(FileManager.default.fileExists(atPath: artifactURL.path))

        // Item-driven sheets clear their binding before running onDismiss.
        model.activityPayload = nil
        model.finishActivityPresentation()
        #expect(model.activityPayload == nil)
        #expect(!FileManager.default.fileExists(atPath: artifactDirectoryURL.path))
    }

    @MainActor
    @Test func preparationDisablesRepeatSelectionWithoutDimmingAvailableRows() async {
        let record = TAPCamDemoTestFixtures.samplePendingRecord(
            captureID: "stable-row",
            capturedAt: Date(timeIntervalSince1970: 1_750_000_000),
            status: .signed,
            signedHEICFilename: "signed.heic"
        )
        let resolver = DepthAnalysisShareRecordResolver(
            captureLoader: { _ in record },
            assetLoader: { _ in nil }
        )
        let preparer = ShareArtifactPreparerStub(
            packageOperation: { _ in
                try await Task.sleep(nanoseconds: 30_000_000_000)
                throw CancellationError()
            },
            imageOperation: { _, _ in
                throw TestError.unexpectedSignedImagePolicy
            }
        )
        let model = DepthAnalysisShareSheetModel(
            subject: DepthAnalysisShareSubject(
                id: "stable-row",
                mediaID: .tapCapture(record.captureID),
                captureID: record.captureID,
                assetID: nil
            ),
            recordResolver: resolver,
            artifactPreparer: preparer
        )

        await model.refreshCertification()
        #expect(model.isPackageAvailable)
        #expect(model.canPreparePackage)

        model.prepare(.tapnapPackage)

        #expect(model.isPackageAvailable)
        #expect(!model.canPreparePackage)
        guard case .preparing(let option, let progress) = model.preparationState else {
            Issue.record("Expected a stable determinate preparation state")
            return
        }
        #expect(option == .tapnapPackage)
        #expect(progress == 0)
        model.cancelPreparation()
    }

    @MainActor
    @Test func packageProgressPublishesThroughTheMainActorWhilePreparationContinues() async {
        let record = TAPCamDemoTestFixtures.samplePendingRecord(
            captureID: "progress-bridge",
            capturedAt: Date(timeIntervalSince1970: 1_750_000_000),
            status: .signed,
            signedHEICFilename: "signed.heic"
        )
        let resolver = DepthAnalysisShareRecordResolver(
            captureLoader: { _ in record },
            assetLoader: { _ in nil }
        )
        let model = DepthAnalysisShareSheetModel(
            subject: DepthAnalysisShareSubject(
                id: "progress-bridge",
                mediaID: .tapCapture(record.captureID),
                captureID: record.captureID,
                assetID: nil
            ),
            recordResolver: resolver,
            artifactPreparer: ProgressReportingShareArtifactPreparerStub(
                packageProgress: 0.84
            )
        )

        await model.refreshCertification()
        model.prepare(.tapnapPackage)

        var publishedProgress: Double?
        for _ in 0..<100 {
            if case .preparing(let option, let progress) = model.preparationState,
               option == .tapnapPackage,
               progress >= 0.84 {
                publishedProgress = progress
                break
            }
            await Task.yield()
        }

        #expect(publishedProgress == 0.84)
        model.cancelPreparation()
    }

    @MainActor
    @Test func fastPackageCompletionNeverRevealsTransientProgress() async throws {
        let record = TAPCamDemoTestFixtures.samplePendingRecord(
            captureID: "fast-progress",
            capturedAt: Date(timeIntervalSince1970: 1_750_000_000),
            status: .signed,
            signedHEICFilename: "signed.heic"
        )
        let resolver = DepthAnalysisShareRecordResolver(
            captureLoader: { _ in record },
            assetLoader: { _ in nil }
        )
        let artifactDirectoryURL = try TAPCamDemoTestFixtures.makeTemporaryDirectory()
        let artifactURL = artifactDirectoryURL.appendingPathComponent("TAPNAP-Capture.tapnap")
        try Data("fast-package".utf8).write(to: artifactURL)
        let artifact = TAPNAPShareArtifact(
            id: UUID(),
            kind: .tapnapPackage,
            fileURL: artifactURL,
            temporaryDirectoryURL: artifactDirectoryURL,
            warnings: []
        )
        let preparer = ShareArtifactPreparerStub(
            packageOperation: { _ in artifact },
            imageOperation: { _, _ in
                throw TestError.unexpectedSignedImagePolicy
            }
        )
        let model = DepthAnalysisShareSheetModel(
            subject: DepthAnalysisShareSubject(
                id: "fast-progress",
                mediaID: .tapCapture(record.captureID),
                captureID: record.captureID,
                assetID: nil
            ),
            recordResolver: resolver,
            artifactPreparer: preparer,
            progressPresentationPolicy: DepthAnalysisShareProgressPresentationPolicy(
                revealDelay: .seconds(1),
                minimumVisibleDuration: .seconds(1)
            )
        )

        await model.refreshCertification()
        model.prepare(.tapnapPackage)
        for _ in 0..<100 where model.activityPayload == nil {
            await Task.yield()
        }

        #expect(model.activityPayload != nil)
        #expect(!model.isPreparationProgressVisible)
        model.finishActivityPresentation()
        #expect(!FileManager.default.fileExists(atPath: artifactDirectoryURL.path))
    }

    @MainActor
    @Test func visibleProgressReachesCompletionAndRemainsStableBeforeSystemShare() async throws {
        let record = TAPCamDemoTestFixtures.samplePendingRecord(
            captureID: "stable-progress",
            capturedAt: Date(timeIntervalSince1970: 1_750_000_000),
            status: .signed,
            signedHEICFilename: "signed.heic"
        )
        let resolver = DepthAnalysisShareRecordResolver(
            captureLoader: { _ in record },
            assetLoader: { _ in nil }
        )
        let gate = ShareArtifactReturnGate()
        let artifactDirectoryURL = try TAPCamDemoTestFixtures.makeTemporaryDirectory()
        let artifactURL = artifactDirectoryURL.appendingPathComponent("TAPNAP-Capture.tapnap")
        try Data("stable-package".utf8).write(to: artifactURL)
        let artifact = TAPNAPShareArtifact(
            id: UUID(),
            kind: .tapnapPackage,
            fileURL: artifactURL,
            temporaryDirectoryURL: artifactDirectoryURL,
            warnings: []
        )
        let preparer = ShareArtifactPreparerStub(
            packageOperation: { _ in
                await gate.signalArtifactReadyAndWaitForRelease()
                return artifact
            },
            imageOperation: { _, _ in
                throw TestError.unexpectedSignedImagePolicy
            }
        )
        let model = DepthAnalysisShareSheetModel(
            subject: DepthAnalysisShareSubject(
                id: "stable-progress",
                mediaID: .tapCapture(record.captureID),
                captureID: record.captureID,
                assetID: nil
            ),
            recordResolver: resolver,
            artifactPreparer: preparer,
            progressPresentationPolicy: DepthAnalysisShareProgressPresentationPolicy(
                revealDelay: .milliseconds(10),
                minimumVisibleDuration: .milliseconds(200)
            )
        )

        await model.refreshCertification()
        model.prepare(.tapnapPackage)
        await gate.waitUntilArtifactIsReady()
        #expect(!model.isPreparationProgressVisible)

        for _ in 0..<20 where !model.isPreparationProgressVisible {
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(model.isPreparationProgressVisible)

        await gate.releaseArtifact()
        try await Task.sleep(for: .milliseconds(40))
        #expect(model.activityPayload == nil)
        guard case .preparing(let option, let progress) = model.preparationState else {
            Issue.record("Expected progress to remain visible before presenting the system share sheet")
            return
        }
        #expect(option == .tapnapPackage)
        #expect(progress == 1)

        try await Task.sleep(for: .milliseconds(220))
        #expect(model.activityPayload != nil)
        #expect(!model.isPreparationProgressVisible)
        model.finishActivityPresentation()
        #expect(!FileManager.default.fileExists(atPath: artifactDirectoryURL.path))
    }

    @MainActor
    @Test func activityDismissalRemovesOnDemandArtifactInsteadOfCachingIt() async throws {
        let record = TAPCamDemoTestFixtures.samplePendingRecord(
            captureID: "activity-cleanup",
            capturedAt: Date(timeIntervalSince1970: 1_750_000_000),
            status: .signed,
            signedHEICFilename: "signed.heic"
        )
        let resolver = DepthAnalysisShareRecordResolver(
            captureLoader: { _ in record },
            assetLoader: { _ in nil }
        )
        let artifactDirectoryURL = try TAPCamDemoTestFixtures.makeTemporaryDirectory()
        let artifactURL = artifactDirectoryURL.appendingPathComponent("TAPNAP-Capture.tapnap")
        try Data("opaque-package".utf8).write(to: artifactURL)
        let artifact = TAPNAPShareArtifact(
            id: UUID(),
            kind: .tapnapPackage,
            fileURL: artifactURL,
            temporaryDirectoryURL: artifactDirectoryURL,
            warnings: []
        )
        let preparer = ShareArtifactPreparerStub(
            packageOperation: { _ in artifact },
            imageOperation: { _, _ in
                throw TestError.unexpectedSignedImagePolicy
            }
        )
        let model = DepthAnalysisShareSheetModel(
            subject: DepthAnalysisShareSubject(
                id: "activity-cleanup",
                mediaID: .tapCapture(record.captureID),
                captureID: record.captureID,
                assetID: nil
            ),
            recordResolver: resolver,
            artifactPreparer: preparer
        )

        await model.refreshCertification()
        model.prepare(.tapnapPackage)
        for _ in 0..<100 where model.activityPayload == nil {
            await Task.yield()
        }
        #expect(model.activityPayload != nil)
        #expect(FileManager.default.fileExists(atPath: artifactDirectoryURL.path))

        model.finishActivityPresentation()

        #expect(model.activityPayload == nil)
        #expect(!FileManager.default.fileExists(atPath: artifactDirectoryURL.path))
        guard case .idle = model.preparationState else {
            Issue.record("Expected dismissal to reset preparation state")
            return
        }
    }

    @Test(.enabled(if: TAPCamDemoTestSourceInspection.isSourceTreeAvailable, "Source tree is unavailable on this runtime."))
    func tapnapGenerationContractIsOnDemandTemporaryAndVisuallyStable() throws {
        let sharePath = "TAPCamDemo/DepthAnalysis/DepthAnalysisShareSheet.swift"
        let builderPath = "TAPCamDemo/DepthAnalysis/TAPNAPShareArtifactBuilder.swift"
        let shareSource = try TAPCamDemoTestSourceInspection.source(relativePath: sharePath)
        let builderSource = try TAPCamDemoTestSourceInspection.source(relativePath: builderPath)
        let readme = try TAPCamDemoTestSourceInspection.source(
            relativePath: "TAPCamDemo/DepthAnalysis/README.md"
        )

        #expect(shareSource.contains("isAvailable: viewModel.isPackageAvailable"))
        #expect(shareSource.contains("allowsSelection: viewModel.canPreparePackage"))
        #expect(shareSource.contains(".buttonStyle(StableShareOptionButtonStyle())"))
        #expect(shareSource.contains(".opacity(isAvailable ? 1 : 0.52)"))
        #expect(!shareSource.contains(".opacity(isEnabled ? 1 : 0.52)"))
        #expect(shareSource.contains("progress: 0"))
        #expect(shareSource.contains("ProgressView(value: progress)"))
        #expect(!shareSource.contains("ProgressView()"))
        #expect(shareSource.contains("revealDelay: .milliseconds(50)"))
        #expect(shareSource.contains("minimumVisibleDuration: .milliseconds(200)"))
        #expect(shareSource.contains("if viewModel.isPreparationProgressVisible"))
        #expect(shareSource.contains(".safeAreaInset(edge: .bottom, spacing: 0)"))
        #expect(shareSource.contains("pinnedPreparationFooter"))
        #expect(shareSource.contains("tap.share.preparation.footer"))
        let pinnedInset = try #require(
            shareSource.range(of: ".safeAreaInset(edge: .bottom, spacing: 0)")
        )
        #expect(!shareSource[..<pinnedInset.lowerBound].contains("preparationStatus"))
        #expect(shareSource.contains("finishActivityPresentation()"))

        #expect(builderSource.contains("Background pre-generation and persistent package caching are prohibited."))
        #expect(builderSource.contains("FileManager.default.temporaryDirectory"))
        #expect(!builderSource.contains("cachesDirectory"))
        #expect(readme.contains("must never pre-generate a package"))
        #expect(readme.contains("must remove that directory"))

        let productionPaths = try TAPCamDemoTestSourceInspection.swiftSourceRelativePathsRecursively(
            under: "TAPCamDemo"
        )
        let packageCallSites = try productionPaths.filter { path in
            guard path != builderPath else {
                return false
            }
            return try TAPCamDemoTestSourceInspection.source(relativePath: path)
                .contains(".prepareTapnapPackage(")
        }
        #expect(packageCallSites == [sharePath])
    }

    @MainActor
    @Test func cancellationCleansArtifactReturnedByCancellationIgnoringPreparer() async throws {
        let record = TAPCamDemoTestFixtures.samplePendingRecord(
            captureID: "cancel-after-build",
            capturedAt: Date(timeIntervalSince1970: 1_750_000_000),
            status: .waitingNetwork,
            signedHEICFilename: nil
        )
        let resolver = DepthAnalysisShareRecordResolver(
            captureLoader: { _ in record },
            assetLoader: { _ in nil }
        )
        let gate = ShareArtifactReturnGate()
        let artifactDirectoryURL = try TAPCamDemoTestFixtures.makeTemporaryDirectory()
        let artifactURL = artifactDirectoryURL.appendingPathComponent("TAPNAP-Photo.heic")
        try Data("opaque-share".utf8).write(to: artifactURL)
        let artifact = TAPNAPShareArtifact(
            id: UUID(),
            kind: .image,
            fileURL: artifactURL,
            temporaryDirectoryURL: artifactDirectoryURL,
            warnings: []
        )
        let preparer = ShareArtifactPreparerStub(
            packageOperation: { _ in
                throw TestError.unexpectedPackagePreparation
            },
            imageOperation: { _, requiresSignedPhoto in
                guard !requiresSignedPhoto else {
                    throw TestError.unexpectedSignedImagePolicy
                }
                await gate.signalArtifactReadyAndWaitForRelease()
                return artifact
            }
        )
        let model = DepthAnalysisShareSheetModel(
            subject: DepthAnalysisShareSubject(
                id: "cancel-after-build",
                mediaID: .tapCapture(record.captureID),
                captureID: record.captureID,
                assetID: nil
            ),
            recordResolver: resolver,
            artifactPreparer: preparer
        )

        await model.refreshCertification()
        model.prepare(.image)
        await gate.waitUntilArtifactIsReady()
        model.cancelPreparation()
        await gate.releaseArtifact()

        for _ in 0..<100 where FileManager.default.fileExists(atPath: artifactDirectoryURL.path) {
            await Task.yield()
        }
        #expect(!FileManager.default.fileExists(atPath: artifactDirectoryURL.path))
    }

    private enum TestError: Error, Equatable {
        case missingCapture
        case unexpectedAssetLookup
        case unexpectedPackagePreparation
        case unexpectedSignedImagePolicy
    }
}

private actor ShareRecordBox {
    private var record: TAPPendingCaptureRecord

    init(_ record: TAPPendingCaptureRecord) {
        self.record = record
    }

    func current() -> TAPPendingCaptureRecord {
        record
    }

    func replace(with record: TAPPendingCaptureRecord) {
        self.record = record
    }
}

private actor ShareArtifactReturnGate {
    private var artifactIsReady = false
    private var readyWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseContinuation: CheckedContinuation<Void, Never>?

    func signalArtifactReadyAndWaitForRelease() async {
        artifactIsReady = true
        let waiters = readyWaiters
        readyWaiters.removeAll()
        waiters.forEach { $0.resume() }
        await withCheckedContinuation { continuation in
            releaseContinuation = continuation
        }
    }

    func waitUntilArtifactIsReady() async {
        guard !artifactIsReady else {
            return
        }
        await withCheckedContinuation { continuation in
            readyWaiters.append(continuation)
        }
    }

    func releaseArtifact() {
        releaseContinuation?.resume()
        releaseContinuation = nil
    }
}

private nonisolated struct ShareArtifactPreparerStub: DepthAnalysisShareArtifactPreparing {
    typealias PackageOperation = @Sendable (
        TAPNAPShareResourceRequest
    ) async throws -> TAPNAPShareArtifact
    typealias ImageOperation = @Sendable (
        TAPNAPShareResourceRequest,
        Bool
    ) async throws -> TAPNAPShareArtifact

    let packageOperation: PackageOperation
    let imageOperation: ImageOperation

    func preparePackage(
        request: TAPNAPShareResourceRequest,
        progress: @escaping TAPNAPShareArtifactBuilder.ProgressHandler
    ) async throws -> TAPNAPShareArtifact {
        try await packageOperation(request)
    }

    func prepareImage(
        request: TAPNAPShareResourceRequest,
        requiresSignedPhoto: Bool,
        progress: @escaping TAPNAPShareArtifactBuilder.ProgressHandler
    ) async throws -> TAPNAPShareArtifact {
        try await imageOperation(request, requiresSignedPhoto)
    }
}

private nonisolated struct ProgressReportingShareArtifactPreparerStub:
    DepthAnalysisShareArtifactPreparing {
    let packageProgress: Double

    func preparePackage(
        request: TAPNAPShareResourceRequest,
        progress: @escaping TAPNAPShareArtifactBuilder.ProgressHandler
    ) async throws -> TAPNAPShareArtifact {
        progress(packageProgress)
        try await Task.sleep(nanoseconds: 30_000_000_000)
        throw CancellationError()
    }

    func prepareImage(
        request: TAPNAPShareResourceRequest,
        requiresSignedPhoto: Bool,
        progress: @escaping TAPNAPShareArtifactBuilder.ProgressHandler
    ) async throws -> TAPNAPShareArtifact {
        throw CancellationError()
    }
}
