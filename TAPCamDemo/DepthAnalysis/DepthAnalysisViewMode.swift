//
//  DepthAnalysisViewMode.swift
//  TAPCamDemo
//
//  Created by Codex on 2026/6/11.
//

enum DepthAnalysisViewMode: String, CaseIterable, Identifiable {
    /// Normal color image. Source: ImageIO primary HEIC image item.
    case rgb

    /// False-color depth image. Source: Apple auxiliary depth/disparity rebuilt
    /// as `AVDepthData`, converted to Float32 metric depth, then colorized.
    case heatmap

    /// Valid-depth coverage image. Source: the same metric depth map; finite
    /// positive samples are colored, missing/invalid samples are transparent.
    case mask

    /// Region plane analysis. Source: selected metric depth samples plus
    /// `AVCameraCalibrationData` intrinsics from the TAP manifest.
    case planes

    /// Lightweight camera-coordinate point preview. Source: metric depth samples
    /// projected with camera intrinsics; this is not a world-space AR mesh.
    case pointCloud

    var id: String { rawValue }

}
