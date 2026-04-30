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
/// `payloadDataExcludingProofs` deliberately excludes `proofs`. The app does not
/// create hashes or signatures; this helper exists so schema tests can assert
/// that placeholder proof records do not change the manifest payload bytes.
nonisolated enum TAPDepthManifestEncoder {
    static func manifestJSON(_ manifest: TAPDepthManifest) throws -> String {
        let data = try encoder.encode(manifest)
        guard let json = String(data: data, encoding: .utf8) else {
            throw TAPDepthCaptureError.invalidUTF8Manifest
        }
        return json
    }

    static func payloadDataExcludingProofs(_ payload: TAPDepthManifest.Payload) throws -> Data {
        try encoder.encode(payload)
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }()
}
