//
//  CameraPreviewStageView.swift
//  TAPCamDemo
//
//  Created by Codex on 2026/6/11.
//

@preconcurrency import AVFoundation
import SwiftUI

/// Field-level state for the live preview stage.
///
/// The stage can render an `AVCaptureSession` because it owns the preview layer
/// bridge. It does not receive capture pipelines, writers, pending stores, App
/// Attest clients, camera/depth profiles, raw device identifiers, Photos
/// identifiers, photo bytes, manifests, or proofs.
struct CameraPreviewStageState {
    let nativePreviewAspectRatio: Double
    let focalLengthOptions: [CameraFocalLengthDisplayOption]
    let shouldShowFocalLengthSelector: Bool
    let guideOverlayPreference: CameraGuideOverlayPreference
    let previewCropRectNormalized: CropRectNormalized
    let temporaryFocusEVOffset: Double
    let focusMode: CameraFocusControlMode
    let focusRuntimeEvent: CameraFocusRuntimeEvent?
    let focusMagnifierPreference: CameraFocusMagnifierPreference
    let focusLoupePulseID: UUID?
    let viewfinderEdgeToastMessage: String?
    let contentRotation: Angle
    let isCameraPathTransitioning: Bool
    let previewReadinessGeneration: Int
}

/// Live camera preview, release FOV selector, and Debug-only instrumentation.
///
/// `CameraView` still owns lifecycle and action orchestration. This view owns
/// only preview-stage layout. Release FOV uses display-only tokens so this view
/// does not receive hardware planning objects.
struct CameraPreviewStageView: View {
    let session: AVCaptureSession
    let manualFocusPreviewStream: CameraManualFocusPreviewStream
    let previewController: CameraPreviewController
    let state: CameraPreviewStageState
    let highlightColor: Color
    let onPreviewCropChange: (CropRectNormalized) -> Void
    let onPreviewingChanged: (Bool, Int) -> Void
    let onSelectFocalLengthOption: (CameraFocalLengthDisplayOption) -> Void
    let onTapFocusPoint: (CameraPreviewFocusPoint) -> Void
    let onManualFocusTapAssist: (CameraPreviewFocusPoint) -> Void
    let onAdjustTemporaryFocusEV: (Double) -> Void
    let onFinishTemporaryFocusEVAdjustment: () -> Void
    let onClearFocusSession: () -> Void
    let onLockFocusAndExposure: (CameraFocusLockRequest) -> Void
    #if DEBUG
    let debugState: CameraPreviewDebugState
    let onSelectDebugDepthOption: (CameraDebugDepthDisplayOption) -> Void
    let onSelectDebugZoomOption: (CameraDebugZoomDisplayOption) -> Void
    let onSelectDebugZoomFactor: (Double) -> Void
    #endif

    @State private var focusTargetOverlay: CameraFocusTargetOverlay?
    @State private var focusExposureScrubStartOffset: Double?
    @State private var focusLoupePoint = CameraPreviewFocusPoint(x: 0.5, y: 0.5)
    @State private var isFocusLoupeVisible = false
    @State private var focusLoupeVisibilityTask: Task<Void, Never>?
    @State private var manualFocusTapMarkerPoint: CameraPreviewFocusPoint?
    @State private var manualFocusTapMarkerTask: Task<Void, Never>?
    @State private var pendingLongPressStartPoint: CameraPreviewFocusPoint?
    @State private var longPressLockTask: Task<Void, Never>?
    @State private var shouldSuppressNextTapFocus = false

