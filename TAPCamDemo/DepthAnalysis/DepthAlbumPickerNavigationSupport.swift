//
//  DepthAlbumPickerNavigationSupport.swift
//  TAPCamDemo
//

import SwiftUI

struct DepthAlbumEdgeBackModifier: ViewModifier {
    let onReturn: () -> Void

    func body(content: Content) -> some View {
        content.simultaneousGesture(edgeBackGesture(), including: .gesture)
    }

    private func edgeBackGesture() -> some Gesture {
        DragGesture(minimumDistance: 16)
            .onChanged { value in
                guard value.startLocation.x <= AnalysisEdgeBackPolicy.edgeActivationWidth else {
                    return
                }
            }
            .onEnded { value in
                guard AnalysisEdgeBackPolicy.shouldReturn(
                    startX: value.startLocation.x,
                    translation: value.translation,
                    predictedTranslation: value.predictedEndTranslation
                ) else {
                    return
                }
                onReturn()
            }
    }
}

nonisolated struct DepthAlbumReturnScrollBookmark: Equatable, Sendable {
    let itemID: String
    let routeAnchor: CameraRouteAlbumAnchor
    let itemViewportY: CGFloat
}
