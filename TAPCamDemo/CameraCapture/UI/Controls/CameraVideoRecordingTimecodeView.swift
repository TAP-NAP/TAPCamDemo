//
//  CameraVideoRecordingTimecodeView.swift
//  TAPCamDemo
//

import Foundation
import SwiftUI
import UIKit

nonisolated struct CameraVideoRecordingTimecodeState: Equatable, Sendable {
    let startedAt: Date
    let maximumDuration: TimeInterval

    func elapsedSeconds(at date: Date) -> Int {
        let elapsed = Int(max(0, date.timeIntervalSince(startedAt)).rounded(.down))
        return min(elapsed, maximumDurationSeconds)
    }

    var maximumDurationSeconds: Int {
        Int(max(0, maximumDuration).rounded(.up))
    }

    func displayText(at date: Date) -> String {
        displayText(elapsedSeconds: elapsedSeconds(at: date))
    }

    func displayText(elapsedSeconds: Int) -> String {
        "\(Self.formatted(seconds: elapsedSeconds)) / \(Self.formatted(seconds: maximumDurationSeconds))"
    }

    static func formatted(seconds: Int) -> String {
        let clampedSeconds = max(0, seconds)
        let hours = clampedSeconds / 3_600
        let minutes = (clampedSeconds % 3_600) / 60
        let seconds = clampedSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }
}

struct CameraVideoRecordingTimecodeView: UIViewRepresentable {
    let state: CameraVideoRecordingTimecodeState

    func makeUIView(context: Context) -> CameraVideoRecordingTimecodeUIView {
        let view = CameraVideoRecordingTimecodeUIView()
        view.configure(state: state)
        return view
    }

    func updateUIView(
        _ uiView: CameraVideoRecordingTimecodeUIView,
        context: Context
    ) {
        uiView.configure(state: state)
    }

    static func dismantleUIView(
        _ uiView: CameraVideoRecordingTimecodeUIView,
        coordinator: ()
    ) {
        uiView.stopUpdating()
    }
}

/// A leaf-native timer boundary for recording chrome.
///
/// The label updates once per second without publishing observable state or
/// invalidating the SwiftUI camera tree while AVFoundation is recording.
final class CameraVideoRecordingTimecodeUIView: UIView {
    private let timecodeLabel = UILabel()
    private var state: CameraVideoRecordingTimecodeState?
    private var timer: Timer?
    private var displayedSecond: Int?

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureLayout()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: Metrics.width, height: Metrics.height)
    }

    deinit {
        timer?.invalidate()
    }

    func configure(state: CameraVideoRecordingTimecodeState) {
        guard self.state != state else {
            return
        }
        self.state = state
        displayedSecond = nil
        updateLabel(at: Date())
        startUpdating()
    }

    func stopUpdating() {
        timer?.invalidate()
        timer = nil
    }

    private func configureLayout() {
        backgroundColor = UIColor.black.withAlphaComponent(0.58)
        layer.cornerRadius = Metrics.height / 2
        layer.cornerCurve = .continuous
        clipsToBounds = true
        isUserInteractionEnabled = false

        let recordingDot = UIView()
        recordingDot.translatesAutoresizingMaskIntoConstraints = false
        recordingDot.backgroundColor = .systemRed
        recordingDot.layer.cornerRadius = Metrics.dotSide / 2

        timecodeLabel.translatesAutoresizingMaskIntoConstraints = false
        timecodeLabel.font = .monospacedSystemFont(
            ofSize: Metrics.fontSize,
            weight: .semibold
        )
        timecodeLabel.textColor = .white
        timecodeLabel.textAlignment = .center
        timecodeLabel.adjustsFontSizeToFitWidth = true
        timecodeLabel.minimumScaleFactor = 0.82
        timecodeLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let stack = UIStackView(arrangedSubviews: [recordingDot, timecodeLabel])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = Metrics.spacing
        addSubview(stack)

        NSLayoutConstraint.activate([
            recordingDot.widthAnchor.constraint(equalToConstant: Metrics.dotSide),
            recordingDot.heightAnchor.constraint(equalToConstant: Metrics.dotSide),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Metrics.horizontalInset),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Metrics.horizontalInset),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])

        isAccessibilityElement = true
        accessibilityLabel = "Video recording time"
        accessibilityIdentifier = "camera.videoRecording.timecode"
    }

    private func startUpdating() {
        stopUpdating()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            self?.updateLabel(at: Date())
        }
        timer.tolerance = 0.15
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func updateLabel(at date: Date) {
        guard let state else {
            return
        }
        let elapsedSecond = state.elapsedSeconds(at: date)
        guard elapsedSecond != displayedSecond else {
            return
        }
        displayedSecond = elapsedSecond
        let text = state.displayText(elapsedSeconds: elapsedSecond)
        timecodeLabel.text = text
        accessibilityValue = text
    }

    private enum Metrics {
        static let width: CGFloat = 120
        static let height: CGFloat = 30
        static let dotSide: CGFloat = 7
        static let fontSize: CGFloat = 13
        static let spacing: CGFloat = 7
        static let horizontalInset: CGFloat = 11
    }
}
