//
//  CameraView.swift
//  TAPCamDemo
//
//  Created by Codex on 2026/4/27.
//

@preconcurrency import AVFoundation
import SwiftUI
import UIKit

/// Main v0.8 capture screen.
///
/// The view is intentionally thin: it renders `CameraProfile`, `DepthProfile`,
/// `ZoomProfile`, and metrics supplied by `CameraViewModel`. AVFoundation
/// details stay below the capability/session layers, which keeps the UI from
/// re-implementing device compatibility rules.
struct CameraView: View {
    @StateObject private var viewModel = CameraViewModel()
    @StateObject private var chromeOrientation = CameraChromeOrientationController()
    @State private var isShowingDepthAlbum = false
    #if DEBUG
    @State private var isDepthSelectorExpanded = false
    @State private var isPerformanceExpanded = false
    #endif

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 10) {
                previewStage
                Spacer(minLength: 8)
                bottomControls
            }
        }
        .task {
            await viewModel.start()
        }
        .onAppear {
            chromeOrientation.start()
        }
        .onDisappear {
            chromeOrientation.stop()
            viewModel.stop()
        }
        .sheet(isPresented: $isShowingDepthAlbum) {
            NavigationStack {
                DepthAlbumPickerView()
            }
        }
    }

    private var previewStage: some View {
        GeometryReader { proxy in
            let horizontalInset: CGFloat = 8
            let availableWidth = max(0, proxy.size.width - horizontalInset * 2)
            let availableHeight = proxy.size.height
            let nativeAspectRatio = CGFloat(max(0.01, viewModel.nativePreviewAspectRatio))
            let widthFromHeight = availableHeight * nativeAspectRatio
            let previewWidth = min(availableWidth, widthFromHeight)
            let previewHeight = previewWidth / nativeAspectRatio

            CameraPreviewView(
                session: viewModel.session,
                onCropRectChanged: { rect in
                    viewModel.updatePreviewCropRect(CropRectNormalized(metadataRect: rect))
                }
            )
            .frame(width: previewWidth, height: previewHeight)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(.white.opacity(0.12), lineWidth: 1)
            }
            .overlay(alignment: .bottom) {
                viewfinderControls
                    .padding(.horizontal, 10)
                    .padding(.bottom, 10)
            }
            #if DEBUG
            /*
             Debug overlays are instrumentation, not camera chrome. They stay
             pinned to the portrait-locked preview coordinates so rotation does
             not move them or rotate their text while we are inspecting capture
             devices, zoom ranges, and performance state.
             */
            .overlay(alignment: .bottomLeading) {
                depthSelector
                    .padding(10)
            }
            .overlay(alignment: .bottomTrailing) {
                debugZoomControl
                    .padding(10)
            }
            .overlay(alignment: .top) {
                debugStatusOverlay
                    .padding(10)
            }
            #endif
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var viewfinderControls: some View {
        ZStack(alignment: .bottom) {
            if viewModel.shouldShowFocalLengthSelector {
                FocalLengthSelectorView(
                    options: viewModel.focalLengthOptions,
                    selectedID: viewModel.activeFocalLengthOptionID,
                    contentRotation: chromeOrientation.angle,
                    select: { option in
                        Task { await viewModel.selectFocalLengthOption(option) }
                    }
                )
                .frame(maxWidth: .infinity, alignment: .center)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .frame(maxWidth: .infinity, minHeight: 70, alignment: .bottom)
    }

    #if DEBUG
    private var debugStatusOverlay: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: viewModel.isDepthCaptureReady ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(viewModel.isDepthCaptureReady ? .green : .yellow)

                Text(viewModel.activeCameraDisplayName)
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

            Text(viewModel.statusMessage)
                .font(.caption2)
                .lineLimit(2)
                .foregroundStyle(.white.opacity(0.82))

            if isPerformanceExpanded {
                PerformancePanelView(
                    metrics: viewModel.recentMetrics,
                    pendingJobCount: viewModel.pendingJobCount
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
        VStack(alignment: .leading, spacing: 7) {
            if isDepthSelectorExpanded {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(viewModel.debugDepthDeviceOptions) { option in
                        Button {
                            Task {
                                await viewModel.selectDebugDepthDevice(option)
                                withAnimation(.spring(response: 0.22, dampingFraction: 0.86)) {
                                    isDepthSelectorExpanded = false
                                }
                            }
                        } label: {
                            DebugDepthDeviceChip(
                                option: option,
                                isSelected: option.id == viewModel.debugSelectedDepthDeviceID
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(!option.isSelectable)
                    }
                }
                .transition(.move(edge: .leading).combined(with: .opacity))
            }

            Button {
                withAnimation(.spring(response: 0.22, dampingFraction: 0.86)) {
                    isDepthSelectorExpanded.toggle()
                }
            } label: {
                Image(systemName: "arkit")
                    .font(.caption.weight(.bold))
                    .frame(width: 38, height: 38)
                    .background(isDepthSelectorExpanded ? .yellow.opacity(0.92) : .yellow.opacity(0.46), in: Circle())
                    .foregroundStyle(isDepthSelectorExpanded ? .black : .white)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Depth sources")
        }
    }

    @ViewBuilder
    private var debugZoomControl: some View {
        if viewModel.isDebugDepthOverrideActive,
           viewModel.debugZoomCapability != nil {
            DebugZoomControlView(
                zoomProfiles: viewModel.debugZoomProfiles,
                selectedZoomID: viewModel.debugSelectedZoomID,
                selectedZoomFactor: viewModel.debugSelectedZoomFactor,
                fovLabel: viewModel.debugFOVLabel,
                sliderRange: viewModel.debugZoomSliderRange,
                isSliderEnabled: viewModel.debugZoomSliderEnabled,
                selectZoom: { zoom in
                    Task { await viewModel.selectDebugZoom(zoom) }
                },
                selectZoomFactor: { zoomFactor in
                    Task { await viewModel.selectDebugZoomFactor(zoomFactor) }
                }
            )
            .transition(.opacity.combined(with: .move(edge: .trailing)))
        }
    }
    #endif

    private var bottomControls: some View {
        HStack {
            recentPhotoButton
                .frame(width: 78, height: 78)
                .rotationEffect(chromeOrientation.angle)

            Spacer()

            Button {
                Task { await viewModel.capture() }
            } label: {
                ZStack {
                    Circle()
                        .strokeBorder(.white, lineWidth: 4)
                        .frame(width: 78, height: 78)

                    Circle()
                        .fill(viewModel.canCapture ? Color.white : Color.gray)
                        .frame(width: 62, height: 62)

                    if viewModel.pendingJobCount > 0 {
                        Text("\(viewModel.pendingJobCount)")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.black)
                            .rotationEffect(chromeOrientation.angle)
                    }
                }
            }
            .disabled(!viewModel.canCapture)
            .accessibilityLabel("Capture depth photo")

            Spacer()

            Button {
                Task { await viewModel.switchCameraPosition() }
            } label: {
                Image(systemName: "arrow.triangle.2.circlepath.camera")
                    .font(.system(size: 27, weight: .semibold))
                    .frame(width: 58, height: 58)
                    .rotationEffect(chromeOrientation.angle)
            }
            .accessibilityLabel("Switch front and back camera")
            .frame(width: 78, height: 78)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .padding(.horizontal, 34)
        .padding(.bottom, 34)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var recentPhotoButton: some View {
        Button {
            isShowingDepthAlbum = true
        } label: {
            if let thumbnail = viewModel.recentThumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 58, height: 58)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(.white.opacity(0.80), lineWidth: 1.5)
                    }
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(.black.opacity(0.48))
                        .frame(width: 58, height: 58)

                    Image(systemName: "photo.on.rectangle")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
        }
        .accessibilityLabel("Open TAPCamDepth album")
    }
}

private struct FocalLengthSelectorView: View {
    let options: [FocalLengthOption]
    let selectedID: String?
    let contentRotation: Angle
    let select: (FocalLengthOption) -> Void

    var body: some View {
        let selectorWidth = min(contentWidth, maximumVisibleWidth)

        GeometryReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(options) { option in
                        Button {
                            select(option)
                        } label: {
                            ZStack {
                                VStack(spacing: 0) {
                                    Text(option.numericLabel)
                                        .font(.system(size: 16, weight: .bold, design: .rounded))
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.72)
                                    Text(option.unitLabel)
                                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                                        .textCase(.lowercase)
                                }
                                .rotationEffect(contentRotation)
                            }
                            .frame(width: 48, height: 42)
                            .background(background(for: option), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                            .foregroundStyle(foreground(for: option))
                        }
                        .buttonStyle(.plain)
                        .disabled(!option.isEnabled)
                        .accessibilityLabel("Use \(option.displayName) field of view")
                    }
                }
                /*
                 A horizontal ScrollView lays out its content from the leading
                 edge. Giving the chip row at least the visible container width
                 keeps small option sets centered, while still allowing larger
                 sets to scroll naturally.
                 */
                .padding(.horizontal, 6)
                .frame(minWidth: proxy.size.width, minHeight: 52, alignment: .center)
            }
        }
        .frame(width: selectorWidth)
        .frame(height: 52)
        .background(.black.opacity(0.44), in: Capsule())
    }

    private var contentWidth: CGFloat {
        let count = CGFloat(options.count)
        let gaps = CGFloat(max(options.count - 1, 0))
        return count * 48 + gaps * 8 + 12
    }

    private var maximumVisibleWidth: CGFloat {
        232
    }

    private func background(for option: FocalLengthOption) -> Color {
        if !option.isEnabled {
            return .white.opacity(0.08)
        }
        return option.id == selectedID ? .white.opacity(0.92) : .white.opacity(0.18)
    }

    private func foreground(for option: FocalLengthOption) -> Color {
        if !option.isEnabled {
            return .white.opacity(0.36)
        }
        return option.id == selectedID ? .black : .white
    }
}

#if DEBUG
private struct DebugDepthDeviceChip: View {
    let option: DebugDepthDeviceOption
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: option.iconName)
                .font(.caption.weight(.bold))
            Text(option.displayName)
                .font(.caption2.weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(width: 126, height: 34, alignment: .leading)
        .padding(.horizontal, 8)
        .background(background, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .foregroundStyle(foreground)
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(isSelected ? strokeColor : Color.clear, lineWidth: 1)
        }
    }

    private var background: Color {
        if !option.isSelectable {
            return .yellow.opacity(0.08)
        }
        return isSelected ? .yellow.opacity(0.92) : .yellow.opacity(0.48)
    }

    private var foreground: Color {
        if !option.isSelectable {
            return .white.opacity(0.36)
        }
        return isSelected ? .black : .white
    }

    private var strokeColor: Color {
        .white.opacity(0.34)
    }
}

