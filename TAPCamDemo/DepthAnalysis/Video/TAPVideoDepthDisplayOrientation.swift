//
//  TAPVideoDepthDisplayOrientation.swift
//  TAPCamDemo
//

import CoreGraphics
import ImageIO

nonisolated enum TAPVideoDepthDisplayOrientation {
    static func cgImageOrientation(from transform: String?) -> CGImagePropertyOrientation {
        guard let transform,
              transform != "identity" else {
            return .up
        }

        let components = transform.split(separator: ";").map(String.init)
        let isMirrored = components.contains("mirrored")
        let rotation = components
            .first { $0.hasPrefix("rotation:") }
            .flatMap { Double($0.dropFirst("rotation:".count)) }
            .map { normalizedDegrees($0) } ?? 0

        switch (rotation, isMirrored) {
        case (0, false):
            return .up
        case (90, false):
            return .right
        case (180, false):
            return .down
        case (270, false):
            return .left
        case (0, true):
            return .upMirrored
        case (90, true):
            return .rightMirrored
        case (180, true):
            return .downMirrored
        case (270, true):
            return .leftMirrored
        default:
            return .up
        }
    }

    static func displaySize(width: Int32, height: Int32, transform: String?) -> CGSize? {
        guard width > 0,
              height > 0 else {
            return nil
        }
        let rotation = rotationDegrees(from: transform)
        let isSideways = rotation == 90 || rotation == 270
        return isSideways
            ? CGSize(width: CGFloat(height), height: CGFloat(width))
            : CGSize(width: CGFloat(width), height: CGFloat(height))
    }

    private static func normalizedDegrees(_ degrees: Double) -> Int {
        let rounded = Int(degrees.rounded())
        return ((rounded % 360) + 360) % 360
    }

    private static func rotationDegrees(from transform: String?) -> Int {
        guard let transform else {
            return 0
        }
        return transform.split(separator: ";")
            .map(String.init)
            .first { $0.hasPrefix("rotation:") }
            .flatMap { Double($0.dropFirst("rotation:".count)) }
            .map { normalizedDegrees($0) } ?? 0
    }
}
