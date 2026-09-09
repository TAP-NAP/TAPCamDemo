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
/// image, XMP manifest, and calibration are kept beside it so downstream inspectors
/// do not need to reach back into Photos or ImageIO.
nonisolated struct TAPDepthAnalysisInput {
    let manifest: TAPDepthManifest?
    let image: CGImage
    let imageOrientation: CGImagePropertyOrientation
    let depthMap: TAPMetricDepthMap
    let depthAccuracy: String
    let depthQuality: String
    let heatmap: TAPDepthHeatmapVisualization
}

nonisolated struct TAPRGBAColor: Equatable {
    let red: UInt8
    let green: UInt8
    let blue: UInt8
    let alpha: UInt8

    var bytes: [UInt8] {
        [red, green, blue, alpha]
    }
}

nonisolated struct TAPDepthHeatmapVisualization {
    let image: CGImage
    let rangeMeters: ClosedRange<Float>
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
        guard let sampleIndex = TAPDepthAnalysisInputValidation.sampleIndex(
            depthMap: self,
            x: x,
            y: y
        ) else {
            return nil
        }

        let value = samples[sampleIndex]
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

nonisolated struct TAPDetectedPlane: Equatable, Identifiable {
    let id: String
    let estimate: TAPPlaneEstimate
    let confidence: Double
    let sampleCount: Int

    var imageBounds: CGRect {
        estimate.imageBounds
    }
}

nonisolated struct TAPPlanePixelRun: Equatable, Identifiable {
    let y: Int
    let xStart: Int
    let xEndExclusive: Int

    var id: String {
        "\(y)-\(xStart)-\(xEndExclusive)"
    }

    var width: Int {
        max(xEndExclusive - xStart, 0)
    }
}

nonisolated struct TAPPlaneGridCell: Equatable, Identifiable {
    let row: Int
    let column: Int
    let imageBounds: CGRect
    let coverage: Double
    let averageResidualMeters: Float
    let confidence: Double
    let sampleCount: Int

    var id: String {
        "\(row)-\(column)"
    }
}

nonisolated struct TAPPlaneRegion: Equatable {
    let seedPixel: CGPoint
    let estimate: TAPPlaneEstimate
    let pixelRuns: [TAPPlanePixelRun]
    let gridCells: [TAPPlaneGridCell]
    let contourPoints: [CGPoint]
    let imageBounds: CGRect
    let confidence: Double
    let flatnessScore: Double
    let sampleCount: Int
    let areaSquareMeters: Double
}

nonisolated struct TAPPlaneGridProgress: Equatable {
    let seedPixel: CGPoint
    let gridCells: [TAPPlaneGridCell]
    let progress: Double
}

nonisolated struct TAPPlaneGrowthParameters: Equatable {
    let strictness: Double
    let residualThresholdMeters: Float
    let normalAngleThresholdDegrees: Float
    let seedWindowRadiusPixels: Int
    let minimumSeedSamples: Int
    let minimumRegionSamples: Int
    let maximumVisitedPixels: Int

    init(strictness: Double) {
        let clamped = min(max(strictness, 0.35), 0.95)
        let normalized = (clamped - 0.35) / 0.60
        self.strictness = clamped
        self.residualThresholdMeters = Float(0.060 - normalized * 0.040)
        self.normalAngleThresholdDegrees = Float(30.0 - normalized * 18.0)
        self.seedWindowRadiusPixels = 5
        self.minimumSeedSamples = 12
        self.minimumRegionSamples = 24
        self.maximumVisitedPixels = 180_000
    }
}

enum TAPPlaneGrowthError: LocalizedError, Equatable {
    case invalidSeed
    case cameraCalibrationMissing
    case notEnoughNearbySamples
    case noPlaneRegion

    var errorDescription: String? {
        switch self {
        case .invalidSeed:
            "No valid depth at this point."
        case .cameraCalibrationMissing:
            "Camera calibration missing."
        case .notEnoughNearbySamples:
            "Not enough nearby depth samples."
        case .noPlaneRegion:
            "No stable plane region found from this point."
        }
    }
}

enum TAPDepthAnalysisError: LocalizedError {
    case missingPrimaryImage
    case missingDepthData
    case unreadableDepthMap
    case invalidDepthMap
    case analysisInputTooLarge
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
        case .invalidDepthMap:
            "The depth map could not be analyzed."
        case .analysisInputTooLarge:
            "The selected image is too large to analyze."
        case .noValidDepthSamples:
            "The depth map does not contain valid metric depth samples."
        case .imageRenderFailed:
            "Unable to render the depth visualization."
        case .assetNotFound:
            "The selected Photos asset could not be found."
        }
    }
}
