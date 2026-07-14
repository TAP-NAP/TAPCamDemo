//
//  TAPDepthHEICWriter.swift
//  TAPCamDemo
//

@preconcurrency import AVFoundation
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Writes and reads the TAP XMP extension inside a TAP depth photo file.
///
/// The writer uses `CGImageDestinationCopyImageSource` instead of decoding and
/// re-encoding pixels. That keeps the primary image and Apple auxiliary
/// depth/disparity attachment as close as ImageIO allows while only metadata is
/// merged. HEIC and JPG are explicit containers; unsupported containers fail.
nonisolated enum TAPDepthPhotoFileWriter {
    /// Injects the TAP manifest while preserving the source image items.
    ///
    /// - Tag: InjectTAPManifestIntoDepthPhotoFile
    static func injectingManifest(_ manifest: TAPDepthManifest, into photoData: Data) throws -> Data {
        try injectingManifestWithMetrics(manifest, into: photoData).data
    }

    /// Injects the TAP manifest and returns timing for XMP write and readback.
    static func injectingManifestWithMetrics(
        _ manifest: TAPDepthManifest,
        into photoData: Data
    ) throws -> TAPDepthPhotoFileWriteResult {
        let injectStart = Date()
        let manifestJSON = try TAPDepthManifestEncoder.manifestJSON(manifest)

        guard let source = CGImageSourceCreateWithData(photoData as CFData, nil) else {
            throw TAPDepthCaptureError.imageSourceCreationFailed
        }

        let imageType = CGImageSourceGetType(source) ?? UTType.heic.identifier as CFString
        guard CapturePhotoFileContainer(imageTypeIdentifier: imageType as String) != nil else {
            throw TAPDepthCaptureError.invalidHEICContainerType(imageType as String)
        }

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, imageType, CGImageSourceGetCount(source), nil) else {
            throw TAPDepthCaptureError.imageDestinationCreationFailed
        }

        let xmp = CGImageMetadataCreateMutable()
        var namespaceError: Unmanaged<CFError>?
        let registered = CGImageMetadataRegisterNamespaceForPrefix(
            xmp,
            TAPDepthManifest.xmpNamespaceURI as CFString,
            TAPDepthManifest.xmpPrefix as CFString,
            &namespaceError
        )

        guard registered else {
            let reason = namespaceError?.takeRetainedValue().localizedDescription ?? "unknown namespace registration error"
            throw TAPDepthCaptureError.xmpNamespaceRegistrationFailed(reason)
        }

        guard CGImageMetadataSetValueWithPath(
            xmp,
            nil,
            TAPDepthManifest.xmpManifestPath as CFString,
            manifestJSON as CFString
        ) else {
            throw TAPDepthCaptureError.xmpManifestWriteFailed
        }

        var copyError: Unmanaged<CFError>?
        let options: [CFString: Any] = [
            kCGImageDestinationMetadata: xmp,
            kCGImageDestinationMergeMetadata: true
        ]

        guard CGImageDestinationCopyImageSource(destination, source, options as CFDictionary, &copyError) else {
            let reason = copyError?.takeRetainedValue().localizedDescription ?? "unknown image copy error"
            throw TAPDepthCaptureError.imageCopyFailed(reason)
        }

        let finalData = output as Data
        let xmpInjectDuration = Date().timeIntervalSince(injectStart)

        let verifyStart = Date()
        let verifiedManifestJSON = try TAPDepthPhotoFileReader.manifestJSON(from: finalData)
        let xmpVerifyDuration = Date().timeIntervalSince(verifyStart)

        guard verifiedManifestJSON == manifestJSON else {
            throw TAPDepthCaptureError.xmpManifestMissing
        }

        return TAPDepthPhotoFileWriteResult(
            data: finalData,
            xmpInjectDuration: xmpInjectDuration,
            xmpVerifyDuration: xmpVerifyDuration
        )
    }
}

nonisolated struct TAPDepthPhotoFileWriteResult: Sendable {
    let data: Data
    let xmpInjectDuration: TimeInterval
    let xmpVerifyDuration: TimeInterval
}

