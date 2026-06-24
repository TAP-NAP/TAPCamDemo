//
//  TAPCaptureContentDigestTests.swift
//  TAPCamDemoTests
//

import Foundation
import AppAttestKit
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
        #expect(json.contains("\"schemaID\":\"urn:tapnap:tapcam:content-binding:v2\""))
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

    private static func bmffBox(_ type: String, payload: Data) -> Data {
        var box = Data()
        box.appendUInt32BE(UInt32(8 + payload.count))
        box.append(Data(type.utf8))
        box.append(payload)
        return box
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
