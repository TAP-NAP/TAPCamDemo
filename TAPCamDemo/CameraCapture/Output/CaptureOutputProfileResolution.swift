//
//  CaptureOutputProfileResolution.swift
//  TAPCamDemo
//

@preconcurrency import AVFoundation
import Foundation

/// Executable output request after a profile has passed contract validation and
/// capability selection for the current `AVCapturePhotoOutput`.
///
/// Runtime should consume this value rather than repeatedly reading profile
/// fields. That keeps format, quality, depth, and dimensions checks identical
/// across session configuration, prewarming, capture, packaging, and export.
nonisolated struct ResolvedCaptureOutputProfile: Equatable, Sendable {
    let profileID: String
    let container: CaptureOutputContainer
    let fileContainer: CapturePhotoFileContainer
    let codec: CapturePhotoCodec
    let depthDataDeliveryEnabled: Bool
    let embedsDepthDataInPhoto: Bool
    let depthDataFiltered: Bool
    let requiresDepthData: Bool
    let photoQualityPolicy: CapturePhotoQualityPolicy
    let maxPhotoDimensions: CapturePhotoDimensions?
    let compressionQuality: Double

    var photoQualityPrioritization: AVCapturePhotoOutput.QualityPrioritization {
        photoQualityPolicy.avFoundationRequestedPrioritization
    }

    var maxPhotoQualityPrioritization: AVCapturePhotoOutput.QualityPrioritization {
        photoQualityPolicy.avFoundationMaximumPrioritization
    }

    var requestedCodec: AVVideoCodecType {
        codec.avVideoCodecType
    }

    var processedFileType: AVFileType {
        fileContainer.avFileType
    }

    fileprivate init(
        profileID: String,
        container: CaptureOutputContainer,
        fileContainer: CapturePhotoFileContainer,
        codec: CapturePhotoCodec,
        depthDataDeliveryEnabled: Bool,
        embedsDepthDataInPhoto: Bool,
        depthDataFiltered: Bool,
        requiresDepthData: Bool,
        photoQualityPolicy: CapturePhotoQualityPolicy,
        maxPhotoDimensions: CapturePhotoDimensions?,
        compressionQuality: Double
    ) {
        self.profileID = profileID
        self.container = container
        self.fileContainer = fileContainer
        self.codec = codec
        self.depthDataDeliveryEnabled = depthDataDeliveryEnabled
        self.embedsDepthDataInPhoto = embedsDepthDataInPhoto
        self.depthDataFiltered = depthDataFiltered
        self.requiresDepthData = requiresDepthData
        self.photoQualityPolicy = photoQualityPolicy
        self.maxPhotoDimensions = maxPhotoDimensions
        self.compressionQuality = compressionQuality
    }
}

