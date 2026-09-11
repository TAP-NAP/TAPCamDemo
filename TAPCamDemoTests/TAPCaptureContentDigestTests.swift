//
//  TAPCaptureContentDigestTests.swift
//  TAPCamDemoTests
//

import Foundation
import CryptoKit
import Testing
@testable import TAPCamDemo

struct TAPCaptureContentDigestTests {
    @Test func captureContentBindingCanonicalJSONIsStable() throws {
        let digest = TAPCaptureProvenanceTestFixtures.sampleContentDigest()
        let first = try digest.canonicalJSONData()
        let second = try digest.canonicalJSONData()
        let decoded = try JSONDecoder().decode(CaptureContentDigest.self, from: first)
        let json = try #require(String(data: first, encoding: .utf8))

        #expect(first == second)
        #expect(decoded == digest)
        #expect(json.contains("\"captureID\":\"sample-capture\""))
        #expect(json.contains("\"schemaID\":\"urn:tapnap:tapcam:still-photo-content-binding:v1\""))
        #expect(json.contains("\"kind\":\"c2pa-style-format-native-byte-ranges\""))
        #expect(json.contains("\"depthResource\""))
    }

    @Test func captureContentBindingDoesNotUsePlatformDecodedPixelsOrConvertedDepth() throws {
        let source = try TAPCamDemoTestSourceInspection.source(
            relativePath: "TAPCamDemo/CameraCapture/Output/CaptureContentDigest.swift"
        )

        #expect(!source.contains("CGImageSourceCreateImageAtIndex"))
        #expect(!source.contains("CGContext("))
        #expect(!source.contains("converting(toDepthDataType:"))
    }

    @Test func livePhotoContentBindingAddsSignedResources() throws {
        let movieURL = try TAPCamDemoTestFixtures.makeTemporaryDirectory()
            .appendingPathComponent("paired-video.mov")
        let movieData = Data("paired-video".utf8)
        try movieData.write(to: movieURL)
        let photoData = try TAPProofSlot.ensuringEmptySlot(
            in: Self.syntheticBMFFData(),
            fileContainer: .heic
        )
        let manifest = TAPDepthManifest(
            payload: TAPCamDemoTestFixtures.samplePayload(
                location: nil,
                capture: TAPCamDemoTestFixtures.sampleManifestCapture(depthAvailability: .unavailable),
                depthAvailability: .unavailable,
                livePhoto: TAPDepthManifest.LivePhoto(
                    presence: "paired-video",
                    pairedVideoFilename: "paired-video.mov",
                    durationSeconds: 1.2,
                    photoDisplayTimeSeconds: 0.5,
                    width: 1440,
                    height: 1080,
                    videoCodec: "hvc1",
                    audio: "not-captured"
                )
            ),
            schema: .livePhoto
        )

        let digest = try CaptureContentDigest.makePhoto(
            document: TAPManifestBindingDocument(data: TAPDepthManifestEncoder.manifestData(manifest)),
            photoData: photoData,
            fileContainer: .heic,
            pairedVideoURL: movieURL
        )
        let primaryDigest = try CaptureContentDigest.makePhoto(
            document: TAPManifestBindingDocument(data: TAPDepthManifestEncoder.manifestData(manifest)),
            photoData: photoData,
            fileContainer: .heic
        )
        let resources = try #require(digest.signedResources)
        let expectedMovieHash = try Self.sha256Base64URL(movieData)

        #expect(digest.schemaID == CaptureContentBinding.livePhotoSchemaIdentifier)
        #expect(digest.manifestSchemaID == TAPDepthManifest.livePhotoSchemaIdentifier)
        #expect(digest.metadataHash.mediaType == "application/vnd.tapnap.live-photo-manifest.payload+json;version=1")
        #expect(resources.map(\.role) == ["primaryPhoto", "tapDepthManifestPayload", "pairedLivePhotoVideo"])
        #expect(resources.last?.mediaType == "com.apple.quicktime-movie")
        #expect(resources.last?.byteCount == movieData.count)
        #expect(resources.last?.value == expectedMovieHash)
        #expect(try String(data: digest.canonicalJSONData(), encoding: .utf8)?.contains("\"signedResources\"") == true)
        #expect(primaryDigest.assetHash == digest.assetHash)
        #expect(primaryDigest.metadataHash == digest.metadataHash)
        #expect(primaryDigest.captureID == digest.captureID)
        #expect(primaryDigest.capturedAt == digest.capturedAt)
    }

