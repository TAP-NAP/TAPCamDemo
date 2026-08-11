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

/// Directional flick interpretation retained for non-pager surfaces and tests.
/// The visual photo/video carousel itself is owned by the native pager below.
nonisolated enum TAPLibraryViewerSwipePolicy {
    static let predictedTranslationThreshold: CGFloat = 80

    static func offset(
        translation: CGSize,
        predictedTranslation: CGSize
    ) -> Int? {
        guard abs(predictedTranslation.width) > abs(predictedTranslation.height),
              abs(predictedTranslation.width) > predictedTranslationThreshold else {
            return nil
        }
        return predictedTranslation.width < 0 ? 1 : -1
    }
}

/// Pure settlement policy shared by the photo and video UIKit pagers.
/// `UIScrollView` supplies the interactive movement and rubber-band physics;
/// this policy only decides whether the final resting page changes the
/// canonical Library cursor.
nonisolated enum TAPLibraryViewerPagingPolicy {
    enum Settlement: Equatable {
        case stay
        case move(Int)
    }

    static func settlement(
        currentIndex: Int,
        pageCount: Int,
        contentOffsetX: CGFloat,
        pageWidth: CGFloat
    ) -> Settlement {
        guard pageCount > 0,
              pageWidth.isFinite,
              pageWidth > 0,
              contentOffsetX.isFinite,
              (0..<pageCount).contains(currentIndex) else {
            return .stay
        }

        let rawDelta = (contentOffsetX / pageWidth) - CGFloat(currentIndex)
        let offset: Int
        if rawDelta > 0.5 {
            offset = 1
        } else if rawDelta < -0.5 {
            offset = -1
        } else {
            return .stay
        }

        guard (0..<pageCount).contains(currentIndex + offset) else {
            return .stay
        }
        return .move(offset)
    }

    static func pageContentSize(
        viewportSize: CGSize,
        pageSpacing: CGFloat
    ) -> CGSize {
        let spacing = min(pageSpacing, max(viewportSize.width - 1, 0))
        return CGSize(
            width: max(viewportSize.width - spacing, 1),
            height: viewportSize.height
        )
    }

    static func pageLocation(
        viewportLocation: CGPoint,
        viewportSize: CGSize,
        pageSpacing: CGFloat
    ) -> CGPoint {
        let spacing = min(pageSpacing, max(viewportSize.width - 1, 0))
        return CGPoint(
            x: viewportLocation.x - spacing * 0.5,
            y: viewportLocation.y
        )
    }
}

/// Keeps edge-back ownership stable across UIKit callback ordering. Sampling
/// a recognizer's instantaneous state from `scrollViewWillEndDragging` is not
/// sufficient because the edge recognizer may already have reached `.ended`.
nonisolated struct TAPLibraryViewerGestureArbitrationState {
    private(set) var edgeBackClaimed = false

    mutating func beginPaging(edgeBackIsActive: Bool) {
        if !edgeBackIsActive {
            edgeBackClaimed = false
        }
    }

    mutating func claimEdgeBack() {
        edgeBackClaimed = true
    }

    /// Returns whether this paging completion belongs to the edge-back
    /// gesture, then resets ownership for the next independent swipe.
    mutating func finishPaging() -> Bool {
        let claimed = edgeBackClaimed
        edgeBackClaimed = false
        return claimed
    }
}
