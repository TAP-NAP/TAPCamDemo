//
//  DepthPointCloudPreview.swift
//  TAPCamDemo
//
//  Created by Codex on 2026/4/27.
//

import SwiftUI

/// Lightweight SwiftUI preview for camera-coordinate depth points.
///
/// The point cloud preview depends on the same projection math as plane
/// fitting, but it stays a visualization tool: it does not create a mesh,
/// stabilize points in world coordinates, or infer hidden geometry.
struct PointCloudPreview: View {
    let depthMap: TAPMetricDepthMap

    var body: some View {
        Canvas { context, size in
            // Cloud preview principle:
            // `TAPDepthGeometryProjector` samples the metric depth map and uses
            // camera calibration intrinsics to create local camera-space points.
            // This Canvas draws a compact 2D preview of those points with a
            // small parallax offset and hue based on depth. It is deliberately
            // native SwiftUI/CoreGraphics UI for v1; a richer interactive cloud
            // can later move to Metal or SceneKit.
            //
            // Dependencies:
            // - `TAPMetricDepthMap.samples` for meter depth values.
            // - `TAPDepthManifest.CameraCalibration` for projection.
            // - SwiftUI `Canvas` for lightweight rendering.
            //
            // References:
            // - https://developer.apple.com/documentation/swiftui/canvas
            // - https://developer.apple.com/documentation/arkit/displaying-a-point-cloud-using-scene-depth
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black))
            let region = CGRect(x: 0, y: 0, width: depthMap.width, height: depthMap.height)
            let samples = TAPDepthGeometryProjector.sampledPoints(from: depthMap, in: region, maxCount: 2_000)
            guard !samples.isEmpty else {
                return
            }

            let zValues = samples.map(\.point.z)
            let minZ = zValues.min() ?? 0
            let maxZ = zValues.max() ?? minZ + 1
            let zRange = max(maxZ - minZ, 0.001)

            for sample in samples {
                let px = sample.imagePoint.x / CGFloat(depthMap.width)
                let py = sample.imagePoint.y / CGFloat(depthMap.height)
                let normalizedZ = CGFloat((sample.point.z - minZ) / zRange)
                let x = px * size.width + (0.5 - normalizedZ) * 80
                let y = py * size.height - (0.5 - normalizedZ) * 42
                let color = Color(hue: 0.62 - Double(normalizedZ) * 0.62, saturation: 0.82, brightness: 1.0)
                context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 2, height: 2)), with: .color(color))
            }
        }
        .aspectRatio(CGSize(width: depthMap.width, height: depthMap.height), contentMode: .fit)
        .background(Color.black)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(alignment: .bottomLeading) {
            Text("Camera-coordinate preview")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.82))
                .padding(8)
        }
    }
}
