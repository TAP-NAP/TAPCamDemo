//
//  TAPPhotoOriginalResourceTests.swift
//  TAPCamDemoTests
//

import Foundation
import Testing
@testable import TAPCamDemo

@Suite(.serialized)
struct TAPPhotoOriginalResourceTests {
    @MainActor
    @Test func ownerReleaseKeepsFilesAliveUntilShareLeaseReleases() throws {
        let directory = try TAPCamDemoTestFixtures.makeTemporaryDirectory()
        let photoURL = directory.appendingPathComponent("original.heic")
        try Data("photo-original".utf8).write(to: photoURL)

        var loadedLease: TAPPhotoOriginalResourceLease? = try TAPPhotoOriginalResourceLease(
            mediaID: .photosAsset("asset-a"),
            origin: .photosAsset(assetID: "asset-a"),
            photoURL: photoURL,
            pairedVideoURL: nil,
            photoFileExtension: "heic",
            photoMediaType: "public.heic",
            fileContainerHint: .heic,
            expectsPairedVideo: false,
            ownedTemporaryDirectoryURL: directory
        )
        let owner = TAPPhotoOriginalResourceOwner()
        owner.install(try #require(loadedLease))
        loadedLease = nil

        var shareLease = owner.acquireLease()
        #expect(shareLease != nil)
        owner.clear()

        #expect(!owner.isReady)
        #expect(FileManager.default.fileExists(atPath: photoURL.path))
        #expect(try Data(contentsOf: try #require(shareLease).photoURL) == Data("photo-original".utf8))

        shareLease = nil
        #expect(!FileManager.default.fileExists(atPath: directory.path))
    }

    @Test func completeLivePhotoLeaseRequiresNonemptyPairedMovie() throws {
        let missingMovieDirectory = try TAPCamDemoTestFixtures.makeTemporaryDirectory()
        let missingMoviePhotoURL = missingMovieDirectory.appendingPathComponent("photo.heic")
        try Data("photo".utf8).write(to: missingMoviePhotoURL)
        defer {
            try? FileManager.default.removeItem(at: missingMovieDirectory)
        }

        #expect(throws: TAPPhotoOriginalResourceError.livePhotoPairedVideoMissing) {
            _ = try TAPPhotoOriginalResourceLease(
                mediaID: .photosAsset("live-a"),
                origin: .photosAsset(assetID: "live-a"),
                photoURL: missingMoviePhotoURL,
                pairedVideoURL: nil,
                photoFileExtension: "heic",
                photoMediaType: "public.heic",
                fileContainerHint: .heic,
                expectsPairedVideo: true,
                ownedTemporaryDirectoryURL: missingMovieDirectory
            )
        }

        let emptyMovieDirectory = try TAPCamDemoTestFixtures.makeTemporaryDirectory()
        let emptyMoviePhotoURL = emptyMovieDirectory.appendingPathComponent("photo.heic")
        let emptyMovieURL = emptyMovieDirectory.appendingPathComponent("paired-video.mov")
        try Data("photo".utf8).write(to: emptyMoviePhotoURL)
        try Data().write(to: emptyMovieURL)
        defer {
            try? FileManager.default.removeItem(at: emptyMovieDirectory)
        }

        #expect(throws: TAPPhotoOriginalResourceError.emptyPairedVideo) {
            _ = try TAPPhotoOriginalResourceLease(
                mediaID: .photosAsset("live-b"),
                origin: .photosAsset(assetID: "live-b"),
                photoURL: emptyMoviePhotoURL,
                pairedVideoURL: emptyMovieURL,
                photoFileExtension: "heic",
                photoMediaType: "public.heic",
                fileContainerHint: .heic,
                expectsPairedVideo: true,
                ownedTemporaryDirectoryURL: emptyMovieDirectory
            )
        }
    }

    @Test func leaseRejectsAResourceSymlinkThatEscapesItsOwnedDirectory() throws {
        let ownedDirectory = try TAPCamDemoTestFixtures.makeTemporaryDirectory()
        let externalDirectory = try TAPCamDemoTestFixtures.makeTemporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: ownedDirectory)
            try? FileManager.default.removeItem(at: externalDirectory)
        }
        let externalPhotoURL = externalDirectory.appendingPathComponent("external.heic")
        try Data("external-photo".utf8).write(to: externalPhotoURL)
        let linkedPhotoURL = ownedDirectory.appendingPathComponent("original.heic")
        try FileManager.default.createSymbolicLink(
            at: linkedPhotoURL,
            withDestinationURL: externalPhotoURL
        )

        #expect(throws: TAPPhotoOriginalResourceError.invalidOwnedDirectory) {
            _ = try TAPPhotoOriginalResourceLease(
                mediaID: .photosAsset("asset-symlink"),
                origin: .photosAsset(assetID: "asset-symlink"),
                photoURL: linkedPhotoURL,
                pairedVideoURL: nil,
                photoFileExtension: "heic",
                photoMediaType: "public.heic",
                fileContainerHint: .heic,
                expectsPairedVideo: false,
                ownedTemporaryDirectoryURL: ownedDirectory
            )
        }
    }

    @Test func loaderBuildsFileBackedPhotosLeaseAndCleansRejectedLiveResource() async throws {
        let successfulDirectory = try TAPCamDemoTestFixtures.makeTemporaryDirectory()
        var successfulLease: TAPPhotoOriginalResourceLease? = try await TAPPhotoOriginalResourceLoader(
            photoLibraryLoader: { assetID, includesPairedVideo, outputDirectory, progress in
                #expect(assetID == "asset-ready")
                #expect(!includesPairedVideo)
                let photoURL = outputDirectory.appendingPathComponent("source-photo.heic")
                try Data("photos-original".utf8).write(to: photoURL)
                progress(1)
                return PhotoLibraryWriter.OriginalShareResources(
                    photoURL: photoURL,
                    photoFileExtension: "heic",
                    photoMediaType: "public.heic",
                    pairedVideoURL: nil,
                    temporaryDirectoryURL: outputDirectory,
                    presentationAdjustmentResourceLabels: ["adjustmentData"]
                )
            },
            pendingLoader: Self.unexpectedPendingLoader,
            directoryProvider: { successfulDirectory },
            resourceProtector: { _ in }
        ).load(TAPPhotoOriginalResourceRequest(
            // An exported TAP capture keeps its capture identity even though
            // the original bytes now come from a Photos asset.
            mediaID: .tapCapture("owned-capture"),
            source: .photosAsset("asset-ready"),
            expectsPairedVideo: false
        ))

        #expect(successfulLease?.origin == .photosAsset(assetID: "asset-ready"))
        #expect(successfulLease?.mediaID == .tapCapture("owned-capture"))
        #expect(successfulLease?.presentationAdjustmentResourceLabels == ["adjustmentData"])
        #expect(try Data(contentsOf: try #require(successfulLease).photoURL) == Data("photos-original".utf8))
        successfulLease = nil
        #expect(!FileManager.default.fileExists(atPath: successfulDirectory.path))

        let incompleteLiveDirectory = try TAPCamDemoTestFixtures.makeTemporaryDirectory()
        await #expect(throws: TAPPhotoOriginalResourceError.livePhotoPairedVideoMissing) {
            _ = try await TAPPhotoOriginalResourceLoader(
                photoLibraryLoader: { _, _, outputDirectory, _ in
                    let photoURL = outputDirectory.appendingPathComponent("source-photo.heic")
                    try Data("photos-original".utf8).write(to: photoURL)
                    return PhotoLibraryWriter.OriginalShareResources(
                        photoURL: photoURL,
                        photoFileExtension: "heic",
                        photoMediaType: "public.heic",
                        pairedVideoURL: nil,
                        temporaryDirectoryURL: outputDirectory,
                        presentationAdjustmentResourceLabels: []
                    )
                },
                pendingLoader: Self.unexpectedPendingLoader,
                directoryProvider: { incompleteLiveDirectory },
                resourceProtector: { _ in }
            ).load(TAPPhotoOriginalResourceRequest(
                mediaID: .photosAsset("asset-live"),
                source: .photosAsset("asset-live"),
                expectsPairedVideo: true
            ))
        }
        #expect(!FileManager.default.fileExists(atPath: incompleteLiveDirectory.path))
    }

    @Test func pendingLoaderReportsWhetherItsAtomicSnapshotSelectedSignedBytes() async throws {
        let outputDirectory = try TAPCamDemoTestFixtures.makeTemporaryDirectory()
        var lease: TAPPhotoOriginalResourceLease? = try await TAPPhotoOriginalResourceLoader(
            photoLibraryLoader: Self.unexpectedPhotoLibraryLoader,
            pendingLoader: { captureID, includesPairedVideo, directory, progress in
                #expect(captureID == "pending-signed")
                #expect(includesPairedVideo)
                let photoURL = directory.appendingPathComponent("source-photo.jpg")
                let movieURL = directory.appendingPathComponent("source-paired-video.mov")
                try Data("signed-jpg".utf8).write(to: photoURL)
                try Data("paired-movie".utf8).write(to: movieURL)
                progress(1)
                return TAPPendingCaptureShareResourceSnapshot(
                    photoURL: photoURL,
                    pairedVideoURL: movieURL,
                    fileContainer: .jpeg,
                    selectedSignedPhoto: true
                )
            },
            directoryProvider: { outputDirectory },
            resourceProtector: { _ in }
        ).load(TAPPhotoOriginalResourceRequest(
            mediaID: .tapCapture("pending-signed"),
            source: .pendingCapture("pending-signed"),
            expectsPairedVideo: true
        ))

        #expect(
            lease?.origin
                == .pendingCapture(captureID: "pending-signed", selectedSignedPhoto: true)
        )
        #expect(lease?.mediaID == .tapCapture("pending-signed"))
        #expect(lease?.fileContainerHint == .jpeg)
        #expect(lease?.pairedVideoURL != nil)
        lease = nil
        #expect(!FileManager.default.fileExists(atPath: outputDirectory.path))
    }

    @Test func localValidatorRoutesSelfDescribedStillWithoutPendingRecord() throws {
        let manifest = TAPDepthManifest(payload: TAPCamDemoTestFixtures.samplePayload(
            id: "self-described-still",
            capturedAt: "2026-08-13T00:00:00.000Z",
            location: nil
        ))
        let photoData = try TAPCaptureProvenanceWriter().writeManifest(
            manifest,
            into: TAPCaptureProvenanceTestFixtures.sampleHEICSourceData()
        ).data
        let directory = try TAPCamDemoTestFixtures.makeTemporaryDirectory()
        let photoURL = directory.appendingPathComponent("original.heic")
        try photoData.write(to: photoURL)
        let lease = try TAPPhotoOriginalResourceLease(
            mediaID: .photosAsset("photos-only-no-record"),
            origin: .photosAsset(assetID: "photos-only-no-record"),
            photoURL: photoURL,
            pairedVideoURL: nil,
            photoFileExtension: "heic",
            photoMediaType: "public.heic",
            fileContainerHint: nil,
            expectsPairedVideo: false,
            ownedTemporaryDirectoryURL: directory
        )

        let result = try TAPPhotoLocalIntegrityValidator(
            localValidator: TAPSignedPhotoResourceValidator(
                validateStillPhoto: { data, captureID, profile in
                    #expect(data == photoData)
                    #expect(captureID == "self-described-still")
                    #expect(profile.fileContainer == .heic)
                    return ValidatedTAPDepthPhoto(
                        data: data,
                        manifest: manifest,
                        fileContainer: .heic
                    )
                },
                validateLivePhoto: { _, _, _, _ in
                    throw TestError.unexpectedRoute
                },
                validateLivePhotoPrimaryPhoto: { _, _, _ in
                    throw TestError.unexpectedRoute
                }
            )
        ).validate(lease)

        #expect(result.captureID == "self-described-still")
        #expect(result.mediaKind == .photo)
        #expect(result.fileContainer == .heic)
    }

    @Test func localValidatorRoutesLivePhotoAndRequiresTheActualMovie() throws {
        let livePhoto = TAPDepthManifest.LivePhoto(
            presence: "paired-video",
            pairedVideoFilename: "paired-video.mov",
            durationSeconds: 1.5,
            photoDisplayTimeSeconds: 0.75,
            width: 1920,
            height: 1440,
            videoCodec: "hvc1",
            audio: "not-captured"
        )
        let manifest = TAPDepthManifest(
            payload: TAPCamDemoTestFixtures.samplePayload(
                id: "self-described-live",
                capturedAt: "2026-08-13T00:00:00.000Z",
                location: nil,
                livePhoto: livePhoto
            ),
            schema: .livePhoto
        )
        let photoData = try TAPCaptureProvenanceWriter().writeManifest(
            manifest,
            into: TAPCaptureProvenanceTestFixtures.sampleHEICSourceData()
        ).data
        let directory = try TAPCamDemoTestFixtures.makeTemporaryDirectory()
        let photoURL = directory.appendingPathComponent("original.heic")
        let movieURL = directory.appendingPathComponent("paired-video.mov")
        try photoData.write(to: photoURL)
        try Data("expected-live-movie".utf8).write(to: movieURL)
        let lease = try TAPPhotoOriginalResourceLease(
            mediaID: .photosAsset("live-no-record"),
            origin: .photosAsset(assetID: "live-no-record"),
            photoURL: photoURL,
            pairedVideoURL: movieURL,
            photoFileExtension: "heic",
            photoMediaType: "public.heic",
            fileContainerHint: .heic,
            expectsPairedVideo: true,
            ownedTemporaryDirectoryURL: directory
        )

        let result = try TAPPhotoLocalIntegrityValidator(
            localValidator: TAPSignedPhotoResourceValidator(
                validateStillPhoto: { _, _, _ in
                    throw TestError.unexpectedRoute
                },
                validateLivePhoto: { data, receivedMovieURL, captureID, profile in
                    #expect(data == photoData)
                    #expect(receivedMovieURL == movieURL)
                    #expect(captureID == "self-described-live")
                    #expect(profile.fileContainer == .heic)
                    return ValidatedTAPLivePhoto(
                        photo: ValidatedTAPDepthPhoto(
                            data: data,
                            manifest: manifest,
                            fileContainer: .heic
                        ),
                        pairedVideoURL: receivedMovieURL
                    )
                },
                validateLivePhotoPrimaryPhoto: { _, _, _ in
                    throw TestError.unexpectedRoute
                }
            )
        ).validate(lease)

        #expect(result.mediaKind == .livePhoto)
        #expect(result.captureID == "self-described-live")
    }

    @Test func pendingPolicyKeepsNeedsRetryQueueOnly() {
        let capturedAt = Date(timeIntervalSince1970: 10)
        for status in [
            TAPPendingCaptureStatus.pending,
            .waitingNetwork,
            .signing,
            .failedRetryable
        ] {
            let record = TAPCamDemoTestFixtures.samplePendingRecord(
                captureID: status.rawValue,
                capturedAt: capturedAt,
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

        let terminal = TAPCamDemoTestFixtures.samplePendingRecord(
            captureID: "terminal",
            capturedAt: capturedAt,
            status: .failedTerminal,
            signedPhotoFilename: nil
        )
        #expect(
            TAPPendingPhotoSharePolicy.disposition(
                for: terminal,
                selectedSignedPhoto: false
            ) == .failed
        )

        let signed = TAPCamDemoTestFixtures.samplePendingRecord(
            captureID: "signed",
            capturedAt: capturedAt,
            status: .signed,
            signedPhotoFilename: "signed.heic"
        )
        #expect(
            TAPPendingPhotoSharePolicy.disposition(
                for: signed,
                selectedSignedPhoto: true
            )
                == .validateSignedOriginal
        )
        #expect(
            TAPPendingPhotoSharePolicy.disposition(
                for: signed,
                selectedSignedPhoto: false
            ) == .failed
        )
        #expect(
            TAPPendingPhotoSharePolicy.disposition(
                for: nil,
                selectedSignedPhoto: true
            ) == .failed
        )
    }

    @Test(.enabled(if: TAPCamDemoTestSourceInspection.isSourceTreeAvailable, "Source tree is unavailable on this runtime."))
    func resourceAndValidatorSourceHaveNoBackendVerificationDependency() throws {
        let source = try TAPCamDemoTestSourceInspection.source(
            relativePath: "TAPCamDemo/DepthAnalysis/TAPPhotoOriginalResource.swift"
        )
        #expect(source.contains("TAPSignedPhotoResourceValidator"))
        #expect(!source.contains("AppAttestCaptureSignatureVerifier"))
        #expect(!source.contains("/tapcam/capture-signatures/verify"))
        #expect(!source.contains("hasValidCredential(assetID:"))
        #expect(!source.contains("TAPNAPShareArtifactBuilder"))
    }

    private static let unexpectedPendingLoader: TAPPhotoOriginalResourceLoader.PendingLoader = {
        _, _, _, _ in
        throw TestError.unexpectedRoute
    }

    private static let unexpectedPhotoLibraryLoader: TAPPhotoOriginalResourceLoader.PhotoLibraryLoader = {
        _, _, _, _ in
        throw TestError.unexpectedRoute
    }
}

private enum TestError: Error {
    case unexpectedRoute
}