/// The `AVCapturePhotoOutput` and active-format capabilities that a resolved
/// output profile needs before Runtime applies settings or reuses a graph.
///
/// Empty arrays mean the source did not expose that capability yet. Runtime uses
/// this during early planning before the output is attached to a session, then
/// repeats validation with populated values after rebuilding the graph.
nonisolated struct CapturePhotoOutputCapabilitySnapshot: Equatable, Sendable {
    let availablePhotoFileTypeIdentifiers: [String]
    let availablePhotoCodecTypes: [AVVideoCodecType]
    let supportedPhotoCodecTypesByFileTypeIdentifier: [String: [AVVideoCodecType]]
    let supportedMaxPhotoDimensions: [CapturePhotoDimensions]
    let configuredMaxPhotoDimensions: CapturePhotoDimensions?
    let isDepthDataDeliverySupported: Bool
    let isDepthDataDeliveryEnabled: Bool
    let maxPhotoQualityPrioritization: AVCapturePhotoOutput.QualityPrioritization

    init(
        availablePhotoFileTypeIdentifiers: [String],
        availablePhotoCodecTypes: [AVVideoCodecType],
        supportedPhotoCodecTypesByFileTypeIdentifier: [String: [AVVideoCodecType]],
        supportedMaxPhotoDimensions: [CapturePhotoDimensions],
        configuredMaxPhotoDimensions: CapturePhotoDimensions?,
        isDepthDataDeliverySupported: Bool,
        isDepthDataDeliveryEnabled: Bool,
        maxPhotoQualityPrioritization: AVCapturePhotoOutput.QualityPrioritization
    ) {
        self.availablePhotoFileTypeIdentifiers = availablePhotoFileTypeIdentifiers
        self.availablePhotoCodecTypes = availablePhotoCodecTypes
        self.supportedPhotoCodecTypesByFileTypeIdentifier = supportedPhotoCodecTypesByFileTypeIdentifier
        self.supportedMaxPhotoDimensions = supportedMaxPhotoDimensions
        self.configuredMaxPhotoDimensions = configuredMaxPhotoDimensions
        self.isDepthDataDeliverySupported = isDepthDataDeliverySupported
        self.isDepthDataDeliveryEnabled = isDepthDataDeliveryEnabled
        self.maxPhotoQualityPrioritization = maxPhotoQualityPrioritization
    }

    init(
        availablePhotoCodecTypes: [AVVideoCodecType],
        isDepthDataDeliverySupported: Bool,
        isDepthDataDeliveryEnabled: Bool,
        maxPhotoQualityPrioritization: AVCapturePhotoOutput.QualityPrioritization
    ) {
        self.init(
            availablePhotoFileTypeIdentifiers: [],
            availablePhotoCodecTypes: availablePhotoCodecTypes,
            supportedPhotoCodecTypesByFileTypeIdentifier: [:],
            supportedMaxPhotoDimensions: [],
            configuredMaxPhotoDimensions: nil,
            isDepthDataDeliverySupported: isDepthDataDeliverySupported,
            isDepthDataDeliveryEnabled: isDepthDataDeliveryEnabled,
            maxPhotoQualityPrioritization: maxPhotoQualityPrioritization
        )
    }

    init(
        photoOutput: AVCapturePhotoOutput,
        activeFormat: AVCaptureDevice.Format? = nil,
        assumesDepthDeliverySupported: Bool = false
    ) {
        let fileTypes = photoOutput.availablePhotoFileTypes
        let codecsByFileType = Dictionary(uniqueKeysWithValues: fileTypes.map { fileType in
            (fileType.rawValue, photoOutput.supportedPhotoCodecTypes(for: fileType))
        })
        let configuredDimensions = CapturePhotoDimensions(photoOutput.maxPhotoDimensions)

        self.init(
            availablePhotoFileTypeIdentifiers: fileTypes.map(\.rawValue),
            availablePhotoCodecTypes: photoOutput.availablePhotoCodecTypes,
            supportedPhotoCodecTypesByFileTypeIdentifier: codecsByFileType,
            supportedMaxPhotoDimensions: activeFormat?.supportedMaxPhotoDimensions.map(CapturePhotoDimensions.init) ?? [],
            configuredMaxPhotoDimensions: configuredDimensions.isValid ? configuredDimensions : nil,
            isDepthDataDeliverySupported: assumesDepthDeliverySupported || photoOutput.isDepthDataDeliverySupported,
            isDepthDataDeliveryEnabled: photoOutput.isDepthDataDeliveryEnabled,
            maxPhotoQualityPrioritization: photoOutput.maxPhotoQualityPrioritization
        )
    }
}

extension CaptureOutputProfile {
    nonisolated func resolvedPhotoOutput(
        availablePhotoCodecTypes: [AVVideoCodecType]
    ) throws -> ResolvedCaptureOutputProfile {
        try resolvedPhotoOutput(
            capabilities: CapturePhotoOutputCapabilitySnapshot(
                availablePhotoFileTypeIdentifiers: [],
                availablePhotoCodecTypes: availablePhotoCodecTypes,
                supportedPhotoCodecTypesByFileTypeIdentifier: [:],
                supportedMaxPhotoDimensions: [],
                configuredMaxPhotoDimensions: nil,
                isDepthDataDeliverySupported: true,
                isDepthDataDeliveryEnabled: depthDataDeliveryEnabled,
                maxPhotoQualityPrioritization: maxPhotoQualityPrioritization
            )
        )
    }

    nonisolated func resolvedPhotoOutput(
        capabilities: CapturePhotoOutputCapabilitySnapshot
    ) throws -> ResolvedCaptureOutputProfile {
        try validateForEmbeddedPhotoDepthCapture()
        let codec = try requiredCodec(
            availablePhotoCodecTypes: supportedCodecTypes(for: fileContainer, in: capabilities)
        )
        let dimensions = try photoDimensionsPolicy.resolve(from: capabilities.supportedMaxPhotoDimensions)

        let resolvedOutput = ResolvedCaptureOutputProfile(
            profileID: id,
            container: container,
            fileContainer: fileContainer,
            codec: codec,
            depthDataDeliveryEnabled: depthDataDeliveryEnabled,
            embedsDepthDataInPhoto: embedsDepthDataInPhoto,
            depthDataFiltered: depthDataFiltered,
            requiresDepthData: requiresDepthData,
            photoQualityPolicy: photoQualityPolicy,
            maxPhotoDimensions: dimensions,
            compressionQuality: compressionQuality
        )
        try resolvedOutput.validatePhotoOutputCapabilities(capabilities)
        return resolvedOutput
    }