    @Test func videoContentBindingHashesMP4BytesExcludingBMFFProofSlot() throws {
        let manifest = Self.sampleVideoManifest(depthSampleCount: 2)
        let fileURL = try Self.makeTemporaryVideoFile()
        let slot = try TAPProofSlot.ensureEmptyBMFFSlot(inFileAt: fileURL)

        let emptyDigest = try CaptureContentDigest.makeVideo(
            document: TAPManifestBindingDocument(data: TAPVideoManifestEncoder.manifestData(manifest)),
            mp4FileURL: fileURL
        )
        try TAPProofSlot.writeProofEnvelope(
            Data("proof-envelope".utf8),
            intoBMFFFileAt: fileURL
        )
        let proofDigest = try CaptureContentDigest.makeVideo(
            document: TAPManifestBindingDocument(data: TAPVideoManifestEncoder.manifestData(manifest)),
            mp4FileURL: fileURL
        )

        #expect(emptyDigest.schemaID == CaptureContentBinding.videoSchemaIdentifier)
        #expect(emptyDigest.manifestSchemaID == TAPVideoManifest.schemaIdentifier)
        #expect(emptyDigest.assetHash.fileContainer == "mp4")
        #expect(emptyDigest.assetHash.value == proofDigest.assetHash.value)
        #expect(emptyDigest.metadataHash.mediaType == "application/vnd.tapnap.video-manifest.payload+json;version=1")
        #expect(emptyDigest.depthResource.presence == "captured")
        #expect(emptyDigest.proofSlot.offset == Int(slot.containerRange.offset))
        #expect(try TAPProofSlot.proofEnvelopeData(fromBMFFFileAt: fileURL) == Data("proof-envelope".utf8))
    }

    @Test func videoContentBindingUsesV1ManifestAndCapturedDepthCoverage() throws {
        let manifest = Self.sampleVideoManifest(depthSampleCount: 1)
        let fileURL = try Self.makeTemporaryVideoFile()
        _ = try TAPProofSlot.ensureEmptyBMFFSlot(inFileAt: fileURL)

        let digest = try CaptureContentDigest.makeVideo(
            document: TAPManifestBindingDocument(data: TAPVideoManifestEncoder.manifestData(manifest)),
            mp4FileURL: fileURL
        )

        #expect(digest.schemaID == "urn:tapnap:tapcam:video-content-binding:v1")
        #expect(digest.manifestSchemaID == "urn:tapnap:tapcam:video-manifest:v1")
        #expect(digest.depthResource.presence == "captured")
        #expect(digest.depthResource.binding == "covered-by-assetHash")
        #expect(digest.signedResources == nil)
    }

