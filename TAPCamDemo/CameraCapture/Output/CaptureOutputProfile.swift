//
//  CaptureOutputProfile.swift
//  TAPCamDemo
//

@preconcurrency import AVFoundation
import Foundation

/// The physical container that the capture pipeline is prepared to create.
///
/// Today there is exactly one release container: an Apple photo-depth HEIC with
/// the TAP manifest embedded as XMP. Keeping that fact in a named type gives
/// future JPEG/RAW/video work a clear place to start without making the current
/// storage layer pretend it is already multi-format.
nonisolated enum CaptureOutputContainer: String, Codable, Equatable, Sendable {
    case embeddedPhotoDepthHEIC

    var preservesEmbeddedPhotoDepth: Bool {
        switch self {
        case .embeddedPhotoDepthHEIC:
            true
        }
    }
}

/// App-level names for codecs that can back an `AVCapturePhotoSettings` request.
///
/// The enum avoids spreading AVFoundation raw string values through the code.
/// Manifest code still records the resolved `AVVideoCodecType.rawValue`, because
/// that is the externally visible capture fact.
nonisolated enum CapturePhotoCodec: String, Codable, Equatable, Sendable {
    case hevc
    case jpeg

    init?(avVideoCodecType: AVVideoCodecType) {
        if avVideoCodecType == .hevc {
            self = .hevc
        } else if avVideoCodecType == .jpeg {
            self = .jpeg
        } else {
            return nil
        }
    }

    var avVideoCodecType: AVVideoCodecType {
        switch self {
        case .hevc:
            .hevc
        case .jpeg:
            .jpeg
        }
    }
}

/// Human-readable output contract failures.
///
/// These cases are intentionally about product invariants, not AVFoundation
/// implementation details. Future JPEG, RAW, Live Photo, or video work should
/// add new contract cases here before adding UI controls that can request them.
nonisolated enum CaptureOutputContractViolation: String, Codable, Equatable, Sendable {
    case emptyProfileID
    case emptyCodecPreference
    case requiredDepthWithoutDepthDelivery
    case requiredDepthWithoutPhotoEmbedding
    case requiredDepthWithoutDepthPreservingContainer
    case photoDepthContainerWithoutRequiredDepth
    case requestedQualityExceedsConfiguredMaximum
    case heicContainerAllowsNonHEVCCodec

    var readerDescription: String {
        switch self {
        case .emptyProfileID:
            "Output profile id must name the requested capture contract."
        case .emptyCodecPreference:
            "Output profile must name at least one acceptable photo codec."
        case .requiredDepthWithoutDepthDelivery:
            "Depth-required output must request AVFoundation depth delivery."
        case .requiredDepthWithoutPhotoEmbedding:
            "Depth-required output must embed depth in the photo artifact."
        case .requiredDepthWithoutDepthPreservingContainer:
            "Depth-required output must use a container that preserves embedded photo depth."
        case .photoDepthContainerWithoutRequiredDepth:
            "Photo-depth containers must keep depth data as a required output."
        case .requestedQualityExceedsConfiguredMaximum:
            "Requested photo quality must not exceed the configured AVCapturePhotoOutput maximum."
        case .heicContainerAllowsNonHEVCCodec:
            "Embedded photo-depth HEIC output must require the HEVC photo codec."
        }
    }
}

