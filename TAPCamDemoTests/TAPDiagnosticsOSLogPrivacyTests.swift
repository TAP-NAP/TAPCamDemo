//
//  TAPDiagnosticsOSLogPrivacyTests.swift
//  TAPCamDemoTests
//

import Foundation
import Testing

struct TAPDiagnosticsOSLogPrivacyTests {
    private static let privateLabels = Set([
            "assetID",
            "bundle",
            "captureID",
            "credentialName",
            "keyID",
            "manifestID"
    ])

    private static let reviewedPublicLabels = Set([
        "album",
        "assetIDPresent",
        "attempt",
        "attemptCount",
        "actualDimensions",
        "backend",
        "availableCodecs",
        "availableFileTypes",
        "bytes",
        "allowsCameraControl",
        "cameraPitch",
        "cameraRoll",
        "cameraScaleX",
        "cameraScaleY",
        "cameraScaleZ",
        "cameraCx",
        "cameraCy",
        "cameraFx",
        "cameraFy",
        "cameraX",
        "cameraY",
        "cameraYaw",
        "cameraZ",
        "codec",
        "configuredDimensions",
        "container",
        "controllerTargetX",
        "controllerTargetY",
        "controllerTargetZ",
        "current",
        "depthHeight",
        "depthMax",
        "depthMean",
        "depthMin",
        "depthWidth",
        "excludedCount",
        "filteredOutPointCount",
        "hasFailureReason",
        "hasLocation",
        "hasPairedVideo",
        "hasHighlight",
        "hasRGB",
        "hasThumbnail",
        "gestureRecognizerCount",
        "highlightPointCount",
        "interactionPitch",
        "interactionRoll",
        "interactionScaleX",
        "interactionScaleY",
        "interactionScaleZ",
        "interactionX",
        "interactionY",
        "interactionYaw",
        "interactionZ",
        "inertiaEnabled",
        "jobID",
        "label",
        "flashMode",
        "method",
        "name",
        "livePhotoMovie",
        "motionPitch",
        "motionRoll",
        "nextStatus",
        "operationID",
        "orientation",
        "orientedImageHeight",
        "orientedImageWidth",
        "path",
        "pendingCaptureIDPresent",
        "pendingJobCount",
        "fileType",
        "pointOfViewIsCameraNode",
        "pointSize",
        "previousStatus",
        "processedCount",
        "profile",
        "projectionM11",
        "projectionM22",
        "projectionM31",
        "projectionM32",
        "projectionM43",
        "proofBytes",
        "rawImageHeight",
        "rawImageWidth",
        "rawSampleCount",
        "readiness",
        "remainingJobs",
        "retryCount",
        "resourceCount",
        "rootPitch",
        "rootRoll",
        "rootScaleX",
        "rootScaleY",
        "rootScaleZ",
        "rootYaw",
        "sampleCount",
        "scannedCount",
        "signedBytes",
        "signedPhoto",
        "status",
        "statusCode",
        "succeeded",
        "selectedDimensions",
        "suppressesShutterSound",
        "supportedDimensions",
        "targetDepth",
        "timeoutSeconds",
        "touchCount",
        "unsignedBytes",
        "vertexMaxZ",
        "vertexMinZ",
        "vpnHint",
        "viewportHeight",
        "viewportWidth",
        "workerActive",
        "workerID",
        "artifactKind",
        "canAddOutput",
        "code",
        "configuring",
        "delayNs",
        "depthSamples",
        "file",
        "format",
        "paused",
        "phase",
        "previewSizedVideo",
        "previous",
        "reason",
        "recording",
        "recordsAudio",
        "recordsDepth",
        "synchronizedDepth",
        "unsupportedByActiveFormat",
        "videoBytes",
        "videoState",
        "albumCount",
        "audioDrops",
        "audioSamples",
        "calibration",
        "cameraBusy",
        "credentialPreparing",
        "depthBeforeVideoStart",
        "depthDeliverySupported",
        "depthEncodingDrops",
        "depthMetadataDrops",
        "depthOutputDrops",
        "depthOutputSamples",
        "dropCount",
        "domain",
        "duration",
        "filtered",
        "height",
        "mediaServicesReset",
        "pixelFormat",
        "requestedExportedCount",
        "resolvedExportedCount",
        "rgbFrames",
        "sourceRowStride",
        "stopReason",
        "timestamp",
        "videoDrops",
        "width",
        "writerError",
        "writerStatus",
        "deviceType",
        "running",
        "traceID"
    ])

