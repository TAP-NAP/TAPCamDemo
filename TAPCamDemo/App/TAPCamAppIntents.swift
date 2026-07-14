//
//  TAPCamAppIntents.swift
//  TAPCamDemo
//

import AppIntents
import Foundation

enum TAPCamIntentDestination: String, AppEnum {
    case camera
    case tapLibrary

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "TAPCam Destination"
    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .camera: "Camera",
        .tapLibrary: "TAP Library"
    ]

    var handoffDestination: TAPCamIntentHandoffDestination {
        switch self {
        case .camera:
            .camera
        case .tapLibrary:
            .tapLibrary
        }
    }
}

nonisolated struct CaptureScoreIntentSnapshot: Equatable, Identifiable, Sendable {
    let id: String
    let capturedAt: Date
    let status: TAPPendingCaptureStatus
    let summary: CaptureScoreSummary

    var title: String {
        "Latest capture score"
    }

    var subtitle: String {
        "\(summary.scoreText) · \(summary.grade) · \(statusLabel)"
    }

    var statusLabel: String {
        switch status {
        case .pending:
            "Pending"
        case .waitingNetwork:
            "Waiting for network"
        case .signing:
            "Signing"
        case .signed:
            "Signed"
        case .exporting:
            "Exporting"
        case .exported:
            "Exported"
        case .failedRetryable:
            "Needs retry"
        case .failedTerminal:
            "Validation failed"
        }
    }

    var capturedAtLabel: String {
        Self.dateFormatter.string(from: capturedAt)
    }

    var dialogText: String {
        "\(title): \(summary.scoreText), \(summary.grade). \(summary.detail). Status: \(statusLabel). Captured \(capturedAtLabel)."
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()
}

nonisolated struct CaptureScoreIntentService: Sendable {
    var records: @Sendable () async throws -> [TAPPendingCaptureRecord]
    var token: @Sendable (String) -> String

    init(
        store: TAPPendingCaptureStore = .shared
    ) {
        self.records = {
            try await store.allRecords()
        }
        self.token = { rawValue in
            CameraRouteFileContextStore().token(for: rawValue)
        }
    }

    init(
        records: @escaping @Sendable () async throws -> [TAPPendingCaptureRecord],
        token: @escaping @Sendable (String) -> String
    ) {
        self.records = records
        self.token = token
    }

    func latestScore() async throws -> CaptureScoreIntentSnapshot? {
        try await scoreSnapshots().first
    }

    func scoreSnapshots(
        matching identifiers: [CaptureScoreIntentSnapshot.ID]? = nil
    ) async throws -> [CaptureScoreIntentSnapshot] {
        let identifierSet = identifiers.map(Set.init)
        return try await records()
            .sorted { $0.capturedAt > $1.capturedAt }
            .map(snapshot(for:))
            .filter { snapshot in
                identifierSet?.contains(snapshot.id) ?? true
            }
    }

    private func snapshot(for record: TAPPendingCaptureRecord) -> CaptureScoreIntentSnapshot {
        CaptureScoreIntentSnapshot(
            id: token("capture-score:\(record.captureID)"),
            capturedAt: record.capturedAt,
            status: record.status,
            summary: record.captureScoreSummary
        )
    }
}

struct CaptureScoreEntity: AppEntity, Identifiable {
    let snapshot: CaptureScoreIntentSnapshot

    var id: String {
        snapshot.id
    }

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Capture Score"
    static let defaultQuery = CaptureScoreQuery()

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(snapshot.title)",
            subtitle: "\(snapshot.subtitle)"
        )
    }
}

struct CaptureScoreQuery: EntityQuery {
    var service = CaptureScoreIntentService()

    func entities(for identifiers: [CaptureScoreEntity.ID]) async throws -> [CaptureScoreEntity] {
        try await service.scoreSnapshots(matching: identifiers).map(CaptureScoreEntity.init)
    }

    func suggestedEntities() async throws -> [CaptureScoreEntity] {
        try await service.scoreSnapshots().prefix(5).map(CaptureScoreEntity.init)
    }

    func defaultResult() async -> CaptureScoreEntity? {
        guard let snapshot = try? await service.latestScore() else {
            return nil
        }
        return CaptureScoreEntity(snapshot: snapshot)
    }
}

struct OpenTAPCameraIntent: AppIntent {
    static let title: LocalizedStringResource = "Open TAP Camera"
    static let description = IntentDescription("Open TAPCam to the selected camera workflow.")
    static let openAppWhenRun = true

    @Parameter(title: "Destination")
    var destination: TAPCamIntentDestination

    static var parameterSummary: some ParameterSummary {
        Summary("Open \(\.$destination)")
    }

    init() {
        self.destination = .camera
    }

    init(destination: TAPCamIntentDestination) {
        self.destination = destination
    }

    func perform() async throws -> some IntentResult {
        TAPCamIntentHandoffStore().saveHandoff(TAPCamIntentHandoff(
            destination: destination.handoffDestination
        ))
        return .result()
    }
}

struct ShowLatestCaptureScoreIntent: AppIntent {
    static let title: LocalizedStringResource = "Show Latest Capture Score"
    static let description = IntentDescription("Show the latest TAP capture score without opening the app.")
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let service = CaptureScoreIntentService()
        guard let snapshot = try await service.latestScore() else {
            return .result(dialog: "No capture score is available yet.")
        }
        return .result(dialog: IntentDialog(stringLiteral: snapshot.dialogText))
    }
}

struct ShowCaptureScoreIntent: AppIntent {
    static let title: LocalizedStringResource = "Show Capture Score"
    static let description = IntentDescription("Show a selected TAP capture score without opening the app.")
    static let openAppWhenRun = false

    @Parameter(title: "Capture Score")
    var captureScore: CaptureScoreEntity?

    static var parameterSummary: some ParameterSummary {
        Summary("Show \(\.$captureScore)")
    }

    init() {
        self.captureScore = nil
    }

    init(captureScore: CaptureScoreEntity?) {
        self.captureScore = captureScore
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let scoreEntity: CaptureScoreEntity?
        if let captureScore {
            scoreEntity = captureScore
        } else {
            scoreEntity = await CaptureScoreQuery().defaultResult()
        }

        guard let scoreEntity else {
            return .result(dialog: "No capture score is available yet.")
        }
        return .result(dialog: IntentDialog(stringLiteral: scoreEntity.snapshot.dialogText))
    }
}

struct TAPCamAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenTAPCameraIntent(destination: .camera),
            phrases: [
                "Open TAP Camera in \(.applicationName)",
                "Start TAP Camera in \(.applicationName)"
            ],
            shortTitle: "Open Camera",
            systemImageName: "camera"
        )

        AppShortcut(
            intent: OpenTAPCameraIntent(destination: .tapLibrary),
            phrases: [
                "Open TAP Library in \(.applicationName)",
                "Show TAP Library in \(.applicationName)"
            ],
            shortTitle: "TAP Library",
            systemImageName: "photo.stack"
        )

        AppShortcut(
            intent: ShowLatestCaptureScoreIntent(),
            phrases: [
                "Show TAP capture score in \(.applicationName)",
                "Check latest TAP score in \(.applicationName)"
            ],
            shortTitle: "Capture Score",
            systemImageName: "gauge.with.dots.needle.67percent"
        )

        AppShortcut(
            intent: ShowCaptureScoreIntent(),
            phrases: [
                "Show a TAP capture score in \(.applicationName)",
                "Check a TAP score in \(.applicationName)"
            ],
            shortTitle: "Score Detail",
            systemImageName: "list.bullet.rectangle"
        )
    }
}
