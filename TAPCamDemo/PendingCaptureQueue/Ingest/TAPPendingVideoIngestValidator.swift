//
//  TAPPendingVideoIngestValidator.swift
//  TAPCamDemo
//

import Foundation

nonisolated enum TAPPendingVideoIngestValidator {
    static func validate(
        artifact: TAPPendingVideoCaptureArtifact,
        expectedWorkspaceURL: URL
    ) throws -> TAPManifestBindingDocument {
        let expectedArtifactURL = expectedWorkspaceURL.appendingPathComponent(
            TAPPendingCaptureBundlePaths.videoArtifactFilename
        )
        guard artifact.videoURL.standardizedFileURL
                == expectedArtifactURL.standardizedFileURL else {
            throw TAPDepthCaptureError.invalidPendingCaptureBundlePath(
                "video recorder output must be inside its pending capture workspace"
            )
        }
        let document = try TAPVideoValidationInput(fileURL: artifact.videoURL).manifestDocument
        guard document.schemaID == TAPVideoManifest.schemaIdentifier,
              document.captureID == artifact.captureID,
              document.packageID.flatMap(UUID.init(uuidString:)) == artifact.packageID else {
            throw TAPDepthCaptureError.invalidTAPManifest(
                "pending video identity does not match its manifest"
            )
        }
        return document
    }
}
