//
//  CameraInitialReadinessGate.swift
//  TAPCamDemo
//

@preconcurrency import AVFoundation
import SwiftUI
import UIKit

/// A two-tick display-link barrier for startup route and `t4 -> t5` commits.
/// The first tick lets SwiftUI/Core Animation present the current state change;
/// the second observes that committed frame before the next startup phase.
@MainActor
final class CameraViewfinderFrameBarrier {
    nonisolated init() {}

    func waitForCommittedViewfinderFrame() async {
        let waiter = CameraViewfinderDisplayLinkWaiter()
        await waiter.waitForCommittedFrame()
    }
}

@MainActor
private final class CameraViewfinderDisplayLinkWaiter: NSObject {
    private var displayLink: CADisplayLink?
    private var continuation: CheckedContinuation<Void, Never>?
    private var remainingTicks = 2

    func waitForCommittedFrame() async {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            let displayLink = CADisplayLink(
                target: self,
                selector: #selector(displayLinkDidFire)
            )
            self.displayLink = displayLink
            displayLink.add(to: .main, forMode: .common)
        }
    }

    @objc private func displayLinkDidFire() {
        remainingTicks -= 1
        guard remainingTicks == 0 else { return }
        displayLink?.invalidate()
        displayLink = nil
        continuation?.resume()
        continuation = nil
    }

    deinit {
        displayLink?.invalidate()
    }
}

struct CameraInitialReadinessGate {
    let isEnabled: Bool
    let prepareCommit: @MainActor () async -> CameraInitialReadinessCommit?

    static let disabled = CameraInitialReadinessGate(
        isEnabled: false,
        prepareCommit: { nil }
    )

    static func resourceInitialization(
        prepareCommit: @escaping @MainActor () async ->
            CameraInitialReadinessCommit?
    ) -> CameraInitialReadinessGate {
        CameraInitialReadinessGate(
            isEnabled: true,
            prepareCommit: prepareCommit
        )
    }
}

/// The prepared I marker's point-of-no-return operations. `commit` is invoked
/// synchronously with the CameraView `t4` state publication; `discard` removes
/// the uncommitted temporary marker when the active journey is canceled.
struct CameraInitialReadinessCommit {
    let commit: @MainActor () -> Bool
    let discard: @MainActor () -> Void
}

/// Low-cardinality attribution for an invariant that has not completed yet.
/// These values are diagnostic checkpoints, not product recovery states.
nonisolated enum ResourceInitializationPendingCheckpoint: String, Equatable {
    case cameraAuthorization
    case cameraSession
    case firstPreview
    case primaryControls
    case haptics
    case libraryCatalog
    case markerCommit
}

nonisolated enum CameraInteractiveReadinessState: Equatable {
    case inactive
    case preparing(ResourceInitializationPendingCheckpoint)
    case ready

    var blocksInteraction: Bool {
        switch self {
        case .inactive:
            false
        case .preparing, .ready:
            true
        }
    }

    var pendingCheckpoint: ResourceInitializationPendingCheckpoint? {
        if case .preparing(let checkpoint) = self {
            return checkpoint
        }
        return nil
    }

    static func resolve(
        isGateEnabled: Bool,
        didCompleteGate: Bool,
        cameraAuthorizationStatus: AVAuthorizationStatus,
        isConfiguringSession: Bool,
        hasActiveSessionConfiguration: Bool,
        isDepthCaptureReady: Bool,
        hasPresentedFirstPreview: Bool,
        hasSafePrimaryControls: Bool,
        hasPreparedHaptics: Bool,
        hasUsableLibraryCatalog: Bool,
        isSceneActive: Bool = true
    ) -> CameraInteractiveReadinessState {
        guard isGateEnabled, !didCompleteGate else {
            return .inactive
        }
        guard isSceneActive else {
            return .preparing(.cameraSession)
        }
        guard cameraAuthorizationStatus == .authorized else {
            return .preparing(.cameraAuthorization)
        }
        guard !isConfiguringSession,
              hasActiveSessionConfiguration,
              isDepthCaptureReady else {
            return .preparing(.cameraSession)
        }
        guard hasPresentedFirstPreview else {
            return .preparing(.firstPreview)
        }
        guard hasSafePrimaryControls else {
            return .preparing(.primaryControls)
        }
        guard hasPreparedHaptics else {
            return .preparing(.haptics)
        }
        guard hasUsableLibraryCatalog else {
            return .preparing(.libraryCatalog)
        }
        return .ready
    }
}

/// First stable app-owned frame shown before route-owned camera construction.
struct ResourceInitializationLaunchView: View {
    var body: some View {
        ResourceInitializationContent(
            isCameraReady: false,
            isLibraryReady: false
        )
            .accessibilityIdentifier("camera.initialReadiness.overlay")
    }
}

struct CameraInitialReadinessOverlayView: View {
    let state: CameraInteractiveReadinessState
    let isCameraReady: Bool
    let isLibraryReady: Bool

    var body: some View {
        ZStack {
            if state.blocksInteraction {
                ResourceInitializationContent(
                    isCameraReady: isCameraReady,
                    isLibraryReady: isLibraryReady
                )
                    .accessibilityValue(
                        state.pendingCheckpoint?.rawValue ?? "preparing"
                    )
            }
        }
        .accessibilityIdentifier("camera.initialReadiness.overlay")
    }
}

private struct ResourceInitializationContent: View {
    let isCameraReady: Bool
    let isLibraryReady: Bool

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                ProgressView()
                    .tint(.white)
                    .scaleEffect(1.18)
                    .padding(.bottom, 24)

                Text("Resource Initialization")
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(.white)

                Text("Please wait…")
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.62))
                    .padding(.top, 9)

                VStack(spacing: 0) {
                    ResourceInitializationReadinessRow(
                        title: "Camera Resources",
                        loadingDetail: "Preparing first preview and controls",
                        readyDetail: "First preview and camera controls are ready",
                        isReady: isCameraReady
                    )

                    Divider()
                        .overlay(.white.opacity(0.10))

                    ResourceInitializationReadinessRow(
                        title: "TAP Library",
                        loadingDetail: "Building media catalog",
                        readyDetail: "First media catalog is ready",
                        isReady: isLibraryReady
                    )
                }
                .frame(maxWidth: 286)
                .background(.white.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 17, style: .continuous)
                        .stroke(.white.opacity(0.12), lineWidth: 1)
                }
                .padding(.top, 34)
            }
            .padding(.horizontal, 44)
        }
    }
}

private struct ResourceInitializationReadinessRow: View {
    let title: LocalizedStringKey
    let loadingDetail: LocalizedStringKey
    let readyDetail: LocalizedStringKey
    let isReady: Bool

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if isReady {
                    ZStack {
                        Circle()
                            .fill(Color.green.opacity(0.16))
                        Circle()
                            .fill(Color.green)
                            .frame(width: 10, height: 10)
                    }
                } else {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(0.58)
                }
            }
            .frame(width: 18, height: 18)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)

                Text(isReady ? readyDetail : loadingDetail)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.55))
            }

            Spacer(minLength: 0)
        }
        .frame(minHeight: 66)
        .padding(.horizontal, 16)
        .accessibilityElement(children: .combine)
        .accessibilityValue(isReady ? "Ready" : "Preparing")
    }
}
