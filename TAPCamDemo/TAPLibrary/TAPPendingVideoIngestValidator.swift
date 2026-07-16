//
//  TAPPendingVideoIngestValidator.swift
//  TAPCamDemo
//

import Foundation

nonisolated enum TAPPendingVideoIngestValidator {
    static func validate(
        artifact: TAPPendingVideoCaptureArtifact,
        expectedWorkspaceURL: URL,
        terminalFailureCode: TAPPendingCaptureFailureCode?
    ) throws -> TAPVideoManifest {
        let expectedArtifactURL = expectedWorkspaceURL.appendingPathComponent(
            TAPPendingCaptureBundlePathPolicy.videoArtifactFilename
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
        let hasRecordedDepth = coverage.sampleCount > 0
            && coverage.trackID != nil
            && coverage.format != nil
        if hasRecordedDepth {
            guard terminalFailureCode == nil else {
                throw TAPDepthCaptureError.invalidTAPManifest(
                    "video with recorded depth cannot enter a terminal ingest state"
                )
            }
        } else {
            guard terminalFailureCode == .missingDepthData else {
                throw TAPDepthCaptureError.missingDepthData
            }
        }
        return manifest
    }
}
