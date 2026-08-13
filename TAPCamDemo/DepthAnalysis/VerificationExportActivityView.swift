//
//  VerificationExportActivityView.swift
//  TAPCamDemo
//

import OSLog
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct VerificationExportActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]
    private let retainedShareArtifact: TAPNAPShareArtifact?
    private let typedShareArtifact: TAPNAPShareArtifact?
    private let preparedSharePresentation: TAPShareActivityPresentation?
    var onAppeared: (() -> Void)?
    var onFinished: (() -> Void)?
    var onDismantled: (() -> Void)?

    init(
        activityItems: [Any],
        retainedShareArtifact: TAPNAPShareArtifact? = nil,
        onAppeared: (() -> Void)? = nil,
        onFinished: (() -> Void)? = nil,
        onDismantled: (() -> Void)? = nil
    ) {
        self.activityItems = activityItems
        self.retainedShareArtifact = retainedShareArtifact
        typedShareArtifact = nil
        preparedSharePresentation = nil
        self.onAppeared = onAppeared
        self.onFinished = onFinished
        self.onDismantled = onDismantled
    }

    init(
        shareArtifact: TAPNAPShareArtifact,
        onAppeared: (() -> Void)? = nil,
        onFinished: (() -> Void)? = nil,
        onDismantled: (() -> Void)? = nil
    ) {
        activityItems = []
        retainedShareArtifact = shareArtifact
        typedShareArtifact = shareArtifact
        preparedSharePresentation = nil
        self.onAppeared = onAppeared
        self.onFinished = onFinished
        self.onDismantled = onDismantled
    }

    init(
        preparedSharePresentation: TAPShareActivityPresentation,
        onAppeared: (() -> Void)? = nil,
        onFinished: (() -> Void)? = nil,
        onDismantled: (() -> Void)? = nil
    ) {
        activityItems = []
        retainedShareArtifact = preparedSharePresentation.artifact
        typedShareArtifact = nil
        self.preparedSharePresentation = preparedSharePresentation
        self.onAppeared = onAppeared
        self.onFinished = onFinished
        self.onDismantled = onDismantled
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller: TAPObservedActivityViewController
        if let preparedSharePresentation {
            controller = preparedSharePresentation.controller
        } else if let typedShareArtifact {
            controller = TAPObservedActivityViewController(
                activityItemsConfiguration: Self.activityItemsConfiguration(
                    for: typedShareArtifact
                )
            )
        } else {
            controller = TAPObservedActivityViewController(
                activityItems: activityItems,
                applicationActivities: nil
            )
        }
        context.coordinator.onDismantled = onDismantled
        controller.onFirstAppearance = {
            Task { @MainActor in
                onAppeared?()
            }
        }
        controller.completionWithItemsHandler = { _, _, _, _ in
            _ = retainedShareArtifact
            Task { @MainActor in
                onFinished?()
            }
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {
        context.coordinator.onDismantled = onDismantled
    }

    static func dismantleUIViewController(
        _ uiViewController: UIActivityViewController,
        coordinator: Coordinator
    ) {
        coordinator.onDismantled?()
        coordinator.onDismantled = nil
    }

    @MainActor
    static func activityItemsConfiguration(
        for artifact: TAPNAPShareArtifact
    ) -> UIActivityItemsConfiguration {
        let provider = NSItemProvider()
        provider.suggestedName = artifact.fileURL.lastPathComponent
        for typeIdentifier in artifact.activityTypeIdentifiers {
            provider.registerFileRepresentation(
                forTypeIdentifier: typeIdentifier,
                fileOptions: [.openInPlace],
                visibility: .all
            ) { completion in
                // The provider and activity controller retain this closure;
                // capturing the artifact therefore keeps its temporary file
                // lease alive until the system has finished requesting it.
                _ = artifact
                completion(artifact.fileURL, false, nil)
                return nil
            }
        }
        return UIActivityItemsConfiguration(itemProviders: [provider])
    }

    final class Coordinator {
        var onDismantled: (() -> Void)?
    }
}

@MainActor
final class TAPShareActivityPresentation: Identifiable {
    let artifact: TAPNAPShareArtifact
    let controller: TAPObservedActivityViewController
    let constructionDuration: Duration

    var id: UUID { artifact.id }

    init(
        artifact: TAPNAPShareArtifact,
        controller: TAPObservedActivityViewController,
        constructionDuration: Duration
    ) {
        self.artifact = artifact
        self.controller = controller
        self.constructionDuration = constructionDuration
    }

    static func prepare(for artifact: TAPNAPShareArtifact) -> Self {
        let clock = ContinuousClock()
        let startedAt = clock.now
        let controller = TAPObservedActivityViewController(
            activityItemsConfiguration: VerificationExportActivityView
                .activityItemsConfiguration(for: artifact)
        )
        let duration = startedAt.duration(to: clock.now)
        #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
        TAPDiagnostics.sharePackaging.info(
            "tap_share_activity_controller_created kind=\(artifact.kind.rawValue, privacy: .public) durationBucket=\(Self.durationBucket(duration), privacy: .public) providerMode=typed"
        )
        #endif
        return Self(
            artifact: artifact,
            controller: controller,
            constructionDuration: duration
        )
    }

    nonisolated private static func durationBucket(_ duration: Duration) -> String {
        switch duration {
        case ..<Duration.milliseconds(50):
            return "under50ms"
        case ..<Duration.milliseconds(200):
            return "50to199ms"
        case ..<Duration.seconds(1):
            return "200to999ms"
        default:
            return "over1s"
        }
    }
}

final class TAPObservedActivityViewController: UIActivityViewController {
    var onFirstAppearance: (() -> Void)?
    private var hasReportedAppearance = false

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !hasReportedAppearance else {
            return
        }
        hasReportedAppearance = true
        onFirstAppearance?()
    }
}

private extension TAPNAPShareArtifact {
    var activityTypeIdentifiers: [String] {
        switch kind {
        case .tapnapPackage:
            [
                UTType.tapnapCapturePackage.identifier,
                UTType.zip.identifier
            ]
        case .image:
            [
                UTType(filenameExtension: fileURL.pathExtension)?.identifier
                    ?? UTType.image.identifier
            ]
        case .video:
            [
                UTType(filenameExtension: fileURL.pathExtension)?.identifier
                    ?? UTType.movie.identifier
            ]
        }
    }
}
