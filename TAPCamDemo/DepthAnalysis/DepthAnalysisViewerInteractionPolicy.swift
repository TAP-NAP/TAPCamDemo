//
//  DepthAnalysisViewerInteractionPolicy.swift
//  TAPCamDemo
//
//  Created by Codex on 2026/7/5.
//

import CoreGraphics
import ImageIO

nonisolated enum AnalysisEdgeBackPolicy {
    static let edgeActivationWidth: CGFloat = 24
    static let translationThreshold: CGFloat = 70
    static let predictedTranslationThreshold: CGFloat = 110
    static let dominanceRatio: CGFloat = 1.15

    static func shouldReturn(
        startX: CGFloat,
        translation: CGSize,
        predictedTranslation: CGSize
    ) -> Bool {
        guard startX <= edgeActivationWidth else {
            return false
        }
        guard translation.width > 0 || predictedTranslation.width > 0 else {
            return false
        }
        guard abs(translation.width) > abs(translation.height) * dominanceRatio else {
            return false
        }
        return translation.width > translationThreshold
            || predictedTranslation.width > predictedTranslationThreshold
    }
}

nonisolated enum DepthAnalysisViewerInteractionPolicy {
    static let zoomedScaleThreshold: CGFloat = 1.05
    static let maximumPhotoScale: CGFloat = 5
    static let doubleTapScale: CGFloat = 2.5
    static let nativePageSpacing: CGFloat = 18

    static func aspectFitRect(
        imageSize: CGSize?,
        orientation: CGImagePropertyOrientation,
        containerSize: CGSize
    ) -> CGRect {
        guard let imageSize,
              imageSize.width > 0,
              imageSize.height > 0,
              containerSize.width > 0,
              containerSize.height > 0 else {
            return CGRect(origin: .zero, size: containerSize)
        }

        let displayedSize = TAPImageOrientationMapper.displayedSize(
            nativeSize: imageSize,
            orientation: orientation
        )
        guard displayedSize.width > 0, displayedSize.height > 0 else {
            return CGRect(origin: .zero, size: containerSize)
        }

        let scale = min(
            containerSize.width / displayedSize.width,
            containerSize.height / displayedSize.height
        )
        let fittedSize = CGSize(
            width: displayedSize.width * scale,
            height: displayedSize.height * scale
        )
        return CGRect(
            x: (containerSize.width - fittedSize.width) * 0.5,
            y: (containerSize.height - fittedSize.height) * 0.5,
            width: fittedSize.width,
            height: fittedSize.height
        )
    }

    static func centeredToolContainerRect(
        imageSize: CGSize?,
        orientation: CGImagePropertyOrientation,
        viewportSize: CGSize
    ) -> CGRect {
        aspectFitRect(
            imageSize: imageSize,
            orientation: orientation,
            containerSize: viewportSize
        )
    }
}
