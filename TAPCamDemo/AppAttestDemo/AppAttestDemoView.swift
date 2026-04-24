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
                    LabeledContent("Mode", value: viewModel.backendDescription)
                }

                Section {
                    TextField("Credential name", text: $viewModel.credentialName)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("1. Credential")
                } footer: {
                    Text("This name is caller-defined. AppAttestKit only uses it to find and reuse the saved keyId.")
                }

                Section {
                    Button {
                        viewModel.prepareIfNeeded()
                    } label: {
                        Label("Ensure Attested", systemImage: "checkmark.seal")
                    }
                    .disabled(viewModel.isWorking)

                    Button {
                        viewModel.prepare()
                    } label: {
                        Label("Force New Attestation", systemImage: "key")
                    }
                    .disabled(viewModel.isWorking)

                    Button {
                        viewModel.refreshStatus()
                    } label: {
                        Label("Check Credential", systemImage: "waveform.path.ecg")
                    }
                    .disabled(viewModel.isWorking)

                    Button(role: .destructive) {
                        viewModel.reset()
                    } label: {
                        Label("Reset", systemImage: "trash")
                    }
                    .disabled(viewModel.isWorking)
                } header: {
                    Text("2. Attestation")
                } footer: {
                    Text("Ensure Attested registers an App Attest public key with the backend and saves the returned keyId under this credential name.")
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
                        Label("Generate Assertion", systemImage: "signature")
                    }
                    .disabled(viewModel.isWorking)
                } header: {
                    Text("3. Assertion")
                } footer: {
                    Text("Generate Assertion is called only for one protected API request. The returned headers are attached by the caller.")
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
