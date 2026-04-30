//
//  RGBDepthCompatibilityMatrix.swift
//  TAPCamDemo
//
//  Created by Codex on 2026/4/27.
//

@preconcurrency import AVFoundation
import CoreGraphics
import CoreMedia
import Darwin
import Foundation

/// Validates whether an RGB source and a depth row can form a legal SingleCam plan.
///
/// This matrix is deliberately conservative. It only reports `.compatible` for
/// Apple-paired single-pipeline configurations the app can actually run today.
/// Other plausible hardware combinations are surfaced as unsupported states so
/// the UI can grey them and diagnostics can explain the boundary.
nonisolated enum RGBDepthCompatibilityMatrix {
    nonisolated struct Result: @unchecked Sendable {
        let status: RGBDepthCompatibilityStatus
        let reason: String?
        let resolvedDevice: AVCaptureDevice?
        let formatSelection: PhotoDepthFormatSelection?
    }

    /// Checks whether one RGB source can use a depth row in SingleCam.
    ///
    /// Compatibility means the same device or an Apple virtual device containing
    /// the selected RGB source. Other combinations stay unsupported facts.
    ///
    /// - Tag: EvaluateRGBDepthCompatibility
    static func evaluate(
        rgbSource: CameraProfile,
        depthKind: DepthProfileKind,
        candidate: DepthDeviceCandidate?,
        preferredZoomFactor: Double? = nil
    ) -> Result {
        guard let candidate else {
            return Result(
                status: .unavailable,
                reason: "Depth source unavailable",
                resolvedDevice: nil,
                formatSelection: nil
            )
        }

        let formatSelection: PhotoDepthFormatSelection?
        if let preferredZoomFactor {
            formatSelection = CameraCapabilityResolver.bestDepthFormatSelection(
                for: candidate.device,
                preferredZoomFactor: preferredZoomFactor,
                requiresPreferredZoomSupport: true
            )
        } else {
            formatSelection = candidate.formatSelection
        }

        guard let formatSelection else {
            return Result(
                status: .unsupportedFormat,
                reason: "No depth-capable format",
                resolvedDevice: candidate.device,
                formatSelection: nil
            )
        }

        if candidate.device.uniqueID == rgbSource.device.uniqueID || candidate.device.containsConstituent(rgbSource.device) {
            return Result(
                status: .compatible,
                reason: nil,
                resolvedDevice: candidate.device,
                formatSelection: formatSelection
            )
        }

        return Result(
            status: .requiresMultiCam,
            reason: "Requires multiple independent camera inputs",
            resolvedDevice: candidate.device,
            formatSelection: formatSelection
        )
    }
}
