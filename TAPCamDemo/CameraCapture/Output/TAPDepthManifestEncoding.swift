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
        let canonicalManifestData = try self.manifestData(manifest)
        let canonicalPayloadData = try payloadDataExcludingProofs(manifest.payload)
        let rawPayloadData = try TAPCanonicalManifestPayload.rawPayloadData(
            in: manifestData,
            canonicalManifestData: canonicalManifestData,
            canonicalPayloadData: canonicalPayloadData
        )
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

/// Returns the payload bytes from the canonical top-level manifest itself.
/// Re-encoding is used only to reject non-canonical input, never as hash input.
nonisolated enum TAPCanonicalManifestPayload {
    private static let payloadPrefix = Data(#"{"payload":"#.utf8)
    private static let proofsPrefix = Data(#","proofs":"#.utf8)

    static func rawPayloadData(
        in manifestData: Data,
        canonicalManifestData: Data,
        canonicalPayloadData: Data
    ) throws -> Data {
        guard manifestData == canonicalManifestData,
              manifestData.starts(with: payloadPrefix) else {
            throw TAPDepthCaptureError.invalidTAPManifest(
                "manifest JSON is not canonical v1 bytes"
            )
        }

        let payloadRange = payloadPrefix.count..<(payloadPrefix.count + canonicalPayloadData.count)
        guard payloadRange.upperBound <= manifestData.count,
              manifestData[payloadRange].elementsEqual(canonicalPayloadData),
              manifestData[payloadRange.upperBound...].starts(with: proofsPrefix) else {
            throw TAPDepthCaptureError.invalidTAPManifest(
                "manifest payload is not the exact embedded canonical member"
            )
        }
        return Data(manifestData[payloadRange])
    }
}
