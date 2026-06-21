//
//  CaptureOutputProfileResolution.swift
//  TAPCamDemo
//

@preconcurrency import AVFoundation
import Foundation

/// Executable output request after a profile has passed contract validation and
/// codec selection for the current `AVCapturePhotoOutput`.
///
/// Runtime should consume this value rather than repeatedly reading profile
/// fields. That keeps future quality/format variants from accidentally skipping
/// the same validation used by the current Release HEIC-depth path.
nonisolated struct ResolvedCaptureOutputProfile: Equatable, Sendable {
    let profileID: String
    let container: CaptureOutputContainer
    let codec: CapturePhotoCodec
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

    var requestedCodec: AVVideoCodecType {
        codec.avVideoCodecType
    }

    fileprivate init(
        profileID: String,
        container: CaptureOutputContainer,
        codec: CapturePhotoCodec,
        depthDataDeliveryEnabled: Bool,
        embedsDepthDataInPhoto: Bool,
        depthDataFiltered: Bool,
        requiresDepthData: Bool,
        photoQualityPolicy: CapturePhotoQualityPolicy
    ) {
        self.profileID = profileID
        self.container = container
        self.codec = codec
        self.depthDataDeliveryEnabled = depthDataDeliveryEnabled
        self.embedsDepthDataInPhoto = embedsDepthDataInPhoto
        self.depthDataFiltered = depthDataFiltered
        self.requiresDepthData = requiresDepthData
        self.photoQualityPolicy = photoQualityPolicy
    }
}

/// The `AVCapturePhotoOutput` capabilities that a resolved output profile needs
/// before Runtime applies settings or reuses an existing graph.
///
/// This is a small snapshot, not an owner of `AVCapturePhotoOutput`. Runtime
/// still owns all AVFoundation mutation; the snapshot only keeps capability
/// checks readable and shared across configure, reuse, and future profile work.
nonisolated struct CapturePhotoOutputCapabilitySnapshot: Equatable, Sendable {
    let availablePhotoCodecTypes: [AVVideoCodecType]
    let isDepthDataDeliverySupported: Bool
    let isDepthDataDeliveryEnabled: Bool
    let maxPhotoQualityPrioritization: AVCapturePhotoOutput.QualityPrioritization

    init(
        availablePhotoCodecTypes: [AVVideoCodecType],
        isDepthDataDeliverySupported: Bool,
        isDepthDataDeliveryEnabled: Bool,
        maxPhotoQualityPrioritization: AVCapturePhotoOutput.QualityPrioritization
    ) {
        self.availablePhotoCodecTypes = availablePhotoCodecTypes
        self.isDepthDataDeliverySupported = isDepthDataDeliverySupported
        self.isDepthDataDeliveryEnabled = isDepthDataDeliveryEnabled
        self.maxPhotoQualityPrioritization = maxPhotoQualityPrioritization
    }

    init(photoOutput: AVCapturePhotoOutput) {
        self.init(
            availablePhotoCodecTypes: photoOutput.availablePhotoCodecTypes,
            isDepthDataDeliverySupported: photoOutput.isDepthDataDeliverySupported,
            isDepthDataDeliveryEnabled: photoOutput.isDepthDataDeliveryEnabled,
            maxPhotoQualityPrioritization: photoOutput.maxPhotoQualityPrioritization
        )
    }
}

extension CaptureOutputProfile {
    nonisolated func resolvedPhotoOutput(
        availablePhotoCodecTypes: [AVVideoCodecType]
    ) throws -> ResolvedCaptureOutputProfile {
        try validateForEmbeddedPhotoDepthCapture()
        let codec = try requiredCodec(availablePhotoCodecTypes: availablePhotoCodecTypes)

        return ResolvedCaptureOutputProfile(
            profileID: id,
            container: container,
            codec: codec,
            depthDataDeliveryEnabled: depthDataDeliveryEnabled,
            embedsDepthDataInPhoto: embedsDepthDataInPhoto,
            depthDataFiltered: depthDataFiltered,
            requiresDepthData: requiresDepthData,
            photoQualityPolicy: photoQualityPolicy
        )
    }