    var body: some View {
        GeometryReader { proxy in
            let previewSize = previewSize(in: proxy.size)

            CameraPreviewView(
                session: session,
                controller: previewController,
                isCameraPathTransitioning: state.isCameraPathTransitioning,
                previewReadinessGeneration: state.previewReadinessGeneration,
                onCropRectChanged: { rect in
                    onPreviewCropChange(CropRectNormalized(metadataRect: rect))
                },
                onPreviewingChanged: onPreviewingChanged
            )
            .frame(width: previewSize.width, height: previewSize.height)
            .clipShape(RoundedRectangle(cornerRadius: previewCornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: previewCornerRadius, style: .continuous)
                    .stroke(.white.opacity(0.12), lineWidth: 1)
            }
            .overlay {
                CameraGuideOverlayView(preference: state.guideOverlayPreference)
                    .clipShape(RoundedRectangle(cornerRadius: previewCornerRadius, style: .continuous))
            }
            .overlay {
                focusGestureLayer(previewSize: previewSize)
            }
            .overlay {
                focusTargetOverlayLayer(previewSize: previewSize)
            }
            .overlay {
                manualFocusTapMarkerLayer(previewSize: previewSize)
            }
            .overlay {
                focusEVControlLayer(previewSize: previewSize)
            }
            .overlay(alignment: .bottomTrailing) {
                focusLoupe(previewSize: previewSize)
                    .padding(.trailing, 12)
                    .padding(.bottom, 12)
            }
            .overlay(alignment: .top) {
                viewfinderEdgeToast
                    .padding(.top, 14)
            }
            .overlay(alignment: .bottom) {
                viewfinderControls
                    .padding(.horizontal, 10)
                    .padding(.bottom, 10)
            }
            #if DEBUG
            .overlay {
                /*
                 Debug overlays are instrumentation, not camera chrome. They
                 stay pinned to the portrait-locked preview coordinates so
                 rotation does not move them or rotate their text while we are
                 inspecting capture devices, zoom ranges, and performance state.
                 */
                CameraPreviewDebugOverlayView(
                    state: debugState,
                    onSelectDepthOption: onSelectDebugDepthOption,
                    onSelectZoomOption: onSelectDebugZoomOption,
                    onSelectZoomFactor: onSelectDebugZoomFactor
                )
            }
            #endif
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: state.focusMode) { _, mode in
            cancelPendingLongPressLock()
            if mode == .manual {
                hideFocusTargetOverlay()
            } else {
                hideFocusLoupe()
                hideManualFocusTapMarker()
            }
        }
        .onChange(of: state.focusLoupePulseID) { _, pulseID in
            guard pulseID != nil else {
                return
            }
            showFocusLoupe()
        }
        .onChange(of: state.focusRuntimeEvent) { _, event in
            guard let event else {
                return
            }
            handleFocusRuntimeEvent(event)
        }
        .onChange(of: state.previewReadinessGeneration) { _, _ in
            focusLoupePoint = CameraPreviewFocusPoint(x: 0.5, y: 0.5)
            hideFocusLoupe()
            hideManualFocusTapMarker()
        }
        .onDisappear {
            cancelPendingLongPressLock()
            hideFocusTargetOverlay()
            hideFocusLoupe()
            hideManualFocusTapMarker()
        }
    }

    private var previewCornerRadius: CGFloat {
        10
    }

