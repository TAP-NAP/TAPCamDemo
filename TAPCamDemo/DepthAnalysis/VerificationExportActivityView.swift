//
//  VerificationExportActivityView.swift
//  TAPCamDemo
//

import OSLog
import SwiftUI
import UIKit

struct VerificationExportActivityView: UIViewControllerRepresentable {
    private let preparedSharePresentation: TAPShareActivityPresentation
    var onAppeared: (() -> Void)?
    var onDismantled: (() -> Void)?

    init(
        preparedSharePresentation: TAPShareActivityPresentation,
        onAppeared: (() -> Void)? = nil,
        onDismantled: (() -> Void)? = nil
    ) {
        self.preparedSharePresentation = preparedSharePresentation
        self.onAppeared = onAppeared
        self.onDismantled = onDismantled
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = preparedSharePresentation.controller
        context.coordinator.onDismantled = onDismantled
        controller.onFirstAppearance = {
            Task { @MainActor in
                onAppeared?()
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
        (uiViewController as? TAPObservedActivityViewController)?.onFirstAppearance = nil
        coordinator.onDismantled?()
        coordinator.onDismantled = nil
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
        controller.retainShareArtifact(artifact)
    }

    static func prepare(for artifact: TAPNAPShareArtifact) -> Self {
        let clock = ContinuousClock()
        let startedAt = clock.now
        let controller = TAPObservedActivityViewController(
            activityItems: activityItems(for: artifact),
            applicationActivities: nil
        )
        let duration = startedAt.duration(to: clock.now)
        #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
        TAPDiagnostics.sharePackaging.info(
            "tap_share_activity_controller_created kind=\(artifact.kind.rawValue, privacy: .public) durationBucket=\(Self.durationBucket(duration), privacy: .public) transport=fileURL"
        )
        #endif
        return Self(
            artifact: artifact,
            controller: controller,
            constructionDuration: duration
        )
    }

    /// Every supported Share kind uses the same system-native file URL item.
    /// UIKit and LaunchServices derive the declared type from the materialized
    /// file and the app's exported UTI instead of an app-owned item provider.
    static func activityItems(for artifact: TAPNAPShareArtifact) -> [Any] {
        [artifact.fileURL]
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
    private var retainedShareArtifact: TAPNAPShareArtifact?

    func retainShareArtifact(_ artifact: TAPNAPShareArtifact) {
        retainedShareArtifact = artifact
    }

    deinit {
        // This is the app's final ownership boundary for a materialized file
        // handed to UIKit. Coordinator callbacks may end SwiftUI state earlier,
        // but only controller release authorizes deleting the source.
        retainedShareArtifact?.removeTemporaryDirectory()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !hasReportedAppearance else {
            return
        }
        hasReportedAppearance = true
        let callback = onFirstAppearance
        onFirstAppearance = nil
        callback?()
    }
}
