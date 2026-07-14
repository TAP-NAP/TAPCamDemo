//
//  CaptureContentDigest.swift
//  TAPCamDemo
//

@preconcurrency import AVFoundation
import AppAttestKit
import CryptoKit
import Foundation

/// C2PA-aligned content binding signed by App Attest for one capture.
///
/// The binding is computed from a deterministic view of the saved artifact:
/// all format-native bytes except TAP's fixed proof slot, plus canonical TAP
/// manifest payload bytes. It deliberately does not decode RGB pixels or convert
/// Apple depth into metric Float32 samples.
typealias CaptureContentDigest = CaptureContentBinding

nonisolated struct CaptureContentBinding: Codable, Equatable, Sendable {
    static let schemaIdentifier = "urn:tapnap:tapcam:content-binding:v2"
    static let livePhotoSchemaIdentifier = "urn:tapnap:tapcam:content-binding:v3"
    static let videoSchemaIdentifier = "urn:tapnap:tapcam:content-binding:v4"

    let schemaID: String
    let manifestSchemaID: String
    let captureID: String
    let capturedAt: String
    let assetHash: AssetHash
    let metadataHash: MetadataHash
    let proofSlot: ProofSlot
    let depthResource: DepthResource
    let signedResources: [SignedResource]?

    nonisolated init(
        schemaID: String = CaptureContentBinding.schemaIdentifier,
        manifestSchemaID: String = TAPDepthManifest.schemaIdentifier,
        captureID: String,
        capturedAt: String,
        assetHash: AssetHash,
        metadataHash: MetadataHash,
        proofSlot: ProofSlot,
        depthResource: DepthResource,
        signedResources: [SignedResource]? = nil
    ) {
        self.schemaID = schemaID
        self.manifestSchemaID = manifestSchemaID
        self.captureID = captureID
        self.capturedAt = capturedAt
        self.assetHash = assetHash
        self.metadataHash = metadataHash
        self.proofSlot = proofSlot
        self.depthResource = depthResource
        self.signedResources = signedResources
    }

    static func make(
        manifest: TAPDepthManifest,
        baseHEICData: Data,
        depthData: AVDepthData
    ) throws -> CaptureContentBinding {
        try make(
            manifest: manifest,
            basePhotoData: baseHEICData,
            fileContainer: .heic,
            depthData: depthData
        )
    }

    static func make(
        manifest: TAPDepthManifest,
        basePhotoData: Data,
        fileContainer: CapturePhotoFileContainer,
        depthData: AVDepthData
    ) throws -> CaptureContentBinding {
        try make(
            manifest: manifest,
            basePhotoData: basePhotoData,
            fileContainer: fileContainer,
            depthData: Optional(depthData)
        )
    }

    static func make(
        manifest: TAPDepthManifest,
        basePhotoData: Data,
        fileContainer: CapturePhotoFileContainer,
        depthData: AVDepthData?,
        pairedVideoURL: URL? = nil
    ) throws -> CaptureContentBinding {
        try makeWithMetrics(
            manifest: manifest,
            basePhotoData: basePhotoData,
            fileContainer: fileContainer,
            depthData: depthData,
            pairedVideoURL: pairedVideoURL
        ).digest
    }

    static func makeVideo(
        manifest: TAPVideoManifest,
        mp4FileURL: URL
    ) throws -> CaptureContentBinding {
        let slot = try TAPProofSlot.locateBMFF(inFileAt: mp4FileURL)
        let byteCount = try TAPBMFFStreamingFile.byteCount(of: mp4FileURL)
        guard byteCount <= UInt64(Int.max) else {
            throw TAPDepthCaptureError.pendingCaptureProofInvalid("video file is too large to describe")
        }
        let assetHash = try AssetHash(
            fileContainerIdentifier: "mp4",
            byteCount: Int(byteCount),
            slot: slot,
            value: TAPBMFFStreamingFile.sha256Base64URL(
                of: mp4FileURL,
                excluding: slot.containerRange
            )
        )
        let payloadData = try TAPVideoManifestEncoder.payloadDataExcludingProofs(manifest.payload)
        let metadataHash = MetadataHash(videoPayloadData: payloadData, schemaVersion: manifest.schema.version)

        return CaptureContentBinding(
            schemaID: CaptureContentBinding.videoSchemaIdentifier,
            manifestSchemaID: manifest.schema.id,
            captureID: manifest.payload.id,
            capturedAt: manifest.payload.capturedAt,
            assetHash: assetHash,
            metadataHash: metadataHash,
            proofSlot: ProofSlot(slot),
            depthResource: depthResource(for: manifest.payload.depthCoverage)
        )
    }

    static func makeWithMetrics(
        manifest: TAPDepthManifest,
        baseHEICData: Data,
        depthData: AVDepthData
    ) throws -> CaptureContentDigestBuildResult {
        try makeWithMetrics(
            manifest: manifest,
            basePhotoData: baseHEICData,
            fileContainer: .heic,
            depthData: depthData
        )
    }

    static func makeWithMetrics(
        manifest: TAPDepthManifest,
        basePhotoData: Data,
        fileContainer: CapturePhotoFileContainer,
        depthData: AVDepthData
    ) throws -> CaptureContentDigestBuildResult {
        try makeWithMetrics(
            manifest: manifest,
            basePhotoData: basePhotoData,
            fileContainer: fileContainer,
            depthData: Optional(depthData)
        )
    }

    static func makeWithMetrics(
        manifest: TAPDepthManifest,
        basePhotoData: Data,
        fileContainer: CapturePhotoFileContainer,
        depthData: AVDepthData?,
        pairedVideoURL: URL? = nil
    ) throws -> CaptureContentDigestBuildResult {
        var metrics = CaptureContentDigestMetrics()

        let contentStart = Date()
        let slot = try TAPProofSlot.locate(in: basePhotoData, fileContainer: fileContainer)
        let assetHash = try AssetHash(
            fileContainer: fileContainer,
            byteCount: basePhotoData.count,
            slot: slot,
            value: TAPContentBindingHash.sha256Base64URL(
                data: basePhotoData,
                excluding: slot.containerRange
            )
        )
        metrics.rgbDigestDuration = Date().timeIntervalSince(contentStart)

        let depthStart = Date()
        let depthResource = depthResource(for: depthData == nil ? .unavailable : .available)
        metrics.depthDigestDuration = Date().timeIntervalSince(depthStart)

        let metadataStart = Date()
        let payloadData = try TAPDepthManifestEncoder.payloadDataExcludingProofs(manifest.payload)
        let metadataHash = MetadataHash(payloadData: payloadData, schemaVersion: manifest.schema.version)
        metrics.metadataDigestDuration = Date().timeIntervalSince(metadataStart)
        let livePhotoSignedResources: [SignedResource]?
        if let pairedVideoURL {
            livePhotoSignedResources = try signedResources(
                pairedVideoURL: pairedVideoURL,
                fileContainer: fileContainer,
                assetHash: assetHash,
                metadataHash: metadataHash,
                payloadByteCount: payloadData.count
            )
        } else {
            livePhotoSignedResources = nil
        }

        return CaptureContentDigestBuildResult(
            digest: CaptureContentBinding(
                schemaID: pairedVideoURL == nil
                    ? CaptureContentBinding.schemaIdentifier
                    : CaptureContentBinding.livePhotoSchemaIdentifier,
                manifestSchemaID: manifest.schema.id,
                captureID: manifest.payload.id,
                capturedAt: manifest.payload.capturedAt,
                assetHash: assetHash,
                metadataHash: metadataHash,
                proofSlot: ProofSlot(slot),
                depthResource: depthResource,
                signedResources: livePhotoSignedResources
            ),
            metrics: metrics
        )
    }

    private static func depthResource(for availability: CaptureDepthAvailability) -> DepthResource {
        switch availability {
        case .available:
            DepthResource(
                presence: "required",
                binding: "covered-by-assetHash",
                interpretation: "not-part-of-base-signature",
                platformPresenceCheck: "AVDepthData-readback"
            )
        case .unavailable:
            DepthResource(
                presence: "unavailable",
                binding: "not-present",
                interpretation: "no-depth-captured",
                platformPresenceCheck: "AVDepthData-readback-missing"
            )
        }
    }

    private static func depthResource(for coverage: TAPVideoManifest.DepthCoverage) -> DepthResource {
        DepthResource(
            presence: coverage.sampleCount > 0 ? "captured" : "no-samples",
            binding: coverage.sampleCount > 0 ? "covered-by-assetHash" : "coverage-recorded-in-manifest",
            interpretation: "not-part-of-base-signature",
            platformPresenceCheck: "TAPVideoManifest.depthCoverage"
        )
    }

    private static func signedResources(
        pairedVideoURL: URL,
        fileContainer: CapturePhotoFileContainer,
        assetHash: AssetHash,
        metadataHash: MetadataHash,
        payloadByteCount: Int
    ) throws -> [SignedResource] {
        let pairedVideoData = try Data(contentsOf: pairedVideoURL)
        return [
            SignedResource(
                role: "primaryPhoto",
                kind: assetHash.kind,
                mediaType: fileContainer.uniformTypeIdentifier,
                algorithm: assetHash.algorithm,
                byteCount: assetHash.byteCount,
                value: assetHash.value,
                binding: "format-native-byte-ranges",
                excludedRanges: assetHash.excludedRanges
            ),
            SignedResource(
                role: "tapDepthManifestPayload",
                kind: metadataHash.kind,
                mediaType: metadataHash.mediaType,
                algorithm: metadataHash.algorithm,
                byteCount: payloadByteCount,
                value: metadataHash.value,
                binding: "canonical-json"
            ),
            SignedResource(
                role: "pairedLivePhotoVideo",
                kind: "format-native-full-file",
                mediaType: "com.apple.quicktime-movie",
                algorithm: "SHA-256",
                byteCount: pairedVideoData.count,
                value: TAPContentBindingHash.sha256Base64URL(data: pairedVideoData),
                binding: "full-file"
            )
        ]
    }

    func canonicalJSONData() throws -> Data {
        try JSONEncoder.tapCaptureCanonical.encode(self)
    }

    nonisolated struct AssetHash: Codable, Equatable, Sendable {
        let kind: String
        let fileContainer: String
        let algorithm: String
        let byteCount: Int
        let value: String
        let excludedRanges: [ExcludedRange]

        nonisolated init(
            fileContainer: CapturePhotoFileContainer,
            byteCount: Int,
            slot: TAPProofSlot.Location,
            value: String
        ) {
            self.init(
                fileContainerIdentifier: fileContainer.rawValue,
                byteCount: byteCount,
                slot: slot,
                value: value
            )
        }

        nonisolated init(
            fileContainerIdentifier: String,
            byteCount: Int,
            slot: TAPProofSlot.Location,
            value: String
        ) {
            self.kind = "c2pa-style-format-native-byte-ranges"
            self.fileContainer = fileContainerIdentifier
            self.algorithm = "SHA-256"
            self.byteCount = byteCount
            self.value = value
            self.excludedRanges = [
                ExcludedRange(
                    offset: slot.containerRange.lowerBound,
                    length: slot.containerRange.count,
                    reason: "tap-proof-slot"
                )
            ]
        }

        nonisolated init(
            fileContainerIdentifier: String,
            byteCount: Int,
            slot: TAPProofSlot.FileLocation,
            value: String
        ) {
            self.kind = "c2pa-style-format-native-byte-ranges"
            self.fileContainer = fileContainerIdentifier
            self.algorithm = "SHA-256"
            self.byteCount = byteCount
            self.value = value
            self.excludedRanges = [
                ExcludedRange(
                    offset: Int(slot.containerRange.offset),
                    length: Int(slot.containerRange.length),
                    reason: "tap-proof-slot"
                )
            ]
        }
    }

    nonisolated struct ExcludedRange: Codable, Equatable, Sendable {
        let offset: Int
        let length: Int
        let reason: String
    }

    nonisolated struct MetadataHash: Codable, Equatable, Sendable {
        let kind: String
        let mediaType: String
        let algorithm: String
        let value: String

        nonisolated init(
            kind: String,
            mediaType: String,
            algorithm: String,
            value: String
        ) {
            self.kind = kind
            self.mediaType = mediaType
            self.algorithm = algorithm
            self.value = value
        }

        nonisolated init(payload: TAPDepthManifest.Payload) throws {
            let payloadData = try TAPDepthManifestEncoder.payloadDataExcludingProofs(payload)
            self.init(payloadData: payloadData, schemaVersion: 1)
        }

        nonisolated init(payloadData: Data, schemaVersion: Int) {
            self.kind = "canonical-json"
            self.mediaType = "application/vnd.tapnap.depth-manifest.payload+json;version=\(schemaVersion)"
            self.algorithm = "SHA-256"
            self.value = TAPContentBindingHash.sha256Base64URL(data: payloadData)
        }

        nonisolated init(videoPayloadData: Data, schemaVersion: Int) {
            self.kind = "canonical-json"
            self.mediaType = "application/vnd.tapnap.video-manifest.payload+json;version=\(schemaVersion)"
            self.algorithm = "SHA-256"
            self.value = TAPContentBindingHash.sha256Base64URL(data: videoPayloadData)
        }
    }

    nonisolated struct ProofSlot: Codable, Equatable, Sendable {
        let kind: String
        let offset: Int
        let length: Int
        let payloadOffset: Int
        let payloadLength: Int
        let padding: String

        nonisolated init(_ slot: TAPProofSlot.Location) {
            self.kind = slot.kind.rawValue
            self.offset = slot.containerRange.lowerBound
            self.length = slot.containerRange.count
            self.payloadOffset = slot.payloadRange.lowerBound
            self.payloadLength = slot.payloadRange.count
            self.padding = "zero-filled-after-envelope"
        }


        nonisolated init(_ slot: TAPProofSlot.FileLocation) {
            self.kind = slot.kind.rawValue
            self.offset = Int(slot.containerRange.offset)
            self.length = Int(slot.containerRange.length)
            self.payloadOffset = Int(slot.payloadRange.offset)
            self.payloadLength = Int(slot.payloadRange.length)
            self.padding = "zero-filled-after-envelope"
        }
    }

    nonisolated struct DepthResource: Codable, Equatable, Sendable {
        let presence: String
        let binding: String
        let interpretation: String
        let platformPresenceCheck: String
    }

    nonisolated struct SignedResource: Codable, Equatable, Sendable {
        let role: String
        let kind: String
        let mediaType: String
        let algorithm: String
        let byteCount: Int
        let value: String
        let binding: String
        let excludedRanges: [ExcludedRange]?

        nonisolated init(
            role: String,
            kind: String,
            mediaType: String,
            algorithm: String,
            byteCount: Int,
            value: String,
            binding: String,
            excludedRanges: [ExcludedRange]? = nil
        ) {
            self.role = role
            self.kind = kind
            self.mediaType = mediaType
            self.algorithm = algorithm
            self.byteCount = byteCount
            self.value = value
            self.binding = binding
            self.excludedRanges = excludedRanges
        }
    }
}

