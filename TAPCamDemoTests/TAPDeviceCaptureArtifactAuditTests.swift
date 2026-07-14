//
//  TAPDeviceCaptureArtifactAuditTests.swift
//  TAPCamDemoTests
//

import Foundation
import ImageIO
import AVFoundation
import AppAttestKit
import Testing
@testable import TAPCamDemo

@Suite(.serialized)
struct TAPDeviceCaptureArtifactAuditTests {
    @MainActor
    @Test func jpgPhysicalDeviceCaptureExportsAndReadsBackFromPhotos() async throws {
        #if targetEnvironment(simulator)
        return
        #else
        let originalFormat = UserDefaults.standard.string(forKey: CameraOutputFormatPreference.storageKey)
        UserDefaults.standard.set(
            CameraOutputFormatPreference.jpeg.rawValue,
            forKey: CameraOutputFormatPreference.storageKey
        )
        defer {
            if let originalFormat {
                UserDefaults.standard.set(originalFormat, forKey: CameraOutputFormatPreference.storageKey)
            } else {
                UserDefaults.standard.removeObject(forKey: CameraOutputFormatPreference.storageKey)
            }
        }

        let store = TAPPendingCaptureStore(
            rootURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("TAPDeviceCaptureJPEGAudit.\(UUID().uuidString)", isDirectory: true)
        )
        let processor = TAPPendingCaptureProcessor()
        let viewModel = CameraViewModel(
            pendingCaptureStore: store,
            pendingCaptureProcessor: processor,
            libraryStore: LibraryMediaStore(observesChanges: false)
        )
        defer {
            viewModel.stop()
        }

        await viewModel.start()
        try await Self.waitForCaptureReadiness(viewModel)

        await viewModel.capture(suppressesShutterSound: true)
        let stagedRecord = try await Self.waitForRecord(
            in: store,
            container: .jpeg
        )
        #expect(stagedRecord.photoFileContainer == .jpeg)

        await processor.processPendingCaptures(
            store: store,
            signer: DeviceAuditPendingCaptureSigner(),
            exporter: PhotoLibraryPendingCaptureExporter(),
            protectedDataIsAvailable: { true }
        )

        let exportedRecord = try await Self.waitForExportedRecord(
            in: store,
            captureID: stagedRecord.captureID
        )
        let artifact = try await Self.auditArtifact(for: exportedRecord)
        #expect(artifact.container == CapturePhotoFileContainer.jpeg.rawValue)
        #expect(artifact.captureScoreValue > 0)
        #expect(!artifact.captureScoreGrade.isEmpty)
        #expect(!artifact.captureScoreDetail.localizedCaseInsensitiveContains("captureID"))
        #expect(!artifact.captureScoreDetail.localizedCaseInsensitiveContains("asset"))
        #expect(!artifact.captureScoreDetail.localizedCaseInsensitiveContains("key"))

        try Self.writeReport(
            DeviceCaptureArtifactAuditReport(
                recordsAvailable: 1,
                recordsChecked: 1,
                artifacts: [artifact]
            ),
            filename: "TAPDeviceCaptureJPEGAudit.json"
        )
        #endif
    }

    @Test func exportedPhysicalDeviceCaptureArtifactsReadBackFromPhotos() async throws {
        #if targetEnvironment(simulator)
        return
        #else
        let records = try await TAPPendingCaptureStore.shared.exportedRecords()
        guard !records.isEmpty else {
            try Self.writeReport(
                DeviceCaptureArtifactAuditReport(
                    recordsAvailable: 0,
                    recordsChecked: 0,
                    artifacts: []
                )
            )
            return
        }

        var artifacts: [DeviceCaptureArtifactAuditReport.Artifact] = []
        for record in records.prefix(2) {
            artifacts.append(try await Self.auditArtifact(for: record))
        }

        #expect(!artifacts.isEmpty)
        try Self.writeReport(
            DeviceCaptureArtifactAuditReport(
                recordsAvailable: records.count,
                recordsChecked: artifacts.count,
                artifacts: artifacts
            )
        )
        #endif
    }

