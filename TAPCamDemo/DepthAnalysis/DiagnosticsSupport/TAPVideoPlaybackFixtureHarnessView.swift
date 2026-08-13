//
//  TAPVideoPlaybackFixtureHarnessView.swift
//  TAPCamDemo
//

#if DEBUG
import Foundation
import SwiftUI

@MainActor
struct TAPVideoPlaybackFixtureHarnessView: View {
    let configuration: TAPVideoPlaybackFixtureLaunchConfiguration

    @State private var phase = Phase.generating
    @State private var presentedArtifact: TAPVideoPlaybackFixtureArtifact?
    @State private var readinessDelayGate = TAPVideoPlaybackFixtureReadinessDelayGate()

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .generating:
                    ProgressView("Generating \(configuration.scenario.rawValue)")
                        .tint(.white)
                        .foregroundStyle(.white)
                        .accessibilityIdentifier("tap.video.fixture.generating")
                case .ready(let artifact):
                    VStack(spacing: 18) {
                        Label("Fixture ready", systemImage: "checkmark.circle.fill")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .accessibilityIdentifier("tap.video.fixture.ready")

                        Text(artifact.scenario.rawValue)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)

                        Button("Open fixture") {
                            readinessDelayGate = .fromLaunchEnvironment()
                            presentedArtifact = artifact
                        }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("tap.video.fixture.open")
                    }
                case .failed(let message):
                    ContentUnavailableView(
                        "Fixture generation failed",
                        systemImage: "video.slash",
                        description: Text(message)
                    )
                    .foregroundStyle(.white)
                    .accessibilityIdentifier("tap.video.fixture.failed")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black.ignoresSafeArea())
            .navigationDestination(isPresented: isArtifactPresented) {
                if let presentedArtifact {
                    TAPVideoDepthPlaybackView(
                        source: .fixtureFile(
                            presentedArtifact.fileURL,
                            automaticSeekScheduleSeconds: configuration.seekScheduleSeconds
                                ?? presentedArtifact.specification.automaticSeekSeconds.map { [$0] }
                                ?? [],
                            autoPlay: configuration.autoPlay
                        ),
                        registrationAdapter: TAPVideoPlaybackFixtureRegistrationAdapter(
                            readinessDelayGate: readinessDelayGate
                        )
                    )
                    .onDisappear {
                        readinessDelayGate.cancel()
                    }
                }
            }
        }
        .dynamicTypeSize(
            configuration.usesAccessibilityDynamicType ? .accessibility3 : .large
        )
        .task(id: configuration.scenario) {
            phase = .generating
            do {
                phase = .ready(
                    try await TAPVideoPlaybackFixtureGenerator.generate(
                        scenario: configuration.scenario
                    )
                )
            } catch is CancellationError {
                return
            } catch {
                phase = .failed("\((error as NSError).domain)(\((error as NSError).code))")
            }
        }
    }

    private var isArtifactPresented: Binding<Bool> {
        Binding(
            get: { presentedArtifact != nil },
            set: { isPresented in
                if !isPresented {
                    presentedArtifact = nil
                }
            }
        )
    }

    private enum Phase {
        case generating
        case ready(TAPVideoPlaybackFixtureArtifact)
        case failed(String)
    }
}

/// DEBUG-only timing seam for UI tests that need to observe Viewer chrome
/// before AVPlayer construction completes. Production playback never reads
/// this environment value.
nonisolated private struct TAPVideoPlaybackFixtureRegistrationAdapter:
    TAPVideoDepthRegistrationAdapting
{
    let readinessDelayGate: TAPVideoPlaybackFixtureReadinessDelayGate

    func registrationDescriptor(
        for manifest: TAPVideoManifest
    ) -> TAPVideoDepthRegistrationDescriptor? {
        readinessDelayGate.waitUntilReadyOrCancelled()
        return TAPVideoFixtureIdentityRegistrationAdapter()
            .registrationDescriptor(for: manifest)
    }
}

/// The delay defaults to zero, is available only in DEBUG, and polls a
/// cancellation gate in short slices so leaving the fixture never strands its
/// detached metadata task in a long sleep.
nonisolated private final class TAPVideoPlaybackFixtureReadinessDelayGate:
    @unchecked Sendable
{
    private static let delayEnvironmentKey =
        "TAPCAM_UI_TEST_VIDEO_FIXTURE_PLAYER_READINESS_DELAY_MS"

    private let delaySeconds: TimeInterval
    private let lock = NSLock()
    private var isCancelled = false

    init(delayMilliseconds: Double = 0) {
        delaySeconds = max(0, delayMilliseconds) / 1_000
    }

    static func fromLaunchEnvironment() -> TAPVideoPlaybackFixtureReadinessDelayGate {
        let rawDelay = ProcessInfo.processInfo.environment[delayEnvironmentKey]
        return TAPVideoPlaybackFixtureReadinessDelayGate(
            delayMilliseconds: rawDelay.flatMap(Double.init) ?? 0
        )
    }

    func cancel() {
        lock.lock()
        isCancelled = true
        lock.unlock()
    }

    func waitUntilReadyOrCancelled() {
        guard delaySeconds > 0 else {
            return
        }
        let deadline = Date().addingTimeInterval(delaySeconds)
        while Date() < deadline {
            lock.lock()
            let shouldStop = isCancelled
            lock.unlock()
            if shouldStop {
                return
            }
            Thread.sleep(
                forTimeInterval: max(0, min(0.01, deadline.timeIntervalSinceNow))
            )
        }
    }
}
#endif
