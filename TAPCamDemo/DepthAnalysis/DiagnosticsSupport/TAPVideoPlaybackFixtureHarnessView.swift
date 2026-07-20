//
//  TAPVideoPlaybackFixtureHarnessView.swift
//  TAPCamDemo
//

#if DEBUG
import SwiftUI

@MainActor
struct TAPVideoPlaybackFixtureHarnessView: View {
    let configuration: TAPVideoPlaybackFixtureLaunchConfiguration

    @State private var phase = Phase.generating
    @State private var presentedArtifact: TAPVideoPlaybackFixtureArtifact?

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
                        registrationAdapter: TAPVideoFixtureIdentityRegistrationAdapter()
                    )
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
#endif
