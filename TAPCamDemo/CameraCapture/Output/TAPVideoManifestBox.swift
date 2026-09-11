//
//  TAPVideoManifestBox.swift
//  TAPCamDemo
//

import Foundation

/// Metadata from one current file read, retained only for this validation.
nonisolated struct TAPVideoValidationInput: Sendable {
    let fileURL: URL
    let layout: TAPVideoContainerLayout
    let manifestDocument: TAPManifestBindingDocument

    init(fileURL: URL) throws {
        try Task<Never, Never>.checkCancellation()
        self.fileURL = fileURL
        layout = try TAPVideoContainerLayout.read(from: fileURL)
        manifestDocument = try TAPManifestBindingDocument(data: TAPVideoManifestBox.manifestData(
            fromFileAt: fileURL, layout: layout
        ))
    }
}

/// TAP-private top-level BMFF `uuid` box that stores the video manifest JSON.
///
/// The manifest box is part of the signed MP4 byte stream. Only the separate
/// TAP proof slot is excluded from the content hash.
nonisolated enum TAPVideoManifestBox {
    private static let uuid = Data("TAPCAMVIDEOMANF1".utf8)

    static func appendManifest(_ manifest: TAPVideoManifest, toFileAt fileURL: URL) throws {
        let boxes = try TAPVideoContainerLayout.read(from: fileURL).topLevelBoxes
        guard !boxes.contains(where: { $0.type == "uuid" && $0.userType == uuid }) else {
            throw TAPDepthCaptureError.invalidTAPManifest("expected no existing TAP video manifest box")
        }
        guard boxes.last?.usesToEndSize != true else {
            throw TAPDepthCaptureError.invalidTAPManifest(
                "cannot append TAP video boxes after a BMFF size-zero box"
            )
        }
        let manifestData = try TAPVideoManifestEncoder.manifestData(manifest)
        guard manifestData.count <= TAPBMFFStreamingFile.maximumManifestByteCount else {
            throw TAPDepthCaptureError.invalidTAPManifest(
                "TAP video manifest exceeds bounded payload limit"
            )
        }
        try TAPBMFFStreamingFile.append(bmffUUIDBox(payload: manifestData), to: fileURL)
    }

    static func decodedManifest(fromFileAt fileURL: URL) throws -> TAPVideoManifest {
        try decodedManifestDocument(fromFileAt: fileURL).manifest
    }

    static func decodedManifestDocument(
        fromFileAt fileURL: URL,
        layout: TAPVideoContainerLayout? = nil
    ) throws -> TAPVideoManifestDocument {
        let manifestData = try manifestData(fromFileAt: fileURL, layout: layout)
        return try TAPVideoManifestEncoder.decodedDocument(from: manifestData)
    }

    /// A supplied layout must come from this unchanged file in the current operation.
    static func manifestData(
        fromFileAt fileURL: URL,
        layout: TAPVideoContainerLayout? = nil
    ) throws -> Data {
        let layout = try layout ?? TAPVideoContainerLayout.read(from: fileURL)
        let matches = layout.topLevelBoxes
            .filter { $0.type == "uuid" && $0.userType == uuid }
        guard !matches.isEmpty else {
            throw TAPDepthCaptureError.xmpManifestMissing
        }
        guard matches.count == 1, let match = matches.first else {
            throw TAPDepthCaptureError.invalidTAPManifest("expected exactly one TAP video manifest box")
        }
        return try TAPBMFFStreamingFile.read(
            match.payloadRange,
            from: fileURL,
            maximumByteCount: TAPBMFFStreamingFile.maximumManifestByteCount
        )
    }

    private static func bmffUUIDBox(payload: Data) -> Data {
        var box = Data()
        box.appendUInt32BE(UInt32(8 + uuid.count + payload.count))
        box.append(Data("uuid".utf8))
        box.append(uuid)
        box.append(payload)
        return box
    }

}

private extension Data {
    nonisolated mutating func appendUInt32BE(_ value: UInt32) {
        append(contentsOf: [
            UInt8((value >> 24) & 0xff),
            UInt8((value >> 16) & 0xff),
            UInt8((value >> 8) & 0xff),
            UInt8(value & 0xff)
        ])
    }
}