    nonisolated func resolvedPhotoOutput(
        capabilities: CapturePhotoOutputCapabilitySnapshot
    ) throws -> ResolvedCaptureOutputProfile {
        let resolvedOutput = try resolvedPhotoOutput(
            availablePhotoCodecTypes: capabilities.availablePhotoCodecTypes
        )
        try resolvedOutput.validatePhotoOutputCapabilities(capabilities)
        return resolvedOutput
    }
}

extension ResolvedCaptureOutputProfile {
    nonisolated func validatePhotoOutputCapabilities(
        _ capabilities: CapturePhotoOutputCapabilitySnapshot,
        requireConfiguredState: Bool = false
    ) throws {
        if !capabilities.availablePhotoCodecTypes.isEmpty,
           !capabilities.availablePhotoCodecTypes.contains(requestedCodec) {
            let available = capabilities.availablePhotoCodecTypes
                .map(\.rawValue)
                .sorted()
                .joined(separator: ", ")
            throw TAPDepthCaptureError.captureOutputCodecUnsupported(
                "Resolved output profile \(profileID) requires \(requestedCodec.rawValue), available [\(available)]."
            )
        }

        if depthDataDeliveryEnabled && !capabilities.isDepthDataDeliverySupported {
            throw TAPDepthCaptureError.depthDeliveryUnsupported
        }

        guard !requireConfiguredState
                || capabilities.isDepthDataDeliveryEnabled == depthDataDeliveryEnabled else {
            throw TAPDepthCaptureError.invalidCaptureOutputProfile(
                "Photo output depth delivery state does not match the resolved output profile."
            )
        }

        guard !requireConfiguredState
                || capabilities.maxPhotoQualityPrioritization == maxPhotoQualityPrioritization else {
            throw TAPDepthCaptureError.invalidCaptureOutputProfile(
                "Photo output maximum quality does not match the resolved output profile."
            )
        }
    }

    nonisolated func validateCapturePlanDepthConfiguration(
        depthDataDeliveryEnabled: Bool,
        embedsDepthDataInPhoto: Bool
    ) throws {
        guard self.depthDataDeliveryEnabled == depthDataDeliveryEnabled else {
            throw TAPDepthCaptureError.invalidCaptureOutputProfile(
                "Resolved output profile depth delivery does not match the capture plan."
            )
        }
        guard self.embedsDepthDataInPhoto == embedsDepthDataInPhoto else {
            throw TAPDepthCaptureError.invalidCaptureOutputProfile(
                "Resolved output profile depth embedding does not match the capture plan."
            )
        }
    }

    nonisolated func validateForEmbeddedPhotoDepthPackaging() throws {
        guard container == .embeddedPhotoDepthHEIC else {
            throw TAPDepthCaptureError.invalidCaptureOutputProfile(
                "Resolved output profile is not an embedded photo-depth HEIC container."
            )
        }
        guard codec == .hevc else {
            throw TAPDepthCaptureError.captureOutputCodecUnsupported(
                "Resolved embedded photo-depth HEIC output must use HEVC."
            )
        }
        guard requiresDepthData else {
            throw TAPDepthCaptureError.invalidCaptureOutputProfile(
                "Resolved embedded photo-depth HEIC output must require depth data."
            )
        }
        guard depthDataDeliveryEnabled else {
            throw TAPDepthCaptureError.invalidCaptureOutputProfile(
                "Resolved embedded photo-depth HEIC output must request depth delivery."
            )
        }
        guard embedsDepthDataInPhoto else {
            throw TAPDepthCaptureError.invalidCaptureOutputProfile(
                "Resolved embedded photo-depth HEIC output must embed depth data."
            )
        }
    }
}
