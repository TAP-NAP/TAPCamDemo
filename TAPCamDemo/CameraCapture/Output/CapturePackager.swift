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

/// Physical packaging strategies known to the architecture.
///
/// The current demo only writes a single embedded photo-depth file. Sidecars and
/// debug bundles were intentionally removed from runtime code because they are
/// not part of the accepted SingleCam product flow.
nonisolated enum PackagingStrategy: String, Codable, Sendable {
    case embeddedPhoto
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
    let strategy: PackagingStrategy
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

/// Converts a logical `CapturePackage` into a physical artifact.
protocol CapturePackager: Sendable {
    var strategy: PackagingStrategy { get }
    func package(
        _ capturePackage: CapturePackage,
        assertionSigner: (any CaptureAssertionSigning)?
    ) async throws -> PackagedCaptureArtifact
}
