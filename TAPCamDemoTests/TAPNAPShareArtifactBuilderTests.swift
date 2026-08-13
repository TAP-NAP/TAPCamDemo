//
//  TAPNAPShareArtifactBuilderTests.swift
//  TAPCamDemoTests
//

import Foundation
import Testing
import ZIPFoundation
@testable import TAPCamDemo

@Suite(.serialized)
struct TAPNAPShareArtifactBuilderTests {
    @Test func shareProgressCoalescerPreservesEndpointsAndBoundsCallbackFlood() async {
        let recorder = TAPNAPShareProgressRecorder()
        let coalescer = TAPShareProgressCoalescer(
            minimumInterval: .milliseconds(50),
            delivery: recorder.record
        )

        coalescer.submit(0)
        for sample in 1...10_000 {
            coalescer.submit(Double(sample) / 10_001)
        }
        coalescer.submit(1)
        await coalescer.finish()

        let values = recorder.snapshot().compactMap { $0 }
        #expect(values.first == 0)
        #expect(values.last == 1)
        #expect(values.count <= 3)
    }

    @Test func shareProgressCompletionDoesNotAddTheThrottleIntervalToFastWork() async {
        let recorder = TAPNAPShareProgressRecorder()
        let clock = ContinuousClock()
        let startedAt = clock.now
        let coalescer = TAPShareProgressCoalescer(
            minimumInterval: .seconds(5),
            delivery: recorder.record
        )

        coalescer.submit(0)
        coalescer.submit(1)
        await coalescer.finish()

        #expect(startedAt.duration(to: clock.now) < .seconds(1))
        #expect(recorder.snapshot().compactMap { $0 } == [0, 1])
    }

    @Test func shareProgressCoalescerDeliversNewestIntermediateAndDropsAfterCancel() async throws {
        let recorder = TAPNAPShareProgressRecorder()
        let coalescer = TAPShareProgressCoalescer(
            minimumInterval: .milliseconds(20),
            delivery: recorder.record
        )

        coalescer.submit(0)
        for _ in 0..<20 where recorder.snapshot().isEmpty {
            try await Task.sleep(for: .milliseconds(2))
        }
        coalescer.submit(0.2)
        coalescer.submit(0.7)
        coalescer.submit(0.9)
        try await Task.sleep(for: .milliseconds(30))

        let beforeCancel = recorder.snapshot().compactMap { $0 }
        #expect(beforeCancel.last == 0.9)
        coalescer.submit(0.95)
        coalescer.cancel()
        try await Task.sleep(for: .milliseconds(30))
        #expect(recorder.snapshot().compactMap { $0 } == beforeCancel)
    }

    @Test func artifactCleanupRetriesTransientFailureAndRemainsIdempotent() throws {
        let directoryURL = try TAPCamDemoTestFixtures.makeTemporaryDirectory()
        let fileURL = directoryURL.appendingPathComponent("payload.tapnap")
        try Data("cleanup-retry".utf8).write(to: fileURL)
        let remover = TAPNAPTemporaryDirectoryRemovalStub(failuresRemaining: 2)
        let artifact = TAPNAPShareArtifact(
            id: UUID(),
            kind: .tapnapPackage,
            fileURL: fileURL,
            temporaryDirectoryURL: directoryURL,
            warnings: [],
            temporaryDirectoryRemover: remover.remove
        )

        artifact.removeTemporaryDirectory()
        artifact.removeTemporaryDirectory()

        #expect(remover.invocationCount == 3)
        #expect(!FileManager.default.fileExists(atPath: directoryURL.path))
    }

    @Test func artifactCleanupCanBeRetriedAfterAttemptBudgetIsExhausted() throws {
        let directoryURL = try TAPCamDemoTestFixtures.makeTemporaryDirectory()
        let fileURL = directoryURL.appendingPathComponent("payload.tapnap")
        try Data("cleanup-explicit-retry".utf8).write(to: fileURL)
        let remover = TAPNAPTemporaryDirectoryRemovalStub(failuresRemaining: 3)
        let artifact = TAPNAPShareArtifact(
            id: UUID(),
            kind: .tapnapPackage,
            fileURL: fileURL,
            temporaryDirectoryURL: directoryURL,
            warnings: [],
            temporaryDirectoryRemover: remover.remove
        )

        artifact.removeTemporaryDirectory()
        #expect(remover.invocationCount == 3)
        #expect(FileManager.default.fileExists(atPath: directoryURL.path))

        artifact.removeTemporaryDirectory()
        #expect(remover.invocationCount == 4)
        #expect(!FileManager.default.fileExists(atPath: directoryURL.path))
    }

