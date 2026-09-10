//
//  TAPVideoViewerChrome.swift
//  TAPCamDemo
//

import SwiftUI

nonisolated enum TAPVideoViewerModePolicy {
    static func effectiveTool(_ selectedTool: AnalysisViewerTool,
                              availability: TAPVideoRegisteredDepthAvailability,
                              isThreeDDepthAvailable: Bool) -> AnalysisViewerTool {
        guard availability != .checking else { return selectedTool }
        switch selectedTool {
        case .twoD where !availability.isAvailable: return .raw
        case .threeD where !isThreeDDepthAvailable: return .raw
        default: return selectedTool
        }
    }

    static func items(
        availability: TAPVideoRegisteredDepthAvailability,
        selectedTool: AnalysisViewerTool,
        isTwoDPlaybackReady: Bool,
        isThreeDDepthAvailable: Bool = false,
        isThreeDPlaybackReady: Bool = false
    ) -> [DepthViewerModeItem] {
        AnalysisViewerTool.allCases.map { tool in
            let accessibilityValue: String?
            switch tool {
            case .raw:
                accessibilityValue = selectedTool == .raw ? "Selected" : nil
            case .twoD:
                switch availability {
                case .checking:
                    accessibilityValue = selectedTool == .twoD ? "Selected, Preparing" : "Preparing registered depth"
                case .available where !availability.isAvailable, .unavailable:
                    accessibilityValue = selectedTool == .twoD ? "Selected, depth unavailable; showing RAW" : "Registered depth unavailable"
                case .available:
                    if selectedTool == .twoD {
                        accessibilityValue = isTwoDPlaybackReady
                            ? "Selected, Ready"
                            : "Selected, Preparing"
                    } else {
                        accessibilityValue = "Available"
                    }
                }
            case .threeD:
                if availability == .checking {
                    accessibilityValue = selectedTool == .threeD ? "Selected, Preparing" : "Preparing 3D"
                } else if !isThreeDDepthAvailable {
                    accessibilityValue = selectedTool == .threeD ? "Selected, depth unavailable; showing RAW" : "3D depth unavailable"
                } else if selectedTool == .threeD {
                    accessibilityValue = isThreeDPlaybackReady
                        ? "Selected, Ready" : "Selected, Preparing"
                } else {
                    accessibilityValue = "Available"
                }
            }
            return DepthViewerModeItem(
                id: tool.rawValue,
                systemImage: tool.systemImage,
                accessibilityLabel: accessibilityLabel(for: tool),
                accessibilityIdentifier: accessibilityIdentifier(for: tool),
                accessibilityValue: accessibilityValue
            )
        }
    }

    private static func accessibilityLabel(
        for tool: AnalysisViewerTool
    ) -> String {
        switch tool {
        case .raw:
            "Raw video"
        case .twoD:
            "2D analysis"
        case .threeD:
            "3D projection"
        }
    }

    private static func accessibilityIdentifier(
        for tool: AnalysisViewerTool
    ) -> String {
        switch tool {
        case .raw:
            "tap.viewer.mode.raw"
        case .twoD:
            "tap.viewer.mode.2d"
        case .threeD:
            "tap.viewer.mode.3d"
        }
    }
}