    @Test func allTAPDiagnosticsLoggingFilesAreCoveredByHarness() throws {
        #expect(
            try Self.discoveredLoggingSourceFiles() == Self.criticalLoggingSourceFiles(),
            "Update TAPDiagnosticsOSLogPrivacyTests when adding a TAPDiagnostics logging file"
        )
    }

    @Test func osLogInterpolationsDeclareReviewedPrivacy() throws {
        var matchedPublicLabels = Set<String>()

        for interpolation in try Self.loggingInterpolations() {
            #expect(
                interpolation.privacy != nil,
                "\(interpolation.location) must declare explicit OSLog privacy"
            )

            if Self.privateLabels.contains(interpolation.label) {
                #expect(
                    interpolation.privacy == ".private",
                    "\(interpolation.location) must keep \(interpolation.label) private in OSLog"
                )
            }

            if interpolation.label == "error" {
                #expect(
                    interpolation.expression == "TAPDiagnostics.describe(error)",
                    "\(interpolation.location) must format public errors through TAPDiagnostics.describe"
                )
                #expect(
                    interpolation.privacy == ".public",
                    "\(interpolation.location) must keep formatted error summaries public"
                )
            } else if interpolation.label == "backend" {
                #expect(
                    interpolation.expression == "self.runtime.backendPublicSummary",
                    "\(interpolation.location) must log only the public App Attest backend summary"
                )
                #expect(
                    interpolation.privacy == ".public",
                    "\(interpolation.location) must keep the public App Attest backend summary public"
                )
                matchedPublicLabels.insert(interpolation.label)
            } else if interpolation.privacy == ".public" {
                #expect(
                    Self.reviewedPublicLabels.contains(interpolation.label),
                    "\(interpolation.location) uses unreviewed public OSLog label \(interpolation.label)"
                )
                matchedPublicLabels.insert(interpolation.label)
            }
        }

        #expect(
            matchedPublicLabels == Self.reviewedPublicLabels,
            "OSLog privacy harness should keep reviewed scalar diagnostics public"
        )
    }

    @Test func sensitiveOSLogLabelsAreNotAccidentallyBroadenedByPrefix() throws {
        let publicLabels = try Self.loggingInterpolations()
            .filter { $0.privacy == ".public" }
            .map(\.label)

        #expect(publicLabels.contains("assetIDPresent"))
        #expect(publicLabels.contains("pendingCaptureIDPresent"))
        #expect(!publicLabels.contains("assetID"))
        #expect(!publicLabels.contains("captureID"))
    }

    @Test func runtimeOutputLogsAreConditionallyCompiled() throws {
        let calls = try Self.runtimeOutputLoggingCalls()
        #expect(!calls.isEmpty, "Output log scanner should find existing runtime logs")

        for call in calls {
            #expect(
                call.isConditionallyCompiled,
                "\(call.location) must be inside #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS"
            )
        }
    }

    private static func loggingInterpolations() throws -> [OSLogInterpolation] {
        try criticalLoggingSourceFiles().flatMap { sourceFile in
            try loggingCalls(relativePath: sourceFile).flatMap(\.interpolations)
        }
    }

    private static func loggingCalls(relativePath: String) throws -> [OSLogCall] {
        let lines = try sourceLines(relativePath: relativePath)
        var calls: [OSLogCall] = []
        var activeLines: [String] = []
        var activeStartLine = 0
        var parenthesisDepth = 0

        for (index, line) in lines.enumerated() {
            if activeLines.isEmpty {
                guard line.contains("TAPDiagnostics.") else {
                    continue
                }
                activeLines = [line]
                activeStartLine = index + 1
                parenthesisDepth = parenthesisBalance(in: line)
            } else {
                activeLines.append(line)
                parenthesisDepth += parenthesisBalance(in: line)
            }

            if !activeLines.isEmpty, parenthesisDepth <= 0 {
                calls.append(
                    OSLogCall(
                        sourceFile: relativePath,
                        startLine: activeStartLine,
                        source: activeLines.joined(separator: "\n")
                    )
                )
                activeLines = []
                activeStartLine = 0
            }
        }

        return calls
    }

    private static func parenthesisBalance(in line: String) -> Int {
        line.reduce(0) { depth, character in
            switch character {
            case "(":
                return depth + 1
            case ")":
                return depth - 1
            default:
                return depth
            }
        }
    }

    private static func criticalLoggingSourceFiles() -> [String] {
        [
            "TAPCamDemo/App/AppAttestRuntime.swift",
            "TAPCamDemo/App/AppAttestRuntimeController.swift",
            "TAPCamDemo/App/StartupBackendSecurityPreflight.swift",
            "TAPCamDemo/CameraCapture/Output/AppAttestCaptureAssertionSigner.swift",
            "TAPCamDemo/CameraCapture/Output/EmbeddedPhotoPackager.swift",
            "TAPCamDemo/CameraCapture/Output/PhotoLibraryWriter.swift",
            "TAPCamDemo/CameraCapture/Runtime/AVFoundationSingleCamPhotoProvider.swift",
            "TAPCamDemo/CameraCapture/Runtime/CameraManualFocusPreviewStream.swift",
            "TAPCamDemo/CameraCapture/Runtime/CaptureSessionController.swift",
            "TAPCamDemo/CameraCapture/Runtime/TAPVideoRecorder.swift",
            "TAPCamDemo/CameraCapture/Runtime/TAPVideoRecorderDiagnostics.swift",
            "TAPCamDemo/CameraCapture/UI/CameraViewModel+Capture.swift",
            "TAPCamDemo/CameraCapture/UI/CameraViewModel+VideoCapture.swift",
            "TAPCamDemo/CameraCapture/UI/CaptureLifecycleCoordinator.swift",
            "TAPCamDemo/DepthAnalysis/AnalysisTools/DepthPointCloudPreview.swift",
            "TAPCamDemo/DepthAnalysis/AppAttestSignatureVerification.swift",
            "TAPCamDemo/DepthAnalysis/AppAttestSignatureVerificationPanel.swift",
            "TAPCamDemo/DepthAnalysis/DepthAnalysisShareSheet.swift",
            "TAPCamDemo/DepthAnalysis/DepthAnalysisView.swift",
            "TAPCamDemo/DepthAnalysis/TAPVideoDepthPlaybackView.swift",
            "TAPCamDemo/MediaLibrary/LibraryMediaFetching.swift",
            "TAPCamDemo/TAPLibrary/AppAttestPendingCaptureSigner.swift",
            "TAPCamDemo/TAPLibrary/PhotoLibraryPendingCaptureExporter.swift",
            "TAPCamDemo/TAPLibrary/TAPPendingCaptureMaintenance.swift",
            "TAPCamDemo/TAPLibrary/TAPPendingCaptureProcessor.swift",
            "TAPCamDemo/TAPLibrary/TAPPendingCaptureStore.swift"
        ]
    }

    private static func discoveredLoggingSourceFiles() throws -> [String] {
        let root = try repositoryRoot()
        let appURL = root.appendingPathComponent("TAPCamDemo")
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: appURL,
            includingPropertiesForKeys: nil
        ) else {
            return []
        }

        var sourceFiles: [String] = []
        for case let fileURL as URL in enumerator where fileURL.pathExtension == "swift" {
            let source = try String(contentsOf: fileURL, encoding: .utf8)
            if source.contains("TAPDiagnostics.") {
                sourceFiles.append(relativePath(for: fileURL, root: root))
            }
        }
        return sourceFiles.sorted()
    }

    private static func runtimeOutputLoggingCalls() throws -> [RuntimeOutputLogCall] {
        let root = try repositoryRoot()
        let appURL = root.appendingPathComponent("TAPCamDemo")
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: appURL,
            includingPropertiesForKeys: nil
        ) else {
            return []
        }

        var calls: [RuntimeOutputLogCall] = []
        for case let fileURL as URL in enumerator where fileURL.pathExtension == "swift" {
            let relativePath = relativePath(for: fileURL, root: root)
            let lines = try sourceLines(relativePath: relativePath)
            for (index, line) in lines.enumerated() where lineContainsRuntimeOutputLogCall(line) {
                calls.append(
                    RuntimeOutputLogCall(
                        sourceFile: relativePath,
                        lineNumber: index + 1,
                        isConditionallyCompiled: lineIsInsideReleaseDiagnosticsConditional(
                            lineNumber: index + 1,
                            lines: lines
                        )
                    )
                )
            }
        }
        return calls.sorted { lhs, rhs in
            lhs.location < rhs.location
        }
    }

    private static func lineContainsRuntimeOutputLogCall(_ line: String) -> Bool {
        let containsTAPDiagnosticsCall = line.range(
            of: #"TAPDiagnostics\.[A-Za-z]+\.(debug|info|notice|warning|error|fault)\s*\("#,
            options: .regularExpression
        ) != nil
        let containsStandardOutputCall = line.range(
            of: #"\b(print|debugPrint|NSLog|os_log)\s*\("#,
            options: .regularExpression
        ) != nil
        return containsTAPDiagnosticsCall || containsStandardOutputCall
    }

    private static func lineIsInsideReleaseDiagnosticsConditional(
        lineNumber: Int,
        lines: [String]
    ) -> Bool {
        var conditions: [String] = []
        for line in lines.prefix(max(lineNumber - 1, 0)) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("#if ") {
                conditions.append(String(trimmed.dropFirst("#if ".count)))
            } else if trimmed.hasPrefix("#elseif ") {
                guard !conditions.isEmpty else {
                    continue
                }
                conditions[conditions.count - 1] = String(trimmed.dropFirst("#elseif ".count))
            } else if trimmed == "#else" {
                guard !conditions.isEmpty else {
                    continue
                }
                conditions[conditions.count - 1] = "#else"
            } else if trimmed == "#endif" {
                _ = conditions.popLast()
            }
        }
        return conditions.contains(where: isReleaseDiagnosticsCondition)
    }

    private static func isReleaseDiagnosticsCondition(_ condition: String) -> Bool {
        let compactCondition = condition
            .replacingOccurrences(of: " ", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "()"))
        return compactCondition == "DEBUG||TAP_ENABLE_RELEASE_DIAGNOSTICS"
    }

    private static func relativePath(for fileURL: URL, root: URL) -> String {
        let rootPath = root.standardizedFileURL.path
        let filePath = fileURL.standardizedFileURL.path
        guard filePath.hasPrefix(rootPath + "/") else {
            return filePath
        }
        return String(filePath.dropFirst(rootPath.count + 1))
    }

    fileprivate static func interpolations(
        in source: String,
        sourceFile: String,
        startLine: Int
    ) -> [OSLogInterpolation] {
        var output: [OSLogInterpolation] = []
        var searchIndex = source.startIndex

        while let markerRange = source.range(of: "=\\(", range: searchIndex..<source.endIndex) {
            guard let labelRange = labelRange(before: markerRange.lowerBound, in: source) else {
                searchIndex = markerRange.upperBound
                continue
            }
            let bodyStart = markerRange.upperBound
            guard let bodyEnd = interpolationEnd(startingAt: bodyStart, in: source) else {
                searchIndex = markerRange.upperBound
                continue
            }

            let body = String(source[bodyStart..<bodyEnd])
            output.append(
                OSLogInterpolation(
                    sourceFile: sourceFile,
                    lineNumber: startLine + source[..<markerRange.lowerBound].filter { $0 == "\n" }.count,
                    label: String(source[labelRange]),
                    expression: expression(in: body),
                    privacy: privacy(in: body)
                )
            )
            searchIndex = source.index(after: bodyEnd)
        }

        return output
    }

    private static func labelRange(
        before markerStart: String.Index,
        in source: String
    ) -> Range<String.Index>? {
        var labelStart = markerStart
        while labelStart > source.startIndex {
            let previous = source.index(before: labelStart)
            guard isLabelCharacter(source[previous]) else {
                break
            }
            labelStart = previous
        }
        guard labelStart < markerStart else {
            return nil
        }
        return labelStart..<markerStart
    }

    private static func interpolationEnd(
        startingAt bodyStart: String.Index,
        in source: String
    ) -> String.Index? {
        var depth = 1
        var index = bodyStart

        while index < source.endIndex {
            switch source[index] {
            case "(":
                depth += 1
            case ")":
                depth -= 1
                if depth == 0 {
                    return index
                }
            default:
                break
            }
            index = source.index(after: index)
        }

        return nil
    }

    private static func expression(in interpolationBody: String) -> String {
        interpolationBody
            .components(separatedBy: ", privacy:")
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? interpolationBody
    }

    private static func privacy(in interpolationBody: String) -> String? {
        guard let privacyRange = interpolationBody.range(of: "privacy:") else {
            return nil
        }
        let suffix = interpolationBody[privacyRange.upperBound...]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if suffix.hasPrefix(".private") {
            return ".private"
        }
        if suffix.hasPrefix(".public") {
            return ".public"
        }
        return String(suffix.split(separator: ",").first ?? "")
    }

    private static func isLabelCharacter(_ character: Character) -> Bool {
        guard character.unicodeScalars.count == 1,
              let value = character.unicodeScalars.first?.value else {
            return false
        }
        return (48...57).contains(value)
            || (65...90).contains(value)
            || (97...122).contains(value)
    }

    private static func sourceLines(relativePath: String) throws -> [String] {
        let fileURL = try repositoryRoot().appendingPathComponent(relativePath)
        let source = try String(contentsOf: fileURL, encoding: .utf8)
        return source.components(separatedBy: .newlines)
    }

    private static func repositoryRoot(
        startingAt filePath: String = #filePath
    ) throws -> URL {
        var directory = URL(fileURLWithPath: filePath).deletingLastPathComponent()
        let fileManager = FileManager.default

        while directory.path != "/" {
            let projectPath = directory.appendingPathComponent("TAPCamDemo.xcodeproj").path
            let testsPath = directory.appendingPathComponent("TAPCamDemoTests").path
            let diagnosticsPath = directory
                .appendingPathComponent("TAPCamDemo/App/AppAttestRuntime.swift")
                .path
            if fileManager.fileExists(atPath: projectPath),
               fileManager.fileExists(atPath: testsPath),
               fileManager.fileExists(atPath: diagnosticsPath) {
                return directory
            }
            directory.deleteLastPathComponent()
        }

        throw TAPDiagnosticsOSLogPrivacyTestError.repositoryRootNotFound(filePath)
    }
}

private struct OSLogCall {
    let sourceFile: String
    let startLine: Int
    let source: String

    var interpolations: [OSLogInterpolation] {
        TAPDiagnosticsOSLogPrivacyTests.interpolations(
            in: source,
            sourceFile: sourceFile,
            startLine: startLine
        )
    }
}

private struct OSLogInterpolation {
    let sourceFile: String
    let lineNumber: Int
    let label: String
    let expression: String
    let privacy: String?

    var location: String {
        "\(sourceFile):\(lineNumber)"
    }
}

private struct RuntimeOutputLogCall {
    let sourceFile: String
    let lineNumber: Int
    let isConditionallyCompiled: Bool

    var location: String {
        "\(sourceFile):\(lineNumber)"
    }
}

private enum TAPDiagnosticsOSLogPrivacyTestError: LocalizedError {
    case repositoryRootNotFound(String)

    var errorDescription: String? {
        switch self {
        case .repositoryRootNotFound(let filePath):
            return "Could not find TAPCamDemo.xcodeproj above \(filePath)."
        }
    }
}
