//
//  DepthAnalysisPanelSupport.swift
//  TAPCamDemo
//
//  Created by Codex on 2026/6/11.
//

import SwiftUI

enum AnalysisViewerTool: String, CaseIterable, Identifiable, Equatable {
    case raw
    case twoD
    case threeD

    nonisolated var id: String { rawValue }

    nonisolated var title: String {
        switch self {
        case .raw:
            "RAW"
        case .twoD:
            "2D"
        case .threeD:
            "3D"
        }
    }

    nonisolated var accessibilityLabel: String {
        switch self {
        case .raw:
            "Raw photo"
        case .twoD:
            "2D analysis"
        case .threeD:
            "3D projection"
        }
    }

    nonisolated var systemImage: String {
        switch self {
        case .raw:
            "photo"
        case .twoD:
            "square.on.square"
        case .threeD:
            "cube"
        }
    }
}
