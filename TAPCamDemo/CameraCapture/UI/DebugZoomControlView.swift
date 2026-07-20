//
//  DebugZoomControlView.swift
//  TAPCamDemo
//
//  Created by Codex on 2026/4/27.
//

#if DEBUG
import SwiftUI

/// Debug-only control for exercising depth-safe zoom on one SingleCam pipeline.
///
/// The chips receive display-only zoom options; `CameraView` resolves the
/// selected token back to the `ZoomProfile` that Runtime applies.
struct DebugZoomControlView: View {
    let zoomOptions: [CameraDebugZoomDisplayOption]
    let selectedZoomFactor: Double
    let fovLabel: String
    let sliderRange: ClosedRange<Double>
    let isSliderEnabled: Bool
    let selectZoom: (CameraDebugZoomDisplayOption) -> Void
    let selectZoomFactor: (Double) -> Void

    @State private var sliderValue: Double = 1.0

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Image(systemName: "scope")
                    .font(.caption.weight(.bold))
                Text(fovLabel)
                    .font(.caption.weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }

            zoomInput
        }
        .onAppear {
            sliderValue = clampedSliderValue(selectedZoomFactor)
        }
        .onChange(of: selectedZoomFactor) { _, newValue in
            sliderValue = clampedSliderValue(newValue)
        }
        .frame(width: 136, alignment: .leading)
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(.yellow.opacity(0.50), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(.white.opacity(0.12), lineWidth: 1)
        }
    }

    @ViewBuilder
    private var zoomInput: some View {
        if hasInteractiveSlider {
            Slider(
                value: $sliderValue,
                in: sliderRange,
                step: 0.1,
                onEditingChanged: { isEditing in
                    guard !isEditing else { return }
                    selectZoomFactor(clampedSliderValue(sliderValue))
                }
            )
            .tint(.black)
        } else {
            /*
             Continuous and discrete depth-safe zoom are different AVFoundation
             capabilities. The compact Debug control uses a slider only when the
             format exposes a real range; otherwise it presents the valid chips
             directly instead of showing both controls plus duplicated range text.
            */
            HStack(spacing: 5) {
                ForEach(zoomOptions) { zoom in
                    Button {
                        selectZoom(zoom)
                    } label: {
                        Text(zoom.displayName)
                            .font(.caption2.weight(.bold))
                            .frame(width: 34, height: 24)
                            .background(background(for: zoom), in: Capsule())
                            .foregroundStyle(foreground(for: zoom))
                    }
                    .buttonStyle(.plain)
                    .disabled(!zoom.isEnabled)
                }
            }
            .frame(height: 24)
        }
    }

    private var hasInteractiveSlider: Bool {
        isSliderEnabled
            && sliderRange.lowerBound.isFinite
            && sliderRange.upperBound.isFinite
            && sliderRange.lowerBound < sliderRange.upperBound
    }

    private func background(for zoom: CameraDebugZoomDisplayOption) -> Color {
        if !zoom.isEnabled {
            return .yellow.opacity(0.08)
        }
        return zoom.isSelected ? .yellow.opacity(0.92) : .black.opacity(0.30)
    }

    private func foreground(for zoom: CameraDebugZoomDisplayOption) -> Color {
        if !zoom.isEnabled {
            return .white.opacity(0.32)
        }
        return zoom.isSelected ? .black : .white
    }

    private func clampedSliderValue(_ value: Double) -> Double {
        min(max(value, sliderRange.lowerBound), sliderRange.upperBound)
    }
}


#endif