    @Test func opaqueStillPhotoBuildsFixedUncompressedTapnapPackageWithoutValidation() async throws {
        let photoData = Data("opaque-not-an-image-or-manifest".utf8)
        let outputDirectoryURL = try TAPCamDemoTestFixtures.makeTemporaryDirectory()
        let request = TAPNAPShareResourceRequest(
            captureID: "signed-still",
            assetLocalIdentifier: nil,
            fileContainer: .heic,
            expectsPairedVideo: false,
            hasSignatureEvidence: true
        )
        let builder = TAPNAPShareArtifactBuilder(
            pendingSnapshotter: Self.pendingSnapshotter(
                photoData: photoData,
                fileContainer: .heic,
                pairedVideoData: nil,
                expectedRequiresSignedPhoto: true
            ),
            temporaryDirectoryProvider: { outputDirectoryURL }
        )

        let artifact = try await builder.prepareTapnapPackage(request: request)
        defer { artifact.removeTemporaryDirectory() }

        #expect(artifact.kind == .tapnapPackage)
        #expect(artifact.fileURL.lastPathComponent == "TAPNAP-Capture.tapnap")
        let archive = try Archive(url: artifact.fileURL, accessMode: .read)
        let entries = Array(archive)
        #expect(entries.map(\.path).sorted() == [
            "primary-photo.heic",
            "tapcam-export.json"
        ])
        #expect(entries.allSatisfy { !$0.isCompressed })

        let extractedDirectoryURL = try TAPCamDemoTestFixtures.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: extractedDirectoryURL) }
        try FileManager.default.unzipItem(
            at: artifact.fileURL,
            to: extractedDirectoryURL
        )
        #expect(
            try Data(contentsOf: extractedDirectoryURL.appendingPathComponent("primary-photo.heic"))
                == photoData
        )

        let sidecarData = try Data(
            contentsOf: extractedDirectoryURL.appendingPathComponent("tapcam-export.json")
        )
        let sidecar = try JSONDecoder().decode(
            TAPVerificationExportSidecar.self,
            from: sidecarData
        )
        let sidecarJSON = try #require(String(data: sidecarData, encoding: .utf8))
        #expect(sidecar.schemaID == "urn:tapnap:tapcam:verification-export:v1")
        #expect(sidecar.packageKind == TAPVerificationExport.Kind.stillPhoto.rawValue)
        #expect(sidecar.resources.map(\.role) == ["primaryPhoto"])
        for forbidden in [
            "captureID", "keyId", "keyID", "assertionObject", "bodySHA256", "proof", "hash"
        ] {
            #expect(!sidecarJSON.localizedCaseInsensitiveContains(forbidden))
        }
    }

    @Test func jpegPackagePreservesOpaquePhotoBytesAndUsesJPGEntry() async throws {
        let photoData = Data([0x01, 0x02, 0x03, 0x04])
        let outputDirectoryURL = try TAPCamDemoTestFixtures.makeTemporaryDirectory()
        let builder = TAPNAPShareArtifactBuilder(
            pendingSnapshotter: Self.pendingSnapshotter(
                photoData: photoData,
                fileContainer: .jpeg,
                pairedVideoData: nil,
                expectedRequiresSignedPhoto: true
            ),
            temporaryDirectoryProvider: { outputDirectoryURL }
        )
        let request = TAPNAPShareResourceRequest(
            captureID: "signed-jpeg",
            assetLocalIdentifier: nil,
            fileContainer: .jpeg,
            expectsPairedVideo: false,
            hasSignatureEvidence: true
        )

        let artifact = try await builder.prepareTapnapPackage(request: request)
        defer { artifact.removeTemporaryDirectory() }
        let extractedDirectoryURL = try TAPCamDemoTestFixtures.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: extractedDirectoryURL) }
        try FileManager.default.unzipItem(at: artifact.fileURL, to: extractedDirectoryURL)

        #expect(
            try Data(contentsOf: extractedDirectoryURL.appendingPathComponent("primary-photo.jpg"))
                == photoData
        )
    }

    @Test func livePhotoPackageContainsExactUncompressedPairAndSidecar() async throws {
        let photoData = Data("signed-live-photo".utf8)
        let movieData = Data("paired-live-video".utf8)
        let outputDirectoryURL = try TAPCamDemoTestFixtures.makeTemporaryDirectory()
        let builder = TAPNAPShareArtifactBuilder(
            pendingSnapshotter: Self.pendingSnapshotter(
                photoData: photoData,
                fileContainer: .heic,
                pairedVideoData: movieData,
                expectedRequiresSignedPhoto: true
            ),
            temporaryDirectoryProvider: { outputDirectoryURL }
        )
        let request = TAPNAPShareResourceRequest(
            captureID: "signed-live",
            assetLocalIdentifier: nil,
            fileContainer: .heic,
            expectsPairedVideo: true,
            hasSignatureEvidence: true
        )

        let artifact = try await builder.prepareTapnapPackage(request: request)
        defer { artifact.removeTemporaryDirectory() }
        let archive = try Archive(url: artifact.fileURL, accessMode: .read)
        let entries = Array(archive)
        #expect(entries.map(\.path).sorted() == [
            "paired-video.mov",
            "primary-photo.heic",
            "tapcam-export.json"
        ])
        #expect(entries.allSatisfy { !$0.isCompressed })

        let extractedDirectoryURL = try TAPCamDemoTestFixtures.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: extractedDirectoryURL) }
        try FileManager.default.unzipItem(at: artifact.fileURL, to: extractedDirectoryURL)
        #expect(
            try Data(contentsOf: extractedDirectoryURL.appendingPathComponent("primary-photo.heic"))
                == photoData
        )
        #expect(
            try Data(contentsOf: extractedDirectoryURL.appendingPathComponent("paired-video.mov"))
                == movieData
        )
        let sidecar = try JSONDecoder().decode(
            TAPVerificationExportSidecar.self,
            from: Data(contentsOf: extractedDirectoryURL.appendingPathComponent("tapcam-export.json"))
        )
        #expect(sidecar.packageKind == TAPVerificationExport.Kind.livePhotoPackage.rawValue)
        #expect(sidecar.resources.map(\.role) == ["primaryPhoto", "pairedLivePhotoVideo"])
    }

    @Test func packagePublishesMonotonicByteProgressWhileWritingZIP() async throws {
        let photoData = Data(repeating: 0xA5, count: 2 * 1_024 * 1_024)
        let outputDirectoryURL = try TAPCamDemoTestFixtures.makeTemporaryDirectory()
        let progressRecorder = TAPNAPShareProgressRecorder()
        let builder = TAPNAPShareArtifactBuilder(
            pendingSnapshotter: Self.pendingSnapshotter(
                photoData: photoData,
                fileContainer: .heic,
                pairedVideoData: nil,
                expectedRequiresSignedPhoto: true
            ),
            temporaryDirectoryProvider: { outputDirectoryURL }
        )
        let request = TAPNAPShareResourceRequest(
            captureID: "progress-still",
            assetLocalIdentifier: nil,
            fileContainer: .heic,
            expectsPairedVideo: false,
            hasSignatureEvidence: true
        )

        let artifact = try await builder.prepareTapnapPackage(
            request: request,
            progress: { progressRecorder.record($0) }
        )
        defer { artifact.removeTemporaryDirectory() }

        let progressValues = progressRecorder.snapshot().compactMap { $0 }
        #expect(progressValues.first == 0)
        #expect(progressValues.last == 1)
        #expect(
            progressValues.elementsEqual(
                progressValues.sorted(),
                by: { abs($0 - $1) < 0.000_001 }
            )
        )
        let zipProgressValues = progressValues.filter { value in
            value > TAPNAPShareArtifactBuilder.archiveProgressOffsetForPresentation
                && value < 0.96
        }
        #expect(progressValues.count <= 24)
        #expect(zipProgressValues.count <= 20)
    }

    @Test func livePhotoWithoutPairedMovieFailsAndRemovesSessionDirectory() async throws {
        let outputDirectoryURL = try TAPCamDemoTestFixtures.makeTemporaryDirectory()
        let builder = TAPNAPShareArtifactBuilder(
            pendingSnapshotter: Self.pendingSnapshotter(
                photoData: Data("signed-live-photo".utf8),
                fileContainer: .heic,
                pairedVideoData: nil,
                expectedRequiresSignedPhoto: true
            ),
            temporaryDirectoryProvider: { outputDirectoryURL }
        )
        let request = TAPNAPShareResourceRequest(
            captureID: "missing-live-movie",
            assetLocalIdentifier: nil,
            fileContainer: .heic,
            expectsPairedVideo: true,
            hasSignatureEvidence: true
        )

        await #expect(throws: TAPNAPShareArtifactError.livePhotoPairedVideoMissing) {
            try await builder.prepareTapnapPackage(request: request)
        }
        #expect(!FileManager.default.fileExists(atPath: outputDirectoryURL.path))
    }

    @Test func packageRequiresDurableSignatureEvidenceBeforeLoadingResources() async throws {
        let outputDirectoryURL = try TAPCamDemoTestFixtures.makeTemporaryDirectory()
        let builder = TAPNAPShareArtifactBuilder(
            pendingSnapshotter: { _, _, _, _, _, _ in
                throw TAPNAPShareArtifactTestError.unexpectedResourceLoad
            },
            temporaryDirectoryProvider: { outputDirectoryURL }
        )
        let request = TAPNAPShareResourceRequest(
            captureID: "unsigned",
            assetLocalIdentifier: nil,
            fileContainer: .heic,
            expectsPairedVideo: false,
            hasSignatureEvidence: false
        )

        await #expect(throws: TAPNAPShareArtifactError.packageRequiresSignatureEvidence) {
            try await builder.prepareTapnapPackage(request: request)
        }
    }

    @Test func verifiedImageUsesSignedOnlyPolicyAndFriendlyFilename() async throws {
        let photoData = Data("signed-image".utf8)
        let outputDirectoryURL = try TAPCamDemoTestFixtures.makeTemporaryDirectory()
        let builder = TAPNAPShareArtifactBuilder(
            pendingSnapshotter: Self.pendingSnapshotter(
                photoData: photoData,
                fileContainer: .heic,
                pairedVideoData: nil,
                expectedRequiresSignedPhoto: true,
                expectedLinkPolicy: .requireIndependentFile
            ),
            temporaryDirectoryProvider: { outputDirectoryURL }
        )
        let request = TAPNAPShareResourceRequest(
            captureID: "verified-image",
            assetLocalIdentifier: nil,
            fileContainer: .heic,
            expectsPairedVideo: false,
            hasSignatureEvidence: true
        )

        let artifact = try await builder.prepareImage(
            request: request,
            requiresSignedPhoto: true
        )
        defer { artifact.removeTemporaryDirectory() }
        #expect(artifact.kind == .image)
        #expect(artifact.fileURL.lastPathComponent == "TAPNAP-Photo.heic")
        #expect(try Data(contentsOf: artifact.fileURL) == photoData)
    }

    @Test func photosOnlyImageUsesOriginalResourceExtensionAndWarning() async throws {
        let photoData = Data("photos-only-jpeg".utf8)
        let outputDirectoryURL = try TAPCamDemoTestFixtures.makeTemporaryDirectory()
        let builder = TAPNAPShareArtifactBuilder(
            photoLibraryResourceLoader: { _, preferredContainer, includesPairedVideo, resourcesURL, progress in
                guard preferredContainer == nil, !includesPairedVideo else {
                    throw TAPNAPShareArtifactTestError.unexpectedResourcePolicy
                }
                try FileManager.default.createDirectory(
                    at: resourcesURL,
                    withIntermediateDirectories: true
                )
                let photoURL = resourcesURL.appendingPathComponent("source-photo.jpg")
                try photoData.write(to: photoURL)
                progress(1)
                return PhotoLibraryWriter.OriginalShareResources(
                    photoURL: photoURL,
                    photoFileExtension: "jpg",
                    photoMediaType: "public.jpeg",
                    pairedVideoURL: nil,
                    temporaryDirectoryURL: resourcesURL,
                    presentationAdjustmentResourceLabels: ["adjustmentData"]
                )
            },
            temporaryDirectoryProvider: { outputDirectoryURL }
        )

        let artifact = try await builder.prepareImage(
            request: TAPNAPShareResourceRequest(assetLocalIdentifier: "photos-only"),
            requiresSignedPhoto: false
        )
        defer { artifact.removeTemporaryDirectory() }
        #expect(artifact.fileURL.lastPathComponent == "TAPNAP-Photo.jpg")
        #expect(try Data(contentsOf: artifact.fileURL) == photoData)
        #expect(artifact.warnings.first?.contains("adjustmentData") == true)
    }

    @Test func exportedStillPackageFallsBackFromCleanedLocalFilesToPhotosOriginal() async throws {
        let photoData = Data("exported-signed-still".utf8)
        let outputDirectoryURL = try TAPCamDemoTestFixtures.makeTemporaryDirectory()
        let builder = TAPNAPShareArtifactBuilder(
            pendingSnapshotter: { _, _, requiresSignedPhoto, _, _, _ in
                guard requiresSignedPhoto else {
                    throw TAPNAPShareArtifactTestError.unexpectedResourcePolicy
                }
                throw TAPDepthCaptureError.pendingCaptureDataMissing
            },
            photoLibraryResourceLoader: Self.photoLibraryResourceLoader(
                photoData: photoData,
                fileContainer: .heic,
                pairedVideoData: nil,
                expectedIncludesPairedVideo: false
            ),
            temporaryDirectoryProvider: { outputDirectoryURL }
        )
        let request = TAPNAPShareResourceRequest(
            captureID: "exported-still",
            assetLocalIdentifier: "photos-still",
            fileContainer: .heic,
            expectsPairedVideo: false,
            hasSignatureEvidence: true
        )

        let artifact = try await builder.prepareTapnapPackage(request: request)
        defer { artifact.removeTemporaryDirectory() }
        let extractedDirectoryURL = try TAPCamDemoTestFixtures.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: extractedDirectoryURL) }
        try FileManager.default.unzipItem(at: artifact.fileURL, to: extractedDirectoryURL)

        #expect(
            try Data(contentsOf: extractedDirectoryURL.appendingPathComponent("primary-photo.heic"))
                == photoData
        )
    }

    @Test func exportedLivePackageFallsBackToCompletePhotosOriginalPair() async throws {
        let photoData = Data("exported-live-photo".utf8)
        let pairedVideoData = Data("exported-live-video".utf8)
        let outputDirectoryURL = try TAPCamDemoTestFixtures.makeTemporaryDirectory()
        let builder = TAPNAPShareArtifactBuilder(
            pendingSnapshotter: { _, _, requiresSignedPhoto, includesPairedVideo, _, _ in
                guard requiresSignedPhoto, includesPairedVideo else {
                    throw TAPNAPShareArtifactTestError.unexpectedResourcePolicy
                }
                throw TAPDepthCaptureError.pendingCaptureDataMissing
            },
            photoLibraryResourceLoader: Self.photoLibraryResourceLoader(
                photoData: photoData,
                fileContainer: .heic,
                pairedVideoData: pairedVideoData,
                expectedIncludesPairedVideo: true
            ),
            temporaryDirectoryProvider: { outputDirectoryURL }
        )
        let legacyRecord = TAPCamDemoTestFixtures.samplePendingRecord(
            captureID: "exported-live",
            capturedAt: Date(timeIntervalSince1970: 1_750_000_000),
            status: .exported,
            signedHEICFilename: nil,
            pairedVideoFilename: nil,
            assetLocalIdentifier: "photos-live"
        )
        let request = TAPNAPShareResourceRequest(
            record: legacyRecord,
            expectsPairedVideo: true
        )

        #expect(request.expectsPairedVideo)
        #expect(request.prefersPhotoLibraryResources)

        let artifact = try await builder.prepareTapnapPackage(request: request)
        defer { artifact.removeTemporaryDirectory() }
        let extractedDirectoryURL = try TAPCamDemoTestFixtures.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: extractedDirectoryURL) }
        try FileManager.default.unzipItem(at: artifact.fileURL, to: extractedDirectoryURL)

        #expect(
            try Data(contentsOf: extractedDirectoryURL.appendingPathComponent("primary-photo.heic"))
                == photoData
        )
        #expect(
            try Data(contentsOf: extractedDirectoryURL.appendingPathComponent("paired-video.mov"))
                == pairedVideoData
        )
    }

    @Test func exportedLivePackageRejectsPhotosOriginalWithoutMovieAndCleansSession() async throws {
        let outputDirectoryURL = try TAPCamDemoTestFixtures.makeTemporaryDirectory()
        let builder = TAPNAPShareArtifactBuilder(
            pendingSnapshotter: { _, _, _, _, _, _ in
                throw TAPDepthCaptureError.pendingCaptureDataMissing
            },
            photoLibraryResourceLoader: Self.photoLibraryResourceLoader(
                photoData: Data("exported-live-photo".utf8),
                fileContainer: .heic,
                pairedVideoData: nil,
                expectedIncludesPairedVideo: true
            ),
            temporaryDirectoryProvider: { outputDirectoryURL }
        )
        let request = TAPNAPShareResourceRequest(
            captureID: "exported-live-missing-movie",
            assetLocalIdentifier: "photos-live-missing-movie",
            fileContainer: .heic,
            expectsPairedVideo: true,
            hasSignatureEvidence: true
        )

        await #expect(throws: TAPNAPShareArtifactError.livePhotoPairedVideoMissing) {
            try await builder.prepareTapnapPackage(request: request)
        }
        #expect(!FileManager.default.fileExists(atPath: outputDirectoryURL.path))
    }

    @Test func cancellationDuringExportedPhotosLoadRemovesSessionDirectory() async throws {
        let outputDirectoryURL = try TAPCamDemoTestFixtures.makeTemporaryDirectory()
        let builder = TAPNAPShareArtifactBuilder(
            pendingSnapshotter: { _, _, _, _, _, _ in
                throw TAPDepthCaptureError.pendingCaptureDataMissing
            },
            photoLibraryResourceLoader: { _, _, _, _, _ in
                try await Task.sleep(for: .seconds(10))
                throw TAPNAPShareArtifactTestError.unexpectedResourceLoad
            },
            temporaryDirectoryProvider: { outputDirectoryURL }
        )
        let request = TAPNAPShareResourceRequest(
            captureID: "cancelled-exported-share",
            assetLocalIdentifier: "photos-cancelled",
            fileContainer: .heic,
            expectsPairedVideo: false,
            hasSignatureEvidence: true
        )

        let task = Task {
            try await builder.prepareTapnapPackage(request: request)
        }
        await Task.yield()
        task.cancel()

        await #expect(throws: CancellationError.self) {
            _ = try await task.value
        }
        #expect(!FileManager.default.fileExists(atPath: outputDirectoryURL.path))
    }

    @Test func viewerLivePhotoLeaseBuildsPackageWithoutRefetchingAndPreservesExactPair() async throws {
        let photoBytes = Data("viewer-ready-photo".utf8)
        let pairedVideoBytes = Data("viewer-ready-paired-video".utf8)
        let sourceDirectoryURL = try TAPCamDemoTestFixtures.makeTemporaryDirectory()
        let photoURL = sourceDirectoryURL.appendingPathComponent("original.heic")
        let pairedVideoURL = sourceDirectoryURL.appendingPathComponent("original.mov")
        try photoBytes.write(to: photoURL)
        try pairedVideoBytes.write(to: pairedVideoURL)

        var lease: TAPPhotoOriginalResourceLease? = try TAPPhotoOriginalResourceLease(
            mediaID: .tapCapture("viewer-live"),
            origin: .pendingCapture(
                captureID: "viewer-live",
                selectedSignedPhoto: true
            ),
            photoURL: photoURL,
            pairedVideoURL: pairedVideoURL,
            photoFileExtension: "heic",
            photoMediaType: "public.heic",
            fileContainerHint: .heic,
            expectsPairedVideo: true,
            ownedTemporaryDirectoryURL: sourceDirectoryURL
        )
        var request: TAPNAPShareResourceRequest? = TAPNAPShareResourceRequest(
            originalResourceLease: try #require(lease),
            hasSignatureEvidence: true
        )
        let outputDirectoryURL = try TAPCamDemoTestFixtures.makeTemporaryDirectory()
        let builder = TAPNAPShareArtifactBuilder(
            pendingSnapshotter: { _, _, _, _, _, _ in
                throw TAPNAPShareArtifactTestError.unexpectedResourceLoad
            },
            photoLibraryResourceLoader: { _, _, _, _, _ in
                throw TAPNAPShareArtifactTestError.unexpectedResourceLoad
            },
            temporaryDirectoryProvider: { outputDirectoryURL }
        )

        let artifact = try await builder.prepareTapnapPackage(
            request: try #require(request)
        )
        defer { artifact.removeTemporaryDirectory() }
        request = nil
        lease = nil
        #expect(!FileManager.default.fileExists(atPath: sourceDirectoryURL.path))

        let extractedDirectoryURL = try TAPCamDemoTestFixtures.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: extractedDirectoryURL) }
        try FileManager.default.unzipItem(
            at: artifact.fileURL,
            to: extractedDirectoryURL
        )
        #expect(
            try Data(contentsOf: extractedDirectoryURL.appendingPathComponent("primary-photo.heic"))
                == photoBytes
        )
        #expect(
            try Data(contentsOf: extractedDirectoryURL.appendingPathComponent("paired-video.mov"))
                == pairedVideoBytes
        )
    }

    @Test func viewerPhotoLeaseDirectShareOwnsCopyAndCarriesVerifiabilityWarning() async throws {
        let photoBytes = Data(repeating: 0x5A, count: 1_100_000)
        let sourceDirectoryURL = try TAPCamDemoTestFixtures.makeTemporaryDirectory()
        let photoURL = sourceDirectoryURL.appendingPathComponent("original.jpg")
        try photoBytes.write(to: photoURL)

        var lease: TAPPhotoOriginalResourceLease? = try TAPPhotoOriginalResourceLease(
            mediaID: .photosAsset("viewer-photo"),
            origin: .photosAsset(assetID: "viewer-photo"),
            photoURL: photoURL,
            pairedVideoURL: nil,
            photoFileExtension: "jpg",
            photoMediaType: "public.jpeg",
            fileContainerHint: .jpeg,
            expectsPairedVideo: false,
            ownedTemporaryDirectoryURL: sourceDirectoryURL
        )
        let warning = "Verifiability is not guaranteed for this shared image."
        var request: TAPNAPShareResourceRequest? = TAPNAPShareResourceRequest(
            originalResourceLease: try #require(lease),
            hasSignatureEvidence: false,
            directShareVerifiabilityWarning: warning
        )
        let outputDirectoryURL = try TAPCamDemoTestFixtures.makeTemporaryDirectory()
        let builder = TAPNAPShareArtifactBuilder(
            pendingSnapshotter: { _, _, _, _, _, _ in
                throw TAPNAPShareArtifactTestError.unexpectedResourceLoad
            },
            photoLibraryResourceLoader: { _, _, _, _, _ in
                throw TAPNAPShareArtifactTestError.unexpectedResourceLoad
            },
            temporaryDirectoryProvider: { outputDirectoryURL }
        )

        let artifact = try await builder.prepareImage(
            request: try #require(request),
            requiresSignedPhoto: false
        )
        defer { artifact.removeTemporaryDirectory() }
        request = nil
        lease = nil

        #expect(!FileManager.default.fileExists(atPath: sourceDirectoryURL.path))
        #expect(try Data(contentsOf: artifact.fileURL) == photoBytes)
        #expect(artifact.warnings == [warning])
    }

    @Test func cancellationRemovesIncompleteSessionDirectory() async throws {
        let outputDirectoryURL = try TAPCamDemoTestFixtures.makeTemporaryDirectory()
        let builder = TAPNAPShareArtifactBuilder(
            pendingSnapshotter: { _, _, _, _, _, _ in
                try await Task.sleep(for: .seconds(10))
                throw TAPNAPShareArtifactTestError.unexpectedResourceLoad
            },
            temporaryDirectoryProvider: { outputDirectoryURL }
        )
        let request = TAPNAPShareResourceRequest(
            captureID: "cancelled-share",
            assetLocalIdentifier: nil,
            fileContainer: .heic,
            expectsPairedVideo: false,
            hasSignatureEvidence: true
        )

        let task = Task {
            try await builder.prepareTapnapPackage(request: request)
        }
        await Task.yield()
        task.cancel()

        do {
            _ = try await task.value
            Issue.record("Expected share preparation cancellation.")
        } catch is CancellationError {
            // Expected.
        } catch {
            Issue.record("Unexpected cancellation error: \(error)")
        }
        #expect(!FileManager.default.fileExists(atPath: outputDirectoryURL.path))
    }

    @Test func videoBuilderPreservesOpaqueMultiBufferMP4BytesAndProgress() async throws {
        let snapshotBufferSize = 512 * 1_024
        let byteCount = snapshotBufferSize * 3 + 137
        let opaqueBytes = Data((0..<byteCount).map { index in
            UInt8(truncatingIfNeeded: index &* 31 &+ 7)
        })
        let outputDirectoryURL = try TAPCamDemoTestFixtures.makeTemporaryDirectory()
        let progressRecorder = TAPNAPShareProgressRecorder()
        let builder = TAPVideoShareArtifactBuilder(
            pendingSnapshotter: { captureID, assetID, destinationURL, requiresSignedVideo, progress in
                guard captureID == "opaque-video",
                      assetID == nil,
                      !requiresSignedVideo else {
                    throw TAPNAPShareArtifactTestError.unexpectedResourcePolicy
                }
                try FileManager.default.createDirectory(
                    at: destinationURL,
                    withIntermediateDirectories: true
                )
                let videoURL = destinationURL.appendingPathComponent("source-video.mp4")
                guard FileManager.default.createFile(atPath: videoURL.path, contents: nil) else {
                    throw TAPNAPShareArtifactTestError.unexpectedResourceLoad
                }
                let handle = try FileHandle(forWritingTo: videoURL)
                do {
                    for offset in stride(from: 0, to: opaqueBytes.count, by: snapshotBufferSize) {
                        try Task.checkCancellation()
                        let end = min(offset + snapshotBufferSize, opaqueBytes.count)
                        try handle.write(contentsOf: opaqueBytes.subdata(in: offset..<end))
                        progress(Double(end) / Double(opaqueBytes.count))
                    }
                    try handle.synchronize()
                    try handle.close()
                } catch {
                    try? handle.close()
                    throw error
                }
                return TAPPendingVideoShareResourceSnapshot(videoURL: videoURL)
            },
            temporaryDirectoryProvider: { outputDirectoryURL }
        )
        let request = TAPVideoShareResourceRequest(
            captureID: "opaque-video",
            assetLocalIdentifier: nil,
            hasSignatureEvidence: false
        )

        let artifact = try await builder.prepareVideo(
            request: request,
            requiresSignedVideo: false,
            progress: { progressRecorder.record($0) }
        )
        defer { artifact.removeTemporaryDirectory() }

        #expect(artifact.kind == .video)
        #expect(artifact.fileURL.lastPathComponent == "TAPNAP-Video.mp4")
        #expect(try Data(contentsOf: artifact.fileURL) == opaqueBytes)
        let progress = progressRecorder.snapshot().compactMap { $0 }
        #expect(progress.first == 0)
        #expect(progress.last == 1)
        #expect(progress.count <= 24)
        #expect(
            progress.elementsEqual(
                progress.sorted(),
                by: { abs($0 - $1) < 0.000_001 }
            )
        )
    }

    @Test func videoBuilderFallsBackToPhotosOnlyWhenLocalSnapshotIsMissing() async throws {
        let photosBytes = Data("opaque-exported-video".utf8)
        let outputDirectoryURL = try TAPCamDemoTestFixtures.makeTemporaryDirectory()
        let routeRecorder = TAPVideoShareRouteRecorder()
        let builder = TAPVideoShareArtifactBuilder(
            pendingSnapshotter: { captureID, assetID, _, requiresSignedVideo, _ in
                routeRecorder.recordPending()
                guard captureID == "fallback-video",
                      assetID == "fallback-asset",
                      requiresSignedVideo else {
                    throw TAPNAPShareArtifactTestError.unexpectedResourcePolicy
                }
                throw TAPPendingVideoShareSnapshotError.sourceUnavailable
            },
            photoLibraryResourceLoader: { assetID, destinationURL, progress in
                routeRecorder.recordPhotos()
                guard assetID == "fallback-asset" else {
                    throw TAPNAPShareArtifactTestError.unexpectedResourcePolicy
                }
                return try Self.originalVideoShareResource(
                    bytes: photosBytes,
                    destinationURL: destinationURL,
                    progress: progress
                )
            },
            temporaryDirectoryProvider: { outputDirectoryURL }
        )

        let artifact = try await builder.prepareVideo(
            request: TAPVideoShareResourceRequest(
                captureID: "fallback-video",
                assetLocalIdentifier: "fallback-asset",
                hasSignatureEvidence: true
            ),
            requiresSignedVideo: true
        )
        defer { artifact.removeTemporaryDirectory() }

        #expect(routeRecorder.snapshot() == .init(pending: 1, photos: 1))
        #expect(try Data(contentsOf: artifact.fileURL) == photosBytes)
    }

    @Test func videoBuilderIdentityMismatchNeverFallsBackToPhotos() async throws {
        let outputDirectoryURL = try TAPCamDemoTestFixtures.makeTemporaryDirectory()
        let routeRecorder = TAPVideoShareRouteRecorder()
        let builder = TAPVideoShareArtifactBuilder(
            pendingSnapshotter: { _, _, _, _, _ in
                routeRecorder.recordPending()
                throw TAPPendingVideoShareSnapshotError.identityMismatch
            },
            photoLibraryResourceLoader: { _, _, _ in
                routeRecorder.recordPhotos()
                throw TAPNAPShareArtifactTestError.unexpectedResourceLoad
            },
            temporaryDirectoryProvider: { outputDirectoryURL }
        )

        await #expect(throws: TAPNAPShareArtifactError.shareResourceUnavailable) {
            _ = try await builder.prepareVideo(
                request: TAPVideoShareResourceRequest(
                    captureID: "identity-capture",
                    assetLocalIdentifier: "wrong-asset"
                ),
                requiresSignedVideo: false
            )
        }

        #expect(routeRecorder.snapshot() == .init(pending: 1, photos: 0))
        #expect(!FileManager.default.fileExists(atPath: outputDirectoryURL.path))
    }

    @Test func exportedVideoRequestPrefersPhotosWithoutTouchingCleanedLocalFiles() async throws {
        let photosBytes = Data("authoritative-exported-video".utf8)
        let outputDirectoryURL = try TAPCamDemoTestFixtures.makeTemporaryDirectory()
        let routeRecorder = TAPVideoShareRouteRecorder()
        let record = TAPCamDemoTestFixtures.samplePendingVideoRecord(
            captureID: "exported-video",
            capturedAt: Date(timeIntervalSince1970: 1_750_000_000),
            status: .exported,
            videoArtifactState: .signed,
            assetLocalIdentifier: "exported-asset"
        )
        let request = TAPVideoShareResourceRequest(record: record)
        #expect(request.prefersPhotoLibraryResource)

        let builder = TAPVideoShareArtifactBuilder(
            pendingSnapshotter: { _, _, _, _, _ in
                routeRecorder.recordPending()
                throw TAPNAPShareArtifactTestError.unexpectedResourceLoad
            },
            photoLibraryResourceLoader: { assetID, destinationURL, progress in
                routeRecorder.recordPhotos()
                guard assetID == "exported-asset" else {
                    throw TAPNAPShareArtifactTestError.unexpectedResourcePolicy
                }
                return try Self.originalVideoShareResource(
                    bytes: photosBytes,
                    destinationURL: destinationURL,
                    progress: progress
                )
            },
            temporaryDirectoryProvider: { outputDirectoryURL }
        )

        let artifact = try await builder.prepareVideo(
            request: request,
            requiresSignedVideo: true
        )
        defer { artifact.removeTemporaryDirectory() }

        #expect(routeRecorder.snapshot() == .init(pending: 0, photos: 1))
        #expect(try Data(contentsOf: artifact.fileURL) == photosBytes)
    }

    @Test func viewerVideoLeaseDirectShareOwnsCopyWithoutRefetchingAndCarriesWarning() async throws {
        let videoBytes = Data(repeating: 0xC3, count: 1_200_000)
        let sourceDirectoryURL = try TAPCamDemoTestFixtures.makeTemporaryDirectory()
        let sourceURL = sourceDirectoryURL.appendingPathComponent("original.mp4")
        try videoBytes.write(to: sourceURL)

        var owner: TAPVideoOriginalResourceOwner? = try TAPVideoOriginalResourceOwner(
            mediaID: .photosAsset("viewer-video"),
            origin: .photosAsset(assetID: "viewer-video"),
            fileURL: sourceURL,
            managedTemporaryFile: LibraryManagedTemporaryFile(
                fileURL: sourceURL,
                directoryURL: sourceDirectoryURL
            )
        )
        var lease: TAPVideoOriginalResourceLease? = owner?.acquireLease()
        let warning = "Verifiability is not guaranteed for this shared video."
        var request: TAPVideoShareResourceRequest? = TAPVideoShareResourceRequest(
            originalResourceLease: try #require(lease),
            hasSignatureEvidence: false,
            directShareVerifiabilityWarning: warning
        )
        let outputDirectoryURL = try TAPCamDemoTestFixtures.makeTemporaryDirectory()
        let progressRecorder = TAPNAPShareProgressRecorder()
        let builder = TAPVideoShareArtifactBuilder(
            pendingSnapshotter: { _, _, _, _, _ in
                throw TAPNAPShareArtifactTestError.unexpectedResourceLoad
            },
            photoLibraryResourceLoader: { _, _, _ in
                throw TAPNAPShareArtifactTestError.unexpectedResourceLoad
            },
            temporaryDirectoryProvider: { outputDirectoryURL }
        )

        let artifact = try await builder.prepareVideo(
            request: try #require(request),
            requiresSignedVideo: false,
            progress: { progressRecorder.record($0) }
        )
        defer { artifact.removeTemporaryDirectory() }
        request = nil
        lease = nil
        owner = nil

        #expect(!FileManager.default.fileExists(atPath: sourceDirectoryURL.path))
        #expect(try Data(contentsOf: artifact.fileURL) == videoBytes)
        #expect(artifact.warnings == [warning])
        let progress = progressRecorder.snapshot().compactMap { $0 }
        #expect(progress.first == 0)
        #expect(progress.last == 1)
        #expect(progress.count <= 24)
    }

    @Test func videoBuilderCancellationRemovesPartialSessionDirectory() async throws {
        let outputDirectoryURL = try TAPCamDemoTestFixtures.makeTemporaryDirectory()
        let gate = TAPVideoShareCancellationGate()
        let builder = TAPVideoShareArtifactBuilder(
            pendingSnapshotter: { _, _, destinationURL, _, _ in
                try FileManager.default.createDirectory(
                    at: destinationURL,
                    withIntermediateDirectories: true
                )
                let videoURL = destinationURL.appendingPathComponent("source-video.mp4")
                try Data("partial-video".utf8).write(to: videoURL)
                await gate.markStarted()
                try await Task.sleep(for: .seconds(30))
                return TAPPendingVideoShareResourceSnapshot(videoURL: videoURL)
            },
            temporaryDirectoryProvider: { outputDirectoryURL }
        )
        let task = Task {
            try await builder.prepareVideo(
                request: TAPVideoShareResourceRequest(
                    captureID: "cancel-video",
                    assetLocalIdentifier: nil
                ),
                requiresSignedVideo: false
            )
        }

        await gate.waitUntilStarted()
        task.cancel()

        await #expect(throws: CancellationError.self) {
            _ = try await task.value
        }
        #expect(!FileManager.default.fileExists(atPath: outputDirectoryURL.path))
    }

    private static func originalVideoShareResource(
        bytes: Data,
        destinationURL: URL,
        progress: TAPVideoShareArtifactBuilder.ProgressHandler
    ) throws -> PhotoLibraryWriter.OriginalVideoShareResource {
        try FileManager.default.createDirectory(
            at: destinationURL,
            withIntermediateDirectories: true
        )
        let videoURL = destinationURL.appendingPathComponent("source-video.mp4")
        try bytes.write(to: videoURL)
        progress(1)
        return PhotoLibraryWriter.OriginalVideoShareResource(
            videoURL: videoURL,
            fileExtension: "mp4",
            mediaType: "public.mpeg-4",
            temporaryDirectoryURL: destinationURL
        )
    }

    private static func pendingSnapshotter(
        photoData: Data,
        fileContainer: CapturePhotoFileContainer,
        pairedVideoData: Data?,
        expectedRequiresSignedPhoto: Bool,
        expectedLinkPolicy: TAPPendingCaptureShareResourceLinkPolicy = .allowReadOnlyHardLink
    ) -> TAPNAPShareArtifactBuilder.PendingSnapshotter {
        { _, destinationURL, requiresSignedPhoto, includesPairedVideo, linkPolicy, progress in
            guard requiresSignedPhoto == expectedRequiresSignedPhoto,
                  linkPolicy == expectedLinkPolicy else {
                throw TAPNAPShareArtifactTestError.unexpectedResourcePolicy
            }
            try FileManager.default.createDirectory(
                at: destinationURL,
                withIntermediateDirectories: true
            )
            let photoURL = destinationURL.appendingPathComponent(
                "source-photo.\(fileContainer.tapnapFileExtension)"
            )
            try photoData.write(to: photoURL)
            let pairedVideoURL: URL?
            if includesPairedVideo, let pairedVideoData {
                let url = destinationURL.appendingPathComponent("source-paired-video.mov")
                try pairedVideoData.write(to: url)
                pairedVideoURL = url
            } else {
                pairedVideoURL = nil
            }
            progress(1)
            return TAPPendingCaptureShareResourceSnapshot(
                photoURL: photoURL,
                pairedVideoURL: pairedVideoURL,
                fileContainer: fileContainer
            )
        }
    }

    private static func photoLibraryResourceLoader(
        photoData: Data,
        fileContainer: CapturePhotoFileContainer,
        pairedVideoData: Data?,
        expectedIncludesPairedVideo: Bool
    ) -> TAPNAPShareArtifactBuilder.PhotoLibraryResourceLoader {
        { _, preferredFileContainer, includesPairedVideo, destinationURL, progress in
            guard preferredFileContainer == fileContainer,
                  includesPairedVideo == expectedIncludesPairedVideo else {
                throw TAPNAPShareArtifactTestError.unexpectedResourcePolicy
            }
            try FileManager.default.createDirectory(
                at: destinationURL,
                withIntermediateDirectories: true
            )
            let photoURL = destinationURL.appendingPathComponent(
                "source-photo.\(fileContainer.tapnapFileExtension)"
            )
            try photoData.write(to: photoURL)
            let pairedVideoURL: URL?
            if includesPairedVideo, let pairedVideoData {
                let url = destinationURL.appendingPathComponent("source-paired-video.mov")
                try pairedVideoData.write(to: url)
                pairedVideoURL = url
            } else {
                pairedVideoURL = nil
            }
            progress(1)
            return PhotoLibraryWriter.OriginalShareResources(
                photoURL: photoURL,
                photoFileExtension: fileContainer.tapnapFileExtension,
                photoMediaType: fileContainer.uniformTypeIdentifier,
                pairedVideoURL: pairedVideoURL,
                temporaryDirectoryURL: destinationURL,
                presentationAdjustmentResourceLabels: []
            )
        }
    }
}

