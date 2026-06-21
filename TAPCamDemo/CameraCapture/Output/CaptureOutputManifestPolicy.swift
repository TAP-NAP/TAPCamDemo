//
//  CaptureOutputManifestPolicy.swift
//  TAPCamDemo
//

@preconcurrency import AVFoundation
import Foundation

/// Manifest-side view of the reviewed capture output policy.
///
/// `CaptureOutputProfile` is the Runtime policy, while `TAPDepthManifest` is the
/// durable export record. This value keeps the mapping between those two worlds
/// explicit so the final Photos gate can reject manifest drift without keeping
/// Release-specific field comparisons inline in `TAPCaptureProvenanceWriter`.
nonisolated struct CaptureOutputManifestPolicy: Equatable, Sendable {
    static let releasePhotoDepthHEIC = CaptureOutputManifestPolicy(
        profile: .releasePhotoDepthHEIC
    )

    let requestedCodec: String
    let depthDataDeliveryEnabled: Bool
    let embedsDepthDataInPhoto: Bool
    let depthDataFiltered: Bool
    let photoQualityPrioritization: String

    init(profile: CaptureOutputProfile) {
        self.requestedCodec = profile.codecPreference.first?.avVideoCodecType.rawValue ?? ""
        self.depthDataDeliveryEnabled = profile.depthDataDeliveryEnabled
        self.embedsDepthDataInPhoto = profile.embedsDepthDataInPhoto
        self.depthDataFiltered = profile.depthDataFiltered
        self.photoQualityPrioritization = profile.photoQualityPolicy.requested.manifestDescription
    }

    func violations(
        in capture: TAPDepthManifest.Capture
    ) -> [CaptureOutputManifestPolicyViolation] {
        var violations: [CaptureOutputManifestPolicyViolation] = []

        if capture.requestedCodec != requestedCodec {
            violations.append(.requestedCodec)
        }
        if capture.depthDataDeliveryEnabled != depthDataDeliveryEnabled {
            violations.append(.depthDataDeliveryEnabled)
        }
        if capture.embedsDepthDataInPhoto != embedsDepthDataInPhoto {
            violations.append(.embedsDepthDataInPhoto)
        }
        if capture.depthDataFiltered != depthDataFiltered {
            violations.append(.depthDataFiltered)
        }
        if capture.photoQualityPrioritization != photoQualityPrioritization {
            violations.append(.photoQualityPrioritization)
        }

        return violations
    }

    func validate(
        _ capture: TAPDepthManifest.Capture
    ) throws {
        let violations = violations(in: capture)
        guard violations.isEmpty else {
            throw TAPDepthCaptureError.invalidCaptureOutputProfile(
                "signed export manifest violates Release output policy: \(violations.map(\.readerDescription).joined(separator: "; "))"
            )
        }
    }
}

nonisolated enum CaptureOutputManifestPolicyViolation: String, Equatable, Sendable {
    case requestedCodec
    case depthDataDeliveryEnabled
    case embedsDepthDataInPhoto
    case depthDataFiltered
    case photoQualityPrioritization

    var readerDescription: String {
        switch self {
        case .requestedCodec:
            "requestedCodec must be HEVC"
        case .depthDataDeliveryEnabled:
            "depthDataDeliveryEnabled must match Release"
        case .embedsDepthDataInPhoto:
            "embedsDepthDataInPhoto must match Release"
        case .depthDataFiltered:
            "depthDataFiltered must match Release"
        case .photoQualityPrioritization:
            "photoQualityPrioritization must match Release"
        }
    }
}