    private func focusGestureLayer(previewSize: CGSize) -> some View {
        Color.clear
            .contentShape(Rectangle())
            .gesture(
                SpatialTapGesture(coordinateSpace: .local)
                    .onEnded { value in
                        guard !shouldSuppressNextTapFocus else {
                            shouldSuppressNextTapFocus = false
                            return
                        }
                        let localPoint = previewFocusPoint(
                            from: value.location,
                            previewSize: previewSize
                        )
                        guard state.focusMode == .auto else {
                            withAnimation(.easeInOut(duration: 0.14)) {
                                focusLoupePoint = localPoint
                            }
                            showManualFocusTapMarker(at: localPoint)
                            showFocusLoupe()
                            if let capturePoint = captureFocusPoint(
                                from: localPoint,
                                previewSize: previewSize
                            ) {
                                onManualFocusTapAssist(capturePoint)
                            }
                            return
                        }
                        guard let capturePoint = captureFocusPoint(
                            from: localPoint,
                            previewSize: previewSize
                        ) else {
                            return
                        }
                        showFocusTargetOverlay(at: localPoint, isLocked: false)
                        onTapFocusPoint(capturePoint)
                    }
            )
            .simultaneousGesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { value in
                        guard state.focusMode == .auto,
                              focusExposureScrubStartOffset == nil,
                              !shouldSuppressNextTapFocus else {
                            return
                        }
                        let pressStartPoint = previewFocusPoint(
                            from: value.startLocation,
                            previewSize: previewSize
                        )
                        scheduleLongPressLock(at: pressStartPoint, previewSize: previewSize)
                    }
                    .onEnded { _ in
                        cancelPendingLongPressLock()
                    }
            )
            .simultaneousGesture(focusExposureScrub())
    }

    private func focusTargetOverlayLayer(previewSize: CGSize) -> some View {
        ZStack {
            if let focusTargetOverlay, state.focusMode == .auto {
                FocusIndicatorView(
                    isLocked: focusTargetOverlay.isLocked,
                    highlightColor: highlightColor
                )
                    .position(
                        x: CGFloat(focusTargetOverlay.point.x) * previewSize.width,
                        y: CGFloat(focusTargetOverlay.point.y) * previewSize.height
                    )
                    .transition(.opacity)
            }
        }
        .allowsHitTesting(false)
    }

    private func manualFocusTapMarkerLayer(previewSize: CGSize) -> some View {
        ZStack {
            if let manualFocusTapMarkerPoint, state.focusMode == .manual {
                ZStack {
                    Circle()
                        .stroke(highlightColor.opacity(0.88), lineWidth: 1.4)
                        .frame(width: 30, height: 30)
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(highlightColor.opacity(0.92))
                }
                .position(
                    x: CGFloat(manualFocusTapMarkerPoint.x) * previewSize.width,
                    y: CGFloat(manualFocusTapMarkerPoint.y) * previewSize.height
                )
                .transition(.opacity.combined(with: .scale(scale: 0.82)))
            }
        }
        .allowsHitTesting(false)
    }

    private func focusEVControlLayer(previewSize: CGSize) -> some View {
        ZStack {
            if let focusTargetOverlay, state.focusMode == .auto {
                FocusEVAdjustmentView(
                    offset: state.temporaryFocusEVOffset,
                    highlightColor: highlightColor
                )
                .position(focusEVControlPosition(for: focusTargetOverlay.point, previewSize: previewSize))
                .transition(.opacity)
            }
        }
        .allowsHitTesting(false)
    }

    private func focusEVControlPosition(
        for point: CameraPreviewFocusPoint,
        previewSize: CGSize
    ) -> CGPoint {
        let focusCenterX = CGFloat(point.x) * previewSize.width
        let focusCenterY = CGFloat(point.y) * previewSize.height
        let rightX = focusCenterX
            + Metrics.focusIndicatorSide / 2
            + Metrics.focusEVEdgeGap
            + Metrics.focusEVRailWidth / 2
        let leftX = focusCenterX
            - Metrics.focusIndicatorSide / 2
            - Metrics.focusEVEdgeGap
            - Metrics.focusEVRailWidth / 2
        let horizontalInset = Metrics.previewEdgeInset + Metrics.focusEVRailWidth / 2
        let rawX = rightX <= previewSize.width - horizontalInset ? rightX : leftX
        return CGPoint(
            x: min(max(rawX, horizontalInset), max(previewSize.width - horizontalInset, horizontalInset)),
            y: min(
                max(focusCenterY, Metrics.focusEVRailHeight / 2 + Metrics.previewEdgeInset),
                max(previewSize.height - Metrics.focusEVRailHeight / 2 - Metrics.previewEdgeInset, Metrics.focusEVRailHeight / 2)
            )
        )
    }

    private func previewFocusPoint(
        from location: CGPoint,
        previewSize: CGSize
    ) -> CameraPreviewFocusPoint {
        CameraPreviewFocusPoint(
            x: Double(location.x / max(previewSize.width, 1)),
            y: Double(location.y / max(previewSize.height, 1))
        )
    }

    private func scheduleLongPressLock(
        at pressStartPoint: CameraPreviewFocusPoint,
        previewSize: CGSize
    ) {
        guard pendingLongPressStartPoint == nil else {
            return
        }

        pendingLongPressStartPoint = pressStartPoint
        longPressLockTask?.cancel()
        longPressLockTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled,
                  pendingLongPressStartPoint == pressStartPoint,
                  state.focusMode == .auto else {
                return
            }
            guard let request = longPressLockRequest(
                for: pressStartPoint,
                previewSize: previewSize
            ) else {
                return
            }
            showFocusTargetOverlay(at: request.displayPoint, isLocked: true)
            onLockFocusAndExposure(request)
        }
    }

    private func cancelPendingLongPressLock() {
        longPressLockTask?.cancel()
        longPressLockTask = nil
        pendingLongPressStartPoint = nil
    }

    private func longPressLockRequest(
        for pressStartPoint: CameraPreviewFocusPoint,
        previewSize: CGSize
    ) -> CameraFocusLockRequest? {
        if let focusTargetOverlay,
           focusTargetOverlay.contains(
                pressStartPoint,
                previewSize: previewSize,
                sideLength: Metrics.focusIndicatorSide
           ) {
            return .lockCurrent(displayPoint: focusTargetOverlay.point)
        }

        guard let capturePoint = captureFocusPoint(
            from: pressStartPoint,
            previewSize: previewSize
        ) else {
            return nil
        }
        return .refocusAndLock(displayPoint: pressStartPoint, capturePoint: capturePoint)
    }

    private func captureFocusPoint(
        from displayPoint: CameraPreviewFocusPoint,
        previewSize: CGSize
    ) -> CameraPreviewFocusPoint? {
        let layerPoint = CGPoint(
            x: CGFloat(displayPoint.x) * previewSize.width,
            y: CGFloat(displayPoint.y) * previewSize.height
        )
        guard let converted = previewController.captureDevicePoint(
            fromLayerPoint: layerPoint
        ) else {
            return nil
        }
        return CameraPreviewFocusPoint(
            x: Double(converted.x),
            y: Double(converted.y)
        )
    }

    private func showFocusTargetOverlay(at point: CameraPreviewFocusPoint, isLocked: Bool) {
        let nextOverlay: CameraFocusTargetOverlay
        if isLocked, let focusTargetOverlay {
            nextOverlay = focusTargetOverlay.lockedOverlay(at: point)
        } else {
            nextOverlay = CameraFocusTargetOverlay(
                point: point,
                phase: isLocked ? .locked : .focusing
            )
        }
        withAnimation(.easeInOut(duration: 0.14)) {
            focusTargetOverlay = nextOverlay
        }
        focusExposureScrubStartOffset = nil
    }

    private func hideFocusTargetOverlay() {
        let shouldClearRuntimeFocusSession = focusTargetOverlay != nil
            || state.temporaryFocusEVOffset != 0
        withAnimation(.easeInOut(duration: 0.14)) {
            focusTargetOverlay = nil
        }
        focusExposureScrubStartOffset = nil
        shouldSuppressNextTapFocus = false
        if shouldClearRuntimeFocusSession {
            onClearFocusSession()
        }
    }

    private func showFocusLoupe() {
        guard let duration = state.focusMagnifierPreference.duration,
              state.focusMode == .manual else {
            hideFocusLoupe()
            return
        }

        focusLoupeVisibilityTask?.cancel()
        withAnimation(.easeInOut(duration: 0.14)) {
            isFocusLoupeVisible = true
        }
        focusLoupeVisibilityTask = Task { @MainActor in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else {
                return
            }
            hideFocusLoupe()
        }
    }

    private func hideFocusLoupe() {
        focusLoupeVisibilityTask?.cancel()
        withAnimation(.easeInOut(duration: 0.14)) {
            isFocusLoupeVisible = false
        }
    }

    private func showManualFocusTapMarker(at point: CameraPreviewFocusPoint) {
        manualFocusTapMarkerTask?.cancel()
        withAnimation(.easeOut(duration: 0.12)) {
            manualFocusTapMarkerPoint = point
        }
        manualFocusTapMarkerTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else {
                return
            }
            hideManualFocusTapMarker()
        }
    }

    private func hideManualFocusTapMarker() {
        manualFocusTapMarkerTask?.cancel()
        manualFocusTapMarkerTask = nil
        withAnimation(.easeInOut(duration: 0.12)) {
            manualFocusTapMarkerPoint = nil
        }
    }

    private func handleFocusRuntimeEvent(_ event: CameraFocusRuntimeEvent) {
        guard state.focusMode == .auto,
              let focusTargetOverlay else {
            return
        }

        guard let nextOverlay = focusTargetOverlay.applyingRuntimeEvent(event.kind) else {
            hideFocusTargetOverlay()
            return
        }

        guard nextOverlay != focusTargetOverlay else {
            return
        }

        withAnimation(.easeInOut(duration: 0.14)) {
            self.focusTargetOverlay = nextOverlay
        }
    }

    private func focusExposureScrub() -> some Gesture {
        DragGesture(minimumDistance: Metrics.focusExposureScrubMinimumDistance, coordinateSpace: .local)
            .onChanged { value in
                guard state.focusMode == .auto,
                      focusTargetOverlay != nil else {
                    return
                }
                shouldSuppressNextTapFocus = true
                cancelPendingLongPressLock()
                if focusExposureScrubStartOffset == nil {
                    focusExposureScrubStartOffset = state.temporaryFocusEVOffset
                }
                onAdjustTemporaryFocusEV(focusExposureScrubOffset(translationHeight: value.translation.height))
            }
            .onEnded { _ in
                let wasScrubbing = focusExposureScrubStartOffset != nil
                focusExposureScrubStartOffset = nil
                guard wasScrubbing else {
                    shouldSuppressNextTapFocus = false
                    return
                }
                onFinishTemporaryFocusEVAdjustment()
                Task { @MainActor in
                    await Task.yield()
                    shouldSuppressNextTapFocus = false
                }
            }
    }

    private func focusExposureScrubOffset(translationHeight: CGFloat) -> Double {
        let startOffset = focusExposureScrubStartOffset ?? state.temporaryFocusEVOffset
        let rawOffset = startOffset - Double(translationHeight / Metrics.focusExposureScrubPointsPerEV)
        let stepped = (rawOffset / CameraTemporaryFocusEVPreferences.adjustmentStep).rounded()
            * CameraTemporaryFocusEVPreferences.adjustmentStep
        return CameraTemporaryFocusEVPreferences.clampedOffset(stepped)
    }

    /// Recreates the original bottom-right loupe geometry while sourcing its
    /// pixels from the PRO graph's lightweight video-data output. The main
    /// preview remains at 1x and keeps publishing the authoritative crop rect.
    @ViewBuilder
    private func focusLoupe(previewSize: CGSize) -> some View {
        if state.focusMode == .manual, isFocusLoupeVisible {
            let loupeWidth = max(112, previewSize.width * 0.34)
            let loupeHeight = loupeWidth * 9.0 / 16.0
            let loupeTransform = CameraManualFocusLoupeTransform(
                focusPoint: focusLoupePoint,
                previewSize: previewSize,
                magnification: 2.4
            )
            ZStack {
                CameraManualFocusLoupePreview(source: manualFocusPreviewStream)
                    .frame(width: previewSize.width, height: previewSize.height)
                    .scaleEffect(
                        loupeTransform.magnification,
                        anchor: UnitPoint(
                            x: CGFloat(focusLoupePoint.x),
                            y: CGFloat(focusLoupePoint.y)
                        )
                    )
                    .offset(
                        x: loupeTransform.centeringOffset.width,
                        y: loupeTransform.centeringOffset.height
                    )
                    .frame(width: loupeWidth, height: loupeHeight)
                    .clipped()

                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(.white.opacity(0.70), lineWidth: 1.2)

                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.82))
            }
            .frame(width: loupeWidth, height: loupeHeight)
            .background(.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .shadow(color: .black.opacity(0.42), radius: 8)
            .allowsHitTesting(false)
            .transition(.opacity)
            .accessibilityLabel("Manual focus magnifier")
            .accessibilityIdentifier("camera.focusLoupe")
        }
    }

    @ViewBuilder
    private var viewfinderEdgeToast: some View {
        if let message = state.viewfinderEdgeToastMessage {
            Text(message)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.76)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.black.opacity(0.58), in: Capsule())
                .allowsHitTesting(false)
                .transition(.opacity)
                .accessibilityIdentifier("camera.viewfinderEdgeToast")
        }
    }

    private func previewSize(in containerSize: CGSize) -> CGSize {
        let horizontalInset: CGFloat = 8
        let availableWidth = max(0, containerSize.width - horizontalInset * 2)
        let availableHeight = containerSize.height
        let nativeAspectRatio = CGFloat(max(0.01, state.nativePreviewAspectRatio))
        let widthFromHeight = availableHeight * nativeAspectRatio
        let previewWidth = min(availableWidth, widthFromHeight)
        let previewHeight = previewWidth / nativeAspectRatio
        return CGSize(width: previewWidth, height: previewHeight)
    }

    private var viewfinderControls: some View {
        ZStack(alignment: .bottom) {
            if state.shouldShowFocalLengthSelector {
                FocalLengthSelectorView(
                    options: state.focalLengthOptions,
                    contentRotation: state.contentRotation,
                    select: onSelectFocalLengthOption
                )
                .frame(maxWidth: .infinity, alignment: .center)
                .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 70, alignment: .bottom)
        .animation(.easeInOut(duration: CameraViewfinderTransitionPresentation.duration), value: state.shouldShowFocalLengthSelector)
    }

    private struct FocusIndicatorView: View {
        let isLocked: Bool
        let highlightColor: Color

        var body: some View {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(isLocked ? highlightColor : .white, lineWidth: 1.8)
                    .frame(width: Metrics.focusIndicatorSide, height: Metrics.focusIndicatorSide)

                if isLocked {
                    lockBadge
                        .offset(y: -(Metrics.focusIndicatorSide / 2 + Metrics.lockBadgeVerticalGap))
                }
            }
            .frame(width: Metrics.focusIndicatorSide, height: Metrics.focusIndicatorSide)
            .shadow(color: .black.opacity(0.42), radius: 8)
            .accessibilityHidden(true)
        }

        private var lockBadge: some View {
            Text("AE/AF LOCK")
                .font(.caption2.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(highlightColor)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.black.opacity(0.48), in: Capsule())
                .fixedSize()
        }
    }

    private struct FocusEVAdjustmentView: View {
        let offset: Double
        let highlightColor: Color

        var body: some View {
            evRail
            .frame(width: Metrics.focusEVRailWidth, height: Metrics.focusEVRailHeight)
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.42), radius: 8)
            .allowsHitTesting(false)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Temporary focus exposure")
        }

        private var evRail: some View {
            ZStack(alignment: .bottom) {
                Capsule()
                    .fill(.white.opacity(0.46))
                    .frame(width: 2, height: Metrics.focusEVRailTravel)

                Image(systemName: "sun.max.fill")
                    .font(.system(size: Metrics.focusEVMarkerSide, weight: .semibold))
                    .foregroundStyle(highlightColor)
                    .frame(width: Metrics.focusEVMarkerSide, height: Metrics.focusEVMarkerSide)
                    .background(.black.opacity(0.24), in: Circle())
                    .offset(y: markerOffset)
                    .animation(.easeOut(duration: 0.12), value: offset)
            }
            .frame(width: Metrics.focusEVRailWidth, height: Metrics.focusEVRailHeight)
        }

        private var markerOffset: CGFloat {
            let normalized = (CameraTemporaryFocusEVPreferences.clampedOffset(offset)
                - CameraTemporaryFocusEVPreferences.minimumOffset)
                / (CameraTemporaryFocusEVPreferences.maximumOffset - CameraTemporaryFocusEVPreferences.minimumOffset)
            return Metrics.focusEVMarkerSide / 2 - CGFloat(normalized * Metrics.focusEVRailTravel)
        }
    }

    private enum Metrics {
        static let focusIndicatorSide: CGFloat = 72
        static let focusEVRailWidth: CGFloat = 20
        static let focusEVRailHeight: CGFloat = 126
        static let focusEVRailTravel: CGFloat = 116
        static let focusEVMarkerSide: CGFloat = 17
        static let focusEVEdgeGap: CGFloat = 2
        static let previewEdgeInset: CGFloat = 12
        static let focusExposureScrubMinimumDistance: CGFloat = 8
        static let focusExposureScrubPointsPerEV: CGFloat = 144
        static let lockBadgeVerticalGap: CGFloat = 16
    }

}
