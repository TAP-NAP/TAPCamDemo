//
//  TAPVideoRegistrationProjection.swift
//  TAPCamDemo
//

import CoreGraphics
import Foundation

/// A validated, renderer-reproducible projection. Coordinates are pixel-center
/// coordinates with a top-left origin, matching AVDepthData and clean aperture
/// metadata. The production adapter is the sole constructor from a manifest.
nonisolated struct TAPVideoRegistrationProjection: Equatable, Sendable {
    let depthWidth: Int
    let depthHeight: Int
    let alignedRGBWidth: Int
    let alignedRGBHeight: Int
    let encodedRGBWidth: Int
    let encodedRGBHeight: Int
    let depthToAlignedRGBPixelCenterAffine: [Double]
    let connectionRotationDegrees: Int
    let isEncodedHorizontallyMirrored: Bool
    let rgbCleanAperture: TAPVideoRegistrationRect

    func projectDepthPixelCenter(x: Double, y: Double) -> CGPoint? {
        guard x.isFinite,
              y.isFinite,
              depthToAlignedRGBPixelCenterAffine.count == 6 else {
            return nil
        }
        let affine = depthToAlignedRGBPixelCenterAffine
        let alignedX = affine[0] * x + affine[1] * y + affine[2]
        let alignedY = affine[3] * x + affine[4] * y + affine[5]
        guard let rotatedPoint = rotatedPoint(
            alignedX: alignedX,
            alignedY: alignedY
        ) else {
            return nil
        }
        let encodedPoint = isEncodedHorizontallyMirrored
            ? CGPoint(
                x: Double(encodedRGBWidth - 1) - rotatedPoint.x,
                y: rotatedPoint.y
            )
            : rotatedPoint
        return CGPoint(
            x: encodedPoint.x - rgbCleanAperture.x,
            y: encodedPoint.y - rgbCleanAperture.y
        )
    }

    private func rotatedPoint(
        alignedX: Double,
        alignedY: Double
    ) -> CGPoint? {
        switch connectionRotationDegrees {
        case 0:
            return CGPoint(x: alignedX, y: alignedY)
        case 90:
            return CGPoint(
                x: Double(alignedRGBHeight - 1) - alignedY,
                y: alignedX
            )
        case 180:
            return CGPoint(
                x: Double(alignedRGBWidth - 1) - alignedX,
                y: Double(alignedRGBHeight - 1) - alignedY
            )
        case 270:
            return CGPoint(
                x: alignedY,
                y: Double(alignedRGBWidth - 1) - alignedX
            )
        default:
            return nil
        }
    }
}
