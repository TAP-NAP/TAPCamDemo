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

    @Test func pendingCaptureBundlePathPolicyKeepsArtifactFilenameAllowListExact() throws {
        let source = try Self.source(relativePath: "TAPCamDemo/TAPLibrary/TAPPendingCaptureBundlePathPolicy.swift")

        #expect(source.contains(#"static let unsignedHEICFilename = "unsigned.heic""#))
        #expect(source.contains(#"static let signedHEICFilename = "signed.heic""#))
        #expect(source.contains(#"static let unsignedJPEGFilename = "unsigned.jpg""#))
        #expect(source.contains(#"static let signedJPEGFilename = "signed.jpg""#))
        #expect(source.contains(#"static let thumbnailFilename = "thumbnail.jpg""#))
        #expect(source.contains(#"""
    private static let artifactFilenames: Set<String> = [
        unsignedHEICFilename,
        signedHEICFilename,
        unsignedJPEGFilename,
        signedJPEGFilename,
        thumbnailFilename
    ]
"""#))
        #expect(!source.contains("pairedVideo"))
        #expect(!source.contains("alternatePhoto"))
        #expect(!source.contains("sidecar"))
        #expect(!source.contains("rawFilename"))
    }

    @Test func pendingCaptureBundlePathPolicyAllowsOnlyCurrentArtifactFilenames() throws {
        let rootURL = try TAPCamDemoTestFixtures.makeTemporaryDirectory()
        let captureID = "artifact-policy-capture"
        let allowedFilenames = [
            TAPPendingCaptureBundlePathPolicy.unsignedHEICFilename,
            TAPPendingCaptureBundlePathPolicy.signedHEICFilename,
            TAPPendingCaptureBundlePathPolicy.unsignedJPEGFilename,
            TAPPendingCaptureBundlePathPolicy.signedJPEGFilename,
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

    @Test func pendingCaptureStoreBestAvailableHEICPrefersSignedAndFallsBackToUnsigned() async throws {
        let rootURL = try TAPCamDemoTestFixtures.makeTemporaryDirectory()
        let store = TAPPendingCaptureStore(rootURL: rootURL)
        let record = try await store.ingest(TAPCamDemoTestFixtures.samplePendingArtifact(photoData: Data("unsigned".utf8)))
        let bundleURL = rootURL.appendingPathComponent(record.captureID, isDirectory: true)
        let signedURL = bundleURL.appendingPathComponent("signed.heic")
        let unsignedURL = bundleURL.appendingPathComponent("unsigned.heic")

        #expect(try await store.bestAvailableHEICData(captureID: record.captureID) == Data("unsigned".utf8))

        _ = try await store.storeSignedHEIC(Data("signed".utf8), captureID: record.captureID)
        #expect(try await store.bestAvailableHEICData(captureID: record.captureID) == Data("signed".utf8))

        try FileManager.default.removeItem(at: signedURL)
        #expect(try await store.bestAvailableHEICData(captureID: record.captureID) == Data("unsigned".utf8))

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

    private static func source(relativePath: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let fileURL = root.appendingPathComponent(relativePath)
        return try String(contentsOf: fileURL, encoding: .utf8)
    }
}
