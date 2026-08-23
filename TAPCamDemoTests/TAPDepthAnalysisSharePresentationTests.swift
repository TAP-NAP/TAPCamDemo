//
//  TAPDepthAnalysisSharePresentationTests.swift
//  TAPCamDemoTests
//

import Foundation
import SwiftUI
import Testing
import UIKit
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
                == [
                    "public.zip-archive",
                    "public.data",
                    "public.content"
                ]
        )
        #expect(tags["public.filename-extension"] as? [String] == ["tapnap"])
        #expect(
            tags["public.mime-type"] as? [String]
                == ["application/vnd.tapnap.capture-package+zip"]
        )
        #expect(Bundle.main.object(forInfoDictionaryKey: "CFBundleDocumentTypes") == nil)
    }

    @Test func pendingPhotoQueueDispositionSeparatesUnsignedRetryFromSignedValidation() {
        let now = Date(timeIntervalSince1970: 1_750_000_000)

        for status in [
            TAPPendingCaptureStatus.pending,
            .waitingNetwork,
            .signing,
            .failedRetryable
        ] {
            let record = TAPCamDemoTestFixtures.samplePendingRecord(
                captureID: "unsigned-photo-\(status.rawValue)",
                capturedAt: now,
                status: status,
                signedPhotoFilename: nil
            )
            #expect(
                TAPPendingPhotoSharePolicy.disposition(
                    for: record,
                    selectedSignedPhoto: false
                ) == .needsRetry
            )
        }

        let signedRecord = TAPCamDemoTestFixtures.samplePendingRecord(
            captureID: "signed-photo",
            capturedAt: now,
            status: .failedTerminal,
            signedPhotoFilename: "signed.heic"
        )
        #expect(
            TAPPendingPhotoSharePolicy.disposition(
                for: signedRecord,
                selectedSignedPhoto: true
            ) == .validateSignedOriginal
        )
        #expect(
            TAPPendingPhotoSharePolicy.disposition(
                for: signedRecord,
                selectedSignedPhoto: false
            ) == .failed
        )
    }

    @Test func pendingVideoQueueDispositionSeparatesUnsignedRetryFromSignedValidation() {
        let now = Date(timeIntervalSince1970: 1_750_000_000)

        for status in [
            TAPPendingCaptureStatus.pending,
            .waitingNetwork,
            .signing,
            .failedRetryable
        ] {
            let record = TAPCamDemoTestFixtures.samplePendingVideoRecord(
                captureID: "unsigned-video-\(status.rawValue)",
                capturedAt: now,
                status: status,
                videoArtifactState: .unsigned
            )
            #expect(
                TAPPendingVideoSharePolicy.disposition(
                    for: record,
                    selectedSignedVideo: false
                ) == .needsRetry
            )
        }

        let signedRecord = TAPCamDemoTestFixtures.samplePendingVideoRecord(
            captureID: "signed-video",
            capturedAt: now,
            status: .failedTerminal,
            videoArtifactState: .signed
        )
        #expect(
            TAPPendingVideoSharePolicy.disposition(
                for: signedRecord,
                selectedSignedVideo: true
            )
                == .validateSignedOriginal
        )
        #expect(
            TAPPendingVideoSharePolicy.disposition(
                for: signedRecord,
                selectedSignedVideo: false
            ) == .failed
        )
    }

    @MainActor
    @Test func shareResourceAccessCannotAcquireUntilCompleteOriginalIsReady() async throws {
        let unavailable = DepthAnalysisShareResourceAccess(
            isReady: false,
            acquire: {
                Issue.record("An unavailable Share resource must not be acquired")
                return nil
            }
        )
        if case .some = unavailable.acquire() {
            Issue.record("Unavailable resource access unexpectedly returned a lease")
        }

        let directoryURL = try TAPCamDemoTestFixtures.makeTemporaryDirectory()
        let photoURL = directoryURL.appendingPathComponent("primary-photo.heic")
        try Data("opaque-ready-photo".utf8).write(to: photoURL)
        let lease = try TAPPhotoOriginalResourceLease(
            mediaID: .photosAsset("ready-asset"),
            origin: .photosAsset(assetID: "ready-asset"),
            photoURL: photoURL,
            pairedVideoURL: nil,
            photoFileExtension: "heic",
            photoMediaType: "public.heic",
            fileContainerHint: .heic,
            expectsPairedVideo: false,
            ownedTemporaryDirectoryURL: directoryURL
        )
        let available = DepthAnalysisShareResourceAccess(
            isReady: true,
            acquire: { .photo(lease.retaining()) }
        )

        let acquired = try #require(available.acquire())
        guard case .photo(let acquiredLease) = acquired else {
            Issue.record("Expected the frozen ready photo lease")
            return
        }
        #expect(acquiredLease.photoURL == photoURL)
    }

    @Test(.enabled(if: TAPCamDemoTestSourceInspection.isSourceTreeAvailable, "Source tree is unavailable on this runtime."))
    func shareLocalIntegrityGateHasNoBackendVerificationDependency() throws {
        let shareIntegritySource = try TAPCamDemoTestSourceInspection.source(
            relativePath: "TAPCamDemo/DepthAnalysis/DepthAnalysisShareOriginalResource.swift"
        )
        let photoIntegritySource = try TAPCamDemoTestSourceInspection.source(
            relativePath: "TAPCamDemo/DepthAnalysis/TAPPhotoOriginalResource.swift"
        )
        let videoIntegritySource = try TAPCamDemoTestSourceInspection.source(
            relativePath: "TAPCamDemo/DepthAnalysis/Playback/TAPVideoPlaybackResourceLoader.swift"
        )
        let sources = [shareIntegritySource, photoIntegritySource, videoIntegritySource]

        #expect(shareIntegritySource.contains("DepthAnalysisShareLocalIntegrityValidator"))
        #expect(photoIntegritySource.contains("TAPSignedPhotoResourceValidator"))
        #expect(videoIntegritySource.contains("validateSignedExportVideoFile"))
        for source in sources {
            #expect(!source.contains("AppAttestCaptureSignatureVerifier"))
            #expect(!source.contains("/tapcam/capture-signatures/verify"))
            #expect(!source.contains("URLSession"))
        }
    }

    @MainActor
    @Test func photosOriginalWithoutPendingRecordUsesLocalIntegrityForVerified() async throws {
        let invocationRecorder = ShareLocalIntegrityInvocationRecorder()
        let subject = DepthAnalysisShareSubject(
            id: "icloud-photo",
            mediaID: .photosAsset("icloud-asset"),
            captureID: nil,
            assetID: "icloud-asset",
            usesPendingCaptureResource: false
        )
        let resource = try Self.makePhotoResource(
            origin: .photosAsset(assetID: "icloud-asset")
        )
        let model = DepthAnalysisShareCoordinator(
            subject: subject,
            originalResource: resource,
            recordResolver: .init(
                captureLoader: { _ in throw TestError.unexpectedCaptureLookup },
                assetLoader: { _ in nil }
            ),
            localIntegrityValidator: ShareLocalIntegrityValidatorStub { resource, captureID, packageID in
                await invocationRecorder.record(
                    resource: resource,
                    expectedCaptureID: captureID,
                    expectedPackageID: packageID
                )
            }
        )

        #expect(model.isPopoverPresented)
        await model.refreshCertification()

        #expect(model.certificationState == .localIntegrityPassed)
        #expect(model.isPackageAvailable)
        #expect(model.isImageAvailable)
        #expect(await invocationRecorder.count() == 1)
        #expect(await invocationRecorder.lastExpectedCaptureID() == nil)
    }

    @MainActor
    @Test func photosShareIgnoresPendingQueueNotifications() async throws {
        let invocationRecorder = ShareLocalIntegrityInvocationRecorder()
        let subject = DepthAnalysisShareSubject(
            id: "photos-notification-isolation",
            mediaID: .photosAsset("photos-notification-isolation"),
            captureID: nil,
            assetID: "photos-notification-isolation",
            usesPendingCaptureResource: false
        )
        let model = DepthAnalysisShareCoordinator(
            subject: subject,
            originalResource: try Self.makePhotoResource(
                origin: .photosAsset(assetID: "photos-notification-isolation")
            ),
            recordResolver: .init(
                captureLoader: { _ in throw TestError.unexpectedCaptureLookup },
                assetLoader: { _ in nil }
            ),
            localIntegrityValidator: ShareLocalIntegrityValidatorStub { resource, captureID, packageID in
                await invocationRecorder.record(
                    resource: resource,
                    expectedCaptureID: captureID,
                    expectedPackageID: packageID
                )
            }
        )

        await model.refreshCertification()
        #expect(model.certificationState == .localIntegrityPassed)
        #expect(await invocationRecorder.count() == 1)

        model.scheduleCertificationRefresh(
            for: TAPLibraryPendingCaptureChange(captureID: "unrelated-pending-capture")
        )
        for _ in 0..<20 {
            await Task.yield()
        }

        #expect(model.certificationState == .localIntegrityPassed)
        #expect(await invocationRecorder.count() == 1)
    }

    @MainActor
    @Test func pendingUnsignedRetryStateDoesNotInvokeLocalValidator() async throws {
        let record = TAPCamDemoTestFixtures.samplePendingRecord(
            captureID: "pending-unsigned",
            capturedAt: Date(timeIntervalSince1970: 1_750_000_000),
            status: .waitingNetwork,
            signedPhotoFilename: nil
        )
        let invocationRecorder = ShareLocalIntegrityInvocationRecorder()
        let model = DepthAnalysisShareCoordinator(
            subject: Self.pendingPhotoSubject(captureID: record.captureID),
            originalResource: try Self.makePhotoResource(
                origin: .pendingCapture(
                    captureID: record.captureID,
                    selectedSignedPhoto: false
                )
            ),
            recordResolver: .init(
                captureLoader: { _ in record },
                assetLoader: { _ in nil }
            ),
            localIntegrityValidator: ShareLocalIntegrityValidatorStub { resource, captureID, packageID in
                await invocationRecorder.record(
                    resource: resource,
                    expectedCaptureID: captureID,
                    expectedPackageID: packageID
                )
                throw ShareLocalIntegrityStubError.unexpectedValidation
            }
        )

        await model.refreshCertification()

        #expect(model.certificationState == .retryPending)
        #expect(!model.isPackageAvailable)
        #expect(model.isImageAvailable)
        #expect(await invocationRecorder.count() == 0)
    }

    @MainActor
    @Test func pendingSignedExactLeaseMustPassLocalIntegrityBeforeVerified() async throws {
        let record = TAPCamDemoTestFixtures.samplePendingRecord(
            captureID: "pending-signed",
            capturedAt: Date(timeIntervalSince1970: 1_750_000_000),
            status: .failedTerminal,
            signedPhotoFilename: "signed.heic"
        )
        let invocationRecorder = ShareLocalIntegrityInvocationRecorder()
        let model = DepthAnalysisShareCoordinator(
            subject: Self.pendingPhotoSubject(captureID: record.captureID),
            originalResource: try Self.makePhotoResource(
                origin: .pendingCapture(
                    captureID: record.captureID,
                    selectedSignedPhoto: true
                )
            ),
            recordResolver: .init(
                captureLoader: { _ in record },
                assetLoader: { _ in nil }
            ),
            localIntegrityValidator: ShareLocalIntegrityValidatorStub { resource, captureID, packageID in
                await invocationRecorder.record(
                    resource: resource,
                    expectedCaptureID: captureID,
                    expectedPackageID: packageID
                )
            }
        )

        await model.refreshCertification()

        #expect(model.certificationState == .localIntegrityPassed)
        #expect(await invocationRecorder.count() == 1)
        #expect(await invocationRecorder.lastExpectedCaptureID() == record.captureID)
    }

    @MainActor
    @Test func localIntegrityMismatchDisablesPackageButKeepsDirectMediaAvailable() async throws {
        let failingValidator = ShareLocalIntegrityValidatorStub { _, _, _ in
            throw ShareLocalIntegrityStubError.mismatch
        }
        let photoSubject = DepthAnalysisShareSubject(
            id: "mismatched-photo",
            mediaID: .photosAsset("mismatched-photo-asset"),
            captureID: nil,
            assetID: "mismatched-photo-asset",
            usesPendingCaptureResource: false
        )
        let photoModel = DepthAnalysisShareCoordinator(
            subject: photoSubject,
            originalResource: try Self.makePhotoResource(
                origin: .photosAsset(assetID: "mismatched-photo-asset")
            ),
            recordResolver: .init(
                captureLoader: { _ in throw TestError.unexpectedCaptureLookup },
                assetLoader: { _ in nil }
            ),
            localIntegrityValidator: failingValidator
        )

        await photoModel.refreshCertification()
        #expect(photoModel.certificationState == .failed)
        #expect(!photoModel.isPackageAvailable)
        #expect(!photoModel.canPreparePackage)
        #expect(photoModel.isImageAvailable)
        #expect(photoModel.canPrepareImage)

        let videoDirectoryURL = try TAPCamDemoTestFixtures.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: videoDirectoryURL) }
        let videoURL = videoDirectoryURL.appendingPathComponent("original.mp4")
        try Data("opaque-video".utf8).write(to: videoURL)
        let videoSubject = DepthAnalysisShareSubject(
            id: "mismatched-video",
            mediaID: .photosAsset("mismatched-video-asset"),
            captureID: nil,
            assetID: "mismatched-video-asset",
            mediaKind: .video,
            usesPendingCaptureResource: false
        )
        let videoModel = DepthAnalysisShareCoordinator(
            subject: videoSubject,
            originalResource: .video(
                try TAPVideoOriginalResourceOwner(
                    mediaID: videoSubject.mediaID,
                    origin: .photosAsset(assetID: "mismatched-video-asset"),
                    fileURL: videoURL
                ).acquireLease()
            ),
            recordResolver: .init(
                captureLoader: { _ in throw TestError.unexpectedCaptureLookup },
                assetLoader: { _ in nil }
            ),
            localIntegrityValidator: failingValidator
        )

        await videoModel.refreshCertification()
        #expect(videoModel.certificationState == .failed)
        #expect(!videoModel.isPackageAvailable)
        #expect(videoModel.isVideoAvailable)
        #expect(videoModel.canPrepareVideo)
    }

    @MainActor
    @Test func coordinatorDoesNotPresentWithoutMatchingReadyResource() {
        let subject = DepthAnalysisShareSubject(
            id: "not-ready",
            mediaID: .photosAsset("not-ready-asset"),
            captureID: nil,
            assetID: "not-ready-asset"
        )
        let model = DepthAnalysisShareCoordinator(subject: subject)

        #expect(!model.isPopoverPresented)
        #expect(model.certificationState == nil)
        #expect(!model.isImageAvailable)
        #expect(!model.isPackageAvailable)
    }

    @MainActor
    @Test func coordinatorRejectsPhotoResourceFromDifferentDisplayedItem() throws {
        let subject = DepthAnalysisShareSubject(
            id: "displayed-photo",
            mediaID: .photosAsset("displayed-photo"),
            captureID: nil,
            assetID: "displayed-photo"
        )
        let model = DepthAnalysisShareCoordinator()

        model.present(
            subject: subject,
            resource: try Self.makePhotoResource(
                origin: .photosAsset(assetID: "stale-photo"),
                mediaID: .photosAsset("stale-photo")
            )
        )

        #expect(!model.isPopoverPresented)
        #expect(model.subject == nil)
        #expect(model.certificationState == nil)
    }

    @MainActor
    @Test func coordinatorRejectsVideoResourceFromDifferentDisplayedItem() throws {
        let directoryURL = try TAPCamDemoTestFixtures.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let videoURL = directoryURL.appendingPathComponent("stale-video.mp4")
        try Data("stale-video".utf8).write(to: videoURL)
        let subject = DepthAnalysisShareSubject(
            id: "displayed-video",
            mediaID: .photosAsset("displayed-video"),
            captureID: nil,
            assetID: "displayed-video",
            mediaKind: .video
        )
        let model = DepthAnalysisShareCoordinator()

        model.present(
            subject: subject,
            resource: .video(
                try TAPVideoOriginalResourceOwner(
                    mediaID: .photosAsset("stale-video"),
                    origin: .photosAsset(assetID: "stale-video"),
                    fileURL: videoURL
                ).acquireLease()
            )
        )

        #expect(!model.isPopoverPresented)
        #expect(model.subject == nil)
        #expect(model.certificationState == nil)
    }

    @MainActor
    @Test func coordinatorRejectsOwnedPhotoFromWrongPhotosAssetEvenWithSameCaptureID() throws {
        let subject = DepthAnalysisShareSubject(
            id: "owned-photo",
            mediaID: .tapCapture("owned-photo-capture"),
            captureID: "owned-photo-capture",
            assetID: "current-photo-asset",
            usesPendingCaptureResource: false
        )
        let model = DepthAnalysisShareCoordinator()

        model.present(
            subject: subject,
            resource: try Self.makePhotoResource(
                origin: .photosAsset(assetID: "stale-photo-asset"),
                mediaID: subject.mediaID
            )
        )

        #expect(!model.isPopoverPresented)
        #expect(model.subject == nil)
    }

    @MainActor
    @Test func coordinatorRejectsOwnedVideoFromWrongPhotosAssetEvenWithSameCaptureID() throws {
        let directoryURL = try TAPCamDemoTestFixtures.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let videoURL = directoryURL.appendingPathComponent("stale-owned-video.mp4")
        try Data("stale-owned-video".utf8).write(to: videoURL)
        let subject = DepthAnalysisShareSubject(
            id: "owned-video",
            mediaID: .tapCapture("owned-video-capture"),
            captureID: "owned-video-capture",
            assetID: "current-video-asset",
            mediaKind: .video,
            usesPendingCaptureResource: false
        )
        let model = DepthAnalysisShareCoordinator()

        model.present(
            subject: subject,
            resource: .video(
                try TAPVideoOriginalResourceOwner(
                    mediaID: subject.mediaID,
                    origin: .ownedPhotosAsset(
                        captureID: "owned-video-capture",
                        assetID: "stale-video-asset"
                    ),
                    fileURL: videoURL
                ).acquireLease()
            )
        )

        #expect(!model.isPopoverPresented)
        #expect(model.subject == nil)
    }

    @MainActor
    @Test func localIntegrityWaitsForTheActuallyVisiblePopover() async throws {
        let invocationRecorder = ShareLocalIntegrityInvocationRecorder()
        let subject = DepthAnalysisShareSubject(
            id: "visible-popover-integrity",
            mediaID: .photosAsset("visible-popover-integrity"),
            captureID: nil,
            assetID: "visible-popover-integrity",
            usesPendingCaptureResource: false
        )
        let model = DepthAnalysisShareCoordinator(
            recordResolver: .init(
                captureLoader: { _ in throw TestError.unexpectedCaptureLookup },
                assetLoader: { _ in nil }
            ),
            localIntegrityValidator: ShareLocalIntegrityValidatorStub { resource, captureID, packageID in
                await invocationRecorder.record(
                    resource: resource,
                    expectedCaptureID: captureID,
                    expectedPackageID: packageID
                )
            }
        )

        model.present(
            subject: subject,
            resource: try Self.makePhotoResource(
                origin: .photosAsset(assetID: "visible-popover-integrity")
            )
        )
        for _ in 0..<30 {
            await Task.yield()
        }

        #expect(model.isPopoverPresented)
        #expect(model.certificationState == nil)
        #expect(await invocationRecorder.count() == 0)
        model.prepare(.image)
        guard case .idle = model.preparationState else {
            Issue.record("Share preparation must wait for the visible popover and integrity verdict")
            return
        }

        model.popoverDidAppear()
        for _ in 0..<100 where model.certificationState == nil {
            await Task.yield()
        }

        #expect(model.certificationState == .localIntegrityPassed)
        #expect(await invocationRecorder.count() == 1)
    }

    @MainActor
    @Test func staleLocalValidationResultCannotOverwriteNewPresentation() async throws {
        let gate = ShareLocalIntegrityStaleResultGate()
        let validator = ShareLocalIntegrityValidatorStub { resource, captureID, packageID in
            try await gate.validate(
                resource: resource,
                expectedCaptureID: captureID,
                expectedPackageID: packageID
            )
        }
        let resolver = DepthAnalysisShareRecordResolver(
            captureLoader: { _ in throw TestError.unexpectedCaptureLookup },
            assetLoader: { _ in nil }
        )
        let firstSubject = DepthAnalysisShareSubject(
            id: "first-validation",
            mediaID: .photosAsset("first-asset"),
            captureID: nil,
            assetID: "first-asset",
            usesPendingCaptureResource: false
        )
        let secondSubject = DepthAnalysisShareSubject(
            id: "second-validation",
            mediaID: .photosAsset("second-asset"),
            captureID: nil,
            assetID: "second-asset",
            usesPendingCaptureResource: false
        )
        let model = DepthAnalysisShareCoordinator(
            recordResolver: resolver,
            localIntegrityValidator: validator
        )

        model.present(
            subject: firstSubject,
            resource: try Self.makePhotoResource(
                origin: .photosAsset(assetID: "first-asset")
            )
        )
        model.popoverDidAppear()
        await gate.waitUntilFirstValidationStarts()

        model.present(
            subject: secondSubject,
            resource: try Self.makePhotoResource(
                origin: .photosAsset(assetID: "second-asset")
            )
        )
        model.popoverDidAppear()
        for _ in 0..<100 where model.certificationState != .localIntegrityPassed {
            await Task.yield()
        }
        #expect(model.subject?.id == secondSubject.id)
        #expect(model.certificationState == .localIntegrityPassed)

        await gate.releaseFirstValidationAsMismatch()
        for _ in 0..<30 {
            await Task.yield()
        }

        #expect(model.subject?.id == secondSubject.id)
        #expect(model.certificationState == .localIntegrityPassed)
        #expect(await gate.invocationCount() == 2)
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

    @Test func recordResolverUsesCaptureIdentityAndRequiresMatchingAsset() async throws {
        let record = TAPCamDemoTestFixtures.samplePendingRecord(
            captureID: "owned-capture",
            capturedAt: Date(timeIntervalSince1970: 1_750_000_000),
            status: .exported,
            signedPhotoFilename: "signed.heic",
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

    @MainActor
    @Test func coordinatorFailsClosedWhenOwnedRecordIdentityConflicts() async throws {
        let subject = DepthAnalysisShareSubject(
            id: "owned-conflict",
            mediaID: .tapCapture("owned-conflict"),
            captureID: "owned-conflict",
            assetID: "current-asset"
        )
        let conflictingRecord = TAPCamDemoTestFixtures.samplePendingRecord(
            captureID: "owned-conflict",
            capturedAt: Date(timeIntervalSince1970: 1_750_000_000),
            status: .exported,
            signedPhotoFilename: "signed.heic",
            assetLocalIdentifier: "different-asset"
        )
        let invocationRecorder = ShareLocalIntegrityInvocationRecorder()
        let model = DepthAnalysisShareCoordinator(
            subject: subject,
            originalResource: try Self.makePhotoResource(
                origin: .photosAsset(assetID: "current-asset"),
                mediaID: subject.mediaID
            ),
            recordResolver: .init(
                captureLoader: { _ in conflictingRecord },
                assetLoader: { _ in nil }
            ),
            localIntegrityValidator: ShareLocalIntegrityValidatorStub { resource, captureID, packageID in
                await invocationRecorder.record(
                    resource: resource,
                    expectedCaptureID: captureID,
                    expectedPackageID: packageID
                )
            }
        )

        await model.refreshCertification()

        #expect(model.certificationState == .failed)
        #expect(!model.isPackageAvailable)
        #expect(model.isImageAvailable)
        #expect(await invocationRecorder.count() == 0)
    }

    @MainActor
    @Test func coordinatorFailsClosedWhenRecordMediaKindConflicts() async throws {
        let subject = DepthAnalysisShareSubject(
            id: "photo-kind-conflict",
            mediaID: .tapCapture("photo-kind-conflict"),
            captureID: "photo-kind-conflict",
            assetID: "photo-kind-asset"
        )
        let videoRecord = TAPCamDemoTestFixtures.samplePendingVideoRecord(
            captureID: "photo-kind-conflict",
            capturedAt: Date(timeIntervalSince1970: 1_750_000_000),
            status: .exported,
            videoArtifactState: .signed,
            assetLocalIdentifier: "photo-kind-asset"
        )
        let invocationRecorder = ShareLocalIntegrityInvocationRecorder()
        let model = DepthAnalysisShareCoordinator(
            subject: subject,
            originalResource: try Self.makePhotoResource(
                origin: .photosAsset(assetID: "photo-kind-asset"),
                mediaID: subject.mediaID
            ),
            recordResolver: .init(
                captureLoader: { _ in videoRecord },
                assetLoader: { _ in nil }
            ),
            localIntegrityValidator: ShareLocalIntegrityValidatorStub { resource, captureID, packageID in
                await invocationRecorder.record(
                    resource: resource,
                    expectedCaptureID: captureID,
                    expectedPackageID: packageID
                )
            }
        )

        await model.refreshCertification()

        #expect(model.certificationState == .failed)
        #expect(await invocationRecorder.count() == 0)
    }

    @MainActor
    @Test func coordinatorTreatsAmbiguousAssetLookupAsFailure() async throws {
        let subject = DepthAnalysisShareSubject(
            id: "ambiguous-asset",
            mediaID: .photosAsset("ambiguous-asset"),
            captureID: nil,
            assetID: "ambiguous-asset"
        )
        let invocationRecorder = ShareLocalIntegrityInvocationRecorder()
        let model = DepthAnalysisShareCoordinator(
            subject: subject,
            originalResource: try Self.makePhotoResource(
                origin: .photosAsset(assetID: "ambiguous-asset")
            ),
            recordResolver: .init(
                captureLoader: { _ in throw TestError.unexpectedCaptureLookup },
                assetLoader: { _ in
                    throw TAPPendingCaptureStoreLookupError
                        .ambiguousAssetLocalIdentifier
                }
            ),
            localIntegrityValidator: ShareLocalIntegrityValidatorStub { resource, captureID, packageID in
                await invocationRecorder.record(
                    resource: resource,
                    expectedCaptureID: captureID,
                    expectedPackageID: packageID
                )
            }
        )

        await model.refreshCertification()

        #expect(model.certificationState == .failed)
        #expect(await invocationRecorder.count() == 0)
    }

    @MainActor
    @Test func verifiedFrozenPendingResourceIgnoresLaterQueueNotifications() async throws {
        let record = TAPCamDemoTestFixtures.samplePendingRecord(
            captureID: "verified-notification-isolation",
            capturedAt: Date(timeIntervalSince1970: 1_750_000_000),
            status: .signed,
            signedPhotoFilename: "signed.heic"
        )
        let invocationRecorder = ShareLocalIntegrityInvocationRecorder()
        let model = DepthAnalysisShareCoordinator(
            subject: Self.pendingPhotoSubject(captureID: record.captureID),
            originalResource: try Self.makePhotoResource(
                origin: .pendingCapture(
                    captureID: record.captureID,
                    selectedSignedPhoto: true
                )
            ),
            recordResolver: .init(
                captureLoader: { _ in record },
                assetLoader: { _ in nil }
            ),
            localIntegrityValidator: ShareLocalIntegrityValidatorStub { resource, captureID, packageID in
                await invocationRecorder.record(
                    resource: resource,
                    expectedCaptureID: captureID,
                    expectedPackageID: packageID
                )
            }
        )

        await model.refreshCertification()
        #expect(model.certificationState == .localIntegrityPassed)
        #expect(await invocationRecorder.count() == 1)

        model.scheduleCertificationRefresh(
            for: TAPLibraryPendingCaptureChange(captureID: record.captureID)
        )
        for _ in 0..<20 {
            await Task.yield()
        }

        #expect(model.certificationState == .localIntegrityPassed)
        #expect(await invocationRecorder.count() == 1)
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
            signedPhotoFilename: nil,
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
    @Test func unrelatedPendingNotificationCannotRefreshCurrentShare() async throws {
        let pendingRecord = TAPCamDemoTestFixtures.samplePendingRecord(
            captureID: "notification-isolation",
            capturedAt: Date(timeIntervalSince1970: 1_750_000_000),
            status: .waitingNetwork,
            signedPhotoFilename: nil
        )
        let signedRecord = TAPCamDemoTestFixtures.samplePendingRecord(
            captureID: "notification-isolation",
            capturedAt: Date(timeIntervalSince1970: 1_750_000_000),
            status: .signed,
            signedPhotoFilename: "signed.heic"
        )
        let box = ShareRecordBox(pendingRecord)
        let invocationRecorder = ShareLocalIntegrityInvocationRecorder()
        let model = DepthAnalysisShareCoordinator(
            subject: Self.pendingPhotoSubject(captureID: pendingRecord.captureID),
            originalResource: try Self.makePhotoResource(
                origin: .pendingCapture(
                    captureID: pendingRecord.captureID,
                    selectedSignedPhoto: false
                )
            ),
            recordResolver: .init(
                captureLoader: { _ in await box.current() },
                assetLoader: { _ in nil }
            ),
            localIntegrityValidator: ShareLocalIntegrityValidatorStub { resource, captureID, packageID in
                await invocationRecorder.record(
                    resource: resource,
                    expectedCaptureID: captureID,
                    expectedPackageID: packageID
                )
            }
        )

        await model.refreshCertification()
        #expect(model.certificationState == .retryPending)
        await box.replace(with: signedRecord)

        model.scheduleCertificationRefresh(
            for: TAPLibraryPendingCaptureChange(captureID: "different-capture")
        )
        for _ in 0..<20 {
            await Task.yield()
        }

        #expect(model.certificationState == .retryPending)
        #expect(await invocationRecorder.count() == 0)
    }

    @MainActor
    @Test func statusOnlyPendingChangeDoesNotInvokeShareLocalValidation() async throws {
        let initialRecord = TAPCamDemoTestFixtures.samplePendingRecord(
            captureID: "status-only-change",
            capturedAt: Date(timeIntervalSince1970: 1_750_000_000),
            status: .waitingNetwork,
            signedPhotoFilename: nil
        )
        let statusOnlyRecord = TAPCamDemoTestFixtures.samplePendingRecord(
            captureID: "status-only-change",
            capturedAt: Date(timeIntervalSince1970: 1_750_000_000),
            status: .failedRetryable,
            signedPhotoFilename: nil
        )
        let box = ShareRecordBox(initialRecord)
        let invocationRecorder = ShareLocalIntegrityInvocationRecorder()
        let model = DepthAnalysisShareCoordinator(
            subject: Self.pendingPhotoSubject(captureID: initialRecord.captureID),
            originalResource: try Self.makePhotoResource(
                origin: .pendingCapture(
                    captureID: initialRecord.captureID,
                    selectedSignedPhoto: false
                )
            ),
            recordResolver: .init(
                captureLoader: { _ in await box.current() },
                assetLoader: { _ in nil }
            ),
            localIntegrityValidator: ShareLocalIntegrityValidatorStub { resource, captureID, packageID in
                await invocationRecorder.record(
                    resource: resource,
                    expectedCaptureID: captureID,
                    expectedPackageID: packageID
                )
            }
        )

        await model.refreshCertification()
        await box.replace(with: statusOnlyRecord)
        model.scheduleCertificationRefresh(
            for: TAPLibraryPendingCaptureChange(captureID: initialRecord.captureID)
        )
        for _ in 0..<50 {
            await Task.yield()
        }

        #expect(model.certificationState == .retryPending)
        #expect(await invocationRecorder.count() == 0)
    }

    @MainActor
    @Test func exactSignedArtifactTransitionRefreshCannotPromoteUnsignedFrozenResource() async throws {
        let pendingRecord = TAPCamDemoTestFixtures.samplePendingRecord(
            captureID: "refresh-capture",
            capturedAt: Date(timeIntervalSince1970: 1_750_000_000),
            status: .waitingNetwork,
            signedPhotoFilename: nil
        )
        let signedRecord = TAPCamDemoTestFixtures.samplePendingRecord(
            captureID: "refresh-capture",
            capturedAt: Date(timeIntervalSince1970: 1_750_000_000),
            status: .signed,
            signedPhotoFilename: "signed.heic"
        )
        let box = ShareRecordBox(pendingRecord)
        let resolver = DepthAnalysisShareRecordResolver(
            captureLoader: { _ in await box.current() },
            assetLoader: { _ in nil }
        )
        let validationRecorder = ShareLocalIntegrityInvocationRecorder()
        let model = DepthAnalysisShareCoordinator(
            subject: DepthAnalysisShareSubject(
                id: "refresh",
                mediaID: .tapCapture("refresh-capture"),
                captureID: "refresh-capture",
                assetID: nil
            ),
            originalResource: try Self.makePhotoResource(
                origin: .pendingCapture(
                    captureID: "refresh-capture",
                    selectedSignedPhoto: false
                )
            ),
            recordResolver: resolver,
            localIntegrityValidator: ShareLocalIntegrityValidatorStub { resource, captureID, packageID in
                await validationRecorder.record(
                    resource: resource,
                    expectedCaptureID: captureID,
                    expectedPackageID: packageID
                )
                throw ShareLocalIntegrityStubError.unexpectedValidation
            }
        )

        await model.refreshCertification()
        #expect(model.certificationState == .retryPending)

        await box.replace(with: signedRecord)
        model.scheduleCertificationRefresh(
            for: TAPLibraryPendingCaptureChange(captureID: "refresh-capture")
        )
        for _ in 0..<50 where model.certificationState != .failed {
            await Task.yield()
        }

        #expect(model.certificationState == .failed)
        #expect(await validationRecorder.count() == 0)
    }

    @MainActor
    @Test func certificationRefreshKeepsActiveSystemShareAttachmentUntilDismissal() async throws {
        let capturedAt = Date(timeIntervalSince1970: 1_750_000_000)
        let pendingRecord = TAPCamDemoTestFixtures.samplePendingRecord(
            captureID: "active-refresh",
            capturedAt: capturedAt,
            status: .waitingNetwork,
            signedPhotoFilename: nil
        )
        let signedRecord = TAPCamDemoTestFixtures.samplePendingRecord(
            captureID: "active-refresh",
            capturedAt: capturedAt,
            status: .signed,
            signedPhotoFilename: "signed.heic"
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
        let validationRecorder = ShareLocalIntegrityInvocationRecorder()
        let model = DepthAnalysisShareCoordinator(
            subject: DepthAnalysisShareSubject(
                id: "active-refresh",
                mediaID: .tapCapture(pendingRecord.captureID),
                captureID: pendingRecord.captureID,
                assetID: nil
            ),
            originalResource: try Self.makePhotoResource(
                origin: .pendingCapture(
                    captureID: pendingRecord.captureID,
                    selectedSignedPhoto: false
                )
            ),
            recordResolver: resolver,
            artifactPreparer: preparer,
            localIntegrityValidator: ShareLocalIntegrityValidatorStub { resource, captureID, packageID in
                await validationRecorder.record(
                    resource: resource,
                    expectedCaptureID: captureID,
                    expectedPackageID: packageID
                )
                throw ShareLocalIntegrityStubError.unexpectedValidation
            }
        )

        await model.refreshCertification()
        #expect(model.certificationState == .retryPending)
        model.prepare(.image)
        for _ in 0..<100 where model.isPopoverPresented {
            await Task.yield()
        }
        model.popoverDidDisappear()
        for _ in 0..<100 where model.activityPayload == nil {
            await Task.yield()
        }
        #expect(model.activityPayload != nil)
        #expect(FileManager.default.fileExists(atPath: artifactURL.path))

        await recordBox.replace(with: signedRecord)
        await model.refreshCertification()

        #expect(model.certificationState == .failed)
        #expect(await validationRecorder.count() == 0)
        #expect(model.activityPayload != nil)
        #expect(FileManager.default.fileExists(atPath: artifactURL.path))

        model.activityPresentationDidEnd(expectedArtifactID: artifact.id)
        #expect(model.activityPayload == nil)
        try await Self.waitUntilDirectoryIsRemoved(artifactDirectoryURL)
    }

    @MainActor
    @Test func libraryRefreshWaitsForActivePreparationAndCannotSwallowHandoff() async throws {
        let capturedAt = Date(timeIntervalSince1970: 1_750_000_000)
        let pendingRecord = TAPCamDemoTestFixtures.samplePendingRecord(
            captureID: "deferred-refresh",
            capturedAt: capturedAt,
            status: .waitingNetwork,
            signedPhotoFilename: nil
        )
        let signedRecord = TAPCamDemoTestFixtures.samplePendingRecord(
            captureID: "deferred-refresh",
            capturedAt: capturedAt,
            status: .signed,
            signedPhotoFilename: "signed.heic"
        )
        let recordBox = ShareRecordBox(pendingRecord)
        let resolver = DepthAnalysisShareRecordResolver(
            captureLoader: { _ in await recordBox.current() },
            assetLoader: { _ in nil }
        )
        let gate = ShareArtifactReturnGate()
        let artifactDirectoryURL = try TAPCamDemoTestFixtures.makeTemporaryDirectory()
        let artifactURL = artifactDirectoryURL.appendingPathComponent("TAPNAP-Photo.heic")
        try Data("deferred-refresh-image".utf8).write(to: artifactURL)
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
        let model = DepthAnalysisShareCoordinator(
            subject: DepthAnalysisShareSubject(
                id: "deferred-refresh",
                mediaID: .tapCapture(pendingRecord.captureID),
                captureID: pendingRecord.captureID,
                assetID: nil
            ),
            originalResource: try Self.makePhotoResource(
                origin: .pendingCapture(
                    captureID: pendingRecord.captureID,
                    selectedSignedPhoto: false
                )
            ),
            recordResolver: resolver,
            artifactPreparer: preparer,
            localIntegrityValidator: ShareLocalIntegrityValidatorStub.unexpected
        )

        await model.refreshCertification()
        model.prepare(.image)
        await gate.waitUntilArtifactIsReady()
        await recordBox.replace(with: signedRecord)
        model.scheduleCertificationRefresh()

        #expect(model.certificationState == .retryPending)
        await gate.releaseArtifact()
        for _ in 0..<100 where model.isPopoverPresented {
            try await Task.sleep(for: .milliseconds(10))
        }
        model.popoverDidDisappear()

        #expect(model.activityPayload?.id == artifact.id)
        #expect(model.certificationState == .retryPending)
        #expect(FileManager.default.fileExists(atPath: artifactURL.path))

        model.activityPresentationDidEnd(expectedArtifactID: artifact.id)
        try await Self.waitUntilDirectoryIsRemoved(artifactDirectoryURL)
    }

    @MainActor
    @Test func inFlightLibraryRefreshDefersWhenPreparationStarts() async throws {
        let capturedAt = Date(timeIntervalSince1970: 1_750_000_000)
        let pendingRecord = TAPCamDemoTestFixtures.samplePendingRecord(
            captureID: "in-flight-refresh",
            capturedAt: capturedAt,
            status: .waitingNetwork,
            signedPhotoFilename: nil
        )
        let signedRecord = TAPCamDemoTestFixtures.samplePendingRecord(
            captureID: "in-flight-refresh",
            capturedAt: capturedAt,
            status: .signed,
            signedPhotoFilename: "signed.heic"
        )
        let recordGate = ShareRecordRefreshGate(
            initialRecord: pendingRecord,
            refreshedRecord: signedRecord
        )
        let resolver = DepthAnalysisShareRecordResolver(
            captureLoader: { _ in await recordGate.load() },
            assetLoader: { _ in nil }
        )
        let artifactGate = ShareArtifactReturnGate()
        let artifactDirectoryURL = try TAPCamDemoTestFixtures.makeTemporaryDirectory()
        let artifactURL = artifactDirectoryURL.appendingPathComponent("TAPNAP-Photo.heic")
        try Data("in-flight-refresh-image".utf8).write(to: artifactURL)
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
                await artifactGate.signalArtifactReadyAndWaitForRelease()
                return artifact
            }
        )
        let model = DepthAnalysisShareCoordinator(
            subject: DepthAnalysisShareSubject(
                id: "in-flight-refresh",
                mediaID: .tapCapture(pendingRecord.captureID),
                captureID: pendingRecord.captureID,
                assetID: nil
            ),
            originalResource: try Self.makePhotoResource(
                origin: .pendingCapture(
                    captureID: pendingRecord.captureID,
                    selectedSignedPhoto: false
                )
            ),
            recordResolver: resolver,
            artifactPreparer: preparer,
            localIntegrityValidator: ShareLocalIntegrityValidatorStub.unexpected
        )

        await model.refreshCertification()
        #expect(model.certificationState == .retryPending)

        model.scheduleCertificationRefresh()
        await recordGate.waitUntilRefreshStarts()
        model.prepare(.image)
        await artifactGate.waitUntilArtifactIsReady()
        await recordGate.releaseRefresh()
        for _ in 0..<20 {
            await Task.yield()
        }

        #expect(model.certificationState == .retryPending)
        #expect(model.isPreparing)

        await artifactGate.releaseArtifact()
        for _ in 0..<100 where model.isPopoverPresented {
            await Task.yield()
        }
        model.popoverDidDisappear()

        #expect(model.activityPayload?.id == artifact.id)
        #expect(model.certificationState == .retryPending)
        #expect(FileManager.default.fileExists(atPath: artifactURL.path))

        model.activityPresentationDidEnd(expectedArtifactID: artifact.id)
        try await Self.waitUntilDirectoryIsRemoved(artifactDirectoryURL)
    }

    @MainActor
    @Test func preparationDisablesRepeatSelectionWithoutDimmingAvailableRows() async throws {
        let record = TAPCamDemoTestFixtures.samplePendingRecord(
            captureID: "stable-row",
            capturedAt: Date(timeIntervalSince1970: 1_750_000_000),
            status: .signed,
            signedPhotoFilename: "signed.heic"
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
        let model = DepthAnalysisShareCoordinator(
            subject: DepthAnalysisShareSubject(
                id: "stable-row",
                mediaID: .tapCapture(record.captureID),
                captureID: record.captureID,
                assetID: nil
            ),
            originalResource: try Self.makePhotoResource(
                origin: .pendingCapture(
                    captureID: record.captureID,
                    selectedSignedPhoto: true
                )
            ),
            recordResolver: resolver,
            artifactPreparer: preparer,
            localIntegrityValidator: ShareLocalIntegrityValidatorStub.succeeding
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
        #expect(model.visibleProgress == 0)
        #expect(model.preparationProgress(for: .tapnapPackage) == 0)
        #expect(model.preparationProgress(for: .image) == nil)
        #expect(model.isImageAvailable)
        #expect(!model.canPrepareImage)
        model.cancelPreparation()
    }

    @MainActor
    @Test func packageProgressPublishesThroughTheMainActorWhilePreparationContinues() async throws {
        let record = TAPCamDemoTestFixtures.samplePendingRecord(
            captureID: "progress-bridge",
            capturedAt: Date(timeIntervalSince1970: 1_750_000_000),
            status: .signed,
            signedPhotoFilename: "signed.heic"
        )
        let resolver = DepthAnalysisShareRecordResolver(
            captureLoader: { _ in record },
            assetLoader: { _ in nil }
        )
        let model = DepthAnalysisShareCoordinator(
            subject: DepthAnalysisShareSubject(
                id: "progress-bridge",
                mediaID: .tapCapture(record.captureID),
                captureID: record.captureID,
                assetID: nil
            ),
            originalResource: try Self.makePhotoResource(
                origin: .pendingCapture(
                    captureID: record.captureID,
                    selectedSignedPhoto: true
                )
            ),
            recordResolver: resolver,
            artifactPreparer: ProgressReportingShareArtifactPreparerStub(
                packageProgress: 0.84
            ),
            localIntegrityValidator: ShareLocalIntegrityValidatorStub.succeeding
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
    @Test func regressingProgressCallbackDoesNotLowerPublishedProgress() async throws {
        let record = TAPCamDemoTestFixtures.samplePendingRecord(
            captureID: "monotonic-share-progress",
            capturedAt: Date(timeIntervalSince1970: 1_750_000_000),
            status: .signed,
            signedPhotoFilename: "signed.heic"
        )
        let model = DepthAnalysisShareCoordinator(
            subject: DepthAnalysisShareSubject(
                id: record.captureID,
                mediaID: .tapCapture(record.captureID),
                captureID: record.captureID,
                assetID: nil
            ),
            originalResource: try Self.makePhotoResource(
                origin: .pendingCapture(
                    captureID: record.captureID,
                    selectedSignedPhoto: true
                )
            ),
            recordResolver: DepthAnalysisShareRecordResolver(
                captureLoader: { _ in record },
                assetLoader: { _ in nil }
            ),
            artifactPreparer: RegressingProgressShareArtifactPreparerStub(),
            localIntegrityValidator: ShareLocalIntegrityValidatorStub.succeeding
        )

        await model.refreshCertification()
        model.prepare(.tapnapPackage)
        for _ in 0..<100 {
            guard case .preparing(_, let progress) = model.preparationState,
                  progress < 0.8 else {
                break
            }
            await Task.yield()
        }

        guard case .preparing(_, let progress) = model.preparationState else {
            Issue.record("Expected active preparation")
            return
        }
        #expect(progress == 0.8)
        model.cancelPreparation()
    }

    @MainActor
    @Test func identityConflictCannotPresentOrInvokePhotoArtifactPreparer() async throws {
        let counter = SharePreparationInvocationCounter()
        let model = DepthAnalysisShareCoordinator(
            subject: DepthAnalysisShareSubject(
                id: "identity-conflict",
                mediaID: .photosAsset("asset-a"),
                captureID: nil,
                assetID: "asset-a",
                hasIdentityConflict: true
            ),
            originalResource: try Self.makePhotoResource(
                origin: .photosAsset(assetID: "asset-a")
            ),
            recordResolver: DepthAnalysisShareRecordResolver(
                captureLoader: { _ in throw TestError.missingCapture },
                assetLoader: { _ in nil }
            ),
            artifactPreparer: CountingShareArtifactPreparer(counter: counter)
        )

        #expect(!model.isPopoverPresented)
        model.prepare(.image)

        #expect(await counter.value() == 0)
        guard case .idle = model.preparationState else {
            Issue.record("Expected identity conflict to stay outside Share presentation")
            return
        }
    }

    @MainActor
    @Test func optionSelectionImmediatelyShowsProgressAndReadyPayloadClosesPopoverWithoutHold() async throws {
        let record = TAPCamDemoTestFixtures.samplePendingRecord(
            captureID: "immediate-progress",
            capturedAt: Date(timeIntervalSince1970: 1_750_000_000),
            status: .signed,
            signedPhotoFilename: "signed.heic"
        )
        let resolver = DepthAnalysisShareRecordResolver(
            captureLoader: { _ in record },
            assetLoader: { _ in nil }
        )
        let gate = ShareArtifactReturnGate()
        let artifactDirectoryURL = try TAPCamDemoTestFixtures.makeTemporaryDirectory()
        let artifactURL = artifactDirectoryURL.appendingPathComponent("TAPNAP-Capture.tapnap")
        try Data("immediate-progress-package".utf8).write(to: artifactURL)
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
        let model = DepthAnalysisShareCoordinator(
            subject: DepthAnalysisShareSubject(
                id: "immediate-progress",
                mediaID: .tapCapture(record.captureID),
                captureID: record.captureID,
                assetID: nil
            ),
            originalResource: try Self.makePhotoResource(
                origin: .pendingCapture(
                    captureID: record.captureID,
                    selectedSignedPhoto: true
                )
            ),
            recordResolver: resolver,
            artifactPreparer: preparer,
            localIntegrityValidator: ShareLocalIntegrityValidatorStub.succeeding
        )

        await model.refreshCertification()
        model.prepare(.tapnapPackage)

        #expect(model.isPopoverPresented)
        #expect(model.isPreparing)
        #expect(model.visibleProgress == 0)
        guard case .preparing(let option, let progress) = model.preparationState else {
            Issue.record("Expected immediate determinate preparation progress")
            return
        }
        #expect(option == .tapnapPackage)
        #expect(progress == 0)

        await gate.waitUntilArtifactIsReady()
        #expect(model.isPopoverPresented)
        #expect(model.activityPayload == nil)

        await gate.releaseArtifact()
        for _ in 0..<100 where model.isPopoverPresented {
            await Task.yield()
        }

        #expect(!model.isPopoverPresented)
        #expect(model.activityPayload == nil)
        #expect(model.hasActiveActivityPresentation)
        #expect(model.visibleProgress == 1)
        #expect(model.preparationProgress(for: .tapnapPackage) == 1)
        #expect(model.preparationProgress(for: .image) == nil)

        model.popoverDidDisappear()
        #expect(model.activityPresentation?.id == artifact.id)
        #expect(model.visibleProgress == nil)

        model.activityPresentationDidEnd(expectedArtifactID: artifact.id)
        try await Self.waitUntilDirectoryIsRemoved(artifactDirectoryURL)
    }

    @MainActor
    @Test func bindingEndCleansArtifactWhileUIKitStillRetainsController() async throws {
        let record = TAPCamDemoTestFixtures.samplePendingRecord(
            captureID: "activity-cleanup",
            capturedAt: Date(timeIntervalSince1970: 1_750_000_000),
            status: .signed,
            signedPhotoFilename: "signed.heic"
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
        let model = DepthAnalysisShareCoordinator(
            subject: DepthAnalysisShareSubject(
                id: "activity-cleanup",
                mediaID: .tapCapture(record.captureID),
                captureID: record.captureID,
                assetID: nil
            ),
            originalResource: try Self.makePhotoResource(
                origin: .pendingCapture(
                    captureID: record.captureID,
                    selectedSignedPhoto: true
                )
            ),
            recordResolver: resolver,
            artifactPreparer: preparer,
            localIntegrityValidator: ShareLocalIntegrityValidatorStub.succeeding
        )

        await model.refreshCertification()
        model.prepare(.tapnapPackage)
        for _ in 0..<100 where model.isPopoverPresented {
            await Task.yield()
        }
        model.popoverDidDisappear()
        for _ in 0..<100 where model.activityPayload == nil {
            await Task.yield()
        }
        #expect(model.activityPayload != nil)
        #expect(FileManager.default.fileExists(atPath: artifactDirectoryURL.path))
        let presentation = try #require(model.activityPresentation)
        var retainedController: TAPShareActivityViewController? = presentation.makeViewController()
        #expect(retainedController?.artifact === artifact)

        model.activityPresentationDidEnd(expectedArtifactID: artifact.id)

        #expect(model.activityPayload == nil)
        #expect(!model.hasActiveActivityPresentation)
        guard case .idle = model.preparationState else {
            Issue.record("Expected dismissal to reset preparation state")
            return
        }

        try await Self.waitUntilDirectoryIsRemoved(artifactDirectoryURL)
        #expect(retainedController != nil)
        retainedController = nil
    }

    @MainActor
    @Test func activityBindingAndOnDismissEndSignalsAreIdempotent() async throws {
        let record = TAPCamDemoTestFixtures.samplePendingRecord(
            captureID: "activity-idempotent",
            capturedAt: Date(timeIntervalSince1970: 1_750_000_000),
            status: .signed,
            signedPhotoFilename: "signed.heic"
        )
        let resolver = DepthAnalysisShareRecordResolver(
            captureLoader: { _ in record },
            assetLoader: { _ in nil }
        )
        let artifactDirectoryURL = try TAPCamDemoTestFixtures.makeTemporaryDirectory()
        let artifactURL = artifactDirectoryURL.appendingPathComponent("TAPNAP-Capture.tapnap")
        try Data("typed-package".utf8).write(to: artifactURL)
        let removalRecorder = ShareTemporaryDirectoryRemovalRecorder()
        let artifact = TAPNAPShareArtifact(
            id: UUID(),
            kind: .tapnapPackage,
            fileURL: artifactURL,
            temporaryDirectoryURL: artifactDirectoryURL,
            warnings: [],
            temporaryDirectoryRemover: { url in
                try removalRecorder.remove(url)
            }
        )
        let model = DepthAnalysisShareCoordinator(
            subject: DepthAnalysisShareSubject(
                id: "activity-idempotent",
                mediaID: .tapCapture(record.captureID),
                captureID: record.captureID,
                assetID: nil
            ),
            originalResource: try Self.makePhotoResource(
                origin: .pendingCapture(
                    captureID: record.captureID,
                    selectedSignedPhoto: true
                )
            ),
            recordResolver: resolver,
            artifactPreparer: ShareArtifactPreparerStub(
                packageOperation: { _ in artifact },
                imageOperation: { _, _ in
                    throw TestError.unexpectedSignedImagePolicy
                }
            ),
            localIntegrityValidator: ShareLocalIntegrityValidatorStub.succeeding
        )

        await model.refreshCertification()
        model.prepare(.tapnapPackage)
        for _ in 0..<100 where model.isPopoverPresented {
            await Task.yield()
        }
        model.popoverDidDisappear()
        #expect(model.activityPresentation?.id == artifact.id)

        // SwiftUI may deliver the Binding nil write and onDismiss for the same
        // exact sheet. Both feed the same exact-ID transition.
        model.activityPresentationDidEnd(expectedArtifactID: artifact.id)
        model.activityPresentationDidEnd(expectedArtifactID: artifact.id)
        #expect(!model.hasActiveActivityPresentation)

        try await Self.waitUntilDirectoryIsRemoved(artifactDirectoryURL)
        #expect(removalRecorder.removalCount == 1)
    }

    @MainActor
    @Test func supersedingPendingHandoffCleansTheDiscardedArtifactExactlyOnce() async throws {
        let record = TAPCamDemoTestFixtures.samplePendingRecord(
            captureID: "discard-pending-handoff",
            capturedAt: Date(timeIntervalSince1970: 1_750_000_000),
            status: .signed,
            signedPhotoFilename: "signed.heic"
        )
        let artifactDirectoryURL = try TAPCamDemoTestFixtures.makeTemporaryDirectory()
        let artifactURL = artifactDirectoryURL.appendingPathComponent("TAPNAP-Capture.tapnap")
        try Data("discard-pending-handoff".utf8).write(to: artifactURL)
        let removalRecorder = ShareTemporaryDirectoryRemovalRecorder()
        let artifact = TAPNAPShareArtifact(
            id: UUID(),
            kind: .tapnapPackage,
            fileURL: artifactURL,
            temporaryDirectoryURL: artifactDirectoryURL,
            warnings: [],
            temporaryDirectoryRemover: { url in
                try removalRecorder.remove(url)
            }
        )
        let model = DepthAnalysisShareCoordinator(
            subject: Self.pendingPhotoSubject(captureID: record.captureID),
            originalResource: try Self.makePhotoResource(
                origin: .pendingCapture(
                    captureID: record.captureID,
                    selectedSignedPhoto: true
                )
            ),
            recordResolver: .init(
                captureLoader: { _ in record },
                assetLoader: { _ in nil }
            ),
            artifactPreparer: ShareArtifactPreparerStub(
                packageOperation: { _ in artifact },
                imageOperation: { _, _ in
                    try await Task.sleep(nanoseconds: 30_000_000_000)
                    throw CancellationError()
                }
            ),
            localIntegrityValidator: ShareLocalIntegrityValidatorStub.succeeding
        )

        await model.refreshCertification()
        model.prepare(.tapnapPackage)
        for _ in 0..<100 where model.isPopoverPresented {
            await Task.yield()
        }

        #expect(model.activityPresentation == nil)
        #expect(model.hasActiveActivityPresentation)
        #expect(FileManager.default.fileExists(atPath: artifactDirectoryURL.path))

        // A late app-owned reopen can supersede an unpromoted pending handoff.
        // Starting the new preparation must discard only the old artifact.
        model.cancelPreparation()
        model.setPopoverPresented(true)
        model.prepare(.image)

        try await Self.waitUntilDirectoryIsRemoved(artifactDirectoryURL)
        #expect(removalRecorder.removalCount == 1)
        #expect(model.isPreparing)
        #expect(model.visibleProgress == 0)

        model.cancelPreparation()
    }

    @MainActor
    @Test func staleSheetCallbacksCannotDismissANewerShareAttempt() async throws {
        let record = TAPCamDemoTestFixtures.samplePendingRecord(
            captureID: "stale-sheet-callback",
            capturedAt: Date(timeIntervalSince1970: 1_750_000_000),
            status: .signed,
            signedPhotoFilename: "signed.heic"
        )
        let subject = Self.pendingPhotoSubject(captureID: record.captureID)
        let resource = try Self.makePhotoResource(
            origin: .pendingCapture(
                captureID: record.captureID,
                selectedSignedPhoto: true
            )
        )
        let firstDirectoryURL = try TAPCamDemoTestFixtures.makeTemporaryDirectory()
        let firstFileURL = firstDirectoryURL.appendingPathComponent("TAPNAP-Capture.tapnap")
        try Data("first-attempt".utf8).write(to: firstFileURL)
        let firstRemovalRecorder = ShareTemporaryDirectoryRemovalRecorder()
        let firstArtifact = TAPNAPShareArtifact(
            id: UUID(),
            kind: .tapnapPackage,
            fileURL: firstFileURL,
            temporaryDirectoryURL: firstDirectoryURL,
            warnings: [],
            temporaryDirectoryRemover: { url in
                try firstRemovalRecorder.remove(url)
            }
        )
        let secondDirectoryURL = try TAPCamDemoTestFixtures.makeTemporaryDirectory()
        let secondFileURL = secondDirectoryURL.appendingPathComponent("TAPNAP-Photo.heic")
        try Data("second-attempt".utf8).write(to: secondFileURL)
        let secondRemovalRecorder = ShareTemporaryDirectoryRemovalRecorder()
        let secondArtifact = TAPNAPShareArtifact(
            id: UUID(),
            kind: .image,
            fileURL: secondFileURL,
            temporaryDirectoryURL: secondDirectoryURL,
            warnings: [],
            temporaryDirectoryRemover: { url in
                try secondRemovalRecorder.remove(url)
            }
        )
        let model = DepthAnalysisShareCoordinator(
            subject: subject,
            originalResource: resource,
            recordResolver: .init(
                captureLoader: { _ in record },
                assetLoader: { _ in nil }
            ),
            artifactPreparer: ShareArtifactPreparerStub(
                packageOperation: { _ in firstArtifact },
                imageOperation: { _, _ in secondArtifact }
            ),
            localIntegrityValidator: ShareLocalIntegrityValidatorStub.succeeding
        )

        await model.refreshCertification()
        model.prepare(.tapnapPackage)
        for _ in 0..<100 where model.isPopoverPresented {
            await Task.yield()
        }
        model.popoverDidDisappear()
        for _ in 0..<100 where model.activityPresentation?.id != firstArtifact.id {
            await Task.yield()
        }
        #expect(model.activityPresentation?.id == firstArtifact.id)

        model.activityPresentationDidEnd(expectedArtifactID: firstArtifact.id)
        #expect(!model.hasActiveActivityPresentation)
        try await Self.waitUntilDirectoryIsRemoved(firstDirectoryURL)
        #expect(firstRemovalRecorder.removalCount == 1)

        model.present(subject: subject, resource: resource)
        await model.refreshCertification()
        model.prepare(.image)
        for _ in 0..<100 where model.isPopoverPresented {
            await Task.yield()
        }
        model.popoverDidDisappear()
        for _ in 0..<100 where model.activityPresentation?.id != secondArtifact.id {
            await Task.yield()
        }
        #expect(model.activityPresentation?.id == secondArtifact.id)

        model.activityPresentationDidEnd(expectedArtifactID: firstArtifact.id)

        #expect(model.activityPresentation?.id == secondArtifact.id)
        #expect(model.hasActiveActivityPresentation)
        #expect(FileManager.default.fileExists(atPath: secondDirectoryURL.path))
        #expect(secondRemovalRecorder.removalCount == 0)

        model.activityPresentationDidEnd(expectedArtifactID: secondArtifact.id)
        try await Self.waitUntilDirectoryIsRemoved(secondDirectoryURL)
        #expect(secondRemovalRecorder.removalCount == 1)
    }

    @MainActor
    @Test func everyShareKindUsesOneSystemNativeFileURLActivityItem() throws {
        let cases: [(TAPNAPShareArtifact.Kind, String)] = [
            (.tapnapPackage, "TAPNAP-Capture.tapnap"),
            (.image, "TAPNAP-Photo.heic"),
            (.video, "TAPNAP-Video.mp4")
        ]

        for (kind, filename) in cases {
            let directoryURL = try TAPCamDemoTestFixtures.makeTemporaryDirectory()
            let fileURL = directoryURL.appendingPathComponent(filename)
            try Data(kind.rawValue.utf8).write(to: fileURL)
            let artifact = TAPNAPShareArtifact(
                id: UUID(),
                kind: kind,
                fileURL: fileURL,
                temporaryDirectoryURL: directoryURL,
                warnings: []
            )

            let items = TAPShareActivityPresentation.activityItems(for: artifact)

            #expect(items.count == 1)
            #expect(items.first as? URL == fileURL)
            artifact.removeTemporaryDirectory()
        }
    }

    @Test func abandonedShareArtifactLeaseRemovesTemporaryDirectory() throws {
        let artifactDirectoryURL = try TAPCamDemoTestFixtures.makeTemporaryDirectory()
        let artifactURL = artifactDirectoryURL.appendingPathComponent("TAPNAP-Capture.tapnap")
        try Data("abandoned-package".utf8).write(to: artifactURL)

        var artifact: TAPNAPShareArtifact? = TAPNAPShareArtifact(
            id: UUID(),
            kind: .tapnapPackage,
            fileURL: artifactURL,
            temporaryDirectoryURL: artifactDirectoryURL,
            warnings: []
        )
        #expect(artifact != nil)
        #expect(FileManager.default.fileExists(atPath: artifactDirectoryURL.path))

        artifact = nil

        #expect(!FileManager.default.fileExists(atPath: artifactDirectoryURL.path))
    }

    @MainActor
    @Test func cancellationBeforePendingHandoffCleansReturnedArtifactExactlyOnce() async throws {
        let record = TAPCamDemoTestFixtures.samplePendingRecord(
            captureID: "cancel-after-build",
            capturedAt: Date(timeIntervalSince1970: 1_750_000_000),
            status: .waitingNetwork,
            signedPhotoFilename: nil
        )
        let resolver = DepthAnalysisShareRecordResolver(
            captureLoader: { _ in record },
            assetLoader: { _ in nil }
        )
        let gate = ShareArtifactReturnGate()
        let artifactDirectoryURL = try TAPCamDemoTestFixtures.makeTemporaryDirectory()
        let artifactURL = artifactDirectoryURL.appendingPathComponent("TAPNAP-Photo.heic")
        try Data("opaque-share".utf8).write(to: artifactURL)
        let removalRecorder = ShareTemporaryDirectoryRemovalRecorder()
        let artifact = TAPNAPShareArtifact(
            id: UUID(),
            kind: .image,
            fileURL: artifactURL,
            temporaryDirectoryURL: artifactDirectoryURL,
            warnings: [],
            temporaryDirectoryRemover: { url in
                try removalRecorder.remove(url)
            }
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
        let model = DepthAnalysisShareCoordinator(
            subject: DepthAnalysisShareSubject(
                id: "cancel-after-build",
                mediaID: .tapCapture(record.captureID),
                captureID: record.captureID,
                assetID: nil
            ),
            originalResource: try Self.makePhotoResource(
                origin: .pendingCapture(
                    captureID: record.captureID,
                    selectedSignedPhoto: false
                )
            ),
            recordResolver: resolver,
            artifactPreparer: preparer,
            localIntegrityValidator: ShareLocalIntegrityValidatorStub.unexpected
        )

        await model.refreshCertification()
        model.prepare(.image)
        await gate.waitUntilArtifactIsReady()
        model.cancelPreparation()
        await gate.releaseArtifact()

        try await Self.waitUntilDirectoryIsRemoved(artifactDirectoryURL)
        #expect(removalRecorder.removalCount == 1)
        #expect(!model.isPreparing)
        #expect(model.activityPresentation == nil)
        #expect(!model.hasActiveActivityPresentation)
    }

    private static func waitUntilDirectoryIsRemoved(_ directoryURL: URL) async throws {
        for _ in 0..<100 {
            if !FileManager.default.fileExists(atPath: directoryURL.path) {
                return
            }
            try await Task.sleep(for: .milliseconds(5))
        }
        Issue.record("Expected Share artifact directory to be removed")
    }

    private static func pendingPhotoSubject(
        captureID: String
    ) -> DepthAnalysisShareSubject {
        DepthAnalysisShareSubject(
            id: captureID,
            mediaID: .tapCapture(captureID),
            captureID: captureID,
            assetID: nil,
            usesPendingCaptureResource: true
        )
    }

    private static func makePhotoResource(
        origin: TAPPhotoOriginalResourceOrigin,
        mediaID: LibraryMediaID? = nil,
        expectsPairedVideo: Bool = false
    ) throws -> DepthAnalysisShareOriginalResource {
        let directoryURL = try TAPCamDemoTestFixtures.makeTemporaryDirectory()
        let photoURL = directoryURL.appendingPathComponent("primary-photo.heic")
        try Data("opaque-viewer-original".utf8).write(to: photoURL)
        let pairedVideoURL: URL?
        if expectsPairedVideo {
            let url = directoryURL.appendingPathComponent("paired-video.mov")
            try Data("opaque-paired-video".utf8).write(to: url)
            pairedVideoURL = url
        } else {
            pairedVideoURL = nil
        }
        let resolvedMediaID: LibraryMediaID
        if let mediaID {
            resolvedMediaID = mediaID
        } else {
            switch origin {
            case .photosAsset(let assetID):
                resolvedMediaID = .photosAsset(assetID)
            case .pendingCapture(let captureID, _):
                resolvedMediaID = .tapCapture(captureID)
            }
        }
        return .photo(try TAPPhotoOriginalResourceLease(
            mediaID: resolvedMediaID,
            origin: origin,
            photoURL: photoURL,
            pairedVideoURL: pairedVideoURL,
            photoFileExtension: "heic",
            photoMediaType: "public.heic",
            fileContainerHint: .heic,
            expectsPairedVideo: expectsPairedVideo,
            ownedTemporaryDirectoryURL: directoryURL
        ))
    }

    private enum TestError: Error, Equatable {
        case missingCapture
        case unexpectedCaptureLookup
        case unexpectedAssetLookup
        case unexpectedPackagePreparation
        case unexpectedSignedImagePolicy
    }
}

private enum ShareLocalIntegrityStubError: Error {
    case mismatch
    case unexpectedValidation
}

private nonisolated final class ShareTemporaryDirectoryRemovalRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var removalCount: Int {
        lock.withLock { count }
    }

    func remove(_ directoryURL: URL) throws {
        lock.withLock {
            count += 1
        }
        try FileManager.default.removeItem(at: directoryURL)
    }
}

private nonisolated struct ShareLocalIntegrityValidatorStub:
    DepthAnalysisShareLocalIntegrityValidating {
    typealias Operation = @Sendable (
        DepthAnalysisShareOriginalResource,
        String?,
        UUID?
    ) async throws -> Void

    let operation: Operation

    static let succeeding = Self { _, _, _ in }
    static let unexpected = Self { _, _, _ in
        throw ShareLocalIntegrityStubError.unexpectedValidation
    }

    init(operation: @escaping Operation) {
        self.operation = operation
    }

    func validate(
        resource: DepthAnalysisShareOriginalResource,
        expectedCaptureID: String?,
        expectedPackageID: UUID?
    ) async throws {
        try await operation(resource, expectedCaptureID, expectedPackageID)
    }
}

private actor ShareLocalIntegrityInvocationRecorder {
    private var invocationCount = 0
    private var expectedCaptureID: String?
    private var expectedPackageID: UUID?
    private var mediaKind: DepthAnalysisShareMediaKind?

    func record(
        resource: DepthAnalysisShareOriginalResource,
        expectedCaptureID: String?,
        expectedPackageID: UUID?
    ) {
        invocationCount += 1
        self.expectedCaptureID = expectedCaptureID
        self.expectedPackageID = expectedPackageID
        mediaKind = resource.mediaKind
    }

    func count() -> Int {
        invocationCount
    }

    func lastExpectedCaptureID() -> String? {
        expectedCaptureID
    }
}

private actor ShareLocalIntegrityStaleResultGate {
    private var count = 0
    private var firstValidationStarted = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var firstReleaseContinuation: CheckedContinuation<Void, Never>?

    func validate(
        resource: DepthAnalysisShareOriginalResource,
        expectedCaptureID: String?,
        expectedPackageID: UUID?
    ) async throws {
        _ = resource
        _ = expectedCaptureID
        _ = expectedPackageID
        count += 1
        guard count == 1 else {
            return
        }

        firstValidationStarted = true
        let waiters = startWaiters
        startWaiters.removeAll()
        waiters.forEach { $0.resume() }
        await withCheckedContinuation { continuation in
            firstReleaseContinuation = continuation
        }
        throw ShareLocalIntegrityStubError.mismatch
    }

    func waitUntilFirstValidationStarts() async {
        guard !firstValidationStarted else {
            return
        }
        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }

    func releaseFirstValidationAsMismatch() {
        firstReleaseContinuation?.resume()
        firstReleaseContinuation = nil
    }

    func invocationCount() -> Int {
        count
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

private actor ShareRecordRefreshGate {
    private let initialRecord: TAPPendingCaptureRecord
    private let refreshedRecord: TAPPendingCaptureRecord
    private var loadCount = 0
    private var refreshStarted = false
    private var refreshStartWaiters: [CheckedContinuation<Void, Never>] = []
    private var refreshReleaseContinuation: CheckedContinuation<Void, Never>?

    init(
        initialRecord: TAPPendingCaptureRecord,
        refreshedRecord: TAPPendingCaptureRecord
    ) {
        self.initialRecord = initialRecord
        self.refreshedRecord = refreshedRecord
    }

    func load() async -> TAPPendingCaptureRecord {
        loadCount += 1
        guard loadCount > 1 else {
            return initialRecord
        }

        refreshStarted = true
        let waiters = refreshStartWaiters
        refreshStartWaiters.removeAll()
        waiters.forEach { $0.resume() }
        await withCheckedContinuation { continuation in
            refreshReleaseContinuation = continuation
        }
        return refreshedRecord
    }

    func waitUntilRefreshStarts() async {
        guard !refreshStarted else {
            return
        }
        await withCheckedContinuation { continuation in
            refreshStartWaiters.append(continuation)
        }
    }

    func releaseRefresh() {
        refreshReleaseContinuation?.resume()
        refreshReleaseContinuation = nil
    }
}

private actor SharePreparationInvocationCounter {
    private var count = 0

    func increment() {
        count += 1
    }

    func value() -> Int {
        count
    }
}

private nonisolated struct CountingShareArtifactPreparer: DepthAnalysisShareArtifactPreparing {
    let counter: SharePreparationInvocationCounter

    func preparePackage(
        request: TAPNAPShareResourceRequest,
        progress: @escaping TAPNAPShareArtifactBuilder.ProgressHandler
    ) async throws -> TAPNAPShareArtifact {
        await counter.increment()
        throw TAPNAPShareArtifactError.shareResourceUnavailable
    }

    func prepareImage(
        request: TAPNAPShareResourceRequest,
        requiresSignedPhoto: Bool,
        progress: @escaping TAPNAPShareArtifactBuilder.ProgressHandler
    ) async throws -> TAPNAPShareArtifact {
        await counter.increment()
        throw TAPNAPShareArtifactError.shareResourceUnavailable
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

private nonisolated struct RegressingProgressShareArtifactPreparerStub:
    DepthAnalysisShareArtifactPreparing {
    func preparePackage(
        request: TAPNAPShareResourceRequest,
        progress: @escaping TAPNAPShareArtifactBuilder.ProgressHandler
    ) async throws -> TAPNAPShareArtifact {
        progress(0.8)
        progress(0.3)
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