private struct DebugZoomControlView: View {
    let zoomProfiles: [ZoomProfile]
    let selectedZoomID: String?
    let selectedZoomFactor: Double
    let fovLabel: String
    let sliderRange: ClosedRange<Double>
    let isSliderEnabled: Bool
    let selectZoom: (ZoomProfile) -> Void
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
                ForEach(zoomProfiles) { zoom in
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

    private func background(for zoom: ZoomProfile) -> Color {
        if !zoom.isEnabled {
            return .yellow.opacity(0.08)
        }
        return isSelected(zoom) ? .yellow.opacity(0.92) : .black.opacity(0.30)
    }

    private func foreground(for zoom: ZoomProfile) -> Color {
        if !zoom.isEnabled {
            return .white.opacity(0.32)
        }
        return isSelected(zoom) ? .black : .white
    }

    private func isSelected(_ zoom: ZoomProfile) -> Bool {
        if let selectedZoomID {
            return zoom.id == selectedZoomID
        }
        return abs(zoom.requestedZoomFactor - selectedZoomFactor) < 0.001
    }

    private func clampedSliderValue(_ value: Double) -> Double {
        min(max(value, sliderRange.lowerBound), sliderRange.upperBound)
    }
}

private struct PerformancePanelView: View {
    let metrics: [CaptureJobMetrics]
    let pendingJobCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Pending \(pendingJobCount)")
                .font(.caption2.weight(.semibold))

            ForEach(metrics.prefix(3)) { metric in
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(metric.status.rawValue)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(metric.status == .succeeded ? .green : .yellow)
                        Text("total \(format(metric.totalDuration))")
                        Text("capture \(format(metric.captureDuration))")
                        Text("write \(format(metric.writeDuration))")
                    }
                    HStack(spacing: 8) {
                        Text(metric.pairingMode ?? "-")
                        Text(metric.selectedRGBSource ?? "-")
                        Text(metric.selectedDepthSource ?? "-")
                        Text(metric.currentZoomFactor.map { "\($0)x" } ?? "-")
                    }
                }
                .font(.caption2)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            }
        }
        .foregroundStyle(.white.opacity(0.86))
    }

    private func format(_ value: TimeInterval?) -> String {
        guard let value else {
            return "-"
        }
        return "\(Int(value * 1_000))ms"
    }
}
#endif
