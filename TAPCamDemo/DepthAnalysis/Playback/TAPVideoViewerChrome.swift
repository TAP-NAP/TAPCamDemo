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
                isEnabled = true
                accessibilityValue = "Coming soon"
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
    let playbackIntentState: TAPVideoPlaybackIntentState
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
    @State private var comingSoonToastTrigger: UUID?

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
            bottomAccessory: TAPVideoPlaybackTransportAccessory(
                player: player,
                intentState: playbackIntentState
            ),
            onBackTapped: onBackTapped,
            onShareTapped: onShareTapped,
            onModeTapped: handleModeTapped,
            onDeleteTapped: onDeleteTapped
        )
        .overlay(alignment: .top) {
            TAPVideoComingSoonToast()
                .padding(.horizontal, 38)
                .padding(
                    .top,
                    TAPVideoViewerChromeLayout.noticeTopPadding(
                        topSafeArea: topSafeArea
                    )
                )
                .phaseAnimator(
                    TAPVideoComingSoonToastPhase.allCases,
                    trigger: comingSoonToastTrigger
                ) { content, phase in
                    content
                        .opacity(phase.opacity)
                        .accessibilityHidden(!phase.isVisible)
                } animation: { phase in
                    phase.animation
                }
        }
    }

    private func shareAccessibilityLabel(isPlayerReady: Bool) -> String {
        if !isPlayerReady {
            return "Preparing video"
        }
        return isSharePreparing ? "Preparing share" : "Share video"
    }

    private func handleModeTapped(_ itemID: String) {
        guard itemID == AnalysisViewerTool.threeD.rawValue else {
            onModeTapped(itemID)
            return
        }
        showComingSoonToast()
    }

    private func showComingSoonToast() {
        comingSoonToastTrigger = UUID()
    }
}

private enum TAPVideoComingSoonToastPhase: CaseIterable {
    case hidden
    case visible
    case holding
    case dismissed

    var isVisible: Bool {
        self == .visible || self == .holding
    }

    var opacity: Double {
        switch self {
        case .hidden, .dismissed:
            0
        case .visible:
            1
        case .holding:
            // Keep one imperceptibly small animatable delta so PhaseAnimator
            // owns the full two-second hold before accessibility is hidden.
            0.999
        }
    }

    var animation: Animation? {
        switch self {
        case .hidden:
            nil
        case .visible:
            .easeInOut(duration: 0.18)
        case .holding:
            .linear(duration: 2)
        case .dismissed:
            .easeInOut(duration: 0.18)
        }
    }
}

private struct TAPVideoComingSoonToast: View {
    var body: some View {
        Text("Coming soon")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.76)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.black.opacity(0.58), in: Capsule())
            .allowsHitTesting(false)
            .accessibilityIdentifier("tap.viewer.edgeToast")
    }
}
