//
//  AppAttestSignatureVerificationPanel.swift
//  TAPCamDemo
//

import Combine
import SwiftUI

struct AppAttestSignatureVerificationPanel: View {
    let assetID: String
    @ObservedObject private var appAttestController: AppAttestRuntimeController
    let runID: UUID
    @StateObject private var viewModel = AppAttestSignatureVerificationPanelModel()

    init(
        assetID: String,
        appAttestController: AppAttestRuntimeController,
        runID: UUID
    ) {
        self.assetID = assetID
        self.appAttestController = appAttestController
        self.runID = runID
    }

    var body: some View {
        ScrollViewReader { proxy in
            VStack(alignment: .leading, spacing: 12) {
                SignatureVerificationHeader(
                    report: viewModel.report,
                    onRetry: retry,
                    onAttentionTapped: {
                        scrollToAttention(in: proxy)
                    }
                )

                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(viewModel.report.steps) { step in
                        SignatureVerificationStepRow(step: step)
                            .id(step.id)
                    }
                }
            }
            .task(id: runID) {
                await verify()
            }
        }
    }

    private func retry() {
        Task {
            await verify()
        }
    }

    private func scrollToAttention(in proxy: ScrollViewProxy) {
        guard let stepID = viewModel.report.firstAttentionStepID else {
            return
        }

        withAnimation(.easeInOut(duration: 0.18)) {
            proxy.scrollTo(stepID, anchor: .center)
        }
    }

    private func verify() async {
        await viewModel.verify(
            assetID: assetID,
            appAttestController: appAttestController
        )
    }

}

struct SignatureVerificationUnavailablePanel: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Verification unavailable", systemImage: "clock.badge.exclamationmark")
                .font(.subheadline.weight(.semibold))

            Text("This capture is still pending export to Photos. Return after export completes, then open the saved photo to verify its App Attest proof.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

@MainActor
private final class AppAttestSignatureVerificationPanelModel: ObservableObject {
    @Published private(set) var report = AppAttestSignatureVerificationReport.idle
    private let verifier: AppAttestCaptureSignatureVerifier

    init(
        verifier: AppAttestCaptureSignatureVerifier = AppAttestCaptureSignatureVerifier()
    ) {
        self.verifier = verifier
    }

    func verify(
        assetID: String,
        appAttestController: AppAttestRuntimeController
    ) async {
        report = .running

        let runtime = appAttestController.runtime
        let context = AppAttestSignatureVerificationContext(
            backendURL: runtime.backendURL,
            backendPublicSummary: runtime.backendPublicSummary
        )
        report = await verifier.verify(assetID: assetID, context: context)
    }

}

private struct SignatureVerificationHeader: View {
    let report: AppAttestSignatureVerificationReport
    let onRetry: () -> Void
    let onAttentionTapped: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            if report.firstAttentionStepID == nil {
                Label(report.summary.title, systemImage: report.summary.systemImage)
                    .font(.subheadline.weight(.semibold))
            } else {
                Button(action: onAttentionTapped) {
                    Label(report.summary.title, systemImage: report.summary.systemImage)
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(report.summary.title)
            }

            Spacer(minLength: 8)

            Button(action: onRetry) {
                Image(systemName: "arrow.clockwise")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .disabled(report.summary.isRunning)
            .accessibilityLabel("Verify again")
            .help("Verify this photo's App Attest proof again.")
        }
        .foregroundStyle(report.summary.foregroundStyle)
    }
}

private struct SignatureVerificationStepRow: View {
    let step: AppAttestSignatureVerificationStep

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: step.status.systemImage)
                .font(.caption.weight(.bold))
                .foregroundStyle(step.status.foregroundStyle)
                .frame(width: 18, height: 18)

            VStack(alignment: .leading, spacing: 3) {
                Text(step.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)

                Text(step.detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}

private extension AppAttestSignatureVerificationReport.Summary {
    var systemImage: String {
        switch state {
        case .idle, .running:
            "checkmark.shield"
        case .success:
            "checkmark.seal.fill"
        case .warning:
            "exclamationmark.triangle.fill"
        case .failure:
            "xmark.octagon.fill"
        }
    }

    var foregroundStyle: Color {
        switch state {
        case .idle, .running:
            .primary
        case .success:
            .green
        case .warning:
            .yellow
        case .failure:
            .red
        }
    }
}

private extension AppAttestSignatureVerificationStatus {
    var systemImage: String {
        switch self {
        case .info:
            "info.circle"
        case .success:
            "checkmark.circle.fill"
        case .warning:
            "exclamationmark.triangle.fill"
        case .failure:
            "xmark.circle.fill"
        }
    }

    var foregroundStyle: Color {
        switch self {
        case .info:
            .secondary
        case .success:
            .green
        case .warning:
            .yellow
        case .failure:
            .red
        }
    }
}