/// Minimal readback API for app-side verification and analysis.
///
/// When the file lives in Photos, callers should first use
/// `PhotoLibraryWriter.originalPhotoData(localIdentifier:)` to obtain original resource
/// bytes, then pass those bytes into these functions. Reading a thumbnail or
/// edited representation is not enough because Photos may transform metadata.
nonisolated enum TAPDepthPhotoFileReader {
    static func manifestJSON(from photoData: Data) throws -> String {
        guard let source = CGImageSourceCreateWithData(photoData as CFData, nil),
              let metadata = CGImageSourceCopyMetadataAtIndex(source, 0, nil),
              let manifest = CGImageMetadataCopyStringValueWithPath(metadata, nil, TAPDepthManifest.xmpManifestPath as CFString) else {
            throw TAPDepthCaptureError.xmpManifestMissing
        }

        return manifest as String
    }

    static func decodedManifest(from photoData: Data) throws -> TAPDepthManifest {
        let json = try manifestJSON(from: photoData)
        guard let data = json.data(using: .utf8) else {
            throw TAPDepthCaptureError.invalidUTF8Manifest
        }
        return try JSONDecoder().decode(TAPDepthManifest.self, from: data)
    }

    static func containerTypeIdentifier(from photoData: Data) throws -> String {
        guard let source = CGImageSourceCreateWithData(photoData as CFData, nil),
              let type = CGImageSourceGetType(source) else {
            throw TAPDepthCaptureError.imageSourceCreationFailed
        }
        return type as String
    }

    static func fileContainer(from photoData: Data) throws -> CapturePhotoFileContainer {
        let type = try containerTypeIdentifier(from: photoData)
        guard let container = CapturePhotoFileContainer(imageTypeIdentifier: type) else {
            throw TAPDepthCaptureError.invalidHEICContainerType(type)
        }
        return container
    }

    static func validateSupportedContainer(_ photoData: Data) throws -> CapturePhotoFileContainer {
        try fileContainer(from: photoData)
    }

    static func validateContainer(
        _ photoData: Data,
        expected expectedContainer: CapturePhotoFileContainer
    ) throws {
        let actualContainer = try fileContainer(from: photoData)
        guard actualContainer == expectedContainer else {
            throw TAPDepthCaptureError.invalidHEICContainerType(actualContainer.uniformTypeIdentifier)
        }
    }

    static func validateHEICContainer(_ photoData: Data) throws {
        try validateContainer(photoData, expected: .heic)
    }

    static func depthAuxiliaryInfo(from photoData: Data) -> [AnyHashable: Any]? {
        auxiliaryInfo(from: photoData, type: kCGImageAuxiliaryDataTypeDepth)
    }

    static func disparityAuxiliaryInfo(from photoData: Data) -> [AnyHashable: Any]? {
        auxiliaryInfo(from: photoData, type: kCGImageAuxiliaryDataTypeDisparity)
    }

    static func depthData(from photoData: Data) throws -> AVDepthData? {
        if let depthAuxiliaryInfo = depthAuxiliaryInfo(from: photoData) {
            return try AVDepthData(fromDictionaryRepresentation: depthAuxiliaryInfo)
        }

        if let disparityAuxiliaryInfo = disparityAuxiliaryInfo(from: photoData) {
            return try AVDepthData(fromDictionaryRepresentation: disparityAuxiliaryInfo)
        }

        return nil
    }

    private static func auxiliaryInfo(from photoData: Data, type: CFString) -> [AnyHashable: Any]? {
        guard let source = CGImageSourceCreateWithData(photoData as CFData, nil),
              let info = CGImageSourceCopyAuxiliaryDataInfoAtIndex(source, 0, type) else {
            return nil
        }

        return info as? [AnyHashable: Any]
    }
}

/// Backward-compatible HEIC wrapper for older call sites and tests.
nonisolated enum TAPDepthHEICWriter {
    static func injectingManifest(_ manifest: TAPDepthManifest, into heicData: Data) throws -> Data {
        try TAPDepthPhotoFileWriter.injectingManifest(manifest, into: heicData)
    }

    static func injectingManifestWithMetrics(
        _ manifest: TAPDepthManifest,
        into heicData: Data
    ) throws -> TAPDepthHEICWriteResult {
        let result = try TAPDepthPhotoFileWriter.injectingManifestWithMetrics(manifest, into: heicData)
        return TAPDepthHEICWriteResult(
            data: result.data,
            xmpInjectDuration: result.xmpInjectDuration,
            xmpVerifyDuration: result.xmpVerifyDuration
        )
    }
}

nonisolated struct TAPDepthHEICWriteResult: Sendable {
    let data: Data
    let xmpInjectDuration: TimeInterval
    let xmpVerifyDuration: TimeInterval
}

/// Backward-compatible HEIC wrapper for older call sites and tests.
nonisolated enum TAPDepthHEICReader {
    static func manifestJSON(from heicData: Data) throws -> String {
        try TAPDepthPhotoFileReader.manifestJSON(from: heicData)
    }

    static func decodedManifest(from heicData: Data) throws -> TAPDepthManifest {
        try TAPDepthPhotoFileReader.decodedManifest(from: heicData)
    }

    static func containerTypeIdentifier(from heicData: Data) throws -> String {
        try TAPDepthPhotoFileReader.containerTypeIdentifier(from: heicData)
    }

    static func validateHEICContainer(_ heicData: Data) throws {
        try TAPDepthPhotoFileReader.validateHEICContainer(heicData)
    }

    static func depthAuxiliaryInfo(from heicData: Data) -> [AnyHashable: Any]? {
        TAPDepthPhotoFileReader.depthAuxiliaryInfo(from: heicData)
    }

    static func disparityAuxiliaryInfo(from heicData: Data) -> [AnyHashable: Any]? {
        TAPDepthPhotoFileReader.disparityAuxiliaryInfo(from: heicData)
    }

    static func depthData(from heicData: Data) throws -> AVDepthData? {
        try TAPDepthPhotoFileReader.depthData(from: heicData)
    }
}
