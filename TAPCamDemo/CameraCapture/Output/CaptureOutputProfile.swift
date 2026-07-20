//
//  CaptureOutputProfile.swift
//  TAPCamDemo
//

@preconcurrency import AVFoundation
import CoreMedia
import Foundation
import UniformTypeIdentifiers

/// App-reviewed file containers for TAP photo-depth artifacts.
///
/// This is the durable file boundary. HEIC and JPEG are both explicit output
/// contracts; neither one is a hidden fallback for the other.
nonisolated enum CapturePhotoFileContainer: String, CaseIterable, Codable, Equatable, Sendable {
    case heic
    case jpeg

    init?(imageTypeIdentifier: String) {
        if imageTypeIdentifier == UTType.heic.identifier || imageTypeIdentifier == UTType.heif.identifier {
            self = .heic
        } else if imageTypeIdentifier == UTType.jpeg.identifier {
            self = .jpeg
        } else {
            return nil
        }
    }

    var avFileType: AVFileType {
        switch self {
        case .heic:
            .heic
        case .jpeg:
            .jpg
        }
    }

    var uniformTypeIdentifier: String {
        switch self {
        case .heic:
            UTType.heic.identifier
        case .jpeg:
            UTType.jpeg.identifier
        }
    }

    var defaultCodec: CapturePhotoCodec {
        switch self {
        case .heic:
            .hevc
        case .jpeg:
            .jpeg
        }
    }

    var unsignedFilename: String {
        switch self {
        case .heic:
            "unsigned.heic"
        case .jpeg:
            "unsigned.jpg"
        }
    }

    var signedFilename: String {
        switch self {
        case .heic:
            "signed.heic"
        case .jpeg:
            "signed.jpg"
        }
    }

    var displayName: String {
        switch self {
        case .heic:
            "HEIC"
        case .jpeg:
            "JPG"
        }
    }
}

/// Still-photo dimensions selected for an `AVCapturePhotoOutput` request.
///
/// AVFoundation reports these as `CMVideoDimensions`. Keeping a small app type
/// makes sorting, policy decisions, and tests readable without passing raw
/// CoreMedia structs through the output profile layer.
nonisolated struct CapturePhotoDimensions: Codable, Equatable, Sendable {
    let width: Int32
    let height: Int32

    init(width: Int32, height: Int32) {
        self.width = width
        self.height = height
    }

    init(_ dimensions: CMVideoDimensions) {
        self.init(width: dimensions.width, height: dimensions.height)
    }

    var cmVideoDimensions: CMVideoDimensions {
        CMVideoDimensions(width: width, height: height)
    }

    var pixelCount: Int64 {
        Int64(width) * Int64(height)
    }

    var isValid: Bool {
        width > 0 && height > 0
    }

    /// iOS can expose 24MP dimensions that are only practical with deferred
    /// photo delivery. This release keeps normal still delivery and chooses the
    /// next largest standard dimension instead.
    var isDeferredOnly24MPCandidate: Bool {
        (width == 5712 && height == 4284) || (width == 4284 && height == 5712)
    }

    var debugDescription: String {
        "\(width)x\(height)"
    }
}

/// Policy for choosing the still-photo dimensions from the active camera format.
nonisolated enum CapturePhotoDimensionsPolicy: String, Codable, Equatable, Sendable {
    case largestStandardSupported

    func resolve(from supportedDimensions: [CapturePhotoDimensions]) throws -> CapturePhotoDimensions? {
        switch self {
        case .largestStandardSupported:
            return supportedDimensions
                .filter { $0.isValid && !$0.isDeferredOnly24MPCandidate }
                .max { lhs, rhs in lhs.pixelCount < rhs.pixelCount }
        }
    }
}