    private nonisolated func supportedCodecTypes(
        for fileContainer: CapturePhotoFileContainer,
        in capabilities: CapturePhotoOutputCapabilitySnapshot
    ) -> [AVVideoCodecType] {
        capabilities.supportedPhotoCodecTypesByFileTypeIdentifier[fileContainer.avFileType.rawValue]
            ?? capabilities.availablePhotoCodecTypes
    }
}

extension ResolvedCaptureOutputProfile {
    nonisolated func validatePhotoOutputCapabilities(
        _ capabilities: CapturePhotoOutputCapabilitySnapshot,
        requireConfiguredState: Bool = false
    ) throws {
        if !capabilities.availablePhotoFileTypeIdentifiers.isEmpty,
           !capabilities.availablePhotoFileTypeIdentifiers.contains(processedFileType.rawValue) {
            let available = capabilities.availablePhotoFileTypeIdentifiers.sorted().joined(separator: ", ")
            throw TAPDepthCaptureError.invalidCaptureOutputProfile(
                "Resolved output profile \(profileID) requires file type \(processedFileType.rawValue), available [\(available)]."
            )
        }

        if let fileSpecificCodecs = capabilities.supportedPhotoCodecTypesByFileTypeIdentifier[processedFileType.rawValue],
           !fileSpecificCodecs.isEmpty,
           !fileSpecificCodecs.contains(requestedCodec) {
            let available = fileSpecificCodecs.map(\.rawValue).sorted().joined(separator: ", ")
            throw TAPDepthCaptureError.captureOutputCodecUnsupported(
                "Resolved output profile \(profileID) requires \(requestedCodec.rawValue) for \(processedFileType.rawValue), available [\(available)]."
            )
        } else if !capabilities.availablePhotoCodecTypes.isEmpty,
                  !capabilities.availablePhotoCodecTypes.contains(requestedCodec) {
            let available = capabilities.availablePhotoCodecTypes
                .map(\.rawValue)
                .sorted()
                .joined(separator: ", ")
            throw TAPDepthCaptureError.captureOutputCodecUnsupported(
                "Resolved output profile \(profileID) requires \(requestedCodec.rawValue), available [\(available)]."
            )
        }

        if let maxPhotoDimensions,
           !capabilities.supportedMaxPhotoDimensions.isEmpty,
           !capabilities.supportedMaxPhotoDimensions.contains(maxPhotoDimensions) {
            let available = capabilities.supportedMaxPhotoDimensions
                .map(\.debugDescription)
                .sorted()
                .joined(separator: ", ")
            throw TAPDepthCaptureError.invalidCaptureOutputProfile(
                "Resolved output profile \(profileID) requires maxPhotoDimensions \(maxPhotoDimensions.debugDescription), available [\(available)]."
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

        guard !requireConfiguredState
                || maxPhotoDimensions == nil
                || capabilities.configuredMaxPhotoDimensions == maxPhotoDimensions else {
            throw TAPDepthCaptureError.invalidCaptureOutputProfile(
                "Photo output maximum dimensions do not match the resolved output profile."
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
        guard container.preservesEmbeddedPhotoDepth else {
            throw TAPDepthCaptureError.invalidCaptureOutputProfile(
                "Resolved output profile is not an embedded photo-depth container."
            )
        }
        guard fileContainer.defaultCodec == codec else {
            throw TAPDepthCaptureError.captureOutputCodecUnsupported(
                "Resolved \(fileContainer.displayName) photo-depth output must use \(fileContainer.defaultCodec.rawValue)."
            )
        }
        guard requiresDepthData else {
            throw TAPDepthCaptureError.invalidCaptureOutputProfile(
                "Resolved photo-depth output must require depth data."
            )
        }
        guard depthDataDeliveryEnabled else {
            throw TAPDepthCaptureError.invalidCaptureOutputProfile(
                "Resolved photo-depth output must request depth delivery."
            )
        }
        guard embedsDepthDataInPhoto else {
            throw TAPDepthCaptureError.invalidCaptureOutputProfile(
                "Resolved photo-depth output must embed depth data."
            )
        }
    }
}
