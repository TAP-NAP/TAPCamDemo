//
//  CaptureJob.swift
//  TAPCamDemo
//
//  Created by Codex on 2026/4/27.
//

import Foundation

/// One user shutter request as it travels through capture, packaging, writing,
/// and diagnostics.
///
/// The job is intentionally lightweight: it gives the SingleCam pipeline a
/// stable identity without adding another abstraction over AVFoundation.
nonisolated struct CaptureJob: Identifiable, Equatable, Sendable {
    let id: UUID
    let createdAt: Date

    nonisolated init(id: UUID = UUID(), createdAt: Date = Date()) {
        self.id = id
        self.createdAt = createdAt
    }
}
