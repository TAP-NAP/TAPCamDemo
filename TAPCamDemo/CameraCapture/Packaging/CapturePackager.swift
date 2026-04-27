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
/// v0.6 Release allows only `embeddedPhoto`. Debug bundle/sidecar strategies
/// are intentionally represented but rejected by the release policy until the
/// development-only writers are implemented.
nonisolated enum PackagingStrategy: String, Codable, Sendable {
    case embeddedPhoto
    case sidecarJSON
    case bundle
}

/// Result of physically packaging a logical capture package.
///
/// For v0.6 this is a single HEIC byte buffer with Apple auxiliary depth and
/// TAP XMP manifest embedded in the file. Future Debug strategies can add more
/// artifact kinds without changing capture providers.
nonisolated struct PackagedCaptureArtifact: Sendable {
    let packageID: UUID
    let strategy: PackagingStrategy
    let photoData: Data
    let manifest: TAPDepthManifest
    let capturedAt: Date
    let location: CLLocation?
}

/// Converts a logical `CapturePackage` into a physical artifact.
protocol CapturePackager: Sendable {
    var strategy: PackagingStrategy { get }
    func package(_ capturePackage: CapturePackage) async throws -> PackagedCaptureArtifact
}

/// Central release data policy check.
///
/// Keeping this as a tiny explicit type makes tests and future external-entry
/// points enforce the same rule: Release cannot escape to sidecars, bundles,
/// independent depth files, or intermediate metadata files.
nonisolated enum ReleasePackagingPolicy {
    static func validate(_ strategy: PackagingStrategy) throws {
        guard strategy == .embeddedPhoto else {
            throw TAPDepthCaptureError.releasePackagingStrategyRejected
        }
    }
}

#if DEBUG
/// Development-only sidecar packager placeholder.
///
/// v0.8 keeps the type name explicit for tests and future diagnostics, but the
/// shipping app does not instantiate it and release policy rejects the strategy.
nonisolated struct SidecarJSONPackager: CapturePackager {
    let strategy: PackagingStrategy = .sidecarJSON

    func package(_ capturePackage: CapturePackage) async throws -> PackagedCaptureArtifact {
        _ = capturePackage
        throw TAPDepthCaptureError.releasePackagingStrategyRejected
    }
}

/// Development-only bundle packager placeholder.
///
/// Bundle output is useful for future lab inspection of RGB/depth/calibration,
/// but v0.8 release capture remains a single embedded photo artifact.
nonisolated struct BundlePackager: CapturePackager {
    let strategy: PackagingStrategy = .bundle

    func package(_ capturePackage: CapturePackage) async throws -> PackagedCaptureArtifact {
        _ = capturePackage
        throw TAPDepthCaptureError.releasePackagingStrategyRejected
    }
}
#endif
