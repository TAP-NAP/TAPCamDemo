//
//  DepthAnalysisMetadataHUD.swift
//  TAPCamDemo
//
//  Created by Codex on 2026/6/11.
//

import Foundation

struct CaptureMetadataSummary: Equatable {
    let title: String
    let detail: String
    let accessibilityText: String

    init?(payload: TAPDepthManifest.Payload?) {
        guard let payload else {
            return nil
        }

        let focalLabel = Self.safeDisplayText(
            payload.photoLens.requestedFocalLengthLabel,
            fallback: "Lens"
        )
        let captureDevice = Self.captureDeviceText(payload)
        let rgbSource = Self.safeDisplayText(
            payload.rgbSource.displayName,
            fallback: "RGB source"
        )
        let depthSource = Self.depthSourceText(payload)
        let depthMethod = Self.depthMethodText(payload.depth.source)
        let zoom = Self.zoomText(payload)

        self.title = "\(focalLabel) · \(captureDevice)"
        self.detail = [
            "RGB \(rgbSource)",
            "Depth \(depthSource)",
            depthMethod,
            "Zoom \(zoom)"
        ].joined(separator: " · ")
        self.accessibilityText = "\(title). \(detail)."
    }

    private static func captureDeviceText(_ payload: TAPDepthManifest.Payload) -> String {
        let resolvedDevice = Self.safeDisplayText(
            payload.photoLens.resolvedCaptureDeviceName,
            fallback: "Camera"
        )
        guard let rawActiveDevice = payload.photoLens.resolvedActivePrimaryConstituentDeviceName else {
            return resolvedDevice
        }

        let activeDevice = Self.safeDisplayText(rawActiveDevice, fallback: "Camera")
        guard activeDevice != resolvedDevice else {
            return resolvedDevice
        }
        return "\(resolvedDevice) / \(activeDevice)"
    }

    private static func depthSourceText(_ payload: TAPDepthManifest.Payload) -> String {
        let rawSelectedDepth = payload.selectedDepthCamera.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let selectedDepth = Self.safeDisplayText(rawSelectedDepth, fallback: "Depth source")
        if selectedDepth != "None" {
            return selectedDepth
        }

        return Self.safeDisplayText(
            payload.depth.source.captureDeviceName,
            fallback: "Depth source"
        )
    }

    private static func depthMethodText(_ source: TAPDepthManifest.DepthSource) -> String {
        let method: String
        switch source.sensingMethod {
        case "lidarDepthCamera":
            method = "LiDAR"
        case "trueDepthCamera":
            method = "TrueDepth"
        case "multiCameraStereoOrComputational":
            method = "stereo/computational"
        case "singleCameraComputationalOrUnknown":
            method = "single/computational"
        default:
            method = Self.safeDisplayText(source.sensingMethod, fallback: "Depth method")
        }

        switch source.lidarParticipation {
        case "explicit":
            return "\(method) · LiDAR explicit"
        case "notAsserted":
            return "\(method) · LiDAR not asserted"
        default:
            return method
        }
    }

    private static func zoomText(_ payload: TAPDepthManifest.Payload) -> String {
        let zoom = payload.zoom.actualVideoZoomFactor
            ?? payload.zoom.requestedZoomFactor
            ?? payload.selectedZoom.zoomFactor
        return String(format: "%.2fx", zoom)
    }

    private static func safeDisplayText(_ value: String?, fallback: String) -> String {
        guard let value else {
            return fallback
        }

        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedValue.isEmpty,
              !containsSensitiveDisplayFragment(trimmedValue) else {
            return fallback
        }

        return trimmedValue
    }

    private static func containsSensitiveDisplayFragment(_ value: String) -> Bool {
        let lowercasedValue = value.lowercased()
        if lowercasedValue.hasPrefix("/") || lowercasedValue.hasPrefix("~") {
            return true
        }

        // Keep this list focused on identifiers, proofs, URLs, and file paths.
        // Hardware names such as "TrueDepth" and "LiDAR" must remain displayable.
        let sensitiveFragments = [
            "file://",
            "http://",
            "https://",
            "photos://",
            "/private/",
            "/tmp/",
            "/users/",
            "/var/",
            "\\",
            ".heic",
            ".json",
            "captureid",
            "capture id",
            "capture-id",
            "manifestid",
            "manifest id",
            "manifest-id",
            "assetid",
            "asset id",
            "asset-id",
            "keyid",
            "key id",
            "key-id",
            "credential",
            "appattest",
            "app attest",
            "proof",
            "assertion",
            "token="
        ]

        return sensitiveFragments.contains { lowercasedValue.contains($0) }
    }
}

#if DEBUG

import SwiftUI

struct CaptureMetadataHUD: View {
    let summary: CaptureMetadataSummary

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "camera.aperture")
                .font(.caption.weight(.bold))
                .foregroundStyle(.primary)
                .frame(width: 18, height: 18)

            VStack(alignment: .leading, spacing: 3) {
                Text(summary.title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                Text(summary.detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: 560, alignment: .leading)
        .background(AnalysisDebugHighlight.restingBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(.white.opacity(0.16), lineWidth: 1)
        }
        .accessibilityLabel(summary.accessibilityText)
    }
}

#endif
