//
//  DepthAnalysisModels.swift
//  TAPCamDemo
//
//  Created by Codex on 2026/4/27.
//

import CoreGraphics
import Foundation
import ImageIO
import simd

/// Canonical in-memory form used by the analysis module.
///
/// The capture module stores Apple's auxiliary depth/disparity attachment as
/// the source of truth. Analysis starts by converting that attachment into a
/// dense Float32 depth map whose samples are meters from the camera. The RGB
/// image, XMP manifest, and calibration are kept beside it so downstream tools
/// do not need to reach back into Photos or ImageIO.
nonisolated struct TAPDepthAnalysisInput {
    let manifest: TAPDepthManifest?
    let image: CGImage
    let imageOrientation: CGImagePropertyOrientation
    let depthMap: TAPMetricDepthMap
    let heatmap: CGImage
    let validMask: CGImage
}

/// A row-major metric depth map. Invalid, zero, infinite, or NaN samples are
/// preserved in `samples` but ignored by statistics and plane fitting.
nonisolated struct TAPMetricDepthMap: Equatable {
    let width: Int
    let height: Int
    let samples: [Float]
    let calibration: TAPDepthManifest.CameraCalibration?

    func index(x: Int, y: Int) -> Int {
        y * width + x
    }

    func sample(x: Int, y: Int) -> Float? {
        guard x >= 0, y >= 0, x < width, y < height else {
            return nil
        }

        let value = samples[index(x: x, y: y)]
        return value.isFinite && value > 0 ? value : nil
    }
}

nonisolated struct TAPDepthRegionStats: Equatable {
    let validSampleCount: Int
    let totalSampleCount: Int
    let minimumDepthMeters: Float?
    let maximumDepthMeters: Float?
    let medianDepthMeters: Float?
    let validRatio: Double
}

nonisolated struct TAPPoint3D: Equatable {
    let x: Float
    let y: Float
    let z: Float
}

nonisolated struct TAPPlaneEstimate: Equatable {
    let normal: SIMD3<Float>
    let centroid: SIMD3<Float>
    let averageResidualMeters: Float
    let inlierRatio: Double
    let depthRangeMeters: ClosedRange<Float>
    let imageBounds: CGRect
}

enum TAPDepthAnalysisError: LocalizedError {
    case missingPrimaryImage
    case missingDepthData
    case unreadableDepthMap
    case noValidDepthSamples
    case imageRenderFailed
    case assetNotFound

    var errorDescription: String? {
        switch self {
        case .missingPrimaryImage:
            "The selected file does not contain a readable primary image."
        case .missingDepthData:
            "The selected image does not contain Apple auxiliary depth or disparity data."
        case .unreadableDepthMap:
            "The depth pixel buffer could not be read."
        case .noValidDepthSamples:
            "The depth map does not contain valid metric depth samples."
        case .imageRenderFailed:
            "Unable to render the depth visualization."
        case .assetNotFound:
            "The selected Photos asset could not be found."
        }
    }
}
