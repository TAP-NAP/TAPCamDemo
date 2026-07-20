//
//  DepthAnalysisHighlightPalette.swift
//  TAPCamDemo
//
//  Created by Codex on 2026/7/6.
//

import SwiftUI
import UIKit

struct AnalysisHighlightPalette {
    let baseColor: Color
    let uiColor: UIColor
    let badgeForeground: Color

    static let fallback = AnalysisHighlightPalette(
        baseColor: .yellow,
        uiColor: .systemYellow,
        badgeForeground: .black
    )

    init(baseColor: Color, uiColor: UIColor, badgeForeground: Color) {
        self.baseColor = baseColor
        self.uiColor = uiColor
        self.badgeForeground = badgeForeground
    }

    init(viewfinderPreference: CameraViewfinderHighlightPreference) {
        switch viewfinderPreference {
        case .yellow:
            self.init(baseColor: .yellow, uiColor: .systemYellow, badgeForeground: .black)
        case .titian:
            let color = UIColor(red: 183.0 / 255.0, green: 40.0 / 255.0, blue: 46.0 / 255.0, alpha: 1)
            self.init(
                baseColor: Color(color),
                uiColor: color,
                badgeForeground: .white
            )
        }
    }

    static func resolved(viewfinderRawValue: String) -> AnalysisHighlightPalette {
        AnalysisHighlightPalette(
            viewfinderPreference: CameraViewfinderHighlightPreference.resolved(rawValue: viewfinderRawValue)
        )
    }

    func gridFill(confidence: Double) -> Color {
        let clampedConfidence = min(max(confidence, 0), 1)
        return baseColor.opacity(0.12 + 0.22 * clampedConfidence)
    }

    func gridStroke(confidence: Double) -> Color {
        let clampedConfidence = min(max(confidence, 0), 1)
        return baseColor.opacity(0.42 + 0.44 * clampedConfidence)
    }

    var contour: Color {
        baseColor.opacity(0.94)
    }

    var seedStroke: Color {
        baseColor
    }

    var seedFill: Color {
        baseColor
    }

    var badgeBackground: Color {
        baseColor
    }

    var sceneEmissionColor: UIColor {
        uiColor.withAlphaComponent(0.74)
    }
}
