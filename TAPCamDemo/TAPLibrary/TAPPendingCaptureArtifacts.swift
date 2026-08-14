//
//  TAPPendingCaptureArtifacts.swift
//  TAPCamDemo
//

import Foundation

nonisolated struct TAPVideoRecordingWorkspace: Equatable, Sendable {
    let captureID: String
    let bundleURL: URL
    let artifactURL: URL
}

nonisolated struct TAPPendingVideoCaptureArtifact: Sendable {
    let captureID: String
    let packageID: UUID
    let capturedAt: Date
    let videoURL: URL
    let captureScoreSummary: CaptureScoreSummary
    let location: TAPPendingCaptureLocation?

    init(
        captureID: String,
        packageID: UUID = UUID(),
        capturedAt: Date,
        videoURL: URL,
        captureScoreSummary: CaptureScoreSummary = .unknown,
        location: TAPPendingCaptureLocation? = nil
    ) {
        self.captureID = captureID
        self.packageID = packageID
        self.capturedAt = capturedAt
        self.videoURL = videoURL
        self.captureScoreSummary = captureScoreSummary
        self.location = location
    }
}
