//
//  TAPCamLockedSessionContentWriter.swift
//  TAPCamDemo
//

import Foundation

nonisolated struct TAPCamLockedSessionContentWriter: Sendable {
    func write(_ photoData: Data, to directoryURL: URL) async throws -> URL {
        try await Task.detached(priority: .userInitiated) {
            let fileManager = FileManager.default
            try fileManager.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true
            )

            let fileName = "TAPCam-\(UUID().uuidString).heic"
            let finalURL = directoryURL.appendingPathComponent(fileName, isDirectory: false)
            let stagingURL = directoryURL.appendingPathComponent(
                ".\(fileName).\(UUID().uuidString).tmp",
                isDirectory: false
            )

            do {
                try photoData.write(to: stagingURL, options: .withoutOverwriting)
                try fileManager.moveItem(at: stagingURL, to: finalURL)
                return finalURL
            } catch {
                try? fileManager.removeItem(at: stagingURL)
                throw error
            }
        }.value
    }
}
