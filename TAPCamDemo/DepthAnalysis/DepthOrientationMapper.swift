//
//  DepthOrientationMapper.swift
//  TAPCamDemo
//
//  Created by Codex on 2026/4/27.
//

import CoreGraphics
import ImageIO
import SwiftUI

/// Maps rectangles between the orientation-corrected display plane and the
/// native pixel plane stored in the HEIC. ImageIO returns the primary `CGImage`
/// pixels without applying EXIF orientation, while SwiftUI displays them with an
/// orientation transform. Selection rectangles therefore need the inverse
/// transform before sampling the depth map.
nonisolated enum TAPImageOrientationMapper {
    static func displayedSize(nativeSize: CGSize, orientation: CGImagePropertyOrientation) -> CGSize {
        orientation.rotatesDimensions
            ? CGSize(width: nativeSize.height, height: nativeSize.width)
            : nativeSize
    }

    static func nativeRect(fromDisplayed rect: CGRect, nativeSize: CGSize, orientation: CGImagePropertyOrientation) -> CGRect {
        switch orientation {
        case .up:
            return rect
        case .upMirrored:
            return CGRect(x: nativeSize.width - rect.maxX, y: rect.minY, width: rect.width, height: rect.height)
        case .down:
            return CGRect(x: nativeSize.width - rect.maxX, y: nativeSize.height - rect.maxY, width: rect.width, height: rect.height)
        case .downMirrored:
            return CGRect(x: rect.minX, y: nativeSize.height - rect.maxY, width: rect.width, height: rect.height)
        case .right:
            return CGRect(x: rect.minY, y: nativeSize.height - rect.maxX, width: rect.height, height: rect.width)
        case .rightMirrored:
            return CGRect(x: rect.minY, y: rect.minX, width: rect.height, height: rect.width)
        case .left:
            return CGRect(x: nativeSize.width - rect.maxY, y: rect.minX, width: rect.height, height: rect.width)
        case .leftMirrored:
            return CGRect(x: nativeSize.width - rect.maxY, y: nativeSize.height - rect.maxX, width: rect.height, height: rect.width)
        }
    }

    static func displayedRect(fromNative rect: CGRect, nativeSize: CGSize, orientation: CGImagePropertyOrientation) -> CGRect {
        switch orientation {
        case .up:
            return rect
        case .upMirrored:
            return CGRect(x: nativeSize.width - rect.maxX, y: rect.minY, width: rect.width, height: rect.height)
        case .down:
            return CGRect(x: nativeSize.width - rect.maxX, y: nativeSize.height - rect.maxY, width: rect.width, height: rect.height)
        case .downMirrored:
            return CGRect(x: rect.minX, y: nativeSize.height - rect.maxY, width: rect.width, height: rect.height)
        case .right:
            return CGRect(x: nativeSize.height - rect.maxY, y: rect.minX, width: rect.height, height: rect.width)
        case .rightMirrored:
            return CGRect(x: rect.minY, y: rect.minX, width: rect.height, height: rect.width)
        case .left:
            return CGRect(x: rect.minY, y: nativeSize.width - rect.maxX, width: rect.height, height: rect.width)
        case .leftMirrored:
            return CGRect(x: nativeSize.height - rect.maxY, y: nativeSize.width - rect.maxX, width: rect.height, height: rect.width)
        }
    }
}

extension CGImagePropertyOrientation {
    nonisolated var rotatesDimensions: Bool {
        switch self {
        case .left, .leftMirrored, .right, .rightMirrored:
            true
        default:
            false
        }
    }

    var swiftUIImageOrientation: Image.Orientation {
        switch self {
        case .up:
            .up
        case .upMirrored:
            .upMirrored
        case .down:
            .down
        case .downMirrored:
            .downMirrored
        case .left:
            .left
        case .leftMirrored:
            .leftMirrored
        case .right:
            .right
        case .rightMirrored:
            .rightMirrored
        }
    }
}
