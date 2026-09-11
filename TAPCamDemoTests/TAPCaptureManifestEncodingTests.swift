//
//  TAPCaptureManifestEncodingTests.swift
//  TAPCamDemoTests
//

import Foundation
import Testing
@testable import TAPCamDemo

struct TAPCaptureManifestEncodingTests {
    @Test func embeddedPhotoPayloadBytesAreTheStandaloneHashInput() throws {
        let payload = TAPCamDemoTestFixtures.samplePayload(
            location: TAPCamDemoTestFixtures.sampleHighPrecisionLocation
        )
        let manifest = TAPDepthManifest(payload: payload)
        let photoData = try TAPDepthPhotoFileWriter.injectingManifest(
            manifest,
            into: TAPCamDemoTestFixtures.sampleThumbnailSourceData()
        )
        let document = try TAPDepthPhotoFileReader.decodedManifestDocument(from: photoData)
        let standalonePayloadData = try TAPDepthManifestEncoder.payloadDataExcludingProofs(payload)
        let manifestData = try #require(
            TAPDepthPhotoFileReader.manifestJSON(from: photoData).data(using: .utf8)
        )
        let embeddedRange = try #require(manifestData.range(of: standalonePayloadData))
        let reencodedMetadataHash = try CaptureContentDigest.MetadataHash(payload: payload)

        #expect(document.manifest == manifest)
        #expect(document.rawPayloadData == standalonePayloadData)
        #expect(document.rawPayloadData == manifestData.subdata(in: embeddedRange))
        #expect(
            CaptureContentDigest.MetadataHash(
                payloadData: document.rawPayloadData,
                mediaType: TAPDepthManifest.payloadMediaType
            ) == reencodedMetadataHash
        )
    }

    @Test func bindingReaderPreservesPayloadBytesAcrossOuterWhitespaceAndMemberOrder() throws {
        let payload = #"{ "id": "raw-capture", "capturedAt": "uninterpreted-time", "number": 1e-1, "nested": [0, {"text": "}\"{"}] }"#
        let data = Data(" { \"schema\": {\"description\":null, \"id\":\"\(TAPDepthManifest.schemaIdentifier)\"}, \"proofs\": [null], \"payload\": \(payload) } ".utf8)
        let document = try TAPManifestBindingDocument(data: data)

        #expect(document.captureID == "raw-capture")
        #expect(document.capturedAt == "uninterpreted-time")
        #expect(document.rawPayloadData == Data(payload.utf8))
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(TAPDepthManifest.self, from: data)
        }
    }

    @Test func missingRequiredDepthAvailabilityFailsDecoding() throws {
        let manifest = TAPDepthManifest(
            payload: TAPCamDemoTestFixtures.samplePayload(location: nil)
        )
        let encoded = try TAPDepthManifestEncoder.manifestData(manifest)

        let missingField = try Self.removing(path: ["payload", "depth", "availability"], from: encoded)
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(TAPDepthManifest.self, from: missingField)
        }
    }

    @Test func canonicalEncoderMatchesSharedExactVector() throws {
        let encoded = try JSONEncoder.tapCaptureCanonical.encode(TAPCanonicalJSONGoldenInput())
        let oracle = try Self.canonicalVectorOracle()
        let expected = try #require(Data(base64Encoded: oracle.base64))

        #expect(encoded.count == oracle.byteCount)
        #expect(encoded == expected)
    }

    private static func removing(path: [String], from data: Data) throws -> Data {
        var root = try #require(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        var payload = try #require(root[path[0]] as? [String: Any])
        var object = try #require(payload[path[1]] as? [String: Any])
        object.removeValue(forKey: path[2])
        payload[path[1]] = object
        root[path[0]] = payload
        return try JSONSerialization.data(withJSONObject: root)
    }

    private static func canonicalVectorOracle() throws -> (base64: String, byteCount: Int) {
        let sharedURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("TAPArtifactContracts/examples/vectors/tap-capture-canonical-json-v1.json")
        if FileManager.default.fileExists(atPath: sharedURL.path) {
            let root = try #require(
                JSONSerialization.jsonObject(with: Data(contentsOf: sharedURL)) as? [String: Any]
            )
            return (
                try #require(root["canonicalUTF8Base64"] as? String),
                try #require(root["canonicalUTF8ByteCount"] as? Int)
            )
        }

        return (
            TAPCanonicalJSONGoldenInput.expectedBase64,
            491
        )
    }
}