nonisolated struct CaptureContentDigestBuildResult: Sendable {
    let digest: CaptureContentBinding
    let metrics: CaptureContentDigestMetrics
}

nonisolated struct CaptureContentDigestMetrics: Equatable, Sendable {
    var rgbDigestDuration: TimeInterval?
    var depthDigestDuration: TimeInterval?
    var metadataDigestDuration: TimeInterval?
}

nonisolated enum TAPContentBindingHash {
    static func sha256Base64URL(data: Data) -> String {
        sha256Base64URL { hasher in
            hasher.update(data: data)
        }
    }

    static func sha256Base64URL(data: Data, excluding excludedRange: Range<Int>) throws -> String {
        guard excludedRange.lowerBound >= 0,
              excludedRange.upperBound <= data.count,
              excludedRange.lowerBound <= excludedRange.upperBound else {
            throw TAPDepthCaptureError.pendingCaptureProofInvalid("invalid proof slot range")
        }

        return sha256Base64URL { hasher in
            if excludedRange.lowerBound > 0 {
                hasher.update(data: data.subdata(in: 0..<excludedRange.lowerBound))
            }
            if excludedRange.upperBound < data.count {
                hasher.update(data: data.subdata(in: excludedRange.upperBound..<data.count))
            }
        }
    }

    private static func sha256Base64URL(_ update: (inout SHA256) -> Void) -> String {
        var hasher = SHA256()
        update(&hasher)
        return Data(hasher.finalize()).appAttestBase64URL
    }
}

