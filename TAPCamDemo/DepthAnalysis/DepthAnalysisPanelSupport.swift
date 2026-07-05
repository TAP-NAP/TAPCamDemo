//
//  DepthAnalysisPanelSupport.swift
//  TAPCamDemo
//
//  Created by Codex on 2026/6/11.
//

import SwiftUI

enum AnalysisDrawerTool: String, CaseIterable, Identifiable, Equatable {
    case twoD
    case threeD
    case credential

    var id: String { rawValue }

    var title: String {
        switch self {
        case .twoD:
            "2D"
        case .threeD:
            "3D"
        case .credential:
            "凭证"
        }
    }

    var systemImage: String {
        switch self {
        case .twoD:
            "square.on.square"
        case .threeD:
            "cube.transparent"
        case .credential:
            "checkmark.shield"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .twoD:
            "2D analysis"
        case .threeD:
            "3D projection"
        case .credential:
            "Credential"
        }
    }
}

enum AnalysisDebugHighlight {
    static let restingBackground = Color.yellow.opacity(0.44)
    static let selectedBackground = Color.yellow.opacity(0.82)
}

enum AnalysisButtonHint: Equatable {
    case tool(AnalysisDrawerTool)
    case view(DepthAnalysisViewMode)
    case inspector(AnalysisInspector)
    case signatureVerification
    case share
    case delete

    var title: String {
        switch self {
        case .tool(let tool):
            tool.title
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
        case .tool(let tool):
            tool.systemImage
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
