//
//  DepthAnalysisInputLoader.swift
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

/// Loads persisted HEIC bytes for the analysis surface and decodes them.
///
/// This is the boundary between UI state and storage. Photos asset identifiers
/// and pending capture identifiers stay private source selectors; the loader
/// returns only analysis-ready image/depth data or a generic user-facing error.
nonisolated struct DepthAnalysisInputLoader {
    typealias PhotosDataLoader = (String) async throws -> Data
    typealias PendingDataLoader = (String) async throws -> Data
    typealias AnalysisInputReader = (Data) throws -> TAPDepthAnalysisInput
    typealias LibraryRefreshPoster = () -> Void

    private let photosDataLoader: PhotosDataLoader
    private let pendingDataLoader: PendingDataLoader
    private let analysisInputReader: AnalysisInputReader
    private let libraryRefreshPoster: LibraryRefreshPoster

    init(
        photosDataLoader: @escaping PhotosDataLoader = { assetID in
            try await PhotoLibraryWriter.originalPhotoData(localIdentifier: assetID)
        },
        pendingDataLoader: @escaping PendingDataLoader = { captureID in
            try TAPPendingCaptureStore.shared.bestAvailableHEICData(captureID: captureID)
        },
        analysisInputReader: @escaping AnalysisInputReader = { data in
            try TAPDepthMapReader.analysisInput(from: data)
        },
        libraryRefreshPoster: @escaping LibraryRefreshPoster = {
            NotificationCenter.default.post(name: .tapLibraryDidChange, object: nil)
        }
    ) {
        self.photosDataLoader = photosDataLoader
        self.pendingDataLoader = pendingDataLoader
        self.analysisInputReader = analysisInputReader
        self.libraryRefreshPoster = libraryRefreshPoster
    }

    func loadInput(source: DepthAnalysisSource) async throws -> TAPDepthAnalysisInput {
        let data = try await heicData(for: source)
        try TAPDepthAnalysisInputValidation.validateHEICByteCount(data.count)
        return try analysisInputReader(data)
    }

    private func heicData(for source: DepthAnalysisSource) async throws -> Data {
        switch source {
        case .photosAsset(let assetID):
            return try await photosDataLoader(assetID)
        case .pendingCapture(let captureID):
            return try await pendingCaptureHEICData(captureID: captureID)
        }
    }

    private func pendingCaptureHEICData(captureID: String) async throws -> Data {
        do {
            return try await pendingDataLoader(captureID)
        } catch {
            libraryRefreshPoster()
            throw DepthAnalysisInputLoaderError.pendingCaptureTemporarilyUnavailable
        }
    }
}
