//
//  ArtifactHookPipeline.swift
//  TAPCamDemo
//
//  Created by Codex on 2026/4/27.
//

import Foundation

/// Post-packaging hook extension point.
///
/// Hooks run after the HEIC artifact exists and before writing. v0.6 registers
/// no hooks by default, so the app does not hash, sign, watermark, upload, or
/// mutate metadata automatically. External developers can add those behaviors
/// later without touching capture providers or session configuration.
protocol ArtifactProcessingHook: Sendable {
    var id: String { get }
    func process(_ artifact: PackagedCaptureArtifact) async throws -> PackagedCaptureArtifact
}

/// Sequential hook runner.
nonisolated struct ArtifactHookPipeline: Sendable {
    let hooks: [any ArtifactProcessingHook]

    nonisolated init(hooks: [any ArtifactProcessingHook] = []) {
        self.hooks = hooks
    }

    func process(_ artifact: PackagedCaptureArtifact) async throws -> PackagedCaptureArtifact {
        var current = artifact
        for hook in hooks {
            current = try await hook.process(current)
        }
        return current
    }
}

/// Explicit no-op hook useful for tests and examples.
nonisolated struct NoOpArtifactHook: ArtifactProcessingHook {
    let id = "tap.noop"

    func process(_ artifact: PackagedCaptureArtifact) async throws -> PackagedCaptureArtifact {
        artifact
    }
}

