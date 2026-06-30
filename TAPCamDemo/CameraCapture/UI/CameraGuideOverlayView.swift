//
//  CameraGuideOverlayView.swift
//  TAPCamDemo
//

import SwiftUI

struct CameraGuideOverlayView: View {
    let preference: CameraGuideOverlayPreference

    var body: some View {
        GeometryReader { proxy in
            Path { path in
                switch preference {
                case .off:
                    break
                case .ruleOfThirds:
                    addVerticalLine(to: &path, x: proxy.size.width / 3, height: proxy.size.height)
                    addVerticalLine(to: &path, x: proxy.size.width * 2 / 3, height: proxy.size.height)
                    addHorizontalLine(to: &path, y: proxy.size.height / 3, width: proxy.size.width)
                    addHorizontalLine(to: &path, y: proxy.size.height * 2 / 3, width: proxy.size.width)
                case .centerCross:
                    addVerticalLine(to: &path, x: proxy.size.width / 2, height: proxy.size.height)
                    addHorizontalLine(to: &path, y: proxy.size.height / 2, width: proxy.size.width)
                }
            }
            .stroke(.white.opacity(0.38), style: StrokeStyle(lineWidth: 1, lineCap: .round, dash: [5, 5]))
            .allowsHitTesting(false)
        }
        .opacity(preference == .off ? 0 : 1)
        .accessibilityHidden(true)
    }

    private func addVerticalLine(
        to path: inout Path,
        x: CGFloat,
        height: CGFloat
    ) {
        path.move(to: CGPoint(x: x, y: 0))
        path.addLine(to: CGPoint(x: x, y: height))
    }

    private func addHorizontalLine(
        to path: inout Path,
        y: CGFloat,
        width: CGFloat
    ) {
        path.move(to: CGPoint(x: 0, y: y))
        path.addLine(to: CGPoint(x: width, y: y))
    }
}
