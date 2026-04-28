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
    let validMask: TAPDepthMaskVisualization
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

nonisolated struct TAPDepthLegendStop: Equatable, Identifiable {
    let position: Double
    let label: String
    let color: TAPRGBAColor

    var id: String {
        "\(position)-\(label)"
    }
}

nonisolated enum TAPDepthHeatmapRangeScope: Equatable {
    case global
    case region
}

nonisolated struct TAPDepthHeatmapVisualization {
    let image: CGImage
    let rangeMeters: ClosedRange<Float>
    let legendStops: [TAPDepthLegendStop]
    let rangeScope: TAPDepthHeatmapRangeScope
}

nonisolated struct TAPDepthMaskVisualization {
    let image: CGImage
    let validSampleCount: Int
    let totalSampleCount: Int
    let validRatio: Double
    let legendStops: [TAPDepthLegendStop]
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

enum AnalysisPanelDestination: Equatable {
    case inspector(AnalysisInspector)
    case help

    var selectedInspector: AnalysisInspector? {
        guard case .inspector(let inspector) = self else {
            return nil
        }
        return inspector
    }
}

enum AnalysisInspector: String, CaseIterable, Identifiable, Equatable {
    case measurements
    case legend
    case overlay
    case region
    case planeFilter
    case cloudInfo

    var id: String { rawValue }

    var title: String {
        switch self {
        case .measurements:
            "Measurements"
        case .legend:
            "Legend"
        case .overlay:
            "Overlay"
        case .region:
            "Region"
        case .planeFilter:
            "Plane Filter"
        case .cloudInfo:
            "Cloud Info"
        }
    }

    var systemImage: String {
        switch self {
        case .measurements:
            "chart.bar.xaxis"
        case .legend:
            "paintpalette"
        case .overlay:
            "slider.horizontal.3"
        case .region:
            "viewfinder"
        case .planeFilter:
            "square.3.layers.3d"
        case .cloudInfo:
            "point.3.connected.trianglepath.dotted"
        }
    }
}

enum AnalysisInteractionState: Equatable {
    case idle
    case drawingSelection
    case regionSelected

    var showsRegionInspector: Bool {
        self == .regionSelected
    }
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
