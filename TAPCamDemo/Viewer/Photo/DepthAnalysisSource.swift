//
//  DepthAnalysisSource.swift
//  TAPCamDemo
//

import Foundation

nonisolated enum DepthAnalysisSource: Hashable {
    case photosAsset(String)
    case pendingCapture(String)
}

nonisolated enum DepthAnalysisInputLoaderError: LocalizedError {
    case pendingCaptureTemporarilyUnavailable

    var errorDescription: String? {
        switch self {
        case .pendingCaptureTemporarilyUnavailable:
            "Pending capture temporarily unavailable."
        }
    }
}
