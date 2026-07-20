//
//  TAPLocalArtifactStoragePolicy.swift
//  TAPCamDemo
//

import Foundation

/// Shared filesystem rules for app-private photo artifacts and derivatives.
///
/// Read this file before adding another local HEIC, manifest, thumbnail, or
/// cache write. The policy keeps protection behavior explicit at the write
/// boundary instead of relying on each call site to remember file attributes.
nonisolated struct TAPLocalArtifactStoragePolicy {
    let fileProtectionType: FileProtectionType

    static let privatePhotoArtifact = TAPLocalArtifactStoragePolicy(
        fileProtectionType: .completeUntilFirstUserAuthentication
    )

    func createDirectoryIfNeeded(at url: URL, fileManager: FileManager = .default) throws {
        if !fileManager.fileExists(atPath: url.path) {
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        }
        try protectExistingItem(at: url, fileManager: fileManager)
    }

    func write(
        _ data: Data,
        to url: URL,
        options: Data.WritingOptions = [.atomic],
        fileManager: FileManager = .default
    ) throws {
        try data.write(to: url, options: options)
        try protectExistingItem(at: url, fileManager: fileManager)
    }

    func protectDirectoryTree(at url: URL, fileManager: FileManager = .default) throws {
        try protectExistingItem(at: url, fileManager: fileManager)

        guard (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else {
            return
        }

        let childURLs = try fileManager.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        for childURL in childURLs {
            try protectDirectoryTree(at: childURL, fileManager: fileManager)
        }
    }

    private func protectExistingItem(at url: URL, fileManager: FileManager) throws {
        guard fileManager.fileExists(atPath: url.path) else {
            return
        }
        try fileManager.setAttributes(
            [.protectionKey: fileProtectionType],
            ofItemAtPath: url.path
        )
    }
}