/// The physical container that the capture pipeline is prepared to create.
///
/// Release containers are reviewed Apple photo-depth files with the TAP
/// manifest embedded as XMP. Keeping that fact in a named type gives future
/// RAW/video work a clear place to start without making the storage layer infer
/// product meaning from file extensions.
nonisolated enum CaptureOutputContainer: String, Codable, Equatable, Sendable {
    case embeddedPhotoDepthHEIC
    case embeddedPhotoDepthJPEG

    var preservesEmbeddedPhotoDepth: Bool {
        switch self {
        case .embeddedPhotoDepthHEIC, .embeddedPhotoDepthJPEG:
            true
        }
    }

    var fileContainer: CapturePhotoFileContainer {
        switch self {
        case .embeddedPhotoDepthHEIC:
            .heic
        case .embeddedPhotoDepthJPEG:
            .jpeg
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
    case jpegContainerAllowsNonJPEGCodec
    case containerFileTypeMismatch

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
        case .jpegContainerAllowsNonJPEGCodec:
            "Embedded photo-depth JPG output must require the JPEG photo codec."
        case .containerFileTypeMismatch:
            "Output profile container and file container must describe the same file type."
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
    let fileContainer: CapturePhotoFileContainer
    let codecPreference: [CapturePhotoCodec]
    let depthDataDeliveryEnabled: Bool
    let embedsDepthDataInPhoto: Bool
    let depthDataFiltered: Bool
    let requiresDepthData: Bool
    let photoQualityPolicy: CapturePhotoQualityPolicy
    let photoDimensionsPolicy: CapturePhotoDimensionsPolicy
    let compressionQuality: Double

    init(
        id: String,
        container: CaptureOutputContainer,
        fileContainer: CapturePhotoFileContainer? = nil,
        codecPreference: [CapturePhotoCodec],
        depthDataDeliveryEnabled: Bool,
        embedsDepthDataInPhoto: Bool,
        depthDataFiltered: Bool,
        requiresDepthData: Bool,
        photoQualityPolicy: CapturePhotoQualityPolicy,
        photoDimensionsPolicy: CapturePhotoDimensionsPolicy = .largestStandardSupported,
        compressionQuality: Double = 1.0
    ) {
        self.id = id
        self.container = container
        self.fileContainer = fileContainer ?? container.fileContainer
        self.codecPreference = codecPreference
        self.depthDataDeliveryEnabled = depthDataDeliveryEnabled
        self.embedsDepthDataInPhoto = embedsDepthDataInPhoto
        self.depthDataFiltered = depthDataFiltered
        self.requiresDepthData = requiresDepthData
        self.photoQualityPolicy = photoQualityPolicy
        self.photoDimensionsPolicy = photoDimensionsPolicy
        self.compressionQuality = compressionQuality
    }

    var photoQualityPrioritization: AVCapturePhotoOutput.QualityPrioritization {
        photoQualityPolicy.avFoundationRequestedPrioritization
    }

    var maxPhotoQualityPrioritization: AVCapturePhotoOutput.QualityPrioritization {
        photoQualityPolicy.avFoundationMaximumPrioritization
    }

    static let releasePhotoDepthHEIC = CaptureOutputProfile(
        id: "release.photo-depth.heic",
        container: .embeddedPhotoDepthHEIC,
        fileContainer: .heic,
        codecPreference: [.hevc],
        depthDataDeliveryEnabled: true,
        embedsDepthDataInPhoto: true,
        depthDataFiltered: true,
        requiresDepthData: true,
        photoQualityPolicy: .releaseQuality,
        photoDimensionsPolicy: .largestStandardSupported,
        compressionQuality: 1.0
    )

    static let releasePhotoDepthJPEG = CaptureOutputProfile(
        id: "release.photo-depth.jpg",
        container: .embeddedPhotoDepthJPEG,
        fileContainer: .jpeg,
        codecPreference: [.jpeg],
        depthDataDeliveryEnabled: true,
        embedsDepthDataInPhoto: true,
        depthDataFiltered: true,
        requiresDepthData: true,
        photoQualityPolicy: .releaseQuality,
        photoDimensionsPolicy: .largestStandardSupported,
        compressionQuality: 1.0
    )

    static func releasePhotoDepthProfile(
        fileContainer: CapturePhotoFileContainer,
        photoQualityLevel: CapturePhotoQualityLevel = .quality
    ) -> CaptureOutputProfile {
        let baseProfile: CaptureOutputProfile = fileContainer == .jpeg
            ? .releasePhotoDepthJPEG
            : .releasePhotoDepthHEIC
        return baseProfile.withPhotoQualityPolicy(
            .release(requested: photoQualityLevel)
        )
    }

    func withPhotoQualityPolicy(_ policy: CapturePhotoQualityPolicy) -> CaptureOutputProfile {
        CaptureOutputProfile(
            id: id,
            container: container,
            fileContainer: fileContainer,
            codecPreference: codecPreference,
            depthDataDeliveryEnabled: depthDataDeliveryEnabled,
            embedsDepthDataInPhoto: embedsDepthDataInPhoto,
            depthDataFiltered: depthDataFiltered,
            requiresDepthData: requiresDepthData,
            photoQualityPolicy: policy,
            photoDimensionsPolicy: photoDimensionsPolicy,
            compressionQuality: compressionQuality
        )
    }

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

        if container.fileContainer != fileContainer {
            violations.append(.containerFileTypeMismatch)
        }

        if container.preservesEmbeddedPhotoDepth && !requiresDepthData {
            violations.append(.photoDepthContainerWithoutRequiredDepth)
        }

        if container == .embeddedPhotoDepthHEIC && codecPreference != [.hevc] {
            violations.append(.heicContainerAllowsNonHEVCCodec)
        }

        if container == .embeddedPhotoDepthJPEG && codecPreference != [.jpeg] {
            violations.append(.jpegContainerAllowsNonJPEGCodec)
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
