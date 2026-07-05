//
//  DepthAnalysisShareSheet.swift
//  TAPCamDemo
//

import Combine
import OSLog
import SwiftUI

struct DepthAnalysisShareSheet: View {
    let source: DepthAnalysisSource
    @StateObject private var viewModel = DepthAnalysisShareSheetModel()
    @State private var sharePayload: DepthAnalysisSharePayload?

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                LabeledContent("Valid credential", value: viewModel.hasValidCredential ? "Yes" : "No")
                    .font(.body.weight(.semibold))

                Button {
                    exportOriginals()
                } label: {
                    Label(
                        viewModel.isExporting ? "Preparing Share" : "Share",
                        systemImage: "square.and.arrow.up"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!viewModel.canExportOriginals || viewModel.isExporting)

                if viewModel.isExporting {
                    ProgressView()
                        .frame(maxWidth: .infinity, alignment: .center)
                }

                #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
                if let debugStatus = viewModel.debugStatus {
                    LabeledContent("Debug status", value: debugStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                #endif
            }
            .padding()
            .navigationTitle("Share")
            .navigationBarTitleDisplayMode(.inline)
            .task(id: source.loadID) {
                await viewModel.refresh(source: source)
            }
            .sheet(item: $sharePayload) { payload in
                VerificationExportActivityView(activityItems: [payload.export.fileURL])
            }
        }
    }

    private func exportOriginals() {
        Task {
            if let export = await viewModel.exportOriginals(source: source) {
                sharePayload = DepthAnalysisSharePayload(export: export)
            }
        }
    }
}

@MainActor
private final class DepthAnalysisShareSheetModel: ObservableObject {
    @Published private(set) var hasValidCredential = false
    @Published private(set) var canExportOriginals = false
    @Published private(set) var isExporting = false
    #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
    @Published private(set) var debugStatus: String?
    #endif

    private let exportBuilder: TAPVerificationExportBuilder

    init(
        exportBuilder: TAPVerificationExportBuilder = TAPVerificationExportBuilder()
    ) {
        self.exportBuilder = exportBuilder
    }

    func refresh(source: DepthAnalysisSource) async {
        hasValidCredential = false
        canExportOriginals = false
        #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
        debugStatus = nil
        #endif

        guard case .photosAsset(let assetID) = source else {
            #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
            debugStatus = "Pending local item"
            #endif
            return
        }

        canExportOriginals = true
        hasValidCredential = await exportBuilder.hasValidCredential(assetID: assetID)
        #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
        debugStatus = hasValidCredential ? "Local credential valid" : "Local credential unavailable"
        #endif
    }

    func exportOriginals(source: DepthAnalysisSource) async -> TAPVerificationExport? {
        guard case .photosAsset(let assetID) = source else {
            return nil
        }

        isExporting = true
        defer {
            isExporting = false
        }

        do {
            return try await exportBuilder.export(assetID: assetID)
        } catch {
            #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
            debugStatus = "Share unavailable"
            TAPDiagnostics.appAttest.error("analysis share export failed error=\(TAPDiagnostics.describe(error), privacy: .public)")
            #endif
            return nil
        }
    }
}

@MainActor
private final class DepthAnalysisSharePayload: Identifiable {
    let id = UUID()
    let export: TAPVerificationExport

    init(export: TAPVerificationExport) {
        self.export = export
    }

    deinit {
        export.removeTemporaryDirectory()
    }
}
