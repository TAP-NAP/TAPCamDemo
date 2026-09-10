//
//  TAPVideoPerformanceTrace.swift
//  TAPCamDemo
//

import Foundation
import os
import Darwin

/// Stable signpost events and intervals for native Instruments profiling.
/// Instruments uses them to correlate latency and runtime checkpoints.
nonisolated enum TAPVideoPerformanceTrace {
    private static let recording = OSSignposter(
        subsystem: Bundle.main.bundleIdentifier ?? "TAPCamDemo",
        category: "TAPVideo.Recording"
    )
    private static let playback = OSSignposter(
        subsystem: Bundle.main.bundleIdentifier ?? "TAPCamDemo",
        category: "TAPVideo.Playback"
    )
    private static let photos = OSSignposter(
        subsystem: Bundle.main.bundleIdentifier ?? "TAPCamDemo",
        category: "TAPVideo.Photos"
    )
    private static let signing = OSSignposter(
        subsystem: Bundle.main.bundleIdentifier ?? "TAPCamDemo",
        category: "TAPVideo.Signing"
    )
    private static let storage = OSSignposter(
        subsystem: Bundle.main.bundleIdentifier ?? "TAPCamDemo",
        category: "TAPVideo.Storage"
    )
    private static let evidence = OSSignposter(
        subsystem: Bundle.main.bundleIdentifier ?? "TAPCamDemo",
        category: "TAPVideo.Evidence"
    )

    // MARK: - Capture timeline

    static func emitCaptureStart(recordsAudio: Bool, recordsDepth: Bool) {
        recording.emitEvent(
            "TAPVideoCaptureStart",
            "recordsAudio=\(recordsAudio, privacy: .public) recordsDepth=\(recordsDepth, privacy: .public)"
        )
    }

    static func emitCaptureFirstRGB(timestampSeconds: Double) {
        recording.emitEvent(
            "TAPVideoCaptureFirstRGB",
            "timestampSeconds=\(timestampSeconds, privacy: .public)"
        )
    }

    static func emitCaptureFirstDepth(timestampSeconds: Double) {
        recording.emitEvent(
            "TAPVideoCaptureFirstDepth",
            "timestampSeconds=\(timestampSeconds, privacy: .public)"
        )
    }

    static func emitCaptureStop(reason: String) {
        recording.emitEvent(
            "TAPVideoCaptureStop",
            "reason=\(reason, privacy: .public)"
        )
    }

    static func emitWriterFinished(succeeded: Bool) {
        recording.emitEvent(
            "TAPVideoWriterFinished",
            "succeeded=\(succeeded, privacy: .public)"
        )
    }

    static func emitManifestAppended(byteCount: UInt64) {
        recording.emitEvent(
            "TAPVideoManifestAppended",
            "artifactBytes=\(byteCount, privacy: .public)"
        )
    }

    static func beginRecordingFinalize() -> OSSignpostIntervalState {
        recording.beginInterval("TAPVideoRecordingFinalize")
    }

    static func endRecordingFinalize(
        _ state: OSSignpostIntervalState,
        depthSampleCount: Int,
        droppedDepthSampleCount: Int
    ) {
        recording.endInterval(
            "TAPVideoRecordingFinalize",
            state,
            "depthSamples=\(depthSampleCount, privacy: .public) depthDrops=\(droppedDepthSampleCount, privacy: .public)"
        )
    }

    static func beginDepthEncode(frameIndex: Int) -> OSSignpostIntervalState {
        recording.beginInterval(
            "TAPVideoDepthEncode",
            "frameIndex=\(frameIndex, privacy: .public)"
        )
    }

    static func endDepthEncode(
        _ state: OSSignpostIntervalState,
        codec: String,
        inputByteCount: Int,
        outputByteCount: Int
    ) {
        recording.endInterval(
            "TAPVideoDepthEncode",
            state,
            "codec=\(codec, privacy: .public) inputBytes=\(inputByteCount, privacy: .public) outputBytes=\(outputByteCount, privacy: .public)"
        )
    }

    // MARK: - Signing and validation

    static func beginContentHash(purpose: String) -> OSSignpostIntervalState {
        signing.beginInterval(
            "TAPVideoContentHash",
            "purpose=\(purpose, privacy: .public)"
        )
    }

    static func endContentHash(
        _ state: OSSignpostIntervalState,
        purpose: String,
        succeeded: Bool
    ) {
        signing.endInterval(
            "TAPVideoContentHash",
            state,
            "purpose=\(purpose, privacy: .public) succeeded=\(succeeded, privacy: .public)"
        )
    }

    static func beginProofGeneration() -> OSSignpostIntervalState {
        signing.beginInterval("TAPVideoProofGeneration")
    }

    static func emitAssertionFinished(succeeded: Bool) {
        signing.emitEvent(
            "TAPVideoAssertionFinished",
            "succeeded=\(succeeded, privacy: .public)"
        )
    }

    static func endProofGeneration(
        _ state: OSSignpostIntervalState,
        succeeded: Bool
    ) {
        signing.endInterval(
            "TAPVideoProofGeneration",
            state,
            "succeeded=\(succeeded, privacy: .public)"
        )
    }

    static func emitProofWritten(byteCount: Int) {
        signing.emitEvent(
            "TAPVideoProofWritten",
            "proofBytes=\(byteCount, privacy: .public)"
        )
    }

    static func beginLocalValidation(
        purpose: String,
        validatesDepthTrack: Bool
    ) -> OSSignpostIntervalState {
        signing.beginInterval(
            "TAPVideoLocalValidation",
            "purpose=\(purpose, privacy: .public) validatesDepthTrack=\(validatesDepthTrack, privacy: .public)"
        )
    }

    static func endLocalValidation(
        _ state: OSSignpostIntervalState,
        purpose: String,
        validatesDepthTrack: Bool,
        succeeded: Bool
    ) {
        signing.endInterval(
            "TAPVideoLocalValidation",
            state,
            "purpose=\(purpose, privacy: .public) validatesDepthTrack=\(validatesDepthTrack, privacy: .public) succeeded=\(succeeded, privacy: .public)"
        )
    }

    // MARK: - Cleanup

    static func beginPendingCleanup() -> OSSignpostIntervalState {
        storage.beginInterval("TAPVideoPendingCleanup")
    }

    static func endPendingCleanup(
        _ state: OSSignpostIntervalState,
        succeeded: Bool
    ) {
        storage.endInterval(
            "TAPVideoPendingCleanup",
            state,
            "succeeded=\(succeeded, privacy: .public)"
        )
        storage.emitEvent(
            "TAPVideoPendingCleanupFinished",
            "succeeded=\(succeeded, privacy: .public)"
        )
    }

    // MARK: - Machine-readable runtime checkpoints

    /// Emits stable scalar fields that can be exported from Instruments.
    ///
    /// These process-local readings are correlation checkpoints. VM Tracker is
    /// still the release authority for RSS/dirty-memory evidence, and memgraph
    /// ownership paths remain the authority for object lifetime and leaks.
    static func emitRuntimeCheckpoint(
        stage: String,
        rgbFrames: Int = -1,
        videoDrops: Int = -1,
        audioSamples: Int = -1,
        audioDrops: Int = -1,
        depthDelivered: Int = -1,
        depthStored: Int = -1,
        depthOutputDrops: Int = -1,
        depthMetadataDrops: Int = -1,
        depthEncodingDrops: Int = -1
    ) {
        guard evidence.isEnabled else { return }
        let memory = processMemorySnapshot()
        let residentBytes = memory?.residentBytes ?? 0
        let physicalFootprintBytes = memory?.physicalFootprintBytes ?? 0
        let memoryAvailable = memory != nil
        let thermalState = thermalStateDescription(ProcessInfo.processInfo.thermalState)
        evidence.emitEvent(
            "TAPVideoRuntimeCheckpoint",
            "stage=\(stage, privacy: .public) rssBytes=\(residentBytes, privacy: .public) physicalFootprintBytes=\(physicalFootprintBytes, privacy: .public) memoryAvailable=\(memoryAvailable, privacy: .public) thermal=\(thermalState, privacy: .public) rgbFrames=\(rgbFrames, privacy: .public) videoDrops=\(videoDrops, privacy: .public) audioSamples=\(audioSamples, privacy: .public) audioDrops=\(audioDrops, privacy: .public) depthDelivered=\(depthDelivered, privacy: .public) depthStored=\(depthStored, privacy: .public) depthOutputDrops=\(depthOutputDrops, privacy: .public) depthMetadataDrops=\(depthMetadataDrops, privacy: .public) depthEncodingDrops=\(depthEncodingDrops, privacy: .public)"
        )
    }

    static func beginPhotosExport() -> OSSignpostIntervalState {
        photos.beginInterval("TAPVideoPhotosExport")
    }

    static func endPhotosExport(_ state: OSSignpostIntervalState, succeeded: Bool) {
        photos.endInterval(
            "TAPVideoPhotosExport",
            state,
            "succeeded=\(succeeded, privacy: .public)"
        )
        emitRuntimeCheckpoint(stage: succeeded ? "photos-export-finished" : "photos-export-failed")
    }

    static func beginPhotosReadback() -> OSSignpostIntervalState {
        photos.beginInterval("TAPVideoPhotosReadbackValidation")
    }

    static func endPhotosReadback(_ state: OSSignpostIntervalState, succeeded: Bool) {
        photos.endInterval(
            "TAPVideoPhotosReadbackValidation",
            state,
            "succeeded=\(succeeded, privacy: .public)"
        )
        emitRuntimeCheckpoint(stage: succeeded ? "photos-readback-finished" : "photos-readback-failed")
    }

    static func beginPlayerOpen(source: String) -> OSSignpostIntervalState {
        playback.beginInterval(
            "TAPVideoPlayerOpen",
            "source=\(source, privacy: .public)"
        )
    }

    static func endPlayerOpen(_ state: OSSignpostIntervalState, succeeded: Bool) {
        playback.endInterval(
            "TAPVideoPlayerOpen",
            state,
            "succeeded=\(succeeded, privacy: .public)"
        )
    }

    static func beginTwoDReadiness() -> OSSignpostIntervalState {
        playback.beginInterval("TAPVideoTwoDReadiness")
    }

    static func endTwoDReadiness(
        _ state: OSSignpostIntervalState,
        outcome: String
    ) {
        playback.endInterval(
            "TAPVideoTwoDReadiness",
            state,
            "outcome=\(outcome, privacy: .public)"
        )
    }

    static func beginDepthDecode(frameIndex: Int) -> OSSignpostIntervalState {
        playback.beginInterval(
            "TAPVideoDepthDecode",
            "frameIndex=\(frameIndex, privacy: .public)"
        )
    }

    static func endDepthDecode(
        _ state: OSSignpostIntervalState,
        succeeded: Bool,
        outputByteCount: Int
    ) {
        playback.endInterval(
            "TAPVideoDepthDecode",
            state,
            "succeeded=\(succeeded, privacy: .public) outputBytes=\(outputByteCount, privacy: .public)"
        )
    }

    private struct ProcessMemorySnapshot {
        let residentBytes: UInt64
        let physicalFootprintBytes: UInt64
    }

    private static func processMemorySnapshot() -> ProcessMemorySnapshot? {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size
        )
        let status = withUnsafeMutablePointer(to: &info) { infoPointer in
            infoPointer.withMemoryRebound(
                to: integer_t.self,
                capacity: Int(count)
            ) { reboundPointer in
                task_info(
                    mach_task_self_,
                    task_flavor_t(TASK_VM_INFO),
                    reboundPointer,
                    &count
                )
            }
        }
        guard status == KERN_SUCCESS else {
            return nil
        }
        return ProcessMemorySnapshot(
            residentBytes: UInt64(info.resident_size),
            physicalFootprintBytes: UInt64(info.phys_footprint)
        )
    }

    private static func thermalStateDescription(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal:
            "nominal"
        case .fair:
            "fair"
        case .serious:
            "serious"
        case .critical:
            "critical"
        @unknown default:
            "unknown"
        }
    }
}