nonisolated enum TAPProofSlot {
    static let payloadByteCount = 60 * 1024
    private static let magic = Data("TAPCAM-PROOF-SLOT-V1".utf8)
    private static let headerByteCount = 32
    private static let version: UInt32 = 1
    private static let bmffUUID = Data([
        0x54, 0x41, 0x50, 0x43, 0x41, 0x4d, 0x50, 0x52,
        0x4f, 0x4f, 0x46, 0x53, 0x4c, 0x4f, 0x54, 0x31
    ])

    enum Kind: String, Codable, Equatable, Sendable {
        case bmffUUIDBox = "bmff-uuid-proof-slot"
        case jpegAPP11Segment = "jpeg-app11-proof-slot"
    }

    struct Location: Equatable, Sendable {
        let kind: Kind
        let containerRange: Range<Int>
        let payloadRange: Range<Int>
    }

    struct FileLocation: Equatable, Sendable {
        let kind: Kind
        let containerRange: TAPFileByteRange
        let payloadRange: TAPFileByteRange
    }

    static func ensuringEmptySlot(
        in photoData: Data,
        fileContainer: CapturePhotoFileContainer
    ) throws -> Data {
        do {
            _ = try locate(in: photoData, fileContainer: fileContainer)
            return photoData
        } catch TAPDepthCaptureError.pendingCaptureProofMissing {
            switch fileContainer {
            case .heic:
                return photoData + bmffProofBox(payload: emptyPayload())
            case .jpeg:
                return try jpegDataByInsertingAPP11Slot(into: photoData, payload: emptyPayload())
            }
        } catch {
            throw error
        }
    }

    static func ensureEmptyBMFFSlot(inFileAt fileURL: URL) throws -> FileLocation {
        do {
            return try locateBMFF(inFileAt: fileURL)
        } catch TAPDepthCaptureError.pendingCaptureProofMissing {
            let boxes = try TAPBMFFStreamingFile.topLevelBoxes(at: fileURL)
            guard boxes.last?.usesToEndSize != true else {
                throw TAPDepthCaptureError.pendingCaptureProofInvalid(
                    "cannot append TAP proof slot after a BMFF size-zero box"
                )
            }
            try TAPBMFFStreamingFile.append(
                bmffProofBox(payload: emptyPayload()),
                to: fileURL
            )
            return try locateBMFF(inFileAt: fileURL)
        }
    }

    static func writeProofEnvelope(
        _ envelope: Data,
        into photoData: Data,
        fileContainer: CapturePhotoFileContainer
    ) throws -> Data {
        let slot = try locate(in: photoData, fileContainer: fileContainer)
        let payload = try payload(envelope: envelope)
        var output = photoData
        output.replaceSubrange(slot.payloadRange, with: payload)
        return output
    }

    static func writeProofEnvelope(
        _ envelope: Data,
        intoBMFFFileAt fileURL: URL
    ) throws {
        let slot = try locateBMFF(inFileAt: fileURL)
        try TAPBMFFStreamingFile.overwrite(
            try payload(envelope: envelope),
            in: slot.payloadRange,
            at: fileURL
        )
    }

    static func resetBMFFProofSlot(inFileAt fileURL: URL) throws {
        let slot = try locateBMFF(inFileAt: fileURL)
        try TAPBMFFStreamingFile.overwrite(
            emptyPayload(),
            in: slot.payloadRange,
            at: fileURL
        )
    }

    static func proofEnvelopeData(
        from photoData: Data,
        fileContainer: CapturePhotoFileContainer
    ) throws -> Data {
        let slot = try locate(in: photoData, fileContainer: fileContainer)
        let payload = photoData.subdata(in: slot.payloadRange)
        return try envelopeData(fromPayload: payload)
    }

    static func proofEnvelopeData(fromBMFFFileAt fileURL: URL) throws -> Data {
        let slot = try locateBMFF(inFileAt: fileURL)
        let payload = try TAPBMFFStreamingFile.read(
            slot.payloadRange,
            from: fileURL,
            maximumByteCount: payloadByteCount
        )
        return try envelopeData(fromPayload: payload)
    }

    static func locate(
        in photoData: Data,
        fileContainer: CapturePhotoFileContainer
    ) throws -> Location {
        switch fileContainer {
        case .heic:
            return try locateBMFFSlot(in: photoData)
        case .jpeg:
            return try locateJPEGSlot(in: photoData)
        }
    }

    static func locateBMFF(inFileAt fileURL: URL) throws -> FileLocation {
        let matches = try TAPVideoContainerLayout.read(from: fileURL).topLevelBoxes
            .filter { $0.type == "uuid" && $0.userType == bmffUUID }
        guard !matches.isEmpty else {
            throw TAPDepthCaptureError.pendingCaptureProofMissing
        }
        guard matches.count == 1, let match = matches.first else {
            throw TAPDepthCaptureError.pendingCaptureProofInvalid("expected exactly one TAP proof slot")
        }
        guard match.payloadRange.length == UInt64(payloadByteCount) else {
            throw TAPDepthCaptureError.pendingCaptureProofInvalid("unexpected proof slot length")
        }
        return FileLocation(
            kind: .bmffUUIDBox,
            containerRange: match.range,
            payloadRange: match.payloadRange
        )
    }

    private static func emptyPayload() -> Data {
        try! payload(envelope: Data())
    }

    private static func payload(envelope: Data) throws -> Data {
        let payloadCapacity = payloadByteCount - headerByteCount
        guard envelope.count <= payloadCapacity else {
            throw TAPDepthCaptureError.pendingCaptureProofInvalid("proof envelope exceeds fixed proof slot")
        }

        var payload = Data(repeating: 0, count: payloadByteCount)
        payload.replaceSubrange(0..<magic.count, with: magic)
        payload.writeUInt32BE(version, at: 24)
        payload.writeUInt32BE(UInt32(envelope.count), at: 28)
        payload.replaceSubrange(headerByteCount..<(headerByteCount + envelope.count), with: envelope)
        return payload
    }

    private static func envelopeData(fromPayload payload: Data) throws -> Data {
        guard payload.count == payloadByteCount,
              payload.subdata(in: 0..<magic.count) == magic,
              payload.readUInt32BE(at: 24) == version else {
            throw TAPDepthCaptureError.pendingCaptureProofInvalid("invalid proof slot header")
        }

        let envelopeLength = Int(payload.readUInt32BE(at: 28))
        guard envelopeLength > 0 else {
            throw TAPDepthCaptureError.pendingCaptureProofMissing
        }
        guard envelopeLength <= payloadByteCount - headerByteCount else {
            throw TAPDepthCaptureError.pendingCaptureProofInvalid("invalid proof envelope length")
        }

        let envelopeRange = headerByteCount..<(headerByteCount + envelopeLength)
        let paddingRange = envelopeRange.upperBound..<payloadByteCount
        guard payload[paddingRange].allSatisfy({ $0 == 0 }) else {
            throw TAPDepthCaptureError.pendingCaptureProofInvalid("proof slot padding is not zero-filled")
        }

        return payload.subdata(in: envelopeRange)
    }

    private static func bmffProofBox(payload: Data) -> Data {
        var box = Data()
        box.appendUInt32BE(UInt32(8 + bmffUUID.count + payload.count))
        box.append(Data("uuid".utf8))
        box.append(bmffUUID)
        box.append(payload)
        return box
    }

    private static func locateBMFFSlot(in data: Data) throws -> Location {
        var offset = 0
        var matches = [Location]()

        while offset + 8 <= data.count {
            let boxStart = offset
            let size32 = data.readUInt32BE(at: offset)
            let typeStart = offset + 4
            let type = data.subdata(in: typeStart..<(typeStart + 4))
            offset += 8

            let boxSize: Int
            if size32 == 1 {
                guard offset + 8 <= data.count else { break }
                let largeSize = data.readUInt64BE(at: offset)
                guard largeSize <= UInt64(Int.max) else { break }
                boxSize = Int(largeSize)
                offset += 8
            } else if size32 == 0 {
                boxSize = data.count - boxStart
            } else {
                boxSize = Int(size32)
            }

            guard boxSize >= offset - boxStart,
                  boxStart + boxSize <= data.count else {
                break
            }

            if type == Data("uuid".utf8),
               offset + bmffUUID.count <= boxStart + boxSize,
               data.subdata(in: offset..<(offset + bmffUUID.count)) == bmffUUID {
                let payloadStart = offset + bmffUUID.count
                let payloadEnd = boxStart + boxSize
                matches.append(Location(
                    kind: .bmffUUIDBox,
                    containerRange: boxStart..<(boxStart + boxSize),
                    payloadRange: payloadStart..<payloadEnd
                ))
            }

            offset = boxStart + boxSize
        }

        guard !matches.isEmpty else {
            throw TAPDepthCaptureError.pendingCaptureProofMissing
        }
        guard matches.count == 1, let match = matches.first else {
            throw TAPDepthCaptureError.pendingCaptureProofInvalid("expected exactly one TAP proof slot")
        }
        guard match.payloadRange.count == payloadByteCount else {
            throw TAPDepthCaptureError.pendingCaptureProofInvalid("unexpected proof slot length")
        }
        return match
    }

    private static func jpegDataByInsertingAPP11Slot(into data: Data, payload: Data) throws -> Data {
        guard data.count >= 2,
              data[0] == 0xFF,
              data[1] == 0xD8 else {
            throw TAPDepthCaptureError.invalidHEICContainerType("public.jpeg")
        }

        var segment = Data([0xFF, 0xEB])
        segment.appendUInt16BE(UInt16(payload.count + 2))
        segment.append(payload)

        var output = Data()
        output.append(data.subdata(in: 0..<2))
        output.append(segment)
        output.append(data.subdata(in: 2..<data.count))
        return output
    }

    private static func locateJPEGSlot(in data: Data) throws -> Location {
        guard data.count >= 2,
              data[0] == 0xFF,
              data[1] == 0xD8 else {
            throw TAPDepthCaptureError.pendingCaptureProofMissing
        }

        var offset = 2
        var matches = [Location]()

        while offset + 4 <= data.count {
            guard data[offset] == 0xFF else { break }
            var markerOffset = offset
            while markerOffset < data.count, data[markerOffset] == 0xFF {
                markerOffset += 1
            }
            guard markerOffset < data.count else { break }
            let marker = data[markerOffset]
            offset = markerOffset + 1

            if marker == 0xD9 || marker == 0xDA {
                break
            }
            if (0xD0...0xD7).contains(marker) || marker == 0x01 {
                continue
            }

            guard offset + 2 <= data.count else { break }
            let segmentLength = Int(data.readUInt16BE(at: offset))
            let segmentStart = markerOffset - 1
            let payloadStart = offset + 2
            let segmentEnd = offset + segmentLength
            guard segmentLength >= 2, segmentEnd <= data.count else { break }

            if marker == 0xEB,
               segmentLength == payloadByteCount + 2,
               data.subdata(in: payloadStart..<(payloadStart + magic.count)) == magic {
                matches.append(Location(
                    kind: .jpegAPP11Segment,
                    containerRange: segmentStart..<segmentEnd,
                    payloadRange: payloadStart..<segmentEnd
                ))
            }

            offset = segmentEnd
        }

        guard !matches.isEmpty else {
            throw TAPDepthCaptureError.pendingCaptureProofMissing
        }
        guard matches.count == 1, let match = matches.first else {
            throw TAPDepthCaptureError.pendingCaptureProofInvalid("expected exactly one TAP proof slot")
        }
        return match
    }
}