private struct TAPCanonicalJSONGoldenInput: Encodable {
    static let expectedBase64 = [
        "eyJhcnJheSI6WzMsMSwyXSwiZmFsc2VWYWx1ZSI6ZmFsc2UsImZsb2F0MzJOdW1iZXJzIjpbMCwtMCwwLjEsMy4xNDE1OTI1",
        "LDFlLTQ1LDMuNDAyODIzNWUrMzhdLCJpbnRlZ2VyTWF4Ijo5MjIzMzcyMDM2ODU0Nzc1ODA3LCJpbnRlZ2VyTWluIjotOTIyMzM3",
        "MjAzNjg1NDc3NTgwOCwibmVzdGVkIjp7IkEiOjMsImEiOjIsInoiOjEsIsOpIjo0LCLwkICAIjo1fSwibnVsbFZhbHVlIjpudWxs",
        "LCJudW1iZXJzIjpbMCwtMCwxLC0xLDEuNSwwLjAwMDEsMWUtMDUsMTAwMDAwMDAwMDAwMDAwMCwxZSsxNiwzLjE0MTU5MjY1MzU4",
        "OTc5MywzMzMzMzMzMzMuMzMzMzMzMyw1ZS0zMjQsMS43OTc2OTMxMzQ4NjIzMTU3ZSszMDhdLCJzdHJpbmciOiJzbGFzaCAvIHF1",
        "b3RlIFwiIGJhY2tzbGFzaCBcXCBuZXdsaW5lXG4gY29udHJvbCBcdTAwMDEgY29tcG9zZWQgw6kgZGVjb21wb3NlZCBlzIEgZW1v",
        "amkg8J+YgCBzZXBhcmF0b3JzIOKAqOKAqSIsInRydWVWYWx1ZSI6dHJ1ZX0="
    ].joined()

    private enum CodingKeys: String, CodingKey {
        case trueValue
        case string
        case numbers
        case nullValue
        case nested
        case integerMin
        case integerMax
        case float32Numbers
        case falseValue
        case array
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(true, forKey: .trueValue)
        try container.encode(
            "slash / quote \" backslash \\ newline\n control \u{0001} composed é decomposed e\u{301} emoji 😀 separators \u{2028}\u{2029}",
            forKey: .string
        )
        try container.encode(Self.doubles, forKey: .numbers)
        try container.encodeNil(forKey: .nullValue)
        try container.encode(Nested(), forKey: .nested)
        try container.encode(Int64.min, forKey: .integerMin)
        try container.encode(Int64.max, forKey: .integerMax)
        try container.encode(Self.floats, forKey: .float32Numbers)
        try container.encode(false, forKey: .falseValue)
        try container.encode([3, 1, 2], forKey: .array)
    }

    private static let doubles = ([UInt64](arrayLiteral:
        0x0000000000000000, 0x8000000000000000, 0x3FF0000000000000,
        0xBFF0000000000000, 0x3FF8000000000000, 0x3F1A36E2EB1C432D,
        0x3EE4F8B588E368F1, 0x430C6BF526340000, 0x4341C37937E08000,
        0x400921FB54442D18, 0x41B3DE4355555555, 0x0000000000000001,
        0x7FEFFFFFFFFFFFFF
    )).map(Double.init(bitPattern:))

    private static let floats = ([UInt32](arrayLiteral:
        0x00000000, 0x80000000, 0x3DCCCCCD,
        0x40490FDA, 0x00000001, 0x7F7FFFFF
    )).map(Float.init(bitPattern:))

    private struct Nested: Encodable {
        private enum CodingKeys: String, CodingKey {
            case z
            case a
            case uppercaseA = "A"
            case accentedE = "é"
            case supplementary = "𐀀"
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(1, forKey: .z)
            try container.encode(2, forKey: .a)
            try container.encode(3, forKey: .uppercaseA)
            try container.encode(4, forKey: .accentedE)
            try container.encode(5, forKey: .supplementary)
        }
    }
}
