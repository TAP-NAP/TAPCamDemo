//
//  TAPVideoViewerChrome.swift
//  TAPCamDemo
//

import SwiftUI

nonisolated enum TAPVideoViewerChromeLayout {
    static func noticeTopPadding(topSafeArea: CGFloat) -> CGFloat {
        max(topSafeArea + 66, 116)
    }
}

nonisolated enum TAPVideoViewerModePolicy {
    static func items(
        availability: TAPVideoRegisteredDepthAvailability,
        selectedTool: AnalysisViewerTool,
        isTwoDPlaybackReady: Bool,
        isThreeDDepthAvailable: Bool = false,
        isThreeDPlaybackReady: Bool = false
    ) -> [DepthViewerModeItem] {
        AnalysisViewerTool.allCases.map { tool in
            let isEnabled: Bool
            let accessibilityValue: String?
            switch tool {
            case .raw:
                isEnabled = true
                accessibilityValue = selectedTool == .raw ? "Selected" : nil
            case .twoD:
                isEnabled = availability.isAvailable
                switch availability {
                case .checking:
                    accessibilityValue = "Preparing registered depth"
                case .unavailable:
                    accessibilityValue = "Registered depth unavailable"
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
                isEnabled = isThreeDDepthAvailable
                if !isThreeDDepthAvailable {
                    accessibilityValue = "3D depth unavailable"
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
                isEnabled: isEnabled,
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

struct TAPVideoViewerChrome: View {
    let transportModel: TAPVideoPlaybackTransportModel?
    let selectedTool: AnalysisViewerTool
    let availability: TAPVideoRegisteredDepthAvailability
    let isTwoDPlaybackReady: Bool
    var isThreeDDepthAvailable = false
    var isThreeDPlaybackReady = false
    @Binding var overlayOpacity: Double
    let shareSubject: DepthAnalysisShareSubject?
    let shareResourceAccess: DepthAnalysisShareResourceAccess?
    let topSafeArea: CGFloat
    let bottomSafeArea: CGFloat
    let onModeTapped: (String) -> Void
    let onDeleteTapped: () -> Void

    var body: some View {
        let isPlayerReady = transportModel != nil
        DepthViewerChromeView(
            selectedModeID: selectedTool.rawValue,
            modeItems: TAPVideoViewerModePolicy.items(
                availability: availability,
                selectedTool: selectedTool,
                isTwoDPlaybackReady: isTwoDPlaybackReady,
                isThreeDDepthAvailable: isThreeDDepthAvailable,
                isThreeDPlaybackReady: isThreeDPlaybackReady
            ),
            overlayOpacity: $overlayOpacity,
            showsOpacityControl: selectedTool == .twoD
                && availability.isAvailable
                && isPlayerReady,
            shareSubject: shareSubject,
            shareResourceAccess: shareResourceAccess,
            shareAccessibilityLabel: "Share video",
            deleteAccessibilityLabel: "Delete video",
            bottomSafeArea: bottomSafeArea,
            // This accessory type never changes, so the root chrome identity
            // remains stable while its local player content becomes ready.
            bottomAccessory: TAPVideoPlaybackTransportAccessory(
                model: transportModel
            ),
            onModeTapped: onModeTapped,
            onDeleteTapped: onDeleteTapped
        )
    }
}