/// Named output policy for a capture request.
///
/// Read this file first when changing image format or quality. The rest of the
/// runtime should consume this value instead of hard-coding codec, depth, or
/// quality choices at each AVFoundation call site.
nonisolated struct CaptureOutputProfile: Equatable, Sendable {
    let id: String
    let container: CaptureOutputContainer
    let codecPreference: [CapturePhotoCodec]
    let depthDataDeliveryEnabled: Bool
    let embedsDepthDataInPhoto: Bool
    let depthDataFiltered: Bool
    let requiresDepthData: Bool
    let photoQualityPolicy: CapturePhotoQualityPolicy

    var photoQualityPrioritization: AVCapturePhotoOutput.QualityPrioritization {
        photoQualityPolicy.avFoundationRequestedPrioritization
    }

    var maxPhotoQualityPrioritization: AVCapturePhotoOutput.QualityPrioritization {
        photoQualityPolicy.avFoundationMaximumPrioritization
    }

    static let releasePhotoDepthHEIC = CaptureOutputProfile(
        id: "release.photo-depth.heic",
        container: .embeddedPhotoDepthHEIC,
        codecPreference: [.hevc],
        depthDataDeliveryEnabled: true,
        embedsDepthDataInPhoto: true,
        depthDataFiltered: true,
        requiresDepthData: true,
        photoQualityPolicy: .releaseQuality
    )

    func preferredCodec(availablePhotoCodecTypes: [AVVideoCodecType]) -> CapturePhotoCodec? {
        codecPreference.first { codec in
            availablePhotoCodecTypes.contains(codec.avVideoCodecType)
        }
    }

    func requiredCodec(availablePhotoCodecTypes: [AVVideoCodecType]) throws -> CapturePhotoCodec {
        if let preferredCodec = preferredCodec(availablePhotoCodecTypes: availablePhotoCodecTypes) {
            return preferredCodec
        }

        if availablePhotoCodecTypes.isEmpty, let requestedCodec = codecPreference.first {
            return requestedCodec
        }

        let requested = codecPreference.map(\.rawValue).joined(separator: ", ")
        let available = availablePhotoCodecTypes
            .map(\.rawValue)
            .sorted()
            .joined(separator: ", ")
        throw TAPDepthCaptureError.captureOutputCodecUnsupported(
            "profile \(id) requires [\(requested)], available [\(available)]"
        )
    }

    var contractViolations: [CaptureOutputContractViolation] {
        var violations: [CaptureOutputContractViolation] = []
        if id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            violations.append(.emptyProfileID)
        }
        if codecPreference.isEmpty {
            violations.append(.emptyCodecPreference)
        }

        if requiresDepthData {
            if !depthDataDeliveryEnabled {
                violations.append(.requiredDepthWithoutDepthDelivery)
            }
            if !embedsDepthDataInPhoto {
                violations.append(.requiredDepthWithoutPhotoEmbedding)
            }
            if !container.preservesEmbeddedPhotoDepth {
                violations.append(.requiredDepthWithoutDepthPreservingContainer)
            }
        }

        if container == .embeddedPhotoDepthHEIC && !requiresDepthData {
            violations.append(.photoDepthContainerWithoutRequiredDepth)
        }

        if container == .embeddedPhotoDepthHEIC && codecPreference != [.hevc] {
            violations.append(.heicContainerAllowsNonHEVCCodec)
        }

        if photoQualityPolicy.exceedsConfiguredMaximum {
            violations.append(.requestedQualityExceedsConfiguredMaximum)
        }
        return violations
    }

    /// Validates the only executable Release output path in this app today.
    ///
    /// Runtime, package construction, and the embedded HEIC packager all call
    /// this same method so future format or quality work cannot accidentally
    /// bypass the current photo-depth contract at one boundary.
    func validateForEmbeddedPhotoDepthCapture() throws {
        let violations = contractViolations
        guard violations.isEmpty else {
            throw TAPDepthCaptureError.invalidCaptureOutputProfile(
                violations.map(\.readerDescription).joined(separator: " ")
            )
        }
    }

    func validateDepthConfiguration(
        depthDataDeliveryEnabled: Bool,
        embedsDepthDataInPhoto: Bool
    ) throws {
        guard !requiresDepthData || depthDataDeliveryEnabled else {
            throw TAPDepthCaptureError.invalidCaptureOutputProfile(
                "profile \(id) requires depth data but the capture plan disables depth delivery."
            )
        }
        guard !requiresDepthData || embedsDepthDataInPhoto else {
            throw TAPDepthCaptureError.invalidCaptureOutputProfile(
                "profile \(id) requires embedded depth but the capture plan disables photo depth embedding."
            )
        }
    }

}