private extension Data {
    nonisolated mutating func appendUInt16BE(_ value: UInt16) {
        append(contentsOf: [
            UInt8((value >> 8) & 0xff),
            UInt8(value & 0xff)
        ])
    }

    nonisolated mutating func appendUInt32BE(_ value: UInt32) {
        append(contentsOf: [
            UInt8((value >> 24) & 0xff),
            UInt8((value >> 16) & 0xff),
            UInt8((value >> 8) & 0xff),
            UInt8(value & 0xff)
        ])
    }

    nonisolated mutating func writeUInt32BE(_ value: UInt32, at offset: Int) {
        self[offset] = UInt8((value >> 24) & 0xff)
        self[offset + 1] = UInt8((value >> 16) & 0xff)
        self[offset + 2] = UInt8((value >> 8) & 0xff)
        self[offset + 3] = UInt8(value & 0xff)
    }

    nonisolated func readUInt16BE(at offset: Int) -> UInt16 {
        (UInt16(self[offset]) << 8) | UInt16(self[offset + 1])
    }

    nonisolated func readUInt32BE(at offset: Int) -> UInt32 {
        (UInt32(self[offset]) << 24)
            | (UInt32(self[offset + 1]) << 16)
            | (UInt32(self[offset + 2]) << 8)
            | UInt32(self[offset + 3])
    }

    nonisolated func readUInt64BE(at offset: Int) -> UInt64 {
        var value: UInt64 = 0
        for index in 0..<8 {
            value = (value << 8) | UInt64(self[offset + index])
        }
        return value
    }
}

nonisolated extension JSONEncoder {
    static var tapCaptureCanonical: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }
}
