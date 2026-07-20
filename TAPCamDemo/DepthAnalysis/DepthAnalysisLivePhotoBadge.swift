//
//  DepthAnalysisLivePhotoBadge.swift
//  TAPCamDemo
//

import SwiftUI

struct DepthAnalysisLivePhotoBadge: View {
    enum Size {
        case thumbnail
        case viewer

        var imageFont: Font {
            switch self {
            case .thumbnail:
                .system(size: 14, weight: .semibold)
            case .viewer:
                .system(size: 22, weight: .semibold)
            }
        }

        var edgeInset: CGFloat {
            switch self {
            case .thumbnail:
                10
            case .viewer:
                16
            }
        }
    }

    let size: Size

    var body: some View {
        Image(systemName: "livephoto")
            .font(size.imageFont)
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.72), radius: 2, y: 1)
            .accessibilityLabel("Live Photo")
    }
}
