//
//  TAPPhotoFileMetadataCustomizer.swift
//  TAPCamDemo
//
//  Created by Codex on 2026/4/25.
//

@preconcurrency import AVFoundation
import CoreLocation
import ImageIO
import Foundation

/// Supplies standard EXIF/GPS/TIFF metadata while `AVCapturePhoto` flattens the
/// in-memory capture into photo bytes.
///
/// TAP-specific data is intentionally not written here. This customizer keeps
/// generic photo metadata compatible with normal image tools, while
/// `TAPDepthHEICWriter` owns the XMP `tapdepth:Manifest` that defines our
/// format extension. The short EXIF UserComment is only a pointer that tells
/// parsers where to find the authoritative manifest.
nonisolated final class TAPPhotoFileMetadataCustomizer: NSObject, AVCapturePhotoFileDataRepresentationCustomizer {
    private let capturedAt: Date
    private let location: CLLocation?
    private let device: AVCaptureDevice

    init(capturedAt: Date, location: CLLocation?, device: AVCaptureDevice) {
        self.capturedAt = capturedAt
        self.location = location
        self.device = device
        super.init()
    }

    func replacementMetadata(for photo: AVCapturePhoto) -> [String: Any]? {
        var metadata = photo.metadata
        metadata[kCGImagePropertyExifDictionary as String] = exifDictionary(from: metadata)
        metadata[kCGImagePropertyTIFFDictionary as String] = tiffDictionary(from: metadata)

        if let location {
            metadata[kCGImagePropertyGPSDictionary as String] = gpsDictionary(from: location)
        }

        return metadata
    }

    func replacementDepthData(for photo: AVCapturePhoto) -> AVDepthData? {
        // Returning `photo.depthData` makes the preservation of the auxiliary
        // depth attachment explicit. If this method returned nil, the flattened
        // HEIC would become a normal RGB-only photo and the TAP manifest would
        // falsely describe depth data that no longer exists.
        photo.depthData
    }

    private func exifDictionary(from metadata: [String: Any]) -> [String: Any] {
        var exif = metadata[kCGImagePropertyExifDictionary as String] as? [String: Any] ?? [:]
        exif[kCGImagePropertyExifDateTimeOriginal as String] = TAPExifDateFormatting.local.string(from: capturedAt)
        exif[kCGImagePropertyExifDateTimeDigitized as String] = TAPExifDateFormatting.local.string(from: capturedAt)
        exif[kCGImagePropertyExifUserComment as String] = TAPDepthManifest.exifUserCommentPointer
        exif[kCGImagePropertyExifLensModel as String] = device.localizedName
        if let nominalFocalLength = device.tapNominalFocalLengthIn35mmFilm {
            exif[kCGImagePropertyExifFocalLenIn35mmFilm as String] = nominalFocalLength
        }
        return exif
    }

    private func tiffDictionary(from metadata: [String: Any]) -> [String: Any] {
        var tiff = metadata[kCGImagePropertyTIFFDictionary as String] as? [String: Any] ?? [:]
        tiff[kCGImagePropertyTIFFMake as String] = "Apple"
        tiff[kCGImagePropertyTIFFModel as String] = device.modelID
        tiff[kCGImagePropertyTIFFSoftware as String] = "TAPCamDemo"
        tiff[kCGImagePropertyTIFFDateTime as String] = TAPExifDateFormatting.local.string(from: capturedAt)
        return tiff
    }

    private func gpsDictionary(from location: CLLocation) -> [String: Any] {
        let coordinate = location.coordinate
        return [
            kCGImagePropertyGPSLatitude as String: abs(coordinate.latitude),
            kCGImagePropertyGPSLatitudeRef as String: coordinate.latitude >= 0 ? "N" : "S",
            kCGImagePropertyGPSLongitude as String: abs(coordinate.longitude),
            kCGImagePropertyGPSLongitudeRef as String: coordinate.longitude >= 0 ? "E" : "W",
            kCGImagePropertyGPSAltitude as String: abs(location.altitude),
            kCGImagePropertyGPSAltitudeRef as String: location.altitude >= 0 ? 0 : 1,
            kCGImagePropertyGPSHPositioningError as String: location.horizontalAccuracy,
            kCGImagePropertyGPSDateStamp as String: TAPExifDateFormatting.gpsDate.string(from: location.timestamp),
            kCGImagePropertyGPSTimeStamp as String: TAPExifDateFormatting.gpsTime.string(from: location.timestamp)
        ]
    }
}

nonisolated enum TAPExifDateFormatting {
    static let local: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        return formatter
    }()

    static let gpsDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy:MM:dd"
        return formatter
    }()

    static let gpsTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "HH:mm:ss.SSSSSS"
        return formatter
    }()
}
