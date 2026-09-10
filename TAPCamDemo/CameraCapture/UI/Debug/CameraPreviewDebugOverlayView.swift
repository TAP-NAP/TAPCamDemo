//
//  CameraPreviewDebugOverlayView.swift
//  TAPCamDemo
//
//  Created by Codex on 2026/6/11.
//

#if DEBUG
import SwiftUI

/// Display-only Debug depth source row state.
///
/// The token is resolved by `CameraView`; this type does not carry
/// `AVCaptureDevice`, camera profiles, depth profiles, format selections, or
/// capture plans.
struct CameraDebugDepthDisplayOption: Identifiable, Equatable, Sendable {
    let selectionToken: String
    let displayName: String
    let iconName: String
    let isSelected: Bool
    let isEnabled: Bool

    var id: String {
        selectionToken
    }
}

/// Display-only Debug zoom chip state.
///
/// The token is resolved by `CameraView`; the overlay does not receive
/// `ZoomProfile` or any capture-plan object.
struct CameraDebugZoomDisplayOption: Identifiable, Equatable, Sendable {
    let selectionToken: String
    let displayName: String
    let isSelected: Bool
    let isEnabled: Bool

    var id: String {
        selectionToken
    }
}

/// Debug-only presentation values shown over the preview.
///
/// These values are already display strings, counts, metrics, or capability
/// choices from `CameraViewModel`; the overlay does not inspect devices, build
/// capture plans, sign output, export Photos assets, or persist identifiers.
/// Keep this state Debug-only because it can describe engineering devices,
/// formats, raw zoom behavior, transient status text, and job metrics.
struct CameraPreviewDebugState {
    let isDepthReady: Bool
    let activeCameraDisplayName: String
    let statusMessage: String
    let recentMetrics: [CaptureJobMetrics]
    let queuedJobCount: Int
    let depthOptions: [CameraDebugDepthDisplayOption]
    let showsZoomControl: Bool
    let zoomOptions: [CameraDebugZoomDisplayOption]
    let selectedZoomFactor: Double
    let fovLabel: String
    let sliderRange: ClosedRange<Double>
    let isSliderEnabled: Bool
    let manualControlLines: [String]
}

/// Debug-only overlay for camera source, zoom, and recent capture metrics.
///
/// The preview stage owns where this overlay is attached. This view owns only
/// the Debug overlay layout and its local expanded/collapsed state.
struct CameraPreviewDebugOverlayView: View {
    let state: CameraPreviewDebugState
    let onSelectDepthOption: (CameraDebugDepthDisplayOption) -> Void
    let onSelectZoomOption: (CameraDebugZoomDisplayOption) -> Void
    let onSelectZoomFactor: (Double) -> Void

    @State private var isDepthSelectorExpanded = false
    @State private var isPerformanceExpanded = false

    var body: some View {
        ZStack {
            VStack {
                debugStatusOverlay
                    .padding(10)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            HStack(alignment: .bottom) {
                depthSelector
                    .padding(10)

                Spacer(minLength: 0)

                debugZoomControl
                    .padding(10)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
    }

    private var debugStatusOverlay: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: state.isDepthReady ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(state.isDepthReady ? .green : .yellow)

                Text(state.activeCameraDisplayName)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                Spacer(minLength: 8)

                Button {
                    withAnimation(.spring(response: 0.22, dampingFraction: 0.86)) {
                        isPerformanceExpanded.toggle()
                    }
                } label: {
                    Image(systemName: "gauge.with.dots.needle.67percent")
                        .font(.caption.weight(.bold))
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)
            }

            Text(state.statusMessage)
                .font(.caption2)
                .lineLimit(2)
                .foregroundStyle(.white.opacity(0.82))
                .accessibilityIdentifier("camera.capture.status")

            if !state.manualControlLines.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(state.manualControlLines, id: \.self) { line in
                        Text(line)
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                }
                .foregroundStyle(.white.opacity(0.78))
                .accessibilityIdentifier("camera.debug.manualControls")
            }

            if isPerformanceExpanded {
                PerformancePanelView(
                    metrics: state.recentMetrics,
                    pendingJobCount: state.queuedJobCount
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .foregroundStyle(.white)
        .frame(width: 260, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.yellow.opacity(0.50), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(.white.opacity(0.12), lineWidth: 1)
        }
    }

    private var depthSelector: some View {
        DebugDepthPanelView(
            options: state.depthOptions,
            isExpanded: $isDepthSelectorExpanded,
            select: { option in
                onSelectDepthOption(option)
                withAnimation(.spring(response: 0.22, dampingFraction: 0.86)) {
                    isDepthSelectorExpanded = false
                }
            }
        )
    }

    @ViewBuilder
    private var debugZoomControl: some View {
        if state.showsZoomControl {
            DebugZoomControlView(
                zoomOptions: state.zoomOptions,
                selectedZoomFactor: state.selectedZoomFactor,
                fovLabel: state.fovLabel,
                sliderRange: state.sliderRange,
                isSliderEnabled: state.isSliderEnabled,
                selectZoom: onSelectZoomOption,
                selectZoomFactor: onSelectZoomFactor
            )
            .transition(.opacity.combined(with: .move(edge: .trailing)))
        }
    }
}
#endif
