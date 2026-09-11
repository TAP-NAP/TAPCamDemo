//
//  TAPPendingVideoIngestValidator.swift
//  TAPCamDemo
//

import Foundation

nonisolated enum TAPPendingVideoIngestValidator {
    static func validate(
        artifact: TAPPendingVideoCaptureArtifact,
        expectedWorkspaceURL: URL
    ) throws -> TAPVideoManifest {
        let expectedArtifactURL = expectedWorkspaceURL.appendingPathComponent(
            TAPPendingCaptureBundlePaths.videoArtifactFilename
        )
        guard artifact.videoURL.standardizedFileURL
                == expectedArtifactURL.standardizedFileURL else {
            throw TAPDepthCaptureError.invalidPendingCaptureBundlePath(
                "video recorder output must be inside its pending capture workspace"
            )
        }
        let manifest = try TAPVideoManifestBox.decodedManifest(
            fromFileAt: artifact.videoURL
        )
        guard manifest.schema == TAPVideoManifest.Schema(),
              manifest.payload.id == artifact.captureID,
              UUID(uuidString: manifest.payload.packageID) == artifact.packageID else {
            throw TAPDepthCaptureError.invalidTAPManifest(
                "pending video identity does not match its manifest"
            )
        }
        let coverage = manifest.payload.depthCoverage
        if coverage.sampleCount == 0 {
            guard coverage.trackID == nil,
                  coverage.trackCodec == nil,
                  coverage.trackDurationSeconds == nil,
                  coverage.trackTimeScale == nil,
                  coverage.format == nil else {
                throw TAPDepthCaptureError.invalidTAPManifest(
                    "zero-depth video must not declare a stored depth track"
                )
            }
        } else {
            guard coverage.sampleCount > 0,
                  coverage.trackID != nil,
                  coverage.format != nil else {
                throw TAPDepthCaptureError.invalidTAPManifest(
                    "stored depth samples require a depth track and format"
                )
            }
        }
        return manifest
    }
}
