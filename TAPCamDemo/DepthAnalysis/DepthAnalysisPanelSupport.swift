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

    var id: String { rawValue }

    var title: String {
        switch self {
        case .raw:
            "RAW"
        case .twoD:
            "2D"
        case .threeD:
            "3D"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .raw:
            "Raw photo"
        case .twoD:
            "2D analysis"
        case .threeD:
            "3D projection"
        }
    }

    var systemImage: String {
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

enum AnalysisDebugHighlight {
    static let restingBackground = Color.yellow.opacity(0.44)
    static let selectedBackground = Color.yellow.opacity(0.82)
}

enum AnalysisButtonHint: Equatable {
    case view(DepthAnalysisViewMode)
    case inspector(AnalysisInspector)
    case signatureVerification
    case share
    case delete

    var title: String {
        switch self {
        case .view(let viewMode):
            viewMode.title
        case .inspector(let inspector):
            inspector.title
        case .signatureVerification:
            "Verify"
        case .share:
            "Share"
        case .delete:
            "Delete"
        }
    }

    var systemImage: String {
        switch self {
        case .view(let viewMode):
            viewMode.systemImage
        case .inspector(let inspector):
            inspector.systemImage
        case .signatureVerification:
            "checkmark.shield"
        case .share:
            "square.and.arrow.up"
        case .delete:
            "trash"
        }
    }
}