    @MainActor
    private static func waitForCaptureReadiness(
        _ viewModel: CameraViewModel,
        timeout: TimeInterval = 30
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if viewModel.canCapture {
                return
            }
            try await Task.sleep(nanoseconds: 500_000_000)
        }
        throw DeviceCaptureArtifactAuditError.captureNotReady(viewModel.statusMessage)
    }

    private static func waitForRecord(
        in store: TAPPendingCaptureStore,
        container: CapturePhotoFileContainer,
        timeout: TimeInterval = 30
    ) async throws -> TAPPendingCaptureRecord {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let records = try await store.allRecords()
            if let record = records.first(where: { record in
                record.photoFileContainer == container
            }) {
                return record
            }
            try await Task.sleep(nanoseconds: 500_000_000)
        }
        throw DeviceCaptureArtifactAuditError.recordNotFound(container.rawValue)
    }

    private static func waitForExportedRecord(
        in store: TAPPendingCaptureStore,
        captureID: String,
        timeout: TimeInterval = 45
    ) async throws -> TAPPendingCaptureRecord {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let record = try await store.readRecord(captureID: captureID)
            if record.status == .exported, record.assetLocalIdentifier != nil {
                return record
            }
            try await Task.sleep(nanoseconds: 500_000_000)
        }
        throw DeviceCaptureArtifactAuditError.exportNotCompleted(captureID)
    }

    private static func auditArtifact(
        for record: TAPPendingCaptureRecord
    ) async throws -> DeviceCaptureArtifactAuditReport.Artifact {
        let assetID = try #require(record.assetLocalIdentifier)
        let photoData = try await PhotoLibraryWriter.originalPhotoData(localIdentifier: assetID)
        let fileContainer = try TAPDepthPhotoFileReader.fileContainer(from: photoData)
        let manifest = try TAPDepthPhotoFileReader.decodedManifest(from: photoData)
        let depthData = try #require(try TAPDepthPhotoFileReader.depthData(from: photoData))
        let proofEnvelope = try TAPProofSlot.proofEnvelopeData(
            from: photoData,
            fileContainer: fileContainer
        )
        let imageDimensions = try Self.primaryImageDimensions(from: photoData)
        let depthPixelBuffer = depthData.depthDataMap
        let depthWidth = CVPixelBufferGetWidth(depthPixelBuffer)
        let depthHeight = CVPixelBufferGetHeight(depthPixelBuffer)
        let minimumByteCount = fileContainer == .jpeg ? 100_000 : 1_000_000

        #expect(fileContainer == record.photoFileContainer)
        #expect(photoData.count > minimumByteCount)
        #expect(imageDimensions.width > 0)
        #expect(imageDimensions.height > 0)
        #expect(max(imageDimensions.width, imageDimensions.height) >= 3_000)
        #expect(depthWidth > 0)
        #expect(depthHeight > 0)
        #expect(manifest.proofs.isEmpty)
        #expect(!proofEnvelope.isEmpty)
        try CaptureOutputManifestPolicy(profile: record.outputProfile).validate(manifest.payload.capture)
        #expect(
            Self.dimensionsMatchImage(
                imageDimensions,
                manifestDimensions: (
                    width: Int(manifest.payload.photo.width),
                    height: Int(manifest.payload.photo.height)
                )
            )
        )

        return DeviceCaptureArtifactAuditReport.Artifact(
            container: fileContainer.rawValue,
            byteCount: photoData.count,
            imageWidth: imageDimensions.width,
            imageHeight: imageDimensions.height,
            manifestWidth: Int(manifest.payload.photo.width),
            manifestHeight: Int(manifest.payload.photo.height),
            depthWidth: depthWidth,
            depthHeight: depthHeight,
            proofSlotByteCount: TAPProofSlot.payloadByteCount,
            proofEnvelopeByteCount: proofEnvelope.count,
            captureScoreValue: record.captureScoreSummary.value,
            captureScoreGrade: record.captureScoreSummary.grade,
            captureScoreDetail: record.captureScoreSummary.detail
        )
    }

    private static func primaryImageDimensions(from photoData: Data) throws -> (width: Int, height: Int) {
        guard let source = CGImageSourceCreateWithData(photoData as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = integerValue(from: properties[kCGImagePropertyPixelWidth]),
              let height = integerValue(from: properties[kCGImagePropertyPixelHeight]) else {
            throw TAPDepthCaptureError.imageSourceCreationFailed
        }
        return (width, height)
    }

    private static func dimensionsMatchImage(
        _ imageDimensions: (width: Int, height: Int),
        manifestDimensions: (width: Int, height: Int)
    ) -> Bool {
        imageDimensions == manifestDimensions
            || imageDimensions == (width: manifestDimensions.height, height: manifestDimensions.width)
    }

    private static func integerValue(from value: Any?) -> Int? {
        switch value {
        case let value as Int:
            value
        case let value as Int32:
            Int(value)
        case let value as Int64:
            Int(exactly: value)
        case let value as UInt:
            Int(exactly: value)
        case let value as UInt32:
            Int(exactly: value)
        case let value as UInt64:
            Int(exactly: value)
        case let value as NSNumber:
            Int(exactly: value.int64Value)
        default:
            nil
        }
    }

    private static func writeReport(
        _ report: DeviceCaptureArtifactAuditReport,
        filename: String = "TAPDeviceCaptureArtifactAudit.json"
    ) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(report)
        let reportURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(filename)
        try data.write(to: reportURL, options: .atomic)
    }
}

