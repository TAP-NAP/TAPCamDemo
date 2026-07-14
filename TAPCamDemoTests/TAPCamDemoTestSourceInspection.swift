//
//  TAPCamDemoTestSourceInspection.swift
//  TAPCamDemoTests
//

import Foundation

enum TAPCamDemoTestSourceInspection {
    static var isSourceTreeAvailable: Bool {
        FileManager.default.fileExists(
            atPath: sourceRoot.appendingPathComponent("TAPCamDemo/App/TAPCamDemoApp.swift").path
        )
    }

    static func source(relativePath: String) throws -> String {
        let fileURL = sourceRoot.appendingPathComponent(relativePath)
        return try String(contentsOf: fileURL, encoding: .utf8)
    }

    static func swiftSourceRelativePaths(under relativeDirectory: String) throws -> [String] {
        let directoryURL = sourceRoot.appendingPathComponent(relativeDirectory, isDirectory: true)
        let files = try FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil
        )
        return files
            .filter { $0.pathExtension == "swift" }
            .map { "\(relativeDirectory)/\($0.lastPathComponent)" }
            .sorted()
    }

    static func swiftSourceRelativePathsRecursively(
        under relativeDirectory: String
    ) throws -> [String] {
        let directoryURL = sourceRoot.appendingPathComponent(relativeDirectory, isDirectory: true)
        guard let enumerator = FileManager.default.enumerator(
            at: directoryURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        let directoryPrefix = directoryURL.standardizedFileURL.path + "/"
        var relativePaths: [String] = []
        for case let fileURL as URL in enumerator where fileURL.pathExtension == "swift" {
            let standardizedPath = fileURL.standardizedFileURL.path
            guard standardizedPath.hasPrefix(directoryPrefix) else {
                continue
            }
            relativePaths.append(
                "\(relativeDirectory)/\(standardizedPath.dropFirst(directoryPrefix.count))"
            )
        }
        return relativePaths.sorted()
    }

    static func reflectedNames(in value: Any, depth: Int = 0) -> [String] {
        guard depth < 6 else {
            return []
        }

        let mirror = Mirror(reflecting: value)
        var names = [String(reflecting: type(of: value))]
        for child in mirror.children {
            if let label = child.label {
                names.append(label)
            }
            names.append(contentsOf: reflectedNames(in: child.value, depth: depth + 1))
        }
        return names
    }

    static func substring(in source: String, from start: String, to end: String) -> String? {
        guard let startRange = source.range(of: start),
              let endRange = source[startRange.lowerBound...].range(of: end) else {
            return nil
        }
        return String(source[startRange.lowerBound..<endRange.lowerBound])
    }

    private static var sourceRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
