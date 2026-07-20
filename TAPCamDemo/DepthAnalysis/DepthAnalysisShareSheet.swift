//
//  DepthAnalysisShareSheet.swift
//  TAPCamDemo
//

import Combine
import Foundation
import OSLog
import SwiftUI

struct DepthAnalysisShareSheet: View {
    let source: DepthAnalysisSource
    @StateObject private var viewModel = DepthAnalysisShareSheetModel()
    @State private var preparedPayload: DepthAnalysisSharePayload?
    @State private var activityPayload: DepthAnalysisSharePayload?

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                LabeledContent("Valid credential", value: viewModel.hasValidCredential ? "Yes" : "No")
                    .font(.body.weight(.semibold))

                if let preparedPayload {
                    DepthAnalysisShareFileInfoView(fileInfo: preparedPayload.fileInfo)
                }

                Button {
                    handleShareButtonTapped()
                } label: {
                    Label(
                        shareButtonTitle,
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
                resetPreparedShare()
                await viewModel.refresh(source: source)
            }
            .sheet(item: $activityPayload) { payload in
                VerificationExportActivityView(activityItems: [payload.export.fileURL])
            }
        }
    }

    private var shareButtonTitle: String {
        if viewModel.isExporting {
            return "Preparing Share"
        }
        if preparedPayload != nil {
            return "Share File"
        }
        return "Prepare Share"
    }

    private func handleShareButtonTapped() {
        if let preparedPayload {
            activityPayload = preparedPayload
            return
        }
        prepareShare()
    }

    private func prepareShare() {
        Task {
            if let export = await viewModel.exportOriginals(source: source) {
                preparedPayload = DepthAnalysisSharePayload(export: export)
            }
        }
    }

    private func resetPreparedShare() {
        activityPayload = nil
        preparedPayload = nil
    }
}

nonisolated struct DepthAnalysisShareFileInfo: Equatable {
    let fileName: String
    let kind: String
    let fileSize: String
    let warnings: [String]

    init(export: TAPVerificationExport, fileManager: FileManager = .default) {
        self.fileName = export.fileURL.lastPathComponent
        self.kind = export.kind.displayName
        self.fileSize = Self.fileSizeText(for: export.fileURL, fileManager: fileManager)
        self.warnings = export.warnings
    }

    private static func fileSizeText(for fileURL: URL, fileManager: FileManager) -> String {
        guard let byteCount = fileSizeBytes(for: fileURL, fileManager: fileManager) else {
            return "Unknown"
        }
        return ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file)
    }

    private static func fileSizeBytes(for fileURL: URL, fileManager: FileManager) -> Int64? {
        guard let value = try? fileManager.attributesOfItem(atPath: fileURL.path)[.size] as? NSNumber else {
            return nil
        }
        return value.int64Value
    }
}

private struct DepthAnalysisShareFileInfoView: View {
    let fileInfo: DepthAnalysisShareFileInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("File information", systemImage: "doc")
                .font(.subheadline.weight(.semibold))

            shareInfoRow(title: "Name", value: fileInfo.fileName)
            shareInfoRow(title: "Type", value: fileInfo.kind)
            shareInfoRow(title: "Size", value: fileInfo.fileSize)

            if !fileInfo.warnings.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Warnings")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ForEach(fileInfo.warnings, id: \.self) { warning in
                        Text(warning)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func shareInfoRow(title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .leading)
            Text(value)
                .font(.caption)
                .foregroundStyle(.primary)
                .lineLimit(2)
                .minimumScaleFactor(0.75)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: .infinity, alignment: .trailing)
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
    let fileInfo: DepthAnalysisShareFileInfo

    init(export: TAPVerificationExport) {
        self.export = export
        self.fileInfo = DepthAnalysisShareFileInfo(export: export)
    }

    deinit {
        export.removeTemporaryDirectory()
    }
}
