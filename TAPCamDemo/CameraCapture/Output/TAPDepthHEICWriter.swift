//
//  TAPDepthHEICWriter.swift
//  TAPCamDemo
//
//  Created by Codex on 2026/4/25.
//

@preconcurrency import AVFoundation
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Writes and reads the TAP XMP extension inside a HEIC file.
///
/// The writer uses `CGImageDestinationCopyImageSource` instead of decoding and
/// re-encoding pixels. That is important for this format: the photo image and
/// Apple auxiliary depth/disparity attachment must survive byte-for-byte as
/// much as ImageIO allows, while only metadata is merged.
nonisolated enum TAPDepthHEICWriter {
    /// Injects the TAP manifest while preserving the source HEIC image items.
    ///
    /// The copy path avoids a full pixel decode/re-encode so Apple auxiliary
    /// depth/disparity attachments survive the output packaging step.
    ///
    /// - Tag: InjectTAPManifestIntoHEIC
    static func injectingManifest(_ manifest: TAPDepthManifest, into heicData: Data) throws -> Data {
        let manifestJSON = try TAPDepthManifestEncoder.manifestJSON(manifest)

        guard let source = CGImageSourceCreateWithData(heicData as CFData, nil) else {
            throw TAPDepthCaptureError.imageSourceCreationFailed
        }

        let imageType = CGImageSourceGetType(source) ?? UTType.heic.identifier as CFString
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
        guard try TAPDepthHEICReader.manifestJSON(from: finalData) == manifestJSON else {
            throw TAPDepthCaptureError.xmpManifestMissing
        }

        return finalData
    }
}

/// Minimal readback API for third-party tools and app-side verification.
///
/// When the HEIC lives in Photos, callers should first use
/// `PhotoLibraryWriter.originalPhotoData(for:)` to obtain the original resource
/// bytes, then pass those bytes into these functions. Reading the visible asset
/// thumbnail or edited representation is not enough because Photos may transform
/// those derivatives.
nonisolated enum TAPDepthHEICReader {
    static func manifestJSON(from heicData: Data) throws -> String {
        guard let source = CGImageSourceCreateWithData(heicData as CFData, nil),
              let metadata = CGImageSourceCopyMetadataAtIndex(source, 0, nil),
              let manifest = CGImageMetadataCopyStringValueWithPath(metadata, nil, TAPDepthManifest.xmpManifestPath as CFString) else {
            throw TAPDepthCaptureError.xmpManifestMissing
        }

        return manifest as String
    }

    static func decodedManifest(from heicData: Data) throws -> TAPDepthManifest {
        let json = try manifestJSON(from: heicData)
        guard let data = json.data(using: .utf8) else {
            throw TAPDepthCaptureError.invalidUTF8Manifest
        }
        return try JSONDecoder().decode(TAPDepthManifest.self, from: data)
    }

    static func depthAuxiliaryInfo(from heicData: Data) -> [AnyHashable: Any]? {
        auxiliaryInfo(from: heicData, type: kCGImageAuxiliaryDataTypeDepth)
    }

    static func disparityAuxiliaryInfo(from heicData: Data) -> [AnyHashable: Any]? {
        auxiliaryInfo(from: heicData, type: kCGImageAuxiliaryDataTypeDisparity)
    }

    static func depthData(from heicData: Data) throws -> AVDepthData? {
        if let depthAuxiliaryInfo = depthAuxiliaryInfo(from: heicData) {
            return try AVDepthData(fromDictionaryRepresentation: depthAuxiliaryInfo)
        }

        if let disparityAuxiliaryInfo = disparityAuxiliaryInfo(from: heicData) {
            return try AVDepthData(fromDictionaryRepresentation: disparityAuxiliaryInfo)
        }

        return nil
    }

    private static func auxiliaryInfo(from heicData: Data, type: CFString) -> [AnyHashable: Any]? {
        guard let source = CGImageSourceCreateWithData(heicData as CFData, nil),
              let info = CGImageSourceCopyAuxiliaryDataInfoAtIndex(source, 0, type) else {
            return nil
        }

        return info as? [AnyHashable: Any]
    }
}
