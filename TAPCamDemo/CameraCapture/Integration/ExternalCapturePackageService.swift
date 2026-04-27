//
//  ExternalCapturePackageService.swift
//  TAPCamDemo
//
//  Created by Codex on 2026/4/27.
//

import Foundation

/// Payload entry point for apps that already own their camera session.
///
/// External callers can hand completed RGB/depth/metadata data to the TAP
/// packaging architecture without adopting `CameraView` or
/// `CaptureSessionController`. v0.8 defines the safe boundary and release
/// policy; full external HEIC construction is intentionally left for a later
/// slice because it needs format-specific RGB/depth calibration validation.
nonisolated struct ExternalCapturePayload: Sendable {
    let rgbData: Data
    let rawData: Data?
    let depthData: Data?
    let metadata: [String: String]
    let rgbCameraInfo: ExternalCameraInfo
    let depthCameraInfo: ExternalCameraInfo?
    let zoomFactor: Double?
    let cropRectNormalized: CropRectNormalized
    let timestamp: Date
}

/// Device metadata supplied by an external capture pipeline.
nonisolated struct ExternalCameraInfo: Codable, Equatable, Sendable {
    let id: String
    let displayName: String
    let deviceType: String?
    let position: String?
}

/// Converts external payloads into the app's packaging pipeline.
///
/// The current implementation enforces policy and exposes the integration
/// surface. It deliberately does not fabricate Apple auxiliary depth for
/// arbitrary external bytes; future work must validate RGB/depth alignment and
/// calibration before creating a release artifact.
nonisolated struct ExternalCapturePackageService: Sendable {
    func processExternalCapture(
        _ payload: ExternalCapturePayload,
        packagingStrategy: PackagingStrategy,
        hooks: [any ArtifactProcessingHook] = []
    ) async throws -> CaptureWriteResult {
        try ReleasePackagingPolicy.validate(packagingStrategy)
        _ = payload
        _ = hooks
        throw TAPDepthCaptureError.externalPayloadPackagingNotImplemented
    }
}

/// Adapter placeholder for external session callbacks.
///
/// The type exists so documentation and clients have a concrete place to bind
/// existing camera callbacks later. It must not mutate the managed session
/// graph; it only normalizes external data into `ExternalCapturePayload`.
nonisolated struct ExternalOutputAdapter: Sendable {
    func makePayload(
        rgbData: Data,
        depthData: Data?,
        rgbCameraInfo: ExternalCameraInfo,
        depthCameraInfo: ExternalCameraInfo?,
        zoomFactor: Double?,
        cropRectNormalized: CropRectNormalized,
        timestamp: Date
    ) -> ExternalCapturePayload {
        ExternalCapturePayload(
            rgbData: rgbData,
            rawData: nil,
            depthData: depthData,
            metadata: [:],
            rgbCameraInfo: rgbCameraInfo,
            depthCameraInfo: depthCameraInfo,
            zoomFactor: zoomFactor,
            cropRectNormalized: cropRectNormalized,
            timestamp: timestamp
        )
    }
}
