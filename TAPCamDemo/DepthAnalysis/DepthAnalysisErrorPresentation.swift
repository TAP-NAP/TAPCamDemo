//
//  DepthAnalysisErrorPresentation.swift
//  TAPCamDemo
//

import Foundation

/// Public-safe copy for DepthAnalysis and TAP Library visible errors.
///
/// Raw loader, Photos, pending-capture, reader, and local analysis errors can
/// contain asset identifiers, capture identifiers, URLs, paths, or low-level
/// descriptions. Views and view models should use this type before showing an
/// error string.
nonisolated enum DepthAnalysisErrorPresentation {
    static let planeInvalidSeedMessage = "No valid depth at this point."
    static let planeCalibrationMissingMessage = "Camera calibration missing."
    static let planeNotEnoughSamplesMessage = "Not enough nearby depth samples."
    static let planeNoStableRegionMessage = "No stable plane region found from this point."

    static func analysisLoadError(for error: Error) -> DepthAnalysisLoadErrorPresentation {
        if let analysisError = error as? TAPDepthAnalysisError {
            switch analysisError {
            case .missingDepthData:
                return DepthAnalysisLoadErrorPresentation(
                    title: "No Depth",
                    message: "Score 20/100. Depth unavailable for this capture.",
                    systemImage: "photo.badge.exclamationmark"
                )
            default:
                break
            }
        }

        if error is DepthAnalysisInputLoaderError {
            return DepthAnalysisLoadErrorPresentation(
                title: "Image unavailable",
                message: "Temporarily not available. Return to TAP Library; it will refresh automatically.",
                systemImage: "photo.badge.exclamationmark"
            )
        }

        return DepthAnalysisLoadErrorPresentation(
            title: "Unable to analyze image",
            message: "This image cannot be analyzed as a TAP depth photo.",
            systemImage: "exclamationmark.triangle"
        )
    }

    static func albumLoadErrorMessage(for _: Error) -> String {
        "Unable to load TAP Library. Check Photos access and try again."
    }

    static func emptyAlbumPhotosErrorMessage(for _: Error) -> String {
        "Unable to read the TAPCamDepth album. Check Photos access and try again."
    }

    static func planeSelectionErrorMessage(for error: Error) -> String {
        guard let planeGrowthError = error as? TAPPlaneGrowthError else {
            return "No stable plane region found from this point."
        }

        switch planeGrowthError {
        case .invalidSeed:
            return planeInvalidSeedMessage
        case .cameraCalibrationMissing:
            return planeCalibrationMissingMessage
        case .notEnoughNearbySamples:
            return planeNotEnoughSamplesMessage
        case .noPlaneRegion:
            return planeNoStableRegionMessage
        }
    }
}

nonisolated struct DepthAnalysisLoadErrorPresentation: Equatable, Sendable {
    let title: String
    let message: String
    let systemImage: String
}
