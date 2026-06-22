//
//  CaptureOutputResourcePlan.swift
//  TAPCamDemo
//

import Foundation

/// Logical resources that make up one reviewed capture output.
///
/// This is a pure planning model, not a packager and not a storage manifest.
/// It names what Release photo-depth output promises so future RAW, Live Photo,
/// video, or C2PA work has a small place to add resource-level policy before
/// Runtime, Photos, or App Attest code changes.
nonisolated struct CaptureOutputResourcePlan: Equatable, Sendable {
    let container: CaptureOutputContainer
    let resources: [CaptureOutputResource]

    var requiresPrimaryPhoto: Bool {
        requires(.primaryPhoto)
    }

    var requiresEmbeddedDepth: Bool {
        requires(.appleAuxiliaryDepth)
    }

    var requiresTAPManifest: Bool {
        requires(.tapManifest)
    }

    var requiresAppAttestProofBeforeExport: Bool {
        requires(.appAttestCaptureProof)
    }

    var contentDigestResourceKinds: [CaptureOutputResource.Kind] {
        resources
            .filter(\.coveredByAppAttestContentDigest)
            .map(\.kind)
    }

    static let releasePhotoDepthHEIC = CaptureOutputResourcePlan(
        container: .embeddedPhotoDepthHEIC,
        resources: releasePhotoDepthResources
    )

    static let releasePhotoDepthJPEG = CaptureOutputResourcePlan(
        container: .embeddedPhotoDepthJPEG,
        resources: releasePhotoDepthResources
    )

    private static let releasePhotoDepthResources: [CaptureOutputResource] = [
        CaptureOutputResource(
            kind: .primaryPhoto,
            storage: .embeddedInPrimaryPhoto,
            requiredForExport: true,
            coveredByAppAttestContentDigest: true
        ),
        CaptureOutputResource(
            kind: .appleAuxiliaryDepth,
            storage: .embeddedInPrimaryPhoto,
            requiredForExport: true,
            coveredByAppAttestContentDigest: true
        ),
        CaptureOutputResource(
            kind: .tapManifest,
            storage: .embeddedInPrimaryPhoto,
            requiredForExport: true,
            coveredByAppAttestContentDigest: true
        ),
        CaptureOutputResource(
            kind: .appAttestCaptureProof,
            storage: .tapManifestProofRecord,
            requiredForExport: true,
            coveredByAppAttestContentDigest: false
        )
    ]

    private func requires(_ kind: CaptureOutputResource.Kind) -> Bool {
        resources.contains { $0.kind == kind && $0.requiredForExport }
    }
}

/// One logical piece of a capture output contract.
///
/// The value intentionally stores no bytes, paths, URLs, Photos identifiers,
/// App Attest key IDs, capture IDs, manifests, or AVFoundation objects. Runtime
/// and storage code should still carry those concrete values through their
/// existing typed boundaries.
nonisolated struct CaptureOutputResource: Equatable, Sendable {
    nonisolated enum Kind: String, Equatable, Sendable {
        case primaryPhoto
        case appleAuxiliaryDepth
        case tapManifest
        case appAttestCaptureProof
    }

    nonisolated enum Storage: String, Equatable, Sendable {
        case embeddedInPrimaryPhoto
        case tapManifestProofRecord
    }

    let kind: Kind
    let storage: Storage
    let requiredForExport: Bool
    let coveredByAppAttestContentDigest: Bool
}

extension ResolvedCaptureOutputProfile {
    nonisolated var resourcePlan: CaptureOutputResourcePlan {
        get throws {
            try validateForEmbeddedPhotoDepthPackaging()

            switch container {
            case .embeddedPhotoDepthHEIC:
                return CaptureOutputResourcePlan.releasePhotoDepthHEIC
            case .embeddedPhotoDepthJPEG:
                return CaptureOutputResourcePlan.releasePhotoDepthJPEG
            }
        }
    }
}
