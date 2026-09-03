//
//  CapturePackager.swift
//  TAPCamDemo
//
//  Created by Codex on 2026/4/27.
//

import CoreLocation
import Foundation

nonisolated struct PackagedLivePhotoMovie: Sendable {
    let fileURL: URL
    let durationSeconds: Double
    let photoDisplayTimeSeconds: Double
    let width: Int32
    let height: Int32
    let codec: String?
    let capturesAudio: Bool
}

/// Whether a packaged capture contains an App Attest proof.
nonisolated enum CaptureSignatureStatus: Equatable, Sendable {
    case pending(reason: String)
    case signed(keyID: String)
    case unsigned(reason: String)
}

/// Result of physically packaging a logical capture package.
///
/// This is a single photo byte buffer with Apple auxiliary depth and TAP XMP
/// manifest embedded in the file. Packaging metrics are diagnostics only and
/// are not persisted into the photo artifact.
nonisolated struct PackagedCaptureArtifact: Sendable {
    let packageID: UUID
    let photoData: Data
    let fileContainer: CapturePhotoFileContainer
    let photoQualityLevel: CapturePhotoQualityLevel
    let manifest: TAPDepthManifest
    let livePhotoMovie: PackagedLivePhotoMovie?
    let signatureStatus: CaptureSignatureStatus
    let depthAvailability: CaptureDepthAvailability
    let captureScoreSummary: CaptureScoreSummary
    let packagingMetrics: CapturePackagingMetrics
    let capturedAt: Date
    let location: CLLocation?
}