private enum TAPNAPShareArtifactTestError: Error {
    case unexpectedResourceLoad
    case unexpectedResourcePolicy
}

private final class TAPNAPShareProgressRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Double?] = []

    func record(_ value: Double?) {
        lock.lock()
        values.append(value)
        lock.unlock()
    }

    func snapshot() -> [Double?] {
        lock.lock()
        defer { lock.unlock() }
        return values
    }
}

private final class TAPNAPTemporaryDirectoryRemovalStub: @unchecked Sendable {
    private let lock = NSLock()
    private var failuresRemaining: Int
    private var calls = 0

    init(failuresRemaining: Int) {
        self.failuresRemaining = failuresRemaining
    }

    var invocationCount: Int {
        lock.withLock { calls }
    }

    func remove(_ directoryURL: URL) throws {
        let shouldFail = lock.withLock {
            calls += 1
            guard failuresRemaining > 0 else {
                return false
            }
            failuresRemaining -= 1
            return true
        }
        if shouldFail {
            throw CocoaError(.fileWriteUnknown)
        }
        try FileManager.default.removeItem(at: directoryURL)
    }
}

private final class TAPVideoShareRouteRecorder: @unchecked Sendable {
    struct Snapshot: Equatable {
        let pending: Int
        let photos: Int
    }

    private let lock = NSLock()
    private var pendingCalls = 0
    private var photosCalls = 0

    func recordPending() {
        lock.lock()
        pendingCalls += 1
        lock.unlock()
    }

    func recordPhotos() {
        lock.lock()
        photosCalls += 1
        lock.unlock()
    }

    func snapshot() -> Snapshot {
        lock.lock()
        defer { lock.unlock() }
        return Snapshot(pending: pendingCalls, photos: photosCalls)
    }
}

private actor TAPVideoShareCancellationGate {
    private var started = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func markStarted() {
        started = true
        let pendingWaiters = waiters
        waiters.removeAll()
        pendingWaiters.forEach { $0.resume() }
    }

    func waitUntilStarted() async {
        guard !started else {
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }
}
