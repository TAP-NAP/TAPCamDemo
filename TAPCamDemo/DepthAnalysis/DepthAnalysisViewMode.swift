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

    var isDebugOnlyAnalysisButton: Bool {
        self == .heatmap || self == .mask
    }

    var inspectors: [AnalysisInspector] {
        switch self {
        case .rgb:
            [.measurements, .region]
        case .heatmap:
            [.measurements, .legend, .overlay, .region]
        case .mask:
            [.measurements, .legend, .region]
        case .planes:
            [.planeFilter, .legend, .overlay]
        case .pointCloud:
            [.cloudInfo, .measurements, .region]
        }
    }

    var title: String {
        switch self {
        case .rgb:
            "RGB"
        case .heatmap:
            "Depth"
        case .mask:
            "Mask"
        case .planes:
            "Planes"
        case .pointCloud:
            "Cloud"
        }
    }

    var systemImage: String {
        switch self {
        case .rgb:
            "photo"
        case .heatmap:
            "ruler"
        case .mask:
            "checkerboard.rectangle"
        case .planes:
            "square.3.layers.3d"
        case .pointCloud:
            "point.3.connected.trianglepath.dotted"
        }
    }

    var shortExplanation: String {
        switch self {
        case .rgb:
            "The original color photo stored in the TAP depth HEIC."
        case .heatmap:
            "A false-color overlay where color represents metric depth in meters."
        case .mask:
            "A coverage overlay showing which pixels have usable depth samples."
        case .planes:
            "Tap a surface point to grow and grid the connected camera-coordinate plane."
        case .pointCloud:
            "A local camera-coordinate point cloud preview made from valid depth pixels."
        }
    }

    var detailedExplanation: String {
        switch self {
        case .rgb:
            "RGB view shows the primary HEIC image. It is the visual reference used to choose regions, but the depth measurements still come from the auxiliary depth map embedded beside it."
        case .heatmap:
            "Depth view overlays metric depth as a false-color heatmap. Near pixels use the low end of the legend and far pixels use the high end. Transparent pixels do not contain valid depth."
        case .mask:
            "Mask view highlights the pixels that contain finite positive depth samples. Green areas can contribute to statistics, plane fitting, and point projection; transparent areas are ignored."
        case .planes:
            "Planes view grows a connected plane from the surface point you tap, then divides that region into fit-confidence grid cells. Rectangular Region selection is disabled here so the view stays focused on plane analysis."
        case .pointCloud:
            "Cloud view projects valid depth pixels through camera intrinsics into a lightweight camera-coordinate point preview. It is a point cloud, not cloud storage, cloud compute, or a semantic word cloud."
        }
    }

    var legendDescription: String {
        switch self {
        case .rgb:
            "RGB has no color legend because it shows the original photo."
        case .heatmap:
            "The legend maps the current depth range from near to far. Adjust opacity to compare the heatmap against the RGB image."
        case .mask:
            "Green indicates valid depth coverage. Yellow outlines mark transitions between valid and invalid depth."
        case .planes:
            "Plane cells use stronger green for better local plane fit and warmer color for weaker fit; the bright edge marks the grown boundary."
        case .pointCloud:
            "Point colors map near-to-far depth in the same direction as the depth legend."
        }
    }
}
