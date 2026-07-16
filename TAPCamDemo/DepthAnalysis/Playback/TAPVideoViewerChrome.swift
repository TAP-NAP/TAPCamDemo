//
//  TAPVideoViewerChrome.swift
//  TAPCamDemo
//

import AVFoundation
import SwiftUI

nonisolated enum TAPVideoViewerChromeLayout {
    static func noticeTopPadding(topSafeArea: CGFloat) -> CGFloat {
        max(topSafeArea + 66, 116)
    }

    static func noticeContentMaxWidth(availableWidth: CGFloat) -> CGFloat {
        max(0, availableWidth - 76)
    }
}

nonisolated enum TAPVideoViewerModePolicy {
    static func items(
        availability: TAPVideoRegisteredDepthAvailability,
        selectedTool: AnalysisViewerTool,
        isTwoDPlaybackReady: Bool
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
                isEnabled = false
                accessibilityValue = "Unavailable for video"
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
    let player: AVPlayer?
    let selectedTool: AnalysisViewerTool
    let availability: TAPVideoRegisteredDepthAvailability
    let isTwoDPlaybackReady: Bool
    @Binding var overlayOpacity: Double
    let isSharePreparing: Bool
    let topSafeArea: CGFloat
    let bottomSafeArea: CGFloat
    let onBackTapped: () -> Void
    let onShareTapped: () -> Void
    let onModeTapped: (String) -> Void
    let onDeleteTapped: () -> Void

    var body: some View {
        let isPlayerReady = player != nil
        let shareIsDisabled = !isPlayerReady || isSharePreparing
        DepthViewerChromeView(
            selectedModeID: selectedTool.rawValue,
            modeItems: TAPVideoViewerModePolicy.items(
                availability: availability,
                selectedTool: selectedTool,
                isTwoDPlaybackReady: isTwoDPlaybackReady
            ),
            overlayOpacity: $overlayOpacity,
            showsOpacityControl: selectedTool == .twoD
                && availability.isAvailable
                && isPlayerReady,
            isSharePreparing: shareIsDisabled,
            shareAccessibilityLabel: shareAccessibilityLabel(
                isPlayerReady: isPlayerReady
            ),
            deleteAccessibilityLabel: "Delete video",
            topSafeArea: topSafeArea,
            bottomSafeArea: bottomSafeArea,
            // This accessory type never changes, so the root chrome identity
            // remains stable while its local player content becomes ready.
            bottomAccessory: TAPVideoPlaybackTransportAccessory(player: player),
            onBackTapped: onBackTapped,
            onShareTapped: onShareTapped,
            onModeTapped: onModeTapped,
            onDeleteTapped: onDeleteTapped
        )
    }

    private func shareAccessibilityLabel(isPlayerReady: Bool) -> String {
        if !isPlayerReady {
            return "Preparing video"
        }
        return isSharePreparing ? "Preparing share" : "Share video"
    }
}
