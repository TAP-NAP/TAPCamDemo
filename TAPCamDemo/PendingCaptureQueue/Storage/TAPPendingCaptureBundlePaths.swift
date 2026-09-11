//
//  TAPPendingCaptureBundlePaths.swift
//  TAPCamDemo
//

import Foundation

/// Validates app-private pending bundle paths before the store touches disk.
///
/// Normal captures use UUID-like manifest IDs, but this policy keeps future
/// import, repair, migration, or test paths from turning a persisted identifier
/// or filename into an arbitrary filesystem path.
nonisolated enum TAPPendingCaptureBundlePaths {
    static var defaultRootURL: URL {
        let baseURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        return baseURL
            .appendingPathComponent("TAPCaptureLibrary", isDirectory: true)
            .appendingPathComponent(
                TAPPendingCaptureBundlePaths.recordsDirectoryName,
                isDirectory: true
            )
    }

    static let recordsDirectoryName = "Pending"
    static let videoCaptureWorkspacePrefix = ".recording-"
    static let recordFilename = "bundle.json"
    static let unsignedHEICFilename = "unsigned.heic"
    static let signedHEICFilename = "signed.heic"
    static let unsignedJPEGFilename = "unsigned.jpg"
    static let signedJPEGFilename = "signed.jpg"
    static let videoArtifactFilename = "artifact.mp4"
    static let pairedVideoFilename = "paired-video.mov"
    static let thumbnailFilename = "thumbnail.jpg"

    static func bundleURL(rootURL: URL, captureID: String) throws -> URL {
        rootURL.appendingPathComponent(try validatedCaptureID(captureID), isDirectory: true)
    }

    static func recordURL(bundleURL: URL) -> URL {
        bundleURL.appendingPathComponent(recordFilename)
    }

    static func videoCaptureWorkspaceURL(rootURL: URL, captureID: String) throws -> URL {
        rootURL.appendingPathComponent(
            videoCaptureWorkspacePrefix + (try validatedCaptureID(captureID)),
            isDirectory: true
        )
    }

    static func artifactURL(rootURL: URL, captureID: String, filename: String) throws -> URL {
        try bundleURL(rootURL: rootURL, captureID: captureID)
            .appendingPathComponent(validatedArtifactFilename(filename))
    }

    static func validateRecord(_ record: TAPPendingCaptureRecord, expectedCaptureID: String? = nil) throws {
        let validatedID = try validatedCaptureID(record.captureID)
        if let expectedCaptureID, validatedID != expectedCaptureID {
            throw TAPDepthCaptureError.invalidPendingCaptureBundlePath("record captureID must match bundle directory")
        }

        try validateOptionalArtifactFilename(record.unsignedPhotoFilename)
        try validateOptionalArtifactFilename(record.signedPhotoFilename)
        try validateOptionalArtifactFilename(record.videoArtifactFilename)
        try validateOptionalArtifactFilename(record.pairedVideoFilename)
        try validateOptionalArtifactFilename(record.thumbnailFilename)
    }

    private static func validatedCaptureID(_ captureID: String) throws -> String {
        guard (1...128).contains(captureID.count) else {
            throw TAPDepthCaptureError.invalidPendingCaptureBundlePath("captureID must be 1...128 characters")
        }

        guard captureID != ".", captureID != ".." else {
            throw TAPDepthCaptureError.invalidPendingCaptureBundlePath("captureID must be a file name")
        }

        guard !captureID.hasPrefix(".") else {
            throw TAPDepthCaptureError.invalidPendingCaptureBundlePath("captureID must not start with a dot")
        }

        let allowedScalars = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.")
        guard captureID.unicodeScalars.allSatisfy(allowedScalars.contains) else {
            throw TAPDepthCaptureError.invalidPendingCaptureBundlePath("captureID must contain only ASCII letters, numbers, hyphen, underscore, or dot")
        }

        return captureID
    }

    private static func validateOptionalArtifactFilename(_ filename: String?) throws {
        guard let filename else {
            return
        }
        _ = try validatedArtifactFilename(filename)
    }

    private static func validatedArtifactFilename(_ filename: String) throws -> String {
        guard artifactFilenames.contains(filename) else {
            throw TAPDepthCaptureError.invalidPendingCaptureBundlePath("pending artifact filename must be a known bundle resource")
        }
        return filename
    }

    private static let artifactFilenames: Set<String> = [
        unsignedHEICFilename,
        signedHEICFilename,
        unsignedJPEGFilename,
        signedJPEGFilename,
        videoArtifactFilename,
        pairedVideoFilename,
        thumbnailFilename
    ]
}
