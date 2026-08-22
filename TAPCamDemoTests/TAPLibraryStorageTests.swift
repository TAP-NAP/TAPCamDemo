//
//  TAPLibraryStorageTests.swift
//  TAPCamDemoTests
//

import CoreLocation
import Foundation
import Testing
@testable import TAPCamDemo

struct TAPLibraryStorageTests {
    @Test func pendingCaptureStorePersistsLedgerAcrossInstances() async throws {
        let rootURL = try TAPCamDemoTestFixtures.makeTemporaryDirectory()
        let store = TAPPendingCaptureStore(rootURL: rootURL)
        let artifact = TAPCamDemoTestFixtures.samplePendingArtifact(photoData: Data("unsigned".utf8))

        let record = try await store.ingest(artifact)

        #expect(record.captureID == "sample-capture")
        #expect(record.status == .pending)
        #expect(record.captureScoreSummary == artifact.captureScoreSummary)
        #expect(try await store.unsignedHEICData(captureID: record.captureID) == Data("unsigned".utf8))

        let reloadedStore = TAPPendingCaptureStore(rootURL: rootURL)
        let reloadedRecords = try await reloadedStore.visiblePendingRecords()

        #expect(reloadedRecords.map(\.captureID) == ["sample-capture"])
        #expect(reloadedRecords.first?.status == .pending)
        #expect(reloadedRecords.first?.captureScoreSummary == artifact.captureScoreSummary)
    }

    @Test func pendingCaptureStorePersistsPhotoQualityForSigningProfile() async throws {
        let rootURL = try TAPCamDemoTestFixtures.makeTemporaryDirectory()
        let store = TAPPendingCaptureStore(rootURL: rootURL)
        let artifact = TAPCamDemoTestFixtures.samplePendingArtifact(
            photoData: Data("unsigned".utf8),
            photoQualityLevel: .balanced
        )

        let record = try await store.ingest(artifact)
        let reloadedStore = TAPPendingCaptureStore(rootURL: rootURL)
        let reloadedRecords = try await reloadedStore.visiblePendingRecords()
        let reloadedRecord = try #require(reloadedRecords.first)

        #expect(record.photoQualityLevel == .balanced)
        #expect(record.outputProfile.photoQualityPolicy.requested == .balanced)
        #expect(reloadedRecord.photoQualityLevel == .balanced)
        #expect(reloadedRecord.outputProfile.photoQualityPolicy.requested == .balanced)
        #expect(reloadedRecord.outputProfile.fileContainer == .heic)
    }

