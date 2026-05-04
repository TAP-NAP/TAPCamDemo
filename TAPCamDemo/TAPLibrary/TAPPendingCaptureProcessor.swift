//
//  TAPPendingCaptureProcessor.swift
//  TAPCamDemo
//

@preconcurrency import AVFoundation
import AppAttestKit
import Foundation
import UIKit

/// Serial background processor for staged TAP depth HEIC captures.
///
/// The worker only reads bundle state from `TAPPendingCaptureStore`; it does not
/// depend on the current camera UI selection. This is the important split that
/// lets captures survive locked-screen intake, no-network sessions, and app
/// restarts before App Attest is available.
actor TAPPendingCaptureProcessor {
    static let shared = TAPPendingCaptureProcessor()

    private var isProcessing = false

    func processPendingCaptures(
        store: TAPPendingCaptureStore = .shared,
        appAttestClient: any AppAttestClient
    ) async {
        guard !isProcessing else {
            return
        }

        isProcessing = true
        defer { isProcessing = false }

        guard await protectedDataIsAvailable() else {
            return
        }

        try? await reconcile(store: store)

        let candidates: [TAPPendingCaptureRecord]
        do {
            candidates = try await store.processingCandidates()
        } catch {
            return
        }

        let signer = AppAttestCaptureAssertionSigner(client: appAttestClient)
        for candidate in candidates {
            await process(candidate, store: store, signer: signer)
        }

        try? await store.cleanupExportedLargeFiles()
    }

    func reconcile(store: TAPPendingCaptureStore = .shared) async throws {
        let records = try await store.allRecords()
        for record in records {
            switch record.status {
            case .exported:
                continue
            case .exporting:
                if let assetID = try? await PhotoLibraryWriter.depthAssetIdentifier(captureID: record.captureID) {
                    _ = try await store.markExported(captureID: record.captureID, assetLocalIdentifier: assetID)
                }
            case .pending, .waitingNetwork, .signing, .signed, .failedRetryable:
                continue
            }
        }
        try await store.cleanupExportedLargeFiles()
    }

    private func process(
        _ record: TAPPendingCaptureRecord,
        store: TAPPendingCaptureStore,
        signer: AppAttestCaptureAssertionSigner
    ) async {
        do {
            switch record.status {
            case .pending, .waitingNetwork, .signing, .failedRetryable:
                if record.signedHEICFilename != nil {
                    try await export(record, store: store)
                } else {
                    let signedRecord = try await sign(record, store: store, signer: signer)
                    try await export(signedRecord, store: store)
                }

            case .signed, .exporting:
                try await export(record, store: store)

            case .exported:
                return
            }
        } catch {
            let status: TAPPendingCaptureStatus = Self.isNetworkUnavailable(error) ? .waitingNetwork : .failedRetryable
            _ = try? await store.updateStatus(
                captureID: record.captureID,
                status: status,
                failureReason: error.localizedDescription,
                incrementsRetryCount: true
            )
        }
    }

    private func sign(
        _ record: TAPPendingCaptureRecord,
        store: TAPPendingCaptureStore,
        signer: AppAttestCaptureAssertionSigner
    ) async throws -> TAPPendingCaptureRecord {
        _ = try await store.updateStatus(captureID: record.captureID, status: .signing)

        let unsignedData = try await store.unsignedHEICData(captureID: record.captureID)
        let manifest = try TAPDepthHEICReader.decodedManifest(from: unsignedData)
        guard let depthData = try TAPDepthHEICReader.depthData(from: unsignedData) else {
            throw TAPDepthCaptureError.missingDepthData
        }

        let digest = try CaptureContentDigest.make(
            manifest: manifest,
            baseHEICData: unsignedData,
            depthData: depthData,
            capturedAt: record.capturedAt
        )
        let assertionProof = try await signer.sign(contentDigest: digest, capturedAt: record.capturedAt)
        let signedManifest = TAPDepthManifest(payload: manifest.payload, proofs: [assertionProof.proof])
        let signedData = try TAPDepthHEICWriter.injectingManifest(signedManifest, into: unsignedData)
        return try await store.storeSignedHEIC(signedData, captureID: record.captureID)
    }

    private func export(_ record: TAPPendingCaptureRecord, store: TAPPendingCaptureStore) async throws {
        if let existingAssetID = try? await PhotoLibraryWriter.depthAssetIdentifier(captureID: record.captureID) {
            _ = try await store.markExported(captureID: record.captureID, assetLocalIdentifier: existingAssetID)
            return
        }

        _ = try await store.updateStatus(captureID: record.captureID, status: .exporting)
        let signedData = try await store.signedHEICData(captureID: record.captureID)
        let assetID = try await PhotoLibraryWriter.saveDepthHEIC(
            signedData,
            capturedAt: record.capturedAt,
            location: record.location?.clLocation
        )
        _ = try await store.markExported(captureID: record.captureID, assetLocalIdentifier: assetID)
    }

    private func protectedDataIsAvailable() async -> Bool {
        await MainActor.run {
            UIApplication.shared.isProtectedDataAvailable
        }
    }

    private static func isNetworkUnavailable(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            return [
                NSURLErrorNotConnectedToInternet,
                NSURLErrorNetworkConnectionLost,
                NSURLErrorCannotFindHost,
                NSURLErrorCannotConnectToHost,
                NSURLErrorTimedOut,
                NSURLErrorInternationalRoamingOff,
                NSURLErrorDataNotAllowed
            ].contains(nsError.code)
        }

        let message = error.localizedDescription.lowercased()
        return message.contains("network")
            || message.contains("internet")
            || message.contains("offline")
            || message.contains("timed out")
    }
}