private struct DeviceAuditPendingCaptureSigner: TAPPendingCaptureSigning {
    private let provenanceWriter = TAPCaptureProvenanceWriter()

    func sign(
        _ record: TAPPendingCaptureRecord,
        store: TAPPendingCaptureStore
    ) async throws -> TAPPendingCaptureRecord {
        _ = try await store.updateStatus(captureID: record.captureID, status: .signing)
        let unsignedData = try await store.unsignedPhotoData(captureID: record.captureID)
        let signedPhoto = try await provenanceWriter.signedPhotoData(
            from: unsignedData,
            expectedCaptureID: record.captureID,
            expectedProfile: record.outputProfile,
            assertionSigner: DeviceAuditCaptureAssertionSigner()
        )
        return try await store.storeSignedPhoto(signedPhoto.data, captureID: record.captureID)
    }
}

private struct DeviceAuditCaptureAssertionSigner: CaptureAssertionSigning {
    private static let keyID = "device-audit-test-key"

    func sign(contentDigest: CaptureContentDigest) async throws -> CaptureAssertionProof {
        let signingBinding = try CaptureSigningBinding(contentDigest: contentDigest)
        let proofValue = CaptureAssertionProofValue(
            contentDigest: contentDigest,
            keyId: Self.keyID,
            assertionObject: Data([0xA1, 0x01]).appAttestBase64URL,
            signingBinding: signingBinding
        )
        let proofData = try proofValue.canonicalJSONData()
        let proof = TAPDepthManifest.Proof(
            type: "appAttestAssertion",
            algorithm: "TAPCam.AppAttestCaptureSignature.v1",
            keyID: Self.keyID,
            createdAt: contentDigest.capturedAt,
            value: proofData.appAttestBase64URL
        )
        return CaptureAssertionProof(proof: proof, keyID: Self.keyID)
    }
}

private enum DeviceCaptureArtifactAuditError: LocalizedError {
    case captureNotReady(String)
    case recordNotFound(String)
    case exportNotCompleted(String)

    var errorDescription: String? {
        switch self {
        case .captureNotReady(let status):
            "Physical device capture did not become ready. Last status: \(status)"
        case .recordNotFound(let container):
            "No staged \(container) capture record was written before timeout."
        case .exportNotCompleted:
            "Staged capture was not exported before timeout."
        }
    }
}

private struct DeviceCaptureArtifactAuditReport: Codable, Equatable {
    struct Artifact: Codable, Equatable {
        let container: String
        let byteCount: Int
        let imageWidth: Int
        let imageHeight: Int
        let manifestWidth: Int
        let manifestHeight: Int
        let depthWidth: Int
        let depthHeight: Int
        let proofSlotByteCount: Int
        let proofEnvelopeByteCount: Int
        let captureScoreValue: Int
        let captureScoreGrade: String
        let captureScoreDetail: String
    }

    let recordsAvailable: Int
    let recordsChecked: Int
    let artifacts: [Artifact]
}
