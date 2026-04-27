//
//  CaptureJob.swift
//  TAPCamDemo
//
//  Created by Codex on 2026/4/27.
//

import Foundation

/// One user shutter request as it travels through capture, packaging, hooks,
/// writing, and diagnostics.
///
/// The job is intentionally lightweight and stable. It lets diagnostics and
/// future external providers correlate work without giving those providers
/// permission to mutate the managed `AVCaptureSession` directly.
nonisolated struct CaptureJob: Identifiable, Equatable, Sendable {
    let id: UUID
    let createdAt: Date

    nonisolated init(id: UUID = UUID(), createdAt: Date = Date()) {
        self.id = id
        self.createdAt = createdAt
    }
}

