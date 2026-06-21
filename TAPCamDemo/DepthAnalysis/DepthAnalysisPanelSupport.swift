//
//  DepthAnalysisPanelSupport.swift
//  TAPCamDemo
//
//  Created by Codex on 2026/6/11.
//

import SwiftUI

enum AnalysisDebugHighlight {
    static let restingBackground = Color.yellow.opacity(0.44)
    static let selectedBackground = Color.yellow.opacity(0.82)
}

enum AnalysisButtonHint: Equatable {
    case view(DepthAnalysisViewMode)
    case inspector(AnalysisInspector)

    var title: String {
        switch self {
        case .view(let viewMode):
            viewMode.title
        case .inspector(let inspector):
            inspector.title
        }
    }

    var systemImage: String {
        switch self {
        case .view(let viewMode):
            viewMode.systemImage
        case .inspector(let inspector):
            inspector.systemImage
        }
    }
}
