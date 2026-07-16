//
//  TAPVideoPlaybackTransportView.swift
//  TAPCamDemo
//

import AVFoundation
import SwiftUI

struct TAPVideoPlaybackTransportAccessory: View {
    let player: AVPlayer?

    @ViewBuilder
    var body: some View {
        if let player {
            TAPVideoPlaybackTransportView(player: player)
        } else {
            EmptyView()
        }
    }
}

struct TAPVideoPlaybackTransportView: View {
    @State private var model: TAPVideoPlaybackTransportModel

    init(player: AVPlayer) {
        _model = State(initialValue: TAPVideoPlaybackTransportModel(player: player))
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            transportRow(showsTimeLabels: true)
            transportRow(showsTimeLabels: false)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(maxWidth: 460)
        .background(.thinMaterial, in: Capsule())
        .overlay {
            Capsule().stroke(.white.opacity(0.18), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.16), radius: 12, y: 4)
        .padding(.horizontal, 16)
        .accessibilityElement(children: .contain)
        .onDisappear(perform: model.invalidate)
    }

    private func transportRow(showsTimeLabels: Bool) -> some View {
        HStack(spacing: 10) {
            Button(action: model.togglePlayback) {
                Image(systemName: model.hasActivePlaybackIntent ? "pause.fill" : "play.fill")
                    .font(.callout.weight(.semibold))
                    .frame(width: 32, height: 32)
                    .contentShape(Circle())
                    .dynamicTypeSize(.large)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                model.hasActivePlaybackIntent ? "Pause video" : "Play video"
            )
            .accessibilityIdentifier("tap.video.playback.transport.playPause")

            if showsTimeLabels {
                timeLabel(
                    model.elapsedSeconds,
                    confirmedSeconds: model.confirmedElapsedSeconds,
                    identifier: "tap.video.playback.transport.elapsed",
                    accessibilityLabel: "Elapsed time"
                )
            }

            Slider(
                value: Binding(
                    get: { model.elapsedSeconds },
                    set: model.previewSeek(to:)
                ),
                in: 0...max(model.durationSeconds, 0.01),
                onEditingChanged: model.setScrubbing
            )
            .tint(.primary)
            .accessibilityLabel("Video position")
            .accessibilityValue(
                "\(Self.timecode(model.elapsedSeconds)) of "
                    + Self.timecode(model.durationSeconds)
            )
            .accessibilityIdentifier("tap.video.playback.transport.scrubber")

            if showsTimeLabels {
                timeLabel(
                    model.durationSeconds,
                    confirmedSeconds: model.durationSeconds,
                    identifier: "tap.video.playback.transport.duration",
                    accessibilityLabel: "Video duration"
                )
            }
        }
    }

    private func timeLabel(
        _ seconds: Double,
        confirmedSeconds: Double,
        identifier: String,
        accessibilityLabel: String
    ) -> some View {
        Text(Self.timecode(seconds))
            .font(.caption.monospacedDigit())
            .foregroundStyle(.primary)
            .frame(minWidth: 34)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityValue(Self.timecode(confirmedSeconds))
            .accessibilityIdentifier(identifier)
    }

    private static func timecode(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else {
            return "0:00"
        }
        let wholeSeconds = Int(seconds.rounded(.down))
        return "\(wholeSeconds / 60):\(String(format: "%02d", wholeSeconds % 60))"
    }
}
