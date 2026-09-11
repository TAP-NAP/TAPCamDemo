//
//  TAPDepthManifestEncoding.swift
//  TAPCamDemo
//
//  Created by Codex on 2026/4/25.
//

@preconcurrency import AVFoundation
import CoreLocation
import CoreVideo
import Foundation
import ImageIO
import simd

/// Encodes manifests in one place so the app and tests use identical JSON
/// options.
///
/// `payloadDataExcludingProofs` emits only the business payload. V1 keeps
/// `manifest.proofs` empty and writes the assertion into the fixed proof slot,
/// so slot updates cannot change the metadata bytes being signed.
nonisolated enum TAPDepthManifestEncoder {
    static func manifestJSON(_ manifest: TAPDepthManifest) throws -> String {
        let data = try manifestData(manifest)
        guard let json = String(data: data, encoding: .utf8) else {
            throw TAPDepthCaptureError.invalidUTF8Manifest
        }
        return json
    }

    static func manifestData(_ manifest: TAPDepthManifest) throws -> Data {
        try JSONEncoder.tapCaptureCanonical.encode(manifest)
    }

    static func payloadDataExcludingProofs(_ payload: TAPDepthManifest.Payload) throws -> Data {
        try JSONEncoder.tapCaptureCanonical.encode(payload)
    }

    static func decodedDocument(from manifestData: Data) throws -> TAPDepthManifestDocument {
        let manifest = try JSONDecoder().decode(TAPDepthManifest.self, from: manifestData)
        let rawPayloadData = try TAPManifestPayloadBytes.rawPayloadData(in: manifestData)
        return TAPDepthManifestDocument(
            manifest: manifest,
            rawPayloadData: rawPayloadData
        )
    }
}

nonisolated struct TAPDepthManifestDocument {
    let manifest: TAPDepthManifest
    let rawPayloadData: Data
}

/// Locates the embedded payload without re-encoding numbers, strings, or whitespace.
/// JSONSerialization validates the document before this byte-range scan.
nonisolated enum TAPManifestPayloadBytes {
    static func rawPayloadData(in data: Data) throws -> Data {
        guard try JSONSerialization.jsonObject(with: data) is [String: Any] else {
            throw TAPDepthCaptureError.invalidTAPManifest("manifest is not a JSON object")
        }
        let bytes = Array(data)
        func isWhitespace(_ byte: UInt8) -> Bool {
            byte == 0x20 || byte == 0x09 || byte == 0x0a || byte == 0x0d
        }
        func skippingWhitespace(_ start: Int) -> Int {
            var index = start
            while index < bytes.count && isWhitespace(bytes[index]) { index += 1 }
            return index
        }
        func valueEnd(from start: Int) -> Int {
            var depth = 0
            var inString = false
            var escaped = false
            for index in start..<bytes.count {
                let byte = bytes[index]
                if inString {
                    if escaped { escaped = false }
                    else if byte == 0x5c { escaped = true }
                    else if byte == 0x22 {
                        inString = false
                        if depth == 0 { return index + 1 }
                    }
                } else if byte == 0x22 {
                    inString = true
                } else if byte == 0x7b || byte == 0x5b {
                    depth += 1
                } else if byte == 0x7d || byte == 0x5d {
                    if depth == 0 { return index }
                    depth -= 1
                    if depth == 0 { return index + 1 }
                } else if depth == 0 && (byte == 0x2c || isWhitespace(byte)) {
                    return index
                }
            }
            return bytes.count
        }

        var index = skippingWhitespace(skippingWhitespace(0) + 1)
        var payloadRange: Range<Int>?
        while index < bytes.count && bytes[index] != 0x7d {
            let keyEnd = valueEnd(from: index)
            let key = try JSONDecoder().decode(String.self, from: Data(bytes[index..<keyEnd]))
            let valueStart = skippingWhitespace(skippingWhitespace(keyEnd) + 1)
            let end = valueEnd(from: valueStart)
            if key == "payload" {
                guard payloadRange == nil else {
                    throw TAPDepthCaptureError.invalidTAPManifest("duplicate manifest payload")
                }
                payloadRange = valueStart..<end
            }
            index = skippingWhitespace(end)
            if index < bytes.count && bytes[index] == 0x2c {
                index = skippingWhitespace(index + 1)
            }
        }
        guard let payloadRange else {
            throw TAPDepthCaptureError.invalidTAPManifest("missing manifest payload")
        }
        return Data(bytes[payloadRange])
    }
}

/// Only the identity fields and exact payload bytes needed by content binding.
/// Media descriptions are decoded separately by their consumers.
nonisolated struct TAPManifestBindingDocument: Sendable {
    let schemaID: String
    let captureID: String
    let capturedAt: String
    let packageID: String?
    let rawPayloadData: Data

    init(data: Data) throws {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let schema = object["schema"] as? [String: Any],
              let schemaID = schema["id"] as? String else {
            throw TAPDepthCaptureError.invalidTAPManifest("missing manifest binding identity")
        }
        let payloadData = try TAPManifestPayloadBytes.rawPayloadData(in: data)
        guard let payload = try JSONSerialization.jsonObject(with: payloadData) as? [String: Any],
              let captureID = payload["id"] as? String,
              let capturedAt = payload["capturedAt"] as? String else {
            throw TAPDepthCaptureError.invalidTAPManifest("missing manifest binding identity")
        }
        self.schemaID = schemaID
        self.captureID = captureID
        self.capturedAt = capturedAt
        self.packageID = payload["packageID"] as? String
        self.rawPayloadData = payloadData
    }
}
