//
//  AppAttestDemoView.swift
//  TAPCamDemo
//

import SwiftUI
import UniformTypeIdentifiers

struct AppAttestDemoView: View {
    @StateObject private var viewModel: AppAttestDemoViewModel

    init(runtime: AppAttestRuntime) {
        _viewModel = StateObject(
            wrappedValue: AppAttestDemoViewModel(runtime: runtime)
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Backend") {
                    Picker("Backend", selection: $viewModel.selectedBackendMode) {
                        ForEach(AppAttestDemoBackendMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }

                    if viewModel.shouldShowHTTPSettings {
                        TextField("Base URL", text: $viewModel.httpBaseURL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                    }

                    Button {
                        viewModel.applyBackendSelection()
                    } label: {
                        Label("Use Selected Backend", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .disabled(viewModel.isWorking)

                    LabeledContent("Active", value: viewModel.backendDescription)
                }

                Section {
                    TextField("Credential name", text: $viewModel.credentialName)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("1. Credential")
                } footer: {
                    Text("credentialName is caller-defined. Challenge is issued by the selected backend when Prepare Credential or Register New Key runs.")
                }

                Section {
                    Button {
                        viewModel.prepareIfNeeded()
                    } label: {
                        Label("Prepare Credential", systemImage: "checkmark.seal")
                    }
                    .disabled(viewModel.isWorking)

                    Button {
                        viewModel.prepare()
                    } label: {
                        Label("Register New Key", systemImage: "key")
                    }
                    .disabled(viewModel.isWorking)

                    Button {
                        viewModel.refreshStatus()
                    } label: {
                        Label("Check Status", systemImage: "waveform.path.ecg")
                    }
                    .disabled(viewModel.isWorking)

                    Button(role: .destructive) {
                        viewModel.reset()
                    } label: {
                        Label("Reset Local Credential", systemImage: "trash")
                    }
                    .disabled(viewModel.isWorking)
                } header: {
                    Text("2. Attestation")
                } footer: {
                    Text("Prepare Credential reuses a saved keyId when possible. Register New Key always creates and registers a fresh App Attest key.")
                }

                Section {
                    TextField("Method", text: $viewModel.requestMethod)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                    TextField("Path", text: $viewModel.requestPath)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Body", text: $viewModel.requestBody, axis: .vertical)
                        .font(.system(.body, design: .monospaced))
                        .lineLimit(2...5)

                    Button {
                        viewModel.generateAssertion()
                    } label: {
                        Label("Sign Protected Request", systemImage: "signature")
                    }
                    .disabled(viewModel.isWorking)
                } header: {
                    Text("3. Assertion")
                } footer: {
                    Text("Sign Protected Request generates assertion headers for this one method, path, and body.")
                }

                Section("Result") {
                    Text(viewModel.statusText)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)

                    if !viewModel.headersText.isEmpty {
                        Text("Assertion headers")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(viewModel.headersText)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }

                #if DEBUG
                if viewModel.isDebugExportAvailable {
                    Section("Debug Export") {
                        Button {
                            viewModel.saveAttestationObject()
                        } label: {
                            Label("Save Attestation CBOR", systemImage: "square.and.arrow.down")
                        }
                        .disabled(viewModel.isWorking)

                        Button {
                            viewModel.exportDebugJSON()
                        } label: {
                            Label("Export JSON", systemImage: "doc.text")
                        }
                        .disabled(viewModel.isWorking)

                        if !viewModel.debugJSON.isEmpty {
                            Text("Collected mock challenge, attestation, and assertion artifacts")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(viewModel.debugJSON)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                        }
                    }
                }
                #endif
            }
            .navigationTitle("App Attest")
            .fileExporter(
                isPresented: $viewModel.isAttestationExporterPresented,
                document: viewModel.attestationObjectDocument,
                contentType: .data,
                defaultFilename: "attestationObject.cbor"
            ) { result in
                viewModel.handleAttestationObjectExportResult(result)
            }
        }
    }
}
