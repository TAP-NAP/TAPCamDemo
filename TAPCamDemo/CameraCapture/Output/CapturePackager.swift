//
//  CapturePackager.swift
//  TAPCamDemo
//
//  Created by Codex on 2026/4/27.
//

import CoreLocation
import Foundation

/// Physical packaging strategies known to the architecture.
///
/// The current demo only writes a single embedded HEIC photo. Sidecars and
/// debug bundles were intentionally removed from runtime code because they are
/// not part of the accepted SingleCam product flow.
nonisolated enum PackagingStrategy: String, Codable, Sendable {
    case embeddedPhoto
}

/// Whether a packaged capture contains an App Attest proof.
nonisolated enum CaptureSignatureStatus: Equatable, Sendable {
    case signed(keyID: String)
    case unsigned(reason: String)
}

/// Result of physically packaging a logical capture package.
///
/// This is a single HEIC byte buffer with Apple auxiliary depth and TAP XMP
/// manifest embedded in the file.
nonisolated struct PackagedCaptureArtifact: Sendable {
    let packageID: UUID
    let strategy: PackagingStrategy
    let photoData: Data
    let manifest: TAPDepthManifest
    let signatureStatus: CaptureSignatureStatus
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