    @Test func videoContentBindingRejectsNonCurrentManifestSchema() throws {
        let currentManifest = Self.sampleVideoManifest(depthSampleCount: 0)
        let oldManifest = TAPVideoManifest(
            payload: currentManifest.payload,
            schema: TAPVideoManifest.Schema(
                id: "urn:tapnap:tapcam:video-manifest:v2",
                version: 2,
                mediaType: "application/vnd.tapnap.video-manifest+json;version=2"
            )
        )
        let fileURL = try Self.makeTemporaryVideoFile()
        _ = try TAPProofSlot.ensureEmptyBMFFSlot(inFileAt: fileURL)

        #expect(throws: TAPDepthCaptureError.self) {
            try CaptureContentDigest.makeVideo(
                document: TAPManifestBindingDocument(data: TAPVideoManifestEncoder.manifestData(oldManifest)),
                mp4FileURL: fileURL
            )
        }
    }

    @Test func bmffProofSlotIsFixedSizeAndExcludedFromAssetHash() throws {
        let baseData = Self.syntheticBMFFData()
        let emptySlotData = try TAPProofSlot.ensuringEmptySlot(
            in: baseData,
            fileContainer: .heic
        )
        let proofSlotData = try TAPProofSlot.writeProofEnvelope(
            Data("proof-envelope".utf8),
            into: emptySlotData,
            fileContainer: .heic
        )
        let emptySlot = try TAPProofSlot.locate(in: emptySlotData, fileContainer: .heic)
        let proofSlot = try TAPProofSlot.locate(in: proofSlotData, fileContainer: .heic)

        #expect(emptySlot.containerRange == proofSlot.containerRange)
        #expect(emptySlot.payloadRange.count == TAPProofSlot.payloadByteCount)
        #expect(try TAPProofSlot.proofEnvelopeData(from: proofSlotData, fileContainer: .heic) == Data("proof-envelope".utf8))
        #expect(try Self.sha256Base64URL(emptySlotData, excluding: emptySlot.containerRange) == Self.sha256Base64URL(proofSlotData, excluding: proofSlot.containerRange))
        #expect(try Self.sha256Base64URL(emptySlotData, excluding: emptySlot.containerRange) == Self.sha256Base64URL(baseData))
    }

    @Test func jpegProofSlotIsFixedSizeAndExcludedFromAssetHash() throws {
        let baseData = Data([0xff, 0xd8, 0xff, 0xe0, 0x00, 0x04, 0x4a, 0x46, 0xff, 0xd9])
        let emptySlotData = try TAPProofSlot.ensuringEmptySlot(
            in: baseData,
            fileContainer: .jpeg
        )
        let proofSlotData = try TAPProofSlot.writeProofEnvelope(
            Data("proof-envelope".utf8),
            into: emptySlotData,
            fileContainer: .jpeg
        )
        let emptySlot = try TAPProofSlot.locate(in: emptySlotData, fileContainer: .jpeg)
        let proofSlot = try TAPProofSlot.locate(in: proofSlotData, fileContainer: .jpeg)

        #expect(emptySlot.containerRange == proofSlot.containerRange)
        #expect(emptySlot.payloadRange.count == TAPProofSlot.payloadByteCount)
        #expect(try TAPProofSlot.proofEnvelopeData(from: proofSlotData, fileContainer: .jpeg) == Data("proof-envelope".utf8))
        #expect(try Self.sha256Base64URL(emptySlotData, excluding: emptySlot.containerRange) == Self.sha256Base64URL(proofSlotData, excluding: proofSlot.containerRange))
        #expect(try Self.sha256Base64URL(emptySlotData, excluding: emptySlot.containerRange) == Self.sha256Base64URL(baseData))
    }

    @Test func proofSlotRejectsNonZeroPaddingAfterEnvelope() throws {
        let emptySlotData = try TAPProofSlot.ensuringEmptySlot(
            in: Self.syntheticBMFFData(),
            fileContainer: .heic
        )
        var proofSlotData = try TAPProofSlot.writeProofEnvelope(
            Data("proof-envelope".utf8),
            into: emptySlotData,
            fileContainer: .heic
        )
        let slot = try TAPProofSlot.locate(in: proofSlotData, fileContainer: .heic)
        proofSlotData[slot.payloadRange.upperBound - 1] = 0x01

        #expect(throws: TAPDepthCaptureError.self) {
            try TAPProofSlot.proofEnvelopeData(from: proofSlotData, fileContainer: .heic)
        }
    }

    @Test func proofSlotReservationRejectsDuplicateSlots() throws {
        let emptySlotData = try TAPProofSlot.ensuringEmptySlot(
            in: Self.syntheticBMFFData(),
            fileContainer: .heic
        )
        let slot = try TAPProofSlot.locate(in: emptySlotData, fileContainer: .heic)
        let duplicatedSlotData = emptySlotData + emptySlotData.subdata(in: slot.containerRange)

        #expect(throws: TAPDepthCaptureError.self) {
            try TAPProofSlot.locate(in: duplicatedSlotData, fileContainer: .heic)
        }
        #expect(throws: TAPDepthCaptureError.self) {
            try TAPProofSlot.ensuringEmptySlot(in: duplicatedSlotData, fileContainer: .heic)
        }
    }

    private static func syntheticBMFFData() -> Data {
        bmffBox("ftyp", payload: Data("heic".utf8))
            + bmffBox("meta", payload: Data([0x00, 0x00, 0x00, 0x00, 0x69, 0x69, 0x64, 0x00]))
            + bmffBox("mdat", payload: Data("primary-image-bytes-and-depth-aux-bytes".utf8))
    }

    private static func syntheticMP4Data() -> Data {
        bmffBox("ftyp", payload: Data("mp42".utf8))
            + bmffBox("moov", payload: Data("movie-metadata".utf8))
            + bmffBox("mdat", payload: Data("rgb-audio-depth-track-bytes".utf8))
    }

    private static func sampleVideoManifest(depthSampleCount: Int) -> TAPVideoManifest {
        TAPVideoManifest(payload: TAPVideoManifest.Payload(
            id: "video-capture",
            packageID: "00000000-0000-0000-0000-000000000777",
            capturedAt: "2026-07-09T12:00:00Z",
            selectedCameraPlan: TAPVideoManifest.SelectedCameraPlan(
                deviceUniqueID: "device-1",
                deviceType: "BuiltInLiDARDepthCamera",
                localizedName: "Back Camera",
                position: "back",
                requestedFocalLengthLabel: "24mm",
                resolvedFocalLengthLabel: "24mm",
                resolvedZoomFactor: 1,
                depthCapable: true
            ),
            container: TAPVideoManifest.Container(
                fileType: "mp4",
                mediaType: "video/mp4",
                durationSeconds: 1,
                timeScale: 600,
                trackCount: depthSampleCount > 0 ? 2 : 1
            ),
            rgbTrack: TAPVideoManifest.RGBTrack(
                trackID: 1,
                codec: "avc1",
                width: 1920,
                height: 1080,
                durationSeconds: 1,
                timeScale: 600,
                nominalFrameRate: 30,
                frameCount: 30,
                transform: "identity"
            ),
            audioTrack: TAPVideoManifest.AudioTrack(
                status: .notCaptured,
                trackID: nil,
                codec: nil,
                durationSeconds: nil,
                timeScale: nil,
                sampleRate: nil,
                channelCount: nil
            ),
            depthCoverage: TAPVideoManifest.DepthCoverage(
                trackID: depthSampleCount > 0 ? 3 : nil,
                trackCodec: depthSampleCount > 0 ? "mebx" : nil,
                trackDurationSeconds: depthSampleCount > 0 ? 1 : nil,
                trackTimeScale: depthSampleCount > 0 ? 600 : nil,
                sampleCount: depthSampleCount,
                format: depthSampleCount > 0
                    ? TAPVideoManifest.DepthFormat(
                        kind: "depth",
                        pixelFormat: "DepthFloat32",
                        width: 256,
                        height: 192,
                        packedRowStride: 1_024,
                        sourceRowStride: 1_088,
                        bytesPerSample: 4,
                        uncompressedFrameByteCount: 196_608
                    )
                    : nil
            ),
            synchronization: TAPVideoManifest.Synchronization(
                timing: "sample-timestamps",
                rgbToDepthMapping: "nearest-rgb-frame",
                maxObservedDeltaSeconds: nil
            ),
            stop: TAPVideoManifest.Stop(
                reason: .userStop,
                recordedDurationSeconds: 1
            ),
            software: TAPVideoManifest.Software(
                appIdentifier: "net.tapcam.demo",
                appVersion: "1.0",
                buildNumber: "1",
                schemaWriter: "TAPVideoManifestEncoder"
            )
        ))
    }

    private static func bmffBox(_ type: String, payload: Data) -> Data {
        var box = Data()
        box.appendUInt32BE(UInt32(8 + payload.count))
        box.append(Data(type.utf8))
        box.append(payload)
        return box
    }

    private static func makeTemporaryVideoFile() throws -> URL {
        let directoryURL = try TAPCamDemoTestFixtures.makeTemporaryDirectory()
        let fileURL = directoryURL.appendingPathComponent("artifact.mp4")
        try syntheticMP4Data().write(to: fileURL)
        return fileURL
    }

    private static func sha256Base64URL(_ data: Data, excluding excludedRange: Range<Int>? = nil) throws -> String {
        var hasher = SHA256()
        if let excludedRange {
            guard excludedRange.lowerBound >= 0,
                  excludedRange.upperBound <= data.count,
                  excludedRange.lowerBound <= excludedRange.upperBound else {
                throw TAPDepthCaptureError.pendingCaptureProofInvalid("invalid proof slot range")
            }
            if excludedRange.lowerBound > 0 {
                hasher.update(data: data.subdata(in: 0..<excludedRange.lowerBound))
            }
            if excludedRange.upperBound < data.count {
                hasher.update(data: data.subdata(in: excludedRange.upperBound..<data.count))
            }
        } else {
            hasher.update(data: data)
        }
        return Data(hasher.finalize()).appAttestBase64URL
    }
}

private extension Data {
    mutating func appendUInt32BE(_ value: UInt32) {
        append(contentsOf: [
            UInt8((value >> 24) & 0xff),
            UInt8((value >> 16) & 0xff),
            UInt8((value >> 8) & 0xff),
            UInt8(value & 0xff)
        ])
    }
}