    @Test func pendingCaptureRecordNamesIdentityLocationAndVisibilityWithoutStore() throws {
        let location = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 31.2304, longitude: 121.4737),
            altitude: 9,
            horizontalAccuracy: 4,
            verticalAccuracy: 6,
            timestamp: Date(timeIntervalSince1970: 1_779_897_600)
        )
        let pendingLocation = TAPPendingCaptureLocation(location)
        var record = TAPCamDemoTestFixtures.samplePendingRecord(
            captureID: "record-model-capture",
            capturedAt: location.timestamp,
            location: pendingLocation
        )

        #expect(record.id == "record-model-capture")
        #expect(record.isVisiblePendingItem)
        #expect(record.location?.clLocation.coordinate.latitude == location.coordinate.latitude)
        #expect(record.location?.clLocation.coordinate.longitude == location.coordinate.longitude)
        #expect(record.location?.clLocation.altitude == location.altitude)

        record.status = .exported
        #expect(!record.isVisiblePendingItem)
    }

    @Test func pendingCaptureStoreWritesArtifactsThroughLocalStoragePolicy() async throws {
        let rootURL = try TAPCamDemoTestFixtures.makeTemporaryDirectory()
        let store = TAPPendingCaptureStore(rootURL: rootURL)
        let record = try await store.ingest(TAPCamDemoTestFixtures.samplePendingArtifact(photoData: Data("unsigned".utf8)))
        let expectedProtection = TAPLocalArtifactStoragePolicy.privatePhotoArtifact.fileProtectionType
        let bundleURL = rootURL.appendingPathComponent(record.captureID, isDirectory: true)

        #expect(expectedProtection == .completeUntilFirstUserAuthentication)
        #expect(FileManager.default.fileExists(atPath: bundleURL.path))
        #expect(FileManager.default.fileExists(atPath: bundleURL.appendingPathComponent("bundle.json").path))
        #expect(FileManager.default.fileExists(atPath: bundleURL.appendingPathComponent("unsigned.heic").path))

        _ = try await store.storeSignedHEIC(Data("signed".utf8), captureID: record.captureID)

        #expect(FileManager.default.fileExists(atPath: bundleURL.appendingPathComponent("signed.heic").path))
    }

    @Test func pendingCaptureStoreUsesContainerSpecificPhotoFilenames() async throws {
        let rootURL = try TAPCamDemoTestFixtures.makeTemporaryDirectory()
        let store = TAPPendingCaptureStore(rootURL: rootURL)
        let record = try await store.ingest(TAPCamDemoTestFixtures.samplePendingArtifact(
            photoData: Data("unsigned-jpg".utf8),
            fileContainer: .jpeg,
            captureID: "jpg-capture"
        ))
        let bundleURL = rootURL.appendingPathComponent(record.captureID, isDirectory: true)

        #expect(record.photoFileContainer == .jpeg)
        #expect(record.unsignedPhotoFilename == "unsigned.jpg")
        #expect(record.unsignedHEICFilename == nil)
        #expect(FileManager.default.fileExists(atPath: bundleURL.appendingPathComponent("unsigned.jpg").path))
        #expect(!FileManager.default.fileExists(atPath: bundleURL.appendingPathComponent("unsigned.heic").path))
        #expect(try await store.unsignedPhotoData(captureID: record.captureID) == Data("unsigned-jpg".utf8))

        let signedRecord = try await store.storeSignedPhoto(Data("signed-jpg".utf8), captureID: record.captureID)

        #expect(signedRecord.signedPhotoFilename == "signed.jpg")
        #expect(signedRecord.signedHEICFilename == nil)
        #expect(FileManager.default.fileExists(atPath: bundleURL.appendingPathComponent("signed.jpg").path))
        #expect(try await store.signedPhotoData(captureID: record.captureID) == Data("signed-jpg".utf8))
    }

    @Test func pendingCaptureStorePersistsAndCleansLivePhotoPairedVideo() async throws {
        let rootURL = try TAPCamDemoTestFixtures.makeTemporaryDirectory()
        let movieDirectory = try TAPCamDemoTestFixtures.makeTemporaryDirectory()
        let movieURL = movieDirectory.appendingPathComponent("source.mov")
        try Data("paired-video".utf8).write(to: movieURL)
        let store = TAPPendingCaptureStore(rootURL: rootURL)
        let record = try await store.ingest(TAPCamDemoTestFixtures.samplePendingArtifact(
            photoData: Data("unsigned".utf8),
            livePhotoMovie: PackagedLivePhotoMovie(
                fileURL: movieURL,
                durationSeconds: 1.2,
                photoDisplayTimeSeconds: 0.5,
                width: 1440,
                height: 1080,
                codec: "hvc1",
                capturesAudio: false
            )
        ))
        let bundleURL = rootURL.appendingPathComponent(record.captureID, isDirectory: true)
        let pairedVideoURL = bundleURL.appendingPathComponent(TAPPendingCaptureBundlePathPolicy.pairedVideoFilename)
        let storedPairedVideoURL = try #require(await store.pairedVideoURL(captureID: record.captureID))

        #expect(record.pairedVideoFilename == TAPPendingCaptureBundlePathPolicy.pairedVideoFilename)
        #expect(FileManager.default.fileExists(atPath: pairedVideoURL.path))
        #expect(try Data(contentsOf: storedPairedVideoURL) == Data("paired-video".utf8))

        _ = try await store.storeSignedPhoto(Data("signed".utf8), captureID: record.captureID)
        _ = try await store.markExported(captureID: record.captureID, assetLocalIdentifier: "asset-live-photo")

        #expect(!FileManager.default.fileExists(atPath: pairedVideoURL.path))
    }

    @Test func pendingCaptureStorePersistsAndCleansTAPVideoArtifact() async throws {
        let rootURL = try TAPCamDemoTestFixtures.makeTemporaryDirectory()
        let store = TAPPendingCaptureStore(rootURL: rootURL)
        let captureID = "video-capture"
        let packageID = UUID(uuidString: "00000000-0000-0000-0000-000000000777")!
        let workspace = try await store.beginVideoCaptureWorkspace(captureID: captureID)
        let videoURL = workspace.artifactURL
        try Self.writePendingVideoArtifact(
            to: videoURL,
            captureID: captureID,
            packageID: packageID
        )
        let workspaceURL = workspace.bundleURL

        let record = try await store.ingestVideo(TAPPendingVideoCaptureArtifact(
            captureID: captureID,
            packageID: packageID,
            capturedAt: Date(timeIntervalSince1970: 1_779_897_600),
            videoURL: videoURL
        ))
        let bundleURL = rootURL.appendingPathComponent(record.captureID, isDirectory: true)
        let artifactURL = bundleURL.appendingPathComponent(TAPPendingCaptureBundlePathPolicy.videoArtifactFilename)

        #expect(record.artifactKind == .tapVideo)
        #expect(record.unsignedPhotoFilename == nil)
        #expect(record.videoArtifactFilename == TAPPendingCaptureBundlePathPolicy.videoArtifactFilename)
        #expect(record.videoFormatRevision == 2)
        #expect(record.videoArtifactState == .unsigned)
        #expect(record.pairedVideoFilename == nil)
        #expect(!FileManager.default.fileExists(atPath: workspaceURL.path))
        #expect(FileManager.default.fileExists(atPath: artifactURL.path))
        #expect(try await store.videoArtifactURL(captureID: record.captureID) == artifactURL)

        let byteCountBeforeSigning = try artifactURL.resourceValues(forKeys: [.fileSizeKey]).fileSize
        let signedRecord = try await store.markVideoSigned(captureID: record.captureID)

        #expect(signedRecord.videoArtifactState == .signed)
        #expect(signedRecord.processingRoute == .exportSigned)
        #expect(try artifactURL.resourceValues(forKeys: [.fileSizeKey]).fileSize == byteCountBeforeSigning)
        let recoveredRetry = try await store.updateStatus(
            captureID: record.captureID,
            status: .failedRetryable,
            failureReason: .retryableProcessingFailure,
            incrementsRetryCount: true
        )
        #expect(recoveredRetry.processingRoute == .exportSigned)
        await #expect(throws: TAPDepthCaptureError.self) {
            try await store.markVideoPhotosCommit(
                captureID: record.captureID,
                assetLocalIdentifier: "premature-video-asset-id"
            )
        }

        let exportIntent = try await store.markVideoPhotosExportIntent(
            captureID: record.captureID
        )
        #expect(exportIntent.status == .exporting)
        #expect(exportIntent.videoPhotosExportPhase == .preCommitIntent)
        #expect(!exportIntent.shouldAttemptExistingAssetRecoveryBeforeExport)
        let commitAmbiguous = try await store.markVideoPhotosCommitAmbiguous(
            captureID: record.captureID
        )
        #expect(commitAmbiguous.videoPhotosExportPhase == .commitAmbiguous)
        #expect(commitAmbiguous.shouldAttemptExistingAssetRecoveryBeforeExport)

        let committedRecord = try await store.markVideoPhotosCommit(
            captureID: record.captureID,
            assetLocalIdentifier: "video-asset-id"
        )
        #expect(committedRecord.status == .exporting)
        #expect(committedRecord.videoPhotosExportPhase == .committed)
        #expect(committedRecord.assetLocalIdentifier == "video-asset-id")
        #expect(committedRecord.shouldAttemptExistingAssetRecoveryBeforeExport)
        let repeatedCommit = try await store.markVideoPhotosCommit(
            captureID: record.captureID,
            assetLocalIdentifier: "video-asset-id"
        )
        #expect(repeatedCommit.status == .exporting)
        await #expect(throws: TAPDepthCaptureError.self) {
            try await store.markVideoPhotosCommit(
                captureID: record.captureID,
                assetLocalIdentifier: "different-video-asset-id"
            )
        }
        #expect(
            try await store.readRecord(captureID: record.captureID).assetLocalIdentifier
                == "video-asset-id"
        )

        let readbackRetry = try await store.updateStatus(
            captureID: record.captureID,
            status: .failedRetryable,
            failureReason: .retryableProcessingFailure,
            incrementsRetryCount: true
        )
        #expect(readbackRetry.shouldAttemptExistingAssetRecoveryBeforeExport)

        let exported = try await store.markExported(
            captureID: record.captureID,
            assetLocalIdentifier: "video-asset-id"
        )
        let staleRepeatedCommit = try await store.markVideoPhotosCommit(
            captureID: record.captureID,
            assetLocalIdentifier: "video-asset-id"
        )
        #expect(staleRepeatedCommit.status == .exported)
        #expect(staleRepeatedCommit.updatedAt == exported.updatedAt)
        await #expect(throws: TAPDepthCaptureError.self) {
            try await store.markVideoPhotosCommit(
                captureID: record.captureID,
                assetLocalIdentifier: "different-video-asset-id"
            )
        }

        #expect(!FileManager.default.fileExists(atPath: artifactURL.path))
    }

    @Test func videoSigningWorkingArtifactIsIndependentAndDiscardKeepsDurableBytes() async throws {
        let rootURL = try TAPCamDemoTestFixtures.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let store = TAPPendingCaptureStore(rootURL: rootURL)
        let record = try await TAPCamDemoTestFixtures.ingestPendingTAPVideo(
            store: store,
            captureID: "independent-video-signing-artifact"
        )
        _ = try await store.updateStatus(
            captureID: record.captureID,
            status: .signing
        )
        let durableURL = try await store.videoArtifactURL(
            captureID: record.captureID
        )
        let durableBytes = try Data(contentsOf: durableURL)
        let durableInode = try #require(
            FileManager.default.attributesOfItem(atPath: durableURL.path)[
                .systemFileNumber
            ] as? NSNumber
        )

        let signingArtifact = try await store.beginVideoSigningArtifact(
            captureID: record.captureID
        )
        let workingInode = try #require(
            FileManager.default.attributesOfItem(
                atPath: signingArtifact.fileURL.path
            )[.systemFileNumber] as? NSNumber
        )

        #expect(signingArtifact.fileURL != durableURL)
        #expect(workingInode != durableInode)
        #expect(try Data(contentsOf: signingArtifact.fileURL) == durableBytes)

        let workingHandle = try FileHandle(forUpdating: signingArtifact.fileURL)
        try workingHandle.seek(toOffset: 11)
        try workingHandle.write(contentsOf: Data([0x7F]))
        try workingHandle.close()

        #expect(try Data(contentsOf: durableURL) == durableBytes)
        try await store.discardVideoSigningArtifact(signingArtifact)
        #expect(!FileManager.default.fileExists(atPath: signingArtifact.fileURL.path))
        #expect(try Data(contentsOf: durableURL) == durableBytes)
    }

    @Test func videoSigningRecordProtectionFailurePrecedesCommitAndKeepsUnsignedGenerationRetryable() async throws {
        let rootURL = try TAPCamDemoTestFixtures.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let store = TAPPendingCaptureStore(
            rootURL: rootURL,
            videoSigningRecordPreparationFault: { record in
                guard record.videoArtifactState == .signed else {
                    return
                }
                throw TAPPendingVideoSigningPublishTestError.recordWriteRejected
            }
        )
        let record = try await TAPCamDemoTestFixtures.ingestPendingTAPVideo(
            store: store,
            captureID: "video-signing-record-write-failure"
        )
        _ = try await store.updateStatus(
            captureID: record.captureID,
            status: .signing
        )
        let durableURL = try await store.videoArtifactURL(
            captureID: record.captureID
        )
        let unsignedBytes = try Data(contentsOf: durableURL)
        let recordURL = TAPPendingCaptureBundlePathPolicy.recordURL(
            bundleURL: try TAPPendingCaptureBundlePathPolicy.bundleURL(
                rootURL: rootURL,
                captureID: record.captureID
            )
        )
        let unsignedRecordBytes = try Data(contentsOf: recordURL)
        let signingArtifact = try await store.beginVideoSigningArtifact(
            captureID: record.captureID
        )

        await #expect(throws: TAPPendingVideoSigningPublishTestError.self) {
            _ = try await store.publishVideoSigningArtifact(signingArtifact)
        }
        try await store.discardVideoSigningArtifact(signingArtifact)

        let unchangedRecord = try await store.readRecord(captureID: record.captureID)
        #expect(unchangedRecord.status == .signing)
        #expect(unchangedRecord.videoArtifactState == .unsigned)
        #expect(try Data(contentsOf: durableURL) == unsignedBytes)
        #expect(try Data(contentsOf: recordURL) == unsignedRecordBytes)

        let retryArtifact = try await store.beginVideoSigningArtifact(
            captureID: record.captureID
        )
        #expect(try Data(contentsOf: retryArtifact.fileURL) == unsignedBytes)
        try await store.discardVideoSigningArtifact(retryArtifact)
    }

    @Test func zeroDepthVideoPersistsAsTerminalRecordInsteadOfBeingDiscarded() async throws {
        let rootURL = try TAPCamDemoTestFixtures.makeTemporaryDirectory()
        let store = TAPPendingCaptureStore(rootURL: rootURL)
        let captureID = "zero-depth-video"
        let packageID = UUID(uuidString: "00000000-0000-0000-0000-000000000778")!
        let workspace = try await store.beginVideoCaptureWorkspace(captureID: captureID)
        try Self.writePendingVideoArtifact(
            to: workspace.artifactURL,
            captureID: captureID,
            packageID: packageID,
            hasDepth: false
        )

        let record = try await store.ingestVideo(
            TAPPendingVideoCaptureArtifact(
                captureID: captureID,
                packageID: packageID,
                capturedAt: Date(timeIntervalSince1970: 1_779_897_600),
                videoURL: workspace.artifactURL
            ),
            terminalFailureCode: .missingDepthData
        )

        #expect(record.status == .failedTerminal)
        #expect(record.failureCode == .missingDepthData)
        #expect(record.videoArtifactState == .unsigned)
        #expect(FileManager.default.fileExists(
            atPath: try await store.videoArtifactURL(captureID: captureID).path
        ))
        #expect(!(try await store.processingCandidates()).contains { $0.captureID == captureID })
    }

    @Test func pendingCaptureStoreRemovesOnlyUnownedInterruptedVideoWorkspaces() async throws {
        let rootURL = try TAPCamDemoTestFixtures.makeTemporaryDirectory()
        let store = TAPPendingCaptureStore(rootURL: rootURL)
        let active = try await store.beginVideoCaptureWorkspace(captureID: "active-video")
        let staleURL = rootURL.appendingPathComponent(".recording-stale-video", isDirectory: true)
        try FileManager.default.createDirectory(
            at: staleURL,
            withIntermediateDirectories: true
        )
        try Data("partial".utf8).write(
            to: staleURL.appendingPathComponent("artifact.mp4")
        )

        let removedCount = try await store.removeStaleVideoCaptureWorkspaces()

        #expect(removedCount == 1)
        #expect(!FileManager.default.fileExists(atPath: staleURL.path))
        #expect(FileManager.default.fileExists(atPath: active.bundleURL.path))
        try await store.abortVideoCaptureWorkspace(captureID: active.captureID)
    }

    @Test func pendingCaptureStoreRejectsUnsafeCaptureIDsBeforeBundlePathUse() async throws {
        let unsafeCaptureIDs = [
            "",
            ".",
            "..",
            "../escape",
            "nested/path",
            "capture id",
            String(repeating: "a", count: 129)
        ]

        for captureID in unsafeCaptureIDs {
            let store = TAPPendingCaptureStore(rootURL: try TAPCamDemoTestFixtures.makeTemporaryDirectory())
            do {
                _ = try await store.ingest(TAPCamDemoTestFixtures.samplePendingArtifact(
                    photoData: Data("unsigned".utf8),
                    captureID: captureID
                ))
                Issue.record("Expected unsafe pending capture ID to be rejected.")
            } catch TAPDepthCaptureError.invalidPendingCaptureBundlePath(let reason) {
                #expect(!reason.isEmpty)
            } catch {
                Issue.record("Unexpected unsafe pending capture ID error: \(error)")
            }
        }
    }

    @Test func pendingCaptureStoreRejectsHiddenAndUnicodeCaptureIDs() async throws {
        let unsafeCaptureIDs = [
            ".hidden-capture",
            "unicode-\u{00E9}",
            "\u{76F8}\u{673A}"
        ]

        for captureID in unsafeCaptureIDs {
            let store = TAPPendingCaptureStore(rootURL: try TAPCamDemoTestFixtures.makeTemporaryDirectory())
            do {
                _ = try await store.ingest(TAPCamDemoTestFixtures.samplePendingArtifact(
                    photoData: Data("unsigned".utf8),
                    captureID: captureID
                ))
                Issue.record("Expected hidden or Unicode pending capture ID to be rejected.")
            } catch TAPDepthCaptureError.invalidPendingCaptureBundlePath(let reason) {
                #expect(!reason.isEmpty)
            } catch {
                Issue.record("Unexpected hidden or Unicode capture ID error: \(error)")
            }
        }
    }

    @Test func pendingCaptureStoreRejectsTamperedBundleFilenames() async throws {
        let rootURL = try TAPCamDemoTestFixtures.makeTemporaryDirectory()
        let store = TAPPendingCaptureStore(rootURL: rootURL)
        let tamperedRecord = TAPCamDemoTestFixtures.samplePendingRecord(
            captureID: "tampered-filename-capture",
            capturedAt: Date(timeIntervalSince1970: 0),
            unsignedHEICFilename: "../unsigned.heic"
        )
        try TAPCamDemoTestFixtures.writePendingRecord(tamperedRecord, rootURL: rootURL)

        do {
            _ = try await store.unsignedHEICData(captureID: tamperedRecord.captureID)
            Issue.record("Expected tampered pending artifact filename to be rejected.")
        } catch TAPDepthCaptureError.invalidPendingCaptureBundlePath(let reason) {
            #expect(reason.contains("filename"))
        } catch {
            Issue.record("Unexpected tampered filename error: \(error)")
        }
    }

    @Test func pendingCaptureBundlePathPolicyAllowsOnlyCurrentArtifactFilenames() throws {
        let rootURL = try TAPCamDemoTestFixtures.makeTemporaryDirectory()
        let captureID = "artifact-policy-capture"
        let allowedFilenames = [
            TAPPendingCaptureBundlePathPolicy.unsignedHEICFilename,
            TAPPendingCaptureBundlePathPolicy.signedHEICFilename,
            TAPPendingCaptureBundlePathPolicy.unsignedJPEGFilename,
            TAPPendingCaptureBundlePathPolicy.signedJPEGFilename,
            TAPPendingCaptureBundlePathPolicy.videoArtifactFilename,
            TAPPendingCaptureBundlePathPolicy.pairedVideoFilename,
            TAPPendingCaptureBundlePathPolicy.thumbnailFilename
        ]
        let unauthorizedFilenames = [
            "c2pa.json",
            "raw.dng",
            "paired.mov",
            "alternate.heic",
            "sidecar.json",
            "../signed.heic"
        ]

        for filename in allowedFilenames {
            let url = try TAPPendingCaptureBundlePathPolicy.artifactURL(
                rootURL: rootURL,
                captureID: captureID,
                filename: filename
            )

            #expect(url.lastPathComponent == filename)
            #expect(url.deletingLastPathComponent().lastPathComponent == captureID)
        }

        for filename in unauthorizedFilenames {
            do {
                _ = try TAPPendingCaptureBundlePathPolicy.artifactURL(
                    rootURL: rootURL,
                    captureID: captureID,
                    filename: filename
                )
                Issue.record("Expected pending artifact filename to be rejected.")
            } catch TAPDepthCaptureError.invalidPendingCaptureBundlePath(let reason) {
                #expect(reason.contains("known bundle resource"))
            } catch {
                Issue.record("Unexpected pending artifact filename error: \(error)")
            }
        }
    }

    @Test func pendingCaptureStoreRejectsMismatchedBundleRecordCaptureID() async throws {
        let rootURL = try TAPCamDemoTestFixtures.makeTemporaryDirectory()
        let store = TAPPendingCaptureStore(rootURL: rootURL)
        let tamperedRecord = TAPCamDemoTestFixtures.samplePendingRecord(
            captureID: "record-capture",
            capturedAt: Date(timeIntervalSince1970: 0)
        )
        try TAPCamDemoTestFixtures.writePendingRecord(
            tamperedRecord,
            rootURL: rootURL,
            bundleCaptureID: "bundle-capture"
        )

        do {
            _ = try await store.readRecord(captureID: "bundle-capture")
            Issue.record("Expected mismatched bundle record capture ID to be rejected.")
        } catch TAPDepthCaptureError.invalidPendingCaptureBundlePath(let reason) {
            #expect(reason.contains("match bundle directory"))
        } catch {
            Issue.record("Unexpected mismatched bundle record error: \(error)")
        }
    }

    @Test func pendingCaptureStoreSkipsThumbnailWhenSourceCannotDecode() async throws {
        let store = TAPPendingCaptureStore(rootURL: try TAPCamDemoTestFixtures.makeTemporaryDirectory())

        let record = try await store.ingest(TAPCamDemoTestFixtures.samplePendingArtifact(
            photoData: Data("not a decodable image".utf8),
            captureID: "no-thumbnail-capture"
        ))

        #expect(record.thumbnailFilename == nil)
        #expect(try await store.thumbnailData(captureID: record.captureID) == nil)
    }

    @Test func pendingCaptureArtifactWriterKeepsForegroundCaptureOutOfPhotos() async throws {
        let rootURL = try TAPCamDemoTestFixtures.makeTemporaryDirectory()
        let store = TAPPendingCaptureStore(rootURL: rootURL)
        let writer = TAPPendingCaptureArtifactWriter(store: store)
        let artifact = TAPCamDemoTestFixtures.samplePendingArtifact(photoData: Data("unsigned".utf8))

        let result = try await writer.write(artifact)

        #expect(result.assetLocalIdentifier == nil)
        #expect(result.pendingCaptureID == "sample-capture")
        #expect(result.publicDestinationSummary == "Pending TAP capture")
        #expect(!result.publicDestinationSummary.contains("sample-capture"))
        #expect(result.signatureStatus == .pending(reason: "Queued for App Attest signing."))
        #expect(result.captureScoreSummary == artifact.captureScoreSummary)
        #expect(try await store.unsignedHEICData(captureID: "sample-capture") == Data("unsigned".utf8))
    }

    @Test func pendingCaptureStoreTracksSigningExportAndCleanup() async throws {
        let rootURL = try TAPCamDemoTestFixtures.makeTemporaryDirectory()
        let store = TAPPendingCaptureStore(rootURL: rootURL)
        let artifact = TAPCamDemoTestFixtures.samplePendingArtifact(photoData: Data("unsigned".utf8))
        let record = try await store.ingest(artifact)

        _ = try await store.updateStatus(
            captureID: record.captureID,
            status: .waitingNetwork,
            failureReason: .waitingNetwork,
            incrementsRetryCount: true
        )
        let waitingRecord = try await store.readRecord(captureID: record.captureID)
        #expect(waitingRecord.status == .waitingNetwork)
        #expect(waitingRecord.failureReason == "Network unavailable. Capture will retry.")
        #expect(waitingRecord.retryCount == 1)

        _ = try await store.storeSignedHEIC(Data("signed".utf8), captureID: record.captureID)
        #expect(try await store.signedHEICData(captureID: record.captureID) == Data("signed".utf8))
        let signedBundleJSON = try TAPCamDemoTestFixtures.pendingCaptureBundleJSON(
            rootURL: rootURL,
            captureID: record.captureID
        )
        #expect(signedBundleJSON.contains("\"latitude\""))
        #expect(signedBundleJSON.contains("\"longitude\""))

        _ = try await store.markExported(captureID: record.captureID, assetLocalIdentifier: "asset-id")
        let exportedRecord = try await store.readRecord(captureID: record.captureID)
        let exportedBundleJSON = try TAPCamDemoTestFixtures.pendingCaptureBundleJSON(
            rootURL: rootURL,
            captureID: record.captureID
        )
        #expect(exportedRecord.status == .exported)
        #expect(exportedRecord.assetLocalIdentifier == "asset-id")
        #expect(exportedRecord.location == nil)
        #expect(!exportedBundleJSON.contains("\"latitude\""))
        #expect(!exportedBundleJSON.contains("\"longitude\""))
        #expect(try await store.visiblePendingRecords().isEmpty)
    }

    @Test func pendingCaptureStoreNormalizesFailureReasonAtWriteSink() async throws {
        let rootURL = try TAPCamDemoTestFixtures.makeTemporaryDirectory()
        let store = TAPPendingCaptureStore(rootURL: rootURL)
        let record = try await store.ingest(TAPCamDemoTestFixtures.samplePendingArtifact(
            photoData: Data("unsigned".utf8),
            captureID: "write-sink-capture"
        ))

        let updatedRecord = try await store.updateStatus(
            captureID: record.captureID,
            status: .failedRetryable,
            failureReason: .retryableProcessingFailure,
            incrementsRetryCount: true
        )
        let bundleJSON = try TAPCamDemoTestFixtures.pendingCaptureBundleJSON(rootURL: rootURL, captureID: record.captureID)

        #expect(updatedRecord.failureReason == "Capture processing failed. It will retry.")
        #expect(bundleJSON.contains("Capture processing failed. It will retry."))
        #expect(!bundleJSON.contains("localizedDescription"))
        #expect(!bundleJSON.contains("/private/"))
        #expect(!bundleJSON.contains("token="))
    }

    @Test func pendingCaptureStoreClearsFailureReasonForNonFailureStatuses() async throws {
        let rootURL = try TAPCamDemoTestFixtures.makeTemporaryDirectory()
        let store = TAPPendingCaptureStore(rootURL: rootURL)
        let statuses: [TAPPendingCaptureStatus] = [.pending, .signing, .signed, .exporting, .exported]

        for status in statuses {
            let record = try await store.ingest(TAPCamDemoTestFixtures.samplePendingArtifact(
                photoData: Data("unsigned-\(status.rawValue)".utf8),
                captureID: "nonfailure-\(status.rawValue)"
            ))
            _ = try await store.updateStatus(
                captureID: record.captureID,
                status: status,
                failureReason: .waitingNetwork
            )

            let storedRecord = try await store.readRecord(captureID: record.captureID)
            let bundleJSON = try TAPCamDemoTestFixtures.pendingCaptureBundleJSON(rootURL: rootURL, captureID: record.captureID)
            #expect(storedRecord.failureReason == nil)
            #expect(!bundleJSON.contains("Network unavailable. Capture will retry."))
            #expect(!bundleJSON.contains("Capture processing failed. It will retry."))
        }
    }

    @Test func pendingCaptureStoreNormalizesLegacyFailureReasonOnRead() async throws {
        let rootURL = try TAPCamDemoTestFixtures.makeTemporaryDirectory()
        let store = TAPPendingCaptureStore(rootURL: rootURL)
        let legacyReason = "capture pending/private-capture-id failed at /private/tmp/secret.heic token=secret-token"
        let legacyRecord = TAPCamDemoTestFixtures.samplePendingRecord(
            captureID: "legacy-read-capture",
            capturedAt: Date(timeIntervalSince1970: 0),
            status: .waitingNetwork,
            failureReason: legacyReason
        )
        try TAPCamDemoTestFixtures.writePendingRecord(legacyRecord, rootURL: rootURL)

        let readRecord = try await store.readRecord(captureID: legacyRecord.captureID)
        let reason = try #require(readRecord.failureReason)

        #expect(reason == "Network unavailable. Capture will retry.")
        #expect(!reason.contains("pending/private-capture-id"))
        #expect(!reason.contains("/private/"))
        #expect(!reason.contains("token=secret-token"))
    }

    @Test func pendingCaptureStoreMigratesLegacyBundleJSONFailureReason() async throws {
        let rootURL = try TAPCamDemoTestFixtures.makeTemporaryDirectory()
        let store = TAPPendingCaptureStore(rootURL: rootURL)
        let legacyReason = "manifest actual-manifest-id-2 failed at /private/tmp/signed.heic proof=secret-proof"
        let legacyRecord = TAPCamDemoTestFixtures.samplePendingRecord(
            captureID: "legacy-migrate-capture",
            capturedAt: Date(timeIntervalSince1970: 0),
            status: .failedRetryable,
            failureReason: legacyReason
        )
        try TAPCamDemoTestFixtures.writePendingRecord(legacyRecord, rootURL: rootURL)

        let normalizedCount = try await store.normalizePersistedFailureReasons()
        let migratedJSON = try TAPCamDemoTestFixtures.pendingCaptureBundleJSON(rootURL: rootURL, captureID: legacyRecord.captureID)
        let migratedRecord = try await store.readRecord(captureID: legacyRecord.captureID)

        #expect(normalizedCount == 1)
        #expect(migratedRecord.failureReason == "Capture processing failed. It will retry.")
        #expect(migratedJSON.contains("Capture processing failed. It will retry."))
        #expect(!migratedJSON.contains("actual-manifest-id-2"))
        #expect(!migratedJSON.contains("/private/tmp/signed.heic"))
        #expect(!migratedJSON.contains("secret-proof"))
    }

    @Test func pendingCaptureStoreOnlyReopensLegacyUnsignedVideoValidationFailures() async throws {
        let rootURL = try TAPCamDemoTestFixtures.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let store = TAPPendingCaptureStore(rootURL: rootURL)

        let invalidUnsigned = try await TAPCamDemoTestFixtures.ingestPendingTAPVideo(
            store: store,
            captureID: "legacy-invalid-unsigned"
        )
        _ = try await store.markTerminalFailure(
            captureID: invalidUnsigned.captureID,
            code: .invalidVideoArtifact
        )

        let proofUnsigned = try await TAPCamDemoTestFixtures.ingestPendingTAPVideo(
            store: store,
            captureID: "legacy-proof-unsigned"
        )
        _ = try await store.markTerminalFailure(
            captureID: proofUnsigned.captureID,
            code: .proofValidationFailed
        )

        let missingDepth = try await TAPCamDemoTestFixtures.ingestPendingTAPVideo(
            store: store,
            captureID: "terminal-missing-depth"
        )
        _ = try await store.markTerminalFailure(
            captureID: missingDepth.captureID,
            code: .missingDepthData
        )

        let invalidSigned = try await TAPCamDemoTestFixtures.ingestPendingTAPVideo(
            store: store,
            captureID: "terminal-invalid-signed"
        )
        _ = try await store.markVideoSigned(captureID: invalidSigned.captureID)
        _ = try await store.markTerminalFailure(
            captureID: invalidSigned.captureID,
            code: .invalidVideoArtifact
        )

        let reopenedCount = try await store.reopenLegacyUnsignedVideoValidationFailures()

        #expect(reopenedCount == 2)
        #expect(try await store.readRecord(captureID: invalidUnsigned.captureID).status == .failedRetryable)
        #expect(try await store.readRecord(captureID: proofUnsigned.captureID).status == .failedRetryable)
        #expect(try await store.readRecord(captureID: missingDepth.captureID).status == .failedTerminal)
        #expect(try await store.readRecord(captureID: invalidSigned.captureID).status == .failedTerminal)
    }

    @Test func pendingCaptureStoreMigrationSkipsInvalidBundlesAndNormalizesOthers() async throws {
        let rootURL = try TAPCamDemoTestFixtures.makeTemporaryDirectory()
        let store = TAPPendingCaptureStore(rootURL: rootURL)
        let legacyReason = "legacy capture failed at /private/tmp/legacy.heic token=secret-token"
        let legacyRecord = TAPCamDemoTestFixtures.samplePendingRecord(
            captureID: "legacy-continue-capture",
            capturedAt: Date(timeIntervalSince1970: 0),
            status: .waitingNetwork,
            failureReason: legacyReason
        )
        let invalidRecord = TAPCamDemoTestFixtures.samplePendingRecord(
            captureID: "record-mismatch-capture",
            capturedAt: Date(timeIntervalSince1970: 1),
            status: .failedRetryable,
            failureReason: "bad bundle should not block migration"
        )
        try TAPCamDemoTestFixtures.writePendingRecord(legacyRecord, rootURL: rootURL)
        try TAPCamDemoTestFixtures.writePendingRecord(
            invalidRecord,
            rootURL: rootURL,
            bundleCaptureID: "bundle-mismatch-capture"
        )

        let normalizedCount = try await store.normalizePersistedFailureReasons()
        let migratedJSON = try TAPCamDemoTestFixtures.pendingCaptureBundleJSON(rootURL: rootURL, captureID: legacyRecord.captureID)
        let migratedRecord = try await store.readRecord(captureID: legacyRecord.captureID)

        #expect(normalizedCount == 1)
        #expect(migratedRecord.failureReason == "Network unavailable. Capture will retry.")
        #expect(migratedJSON.contains("Network unavailable. Capture will retry."))
        #expect(!migratedJSON.contains("/private/tmp/legacy.heic"))
        #expect(!migratedJSON.contains("secret-token"))

        do {
            _ = try await store.readRecord(captureID: "bundle-mismatch-capture")
            Issue.record("Expected mismatched bundle to remain invalid after migration skips it.")
        } catch TAPDepthCaptureError.invalidPendingCaptureBundlePath(let reason) {
            #expect(reason.contains("match bundle directory"))
        } catch {
            Issue.record("Unexpected invalid bundle error: \(error)")
        }
    }

    @Test func pendingCaptureStoreAllRecordsNormalizesLegacyFailureReasons() async throws {
        let rootURL = try TAPCamDemoTestFixtures.makeTemporaryDirectory()
        let store = TAPPendingCaptureStore(rootURL: rootURL)
        let retryRecord = TAPCamDemoTestFixtures.samplePendingRecord(
            captureID: "legacy-retry-capture",
            capturedAt: Date(timeIntervalSince1970: 0),
            status: .failedRetryable,
            failureReason: "raw retry path /private/tmp/retry.heic"
        )
        let exportedRecord = TAPCamDemoTestFixtures.samplePendingRecord(
            captureID: "legacy-exported-capture",
            capturedAt: Date(timeIntervalSince1970: 1),
            status: .exported,
            assetLocalIdentifier: "asset-id",
            failureReason: "raw exported asset-id failure"
        )
        try TAPCamDemoTestFixtures.writePendingRecord(retryRecord, rootURL: rootURL)
        try TAPCamDemoTestFixtures.writePendingRecord(exportedRecord, rootURL: rootURL)

        let recordsByID = Dictionary(uniqueKeysWithValues: try await store.allRecords().map { ($0.captureID, $0) })

        #expect(recordsByID[retryRecord.captureID]?.failureReason == "Capture processing failed. It will retry.")
        #expect(recordsByID[exportedRecord.captureID]?.failureReason == nil)
    }

    @Test func pendingCaptureStoreResolvesOnlyUniquePhotosAssetRecord() async throws {
        let rootURL = try TAPCamDemoTestFixtures.makeTemporaryDirectory()
        let store = TAPPendingCaptureStore(rootURL: rootURL)
        let record = TAPCamDemoTestFixtures.samplePendingRecord(
            captureID: "owned-photo",
            capturedAt: Date(timeIntervalSince1970: 1),
            status: .exported,
            assetLocalIdentifier: "asset-id"
        )
        try TAPCamDemoTestFixtures.writePendingRecord(record, rootURL: rootURL)

        #expect(try await store.record(assetLocalIdentifier: "missing") == nil)
        #expect(
            try await store.record(assetLocalIdentifier: "asset-id")?.captureID
                == record.captureID
        )
    }

    @Test func pendingCaptureStoreRejectsAmbiguousPhotosAssetRecord() async throws {
        let rootURL = try TAPCamDemoTestFixtures.makeTemporaryDirectory()
        let store = TAPPendingCaptureStore(rootURL: rootURL)
        for (captureID, capturedAt) in [
            ("duplicate-photo-a", Date(timeIntervalSince1970: 1)),
            ("duplicate-photo-b", Date(timeIntervalSince1970: 2))
        ] {
            try TAPCamDemoTestFixtures.writePendingRecord(
                TAPCamDemoTestFixtures.samplePendingRecord(
                    captureID: captureID,
                    capturedAt: capturedAt,
                    status: .exported,
                    assetLocalIdentifier: "duplicate-asset-id"
                ),
                rootURL: rootURL
            )
        }

        await #expect(
            throws: TAPPendingCaptureStoreLookupError.ambiguousAssetLocalIdentifier
        ) {
            try await store.record(assetLocalIdentifier: "duplicate-asset-id")
        }
    }

    @Test func signedShareSnapshotNeverFallsBackToUnsignedPhoto() async throws {
        let rootURL = try TAPCamDemoTestFixtures.makeTemporaryDirectory()
        let store = TAPPendingCaptureStore(rootURL: rootURL)
        let record = try await store.ingest(
            TAPCamDemoTestFixtures.samplePendingArtifact(
                photoData: Data("unsigned-must-not-be-shared".utf8)
            )
        )
        _ = try await store.storeSignedPhoto(
            Data("signed-photo".utf8),
            captureID: record.captureID
        )
        let bundleURL = rootURL.appendingPathComponent(record.captureID, isDirectory: true)
        try FileManager.default.removeItem(
            at: bundleURL.appendingPathComponent("signed.heic")
        )
        let snapshotDirectoryURL = rootURL.appendingPathComponent(
            "share-snapshot",
            isDirectory: true
        )

        await #expect(throws: TAPDepthCaptureError.self) {
            try await store.snapshotPhotoShareResources(
                captureID: record.captureID,
                to: snapshotDirectoryURL,
                requiresSignedPhoto: true,
                includesPairedVideo: false
            )
        }
        #expect(!FileManager.default.fileExists(atPath: snapshotDirectoryURL.path))
        #expect(
            try await store.unsignedPhotoData(captureID: record.captureID)
                == Data("unsigned-must-not-be-shared".utf8)
        )
    }

    @Test func signedLivePhotoShareSnapshotCreatesAStableResourcePair() async throws {
        let rootURL = try TAPCamDemoTestFixtures.makeTemporaryDirectory()
        let movieDirectoryURL = try TAPCamDemoTestFixtures.makeTemporaryDirectory()
        let sourceMovieURL = movieDirectoryURL.appendingPathComponent("source.mov")
        try Data("paired-video".utf8).write(to: sourceMovieURL)
        let store = TAPPendingCaptureStore(rootURL: rootURL)
        let record = try await store.ingest(
            TAPCamDemoTestFixtures.samplePendingArtifact(
                photoData: Data("unsigned-photo".utf8),
                livePhotoMovie: PackagedLivePhotoMovie(
                    fileURL: sourceMovieURL,
                    durationSeconds: 1,
                    photoDisplayTimeSeconds: 0.5,
                    width: 1440,
                    height: 1080,
                    codec: "hvc1",
                    capturesAudio: false
                )
            )
        )
        let signedRecord = try await store.storeSignedPhoto(
            Data("signed-photo".utf8),
            captureID: record.captureID
        )
        let snapshotDirectoryURL = rootURL.appendingPathComponent(
            "share-snapshot",
            isDirectory: true
        )

        let snapshot = try await store.snapshotPhotoShareResources(
            captureID: record.captureID,
            to: snapshotDirectoryURL,
            requiresSignedPhoto: true,
            includesPairedVideo: true,
            linkPolicy: .allowReadOnlyHardLink
        )
        #expect(snapshot.selectedSignedPhoto)

        let bundleURL = rootURL.appendingPathComponent(record.captureID, isDirectory: true)
        try FileManager.default.removeItem(
            at: bundleURL.appendingPathComponent(
                try #require(signedRecord.signedPhotoFilename)
            )
        )
        try FileManager.default.removeItem(
            at: bundleURL.appendingPathComponent(
                try #require(signedRecord.pairedVideoFilename)
            )
        )

        #expect(try Data(contentsOf: snapshot.photoURL) == Data("signed-photo".utf8))
        #expect(
            try Data(contentsOf: #require(snapshot.pairedVideoURL))
                == Data("paired-video".utf8)
        )
    }

    @Test func ordinaryViewerSnapshotReportsUnsignedFallback() async throws {
        let rootURL = try TAPCamDemoTestFixtures.makeTemporaryDirectory()
        let store = TAPPendingCaptureStore(rootURL: rootURL)
        let record = try await store.ingest(
            TAPCamDemoTestFixtures.samplePendingArtifact(
                photoData: Data("unsigned-viewer-photo".utf8)
            )
        )
        let snapshotDirectoryURL = rootURL.appendingPathComponent(
            "viewer-snapshot",
            isDirectory: true
        )

        let snapshot = try await store.snapshotPhotoShareResources(
            captureID: record.captureID,
            to: snapshotDirectoryURL,
            requiresSignedPhoto: false,
            includesPairedVideo: false,
            linkPolicy: .allowReadOnlyHardLink
        )

        #expect(!snapshot.selectedSignedPhoto)
        #expect(
            try Data(contentsOf: snapshot.photoURL)
                == Data("unsigned-viewer-photo".utf8)
        )
    }

    @Test func signedShareSnapshotFallbackStreamsBytesAndPublishesProgress() async throws {
        let rootURL = try TAPCamDemoTestFixtures.makeTemporaryDirectory()
        let signedPhotoData = Data(
            repeating: 0xA5,
            count: (2 * 1_024 * 1_024) + 137
        )
        let progressRecorder = TAPPendingShareSnapshotProgressRecorder()
        let store = TAPPendingCaptureStore(
            rootURL: rootURL,
            shareSnapshotLinker: { _, _ in
                throw TAPPendingShareSnapshotTestError.hardLinkUnavailable
            }
        )
        let record = try await store.ingest(
            TAPCamDemoTestFixtures.samplePendingArtifact(
                photoData: Data("unsigned-photo".utf8)
            )
        )
        _ = try await store.storeSignedPhoto(
            signedPhotoData,
            captureID: record.captureID
        )
        let snapshotDirectoryURL = rootURL.appendingPathComponent(
            "streamed-share-snapshot",
            isDirectory: true
        )

        let snapshot = try await store.snapshotPhotoShareResources(
            captureID: record.captureID,
            to: snapshotDirectoryURL,
            requiresSignedPhoto: true,
            includesPairedVideo: false,
            linkPolicy: .allowReadOnlyHardLink,
            progressHandler: { progressRecorder.record($0) }
        )

        #expect(try Data(contentsOf: snapshot.photoURL) == signedPhotoData)
        let progressValues = progressRecorder.snapshot().compactMap { $0 }
        #expect(progressValues.first == 0)
        #expect(progressValues.last == 1)
        #expect(progressValues.count >= 6)
        #expect(progressValues.allSatisfy { 0 ... 1 ~= $0 })
        #expect(
            progressValues.elementsEqual(
                progressValues.sorted(),
                by: { abs($0 - $1) < 0.000_001 }
            )
        )
    }

    @Test func externallySharedImageSnapshotCannotMutateDurableSignedPhoto() async throws {
        let rootURL = try TAPCamDemoTestFixtures.makeTemporaryDirectory()
        let signedPhotoData = Data("durable-signed-photo".utf8)
        let store = TAPPendingCaptureStore(rootURL: rootURL)
        let record = try await store.ingest(
            TAPCamDemoTestFixtures.samplePendingArtifact(
                photoData: Data("unsigned-photo".utf8)
            )
        )
        _ = try await store.storeSignedPhoto(
            signedPhotoData,
            captureID: record.captureID
        )
        let snapshotDirectoryURL = rootURL.appendingPathComponent(
            "external-image-snapshot",
            isDirectory: true
        )

        let snapshot = try await store.snapshotPhotoShareResources(
            captureID: record.captureID,
            to: snapshotDirectoryURL,
            requiresSignedPhoto: true,
            includesPairedVideo: false,
            linkPolicy: .requireIndependentFile
        )
        let snapshotHandle = try FileHandle(forWritingTo: snapshot.photoURL)
        try snapshotHandle.truncate(atOffset: 0)
        try snapshotHandle.write(contentsOf: Data("external-mutation".utf8))
        try snapshotHandle.close()

        #expect(
            try await store.signedPhotoData(captureID: record.captureID)
                == signedPhotoData
        )
    }

    @Test func pendingCaptureStoreBestAvailableHEICPrefersSignedAndFallsBackToUnsigned() async throws {
        let rootURL = try TAPCamDemoTestFixtures.makeTemporaryDirectory()
        let store = TAPPendingCaptureStore(rootURL: rootURL)
        let record = try await store.ingest(TAPCamDemoTestFixtures.samplePendingArtifact(photoData: Data("unsigned".utf8)))
        let bundleURL = rootURL.appendingPathComponent(record.captureID, isDirectory: true)
        let signedURL = bundleURL.appendingPathComponent("signed.heic")
        let unsignedURL = bundleURL.appendingPathComponent("unsigned.heic")

        #expect(try await store.bestAvailableHEICData(captureID: record.captureID) == Data("unsigned".utf8))
        #expect(try await store.bestAvailablePhotoURL(captureID: record.captureID) == unsignedURL)

        _ = try await store.storeSignedHEIC(Data("signed".utf8), captureID: record.captureID)
        #expect(try await store.bestAvailableHEICData(captureID: record.captureID) == Data("signed".utf8))
        #expect(try await store.bestAvailablePhotoURL(captureID: record.captureID) == signedURL)

        try FileManager.default.removeItem(at: signedURL)
        #expect(try await store.bestAvailableHEICData(captureID: record.captureID) == Data("unsigned".utf8))
        #expect(try await store.bestAvailablePhotoURL(captureID: record.captureID) == unsignedURL)

        try FileManager.default.removeItem(at: unsignedURL)
        do {
            _ = try await store.bestAvailableHEICData(captureID: record.captureID)
            Issue.record("Expected missing pending HEIC data to throw.")
        } catch TAPDepthCaptureError.pendingCaptureDataMissing {
            // Expected path.
        } catch {
            Issue.record("Unexpected pending HEIC error: \(error)")
        }
    }

    @Test func pendingLivePhotoPlaybackResourcesUseUnsignedPhotoBeforeSigningSucceeds() async throws {
        let rootURL = try TAPCamDemoTestFixtures.makeTemporaryDirectory()
        let movieDirectory = try TAPCamDemoTestFixtures.makeTemporaryDirectory()
        let movieURL = movieDirectory.appendingPathComponent("source.mov")
        try Data("paired-video".utf8).write(to: movieURL)

        let store = TAPPendingCaptureStore(rootURL: rootURL)
        let record = try await store.ingest(TAPCamDemoTestFixtures.samplePendingArtifact(
            photoData: Data("unsigned-live-photo".utf8),
            livePhotoMovie: PackagedLivePhotoMovie(
                fileURL: movieURL,
                durationSeconds: 1.2,
                photoDisplayTimeSeconds: 0.5,
                width: 1440,
                height: 1080,
                codec: "hvc1",
                capturesAudio: false
            )
        ))
        let bundleURL = rootURL.appendingPathComponent(record.captureID, isDirectory: true)
        let unsignedPhotoURL = bundleURL.appendingPathComponent(TAPPendingCaptureBundlePathPolicy.unsignedHEICFilename)
        let pairedVideoURL = bundleURL.appendingPathComponent(TAPPendingCaptureBundlePathPolicy.pairedVideoFilename)

        #expect(record.status == .pending)
        #expect(record.signedPhotoFilename == nil)
        #expect(record.pairedVideoFilename == TAPPendingCaptureBundlePathPolicy.pairedVideoFilename)
        #expect(try await store.bestAvailablePhotoURL(captureID: record.captureID) == unsignedPhotoURL)
        #expect(try await store.pairedVideoURL(captureID: record.captureID) == pairedVideoURL)
        #expect(try Data(contentsOf: unsignedPhotoURL) == Data("unsigned-live-photo".utf8))
        #expect(try Data(contentsOf: pairedVideoURL) == Data("paired-video".utf8))
    }

    @Test func pendingCaptureProcessingPolicyKeepsRouteAndPriorityReadable() async throws {
        let rootURL = try TAPCamDemoTestFixtures.makeTemporaryDirectory()
        let store = TAPPendingCaptureStore(rootURL: rootURL)
        let pendingRecord = try await store.ingest(TAPCamDemoTestFixtures.samplePendingArtifact(photoData: Data("unsigned".utf8)))

        #expect(pendingRecord.processingRoute == .signThenExport)
        #expect(pendingRecord.processingPriority == 1)
        #expect(pendingRecord.isProcessingCandidate)
        #expect(!pendingRecord.shouldAttemptExistingAssetRecoveryBeforeExport)

        let signedRecord = try await store.storeSignedHEIC(Data("signed".utf8), captureID: pendingRecord.captureID)
        #expect(signedRecord.processingRoute == .exportSigned)
        #expect(signedRecord.processingPriority == 0)
        #expect(!signedRecord.shouldAttemptExistingAssetRecoveryBeforeExport)

        let exportingRecord = try await store.updateStatus(captureID: pendingRecord.captureID, status: .exporting)
        #expect(exportingRecord.processingRoute == .exportSigned)
        #expect(exportingRecord.processingPriority == 0)
        #expect(exportingRecord.shouldAttemptExistingAssetRecoveryBeforeExport)

        let retryWithSignedFile = try await store.updateStatus(
            captureID: pendingRecord.captureID,
            status: .waitingNetwork,
            failureReason: .waitingNetwork,
            incrementsRetryCount: true
        )
        #expect(retryWithSignedFile.processingRoute == .exportSigned)
        #expect(retryWithSignedFile.processingPriority == 2)
        #expect(!retryWithSignedFile.shouldAttemptExistingAssetRecoveryBeforeExport)

        let exportedRecord = try await store.markExported(captureID: pendingRecord.captureID, assetLocalIdentifier: "asset-id")
        #expect(exportedRecord.processingRoute == .skip)
        #expect(exportedRecord.processingPriority == nil)
        #expect(!exportedRecord.isProcessingCandidate)

        let staleFailureUpdate = try await store.updateStatus(
            captureID: pendingRecord.captureID,
            status: .failedRetryable,
            failureReason: .retryableProcessingFailure,
            incrementsRetryCount: true
        )
        #expect(staleFailureUpdate.status == .exported)
        #expect(staleFailureUpdate.assetLocalIdentifier == "asset-id")
        #expect(staleFailureUpdate.retryCount == exportedRecord.retryCount)
    }

    @Test func pendingCaptureStoreKeepsExportedThumbnailIndex() async throws {
        let rootURL = try TAPCamDemoTestFixtures.makeTemporaryDirectory()
        let store = TAPPendingCaptureStore(rootURL: rootURL)
        let artifact = TAPCamDemoTestFixtures.samplePendingArtifact(photoData: TAPCamDemoTestFixtures.sampleThumbnailSourceData())
        let record = try await store.ingest(artifact)
        let initialThumbnail = try #require(try await store.thumbnailData(captureID: record.captureID))

        _ = try await store.markExported(captureID: record.captureID, assetLocalIdentifier: "asset-id")

        #expect(try await store.visiblePendingRecords().isEmpty)
        #expect(try await store.exportedRecords().map(\.assetLocalIdentifier) == ["asset-id"])
        #expect(try await store.exportedRecords().allSatisfy { $0.location == nil })
        #expect(try #require(try await store.thumbnailData(captureID: record.captureID)) == initialThumbnail)
    }

    @Test func pendingCaptureStoreRetriesInterruptedSigningRecords() async throws {
        let rootURL = try TAPCamDemoTestFixtures.makeTemporaryDirectory()
        let store = TAPPendingCaptureStore(rootURL: rootURL)
        let artifact = TAPCamDemoTestFixtures.samplePendingArtifact(photoData: Data("unsigned".utf8))
        let record = try await store.ingest(artifact)

        _ = try await store.updateStatus(captureID: record.captureID, status: .signing)

        let candidateIDs = try await store.processingCandidates().map(\.captureID)
        #expect(candidateIDs == [record.captureID])
    }

    @Test func pendingCaptureStorePrioritizesSignedExportBeforeFreshSigningAndRetryBacklog() async throws {
        let rootURL = try TAPCamDemoTestFixtures.makeTemporaryDirectory()
        let store = TAPPendingCaptureStore(rootURL: rootURL)

        let retryRecord = try await store.ingest(TAPCamDemoTestFixtures.samplePendingArtifact(
            photoData: Data("retry".utf8),
            captureID: "retry-capture",
            capturedAt: Date(timeIntervalSince1970: 0)
        ))
        _ = try await store.updateStatus(
            captureID: retryRecord.captureID,
            status: .waitingNetwork,
            failureReason: .waitingNetwork,
            incrementsRetryCount: true
        )

        let pendingRecord = try await store.ingest(TAPCamDemoTestFixtures.samplePendingArtifact(
            photoData: Data("pending".utf8),
            captureID: "pending-capture",
            capturedAt: Date(timeIntervalSince1970: 1)
        ))

        let signedRecord = try await store.ingest(TAPCamDemoTestFixtures.samplePendingArtifact(
            photoData: Data("signed-source".utf8),
            captureID: "signed-capture",
            capturedAt: Date(timeIntervalSince1970: 2)
        ))
        _ = try await store.storeSignedHEIC(Data("signed".utf8), captureID: signedRecord.captureID)

        let candidates = try await store.processingCandidates()
        #expect(candidates.map(\.captureID) == [
            signedRecord.captureID,
            pendingRecord.captureID,
            retryRecord.captureID
        ])
        #expect(candidates.map(\.status) == [.signed, .pending, .waitingNetwork])
    }

    @Test func pendingCaptureStoreReturnsNextProcessingCandidateWithExclusions() async throws {
        let rootURL = try TAPCamDemoTestFixtures.makeTemporaryDirectory()
        let store = TAPPendingCaptureStore(rootURL: rootURL)

        let pendingRecord = try await store.ingest(TAPCamDemoTestFixtures.samplePendingArtifact(
            photoData: Data("pending".utf8),
            captureID: "pending-capture",
            capturedAt: Date(timeIntervalSince1970: 1)
        ))

        let signedRecord = try await store.ingest(TAPCamDemoTestFixtures.samplePendingArtifact(
            photoData: Data("signed-source".utf8),
            captureID: "signed-capture",
            capturedAt: Date(timeIntervalSince1970: 2)
        ))
        _ = try await store.storeSignedHEIC(Data("signed".utf8), captureID: signedRecord.captureID)

        let retryRecord = try await store.ingest(TAPCamDemoTestFixtures.samplePendingArtifact(
            photoData: Data("retry".utf8),
            captureID: "retry-capture",
            capturedAt: Date(timeIntervalSince1970: 3)
        ))
        _ = try await store.updateStatus(
            captureID: retryRecord.captureID,
            status: .failedRetryable,
            failureReason: .retryableProcessingFailure,
            incrementsRetryCount: true
        )

        let firstCandidate = try await store.nextProcessingCandidate()
        #expect(firstCandidate?.captureID == signedRecord.captureID)

        let secondCandidate = try await store.nextProcessingCandidate(excludingCaptureIDs: [signedRecord.captureID])
        #expect(secondCandidate?.captureID == pendingRecord.captureID)

        let thirdCandidate = try await store.nextProcessingCandidate(excludingCaptureIDs: [
            signedRecord.captureID,
            pendingRecord.captureID
        ])
        #expect(thirdCandidate?.captureID == retryRecord.captureID)
    }

    private static func writePendingVideoArtifact(
        to fileURL: URL,
        captureID: String,
        packageID: UUID,
        hasDepth: Bool = true
    ) throws {
        var baseMP4 = Data()
        baseMP4.append(contentsOf: [0, 0, 0, 12])
        baseMP4.append(Data("ftyp".utf8))
        baseMP4.append(Data("mp42".utf8))
        try baseMP4.write(to: fileURL)
        try TAPVideoManifestBox.appendManifest(
            pendingVideoManifest(
                captureID: captureID,
                packageID: packageID,
                hasDepth: hasDepth
            ),
            toFileAt: fileURL
        )
        _ = try TAPProofSlot.ensureEmptyBMFFSlot(inFileAt: fileURL)
    }

    private static func pendingVideoManifest(
        captureID: String,
        packageID: UUID,
        hasDepth: Bool = true
    ) -> TAPVideoManifest {
        TAPVideoManifest(payload: TAPVideoManifest.Payload(
            id: captureID,
            packageID: packageID.uuidString,
            capturedAt: "2026-07-09T12:00:00Z",
            selectedCameraPlan: .init(
                deviceUniqueID: "device",
                deviceType: "BuiltInLiDARDepthCamera",
                localizedName: "Back Camera",
                position: "back",
                requestedFocalLengthLabel: "24mm",
                resolvedFocalLengthLabel: "24mm",
                resolvedZoomFactor: 1,
                depthCapable: true
            ),
            container: .init(
                fileType: "mp4",
                mediaType: "video/mp4",
                durationSeconds: 1,
                timeScale: 600,
                trackCount: hasDepth ? 2 : 1
            ),
            rgbTrack: .init(
                trackID: 1,
                codec: "avc1",
                width: 1_920,
                height: 1_080,
                durationSeconds: 1,
                timeScale: 600,
                nominalFrameRate: 30,
                frameCount: 30,
                transform: "rotation:0;not-mirrored"
            ),
            audioTrack: .init(
                status: .notCaptured,
                trackID: nil,
                codec: nil,
                durationSeconds: nil,
                timeScale: nil,
                sampleRate: nil,
                channelCount: nil
            ),
            depthCoverage: hasDepth
                ? .init(
                    trackID: 3,
                    trackCodec: "mebx",
                    trackDurationSeconds: 1,
                    trackTimeScale: 600,
                    sampleCount: 1,
                    format: .init(
                        kind: "depth",
                        pixelFormat: "hdep",
                        width: 256,
                        height: 192,
                        packedRowStride: 512,
                        sourceRowStride: 544,
                        bytesPerSample: 2,
                        uncompressedFrameByteCount: 98_304
                    )
                )
                : .none,
            spatialRegistration: .unavailable,
            synchronization: .init(
                timing: "capture-output-presentation-timestamps",
                rgbToDepthMapping: "independent-timed-metadata",
                maxObservedDeltaSeconds: nil
            ),
            stop: .init(reason: .userStop, recordedDurationSeconds: 1),
            software: .current
        ))
    }

    private static func source(relativePath: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let fileURL = root.appendingPathComponent(relativePath)
        return try String(contentsOf: fileURL, encoding: .utf8)
    }
}

private enum TAPPendingVideoSigningPublishTestError: Error {
    case recordWriteRejected
}

private enum TAPPendingShareSnapshotTestError: Error {
    case hardLinkUnavailable
}

private final class TAPPendingShareSnapshotProgressRecorder: @unchecked Sendable {
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
