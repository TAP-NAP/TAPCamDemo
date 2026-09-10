//
//  VerificationExportActivityView.swift
//  TAPCamDemo
//

import Dispatch
import SwiftUI
import UIKit

struct VerificationExportActivityView: UIViewControllerRepresentable {
    private let sharePresentation: TAPShareActivityPresentation

    init(sharePresentation: TAPShareActivityPresentation) {
        self.sharePresentation = sharePresentation
    }

    func makeUIViewController(context: Context) -> UIActivityViewController {
        sharePresentation.makeViewController()
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

@MainActor
final class TAPShareActivityPresentation: Identifiable {
    let artifact: TAPNAPShareArtifact

    var id: UUID { artifact.id }

    init(artifact: TAPNAPShareArtifact) {
        self.artifact = artifact
    }

    func makeViewController() -> TAPShareActivityViewController {
        TAPShareActivityViewController(
            artifact: artifact,
            activityItems: Self.activityItems(for: artifact)
        )
    }

    /// The item binding's dismissal is the app-owned lifetime boundary for
    /// this attempt. UIKit has already accepted or cancelled the activity by
    /// then, so cleanup no longer depends on when SwiftUI releases a cached
    /// controller instance.
    func scheduleTemporaryDirectoryCleanup() {
        let artifact = artifact
        TAPShareArtifactCleanup.schedule {
            artifact.removeTemporaryDirectory()
        }
    }

    /// Every supported Share kind uses the same system-native file URL item.
    /// UIKit and LaunchServices derive the declared type from the materialized
    /// file and the app's exported UTI instead of an app-owned item provider.
    static func activityItems(for artifact: TAPNAPShareArtifact) -> [Any] {
        [artifact.fileURL]
    }
}

@MainActor
final class TAPShareActivityViewController: UIActivityViewController {
    let artifact: TAPNAPShareArtifact

    init(
        artifact: TAPNAPShareArtifact,
        activityItems: [Any]
    ) {
        // Construction now happens only when SwiftUI begins presenting the
        // system sheet. Retain the artifact through that system-owned UI.
        self.artifact = artifact
        super.init(
            activityItems: activityItems,
            applicationActivities: nil
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }
}

nonisolated enum TAPShareArtifactCleanup {
    private static let queue = DispatchQueue(
        label: "net.tapnap.tapcam.share-artifact-cleanup",
        qos: .utility
    )

    static func schedule(_ cleanup: @escaping @Sendable () -> Void) {
        queue.async(execute: cleanup)
    }
}
