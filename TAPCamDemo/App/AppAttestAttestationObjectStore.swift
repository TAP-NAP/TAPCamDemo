//
//  AppAttestAttestationObjectStore.swift
//  TAPCamDemo
//

import Foundation

nonisolated protocol AppAttestAttestationObjectStoring {
    func save(_ data: Data) throws
    func load() throws -> Data
    func delete() throws
}

nonisolated struct AppAttestAttestationObjectStore: AppAttestAttestationObjectStoring {
    private let baseDirectoryURL: URL?

    init(baseDirectoryURL: URL? = nil) {
        self.baseDirectoryURL = baseDirectoryURL
    }

    func save(_ data: Data) throws {
        try data.write(to: fileURL(), options: .atomic)
    }

    func load() throws -> Data {
        try Data(contentsOf: fileURL())
    }

    func delete() throws {
        let url = try fileURL()
        guard FileManager.default.fileExists(atPath: url.path) else {
            return
        }
        try FileManager.default.removeItem(at: url)
    }

    private func fileURL() throws -> URL {
        let directoryURL = try appAttestDirectoryURL()
        return directoryURL.appendingPathComponent("attestationObject.cbor", isDirectory: false)
    }

    private func appAttestDirectoryURL() throws -> URL {
        let baseURL: URL
        if let baseDirectoryURL {
            baseURL = baseDirectoryURL
        } else {
            baseURL = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
        }

        let directoryURL = baseURL.appendingPathComponent("AppAttest", isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        return directoryURL
    }
}
