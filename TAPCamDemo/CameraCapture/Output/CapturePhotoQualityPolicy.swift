//
//  CapturePhotoQualityPolicy.swift
//  TAPCamDemo
//

@preconcurrency import AVFoundation
import Foundation

/// App-level photo quality names used before AVFoundation settings are built.
///
/// The user-visible labels live in `CameraPhotoQualityPreference`; this type is
/// the durable capture/output value that Runtime and manifests consume.
nonisolated enum CapturePhotoQualityLevel: String, Codable, Equatable, Sendable {
    case speed
    case balanced
    case quality

    var avFoundationPrioritization: AVCapturePhotoOutput.QualityPrioritization {
        switch self {
        case .speed:
            .speed
        case .balanced:
            .balanced
        case .quality:
            .quality
        }
    }

    var manifestDescription: String {
        rawValue
    }

    var contractRank: Int {
        switch self {
        case .speed:
            0
        case .balanced:
            1
        case .quality:
            2
        }
    }
}

/// What the app-level quality policy does and does not promise.
///
/// `AVCapturePhotoOutput.QualityPrioritization.quality` can improve capture
/// prioritization, but it is not a fixed file-size, compression-ratio,
/// resolution, or visual-quality guarantee. Keep those future controls separate
/// from the current depth-preserving Release profile.
nonisolated enum CapturePhotoQualityAssurance: String, Codable, Equatable, Sendable {
    case avFoundationPrioritizationOnly
    case noFileSizeGuarantee
    case noCompressionRatioGuarantee
    case preservesReviewedDepthContract
}

/// Requested per-shot quality and the `AVCapturePhotoOutput` maximum needed to
/// execute it.
///
/// Future UI can choose a reviewed policy, but Runtime should still only see a
/// resolved value after output-profile validation.
nonisolated struct CapturePhotoQualityPolicy: Codable, Equatable, Sendable {
    let requested: CapturePhotoQualityLevel
    let maximum: CapturePhotoQualityLevel

    static let releaseQuality = CapturePhotoQualityPolicy(
        requested: .quality,
        maximum: .quality
    )

    static func release(requested: CapturePhotoQualityLevel) -> CapturePhotoQualityPolicy {
        CapturePhotoQualityPolicy(
            requested: requested,
            maximum: .quality
        )
    }

    var exceedsConfiguredMaximum: Bool {
        requested.contractRank > maximum.contractRank
    }

    var assurances: [CapturePhotoQualityAssurance] {
        [
            .avFoundationPrioritizationOnly,
            .noFileSizeGuarantee,
            .noCompressionRatioGuarantee,
            .preservesReviewedDepthContract
        ]
    }

    var avFoundationRequestedPrioritization: AVCapturePhotoOutput.QualityPrioritization {
        requested.avFoundationPrioritization
    }

    var avFoundationMaximumPrioritization: AVCapturePhotoOutput.QualityPrioritization {
        maximum.avFoundationPrioritization
    }
}
