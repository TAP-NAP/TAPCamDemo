//
//  CropRectNormalized.swift
//  TAPCamDemo
//
//  Created by Codex on 2026/4/27.
//

@preconcurrency import AVFoundation
import CoreGraphics
import CoreMedia
import Darwin
import Foundation

/// Normalized metadata rectangle describing what the preview showed.
///
/// Values are in the metadata-output coordinate space used by
/// `AVCaptureVideoPreviewLayer.metadataOutputRectConverted(fromLayerRect:)`.
/// Release records this only as metadata; it does not destructively crop
/// the RGB image or the depth map.
nonisolated struct CropRectNormalized: Codable, Equatable, Sendable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double

    static let fullFrame = CropRectNormalized(x: 0, y: 0, width: 1, height: 1)

    init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    init(metadataRect rect: CGRect) {
        let standardized = rect.standardized
        self.x = Double(min(max(standardized.origin.x, 0), 1))
        self.y = Double(min(max(standardized.origin.y, 0), 1))
        self.width = Double(min(max(standardized.width, 0), 1))
        self.height = Double(min(max(standardized.height, 0), 1))
    }
}
