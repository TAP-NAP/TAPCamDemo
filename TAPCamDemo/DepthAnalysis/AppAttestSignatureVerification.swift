//
//  AppAttestSignatureVerification.swift
//  TAPCamDemo
//

import AppAttestKit
import Foundation
import OSLog

nonisolated struct AppAttestSignatureVerificationContext: Sendable {
    let backendURL: URL?
    let backendPublicSummary: String

    var verificationEndpoint: URL? {
        backendURL?
            .appendingPathComponent("tapcam")
            .appendingPathComponent("capture-signatures")
            .appendingPathComponent("verify")
    }

    var verificationContextStep: AppAttestSignatureVerificationStep {
        guard verificationEndpoint != nil else {
            return AppAttestSignatureVerificationStep(
                status: .failure,
                title: "Verification backend",
                detail: "Backend configuration is unavailable."
            )
        }

        return AppAttestSignatureVerificationStep(
            status: .success,
            title: "Verification backend",
            detail: "\(backendPublicSummary)."
        )
    }
}

nonisolated struct AppAttestCaptureSignatureVerifier: Sendable {
    typealias PhotoDataLoader = @Sendable (String) async throws -> Data
    typealias RequestMaterialBuilder = @Sendable (Data) throws -> AppAttestSignatureVerificationRequestMaterial
    typealias VerificationSubmitter = @Sendable (Data, URL) async throws -> CaptureSignatureVerificationHTTPResponse

    private let photoDataLoader: PhotoDataLoader
    private let requestMaterialBuilder: RequestMaterialBuilder
    private let verificationSubmitter: VerificationSubmitter

    init(
        photoDataLoader: @escaping PhotoDataLoader = { assetID in
            try await PhotoLibraryWriter.originalPhotoData(localIdentifier: assetID)
        },
        requestMaterialBuilder: @escaping RequestMaterialBuilder = Self.makeRequestMaterial(from:),
        verificationSubmitter: @escaping VerificationSubmitter = Self.submitVerification(requestData:endpoint:)
    ) {
        self.photoDataLoader = photoDataLoader
        self.requestMaterialBuilder = requestMaterialBuilder
        self.verificationSubmitter = verificationSubmitter
    }

    func verify(
        assetID: String,
        context: AppAttestSignatureVerificationContext
    ) async -> AppAttestSignatureVerificationReport {
        var steps = [context.verificationContextStep]

        guard let endpoint = context.verificationEndpoint else {
            return .failure(steps: steps)
        }

        do {
            let heicData = try await photoDataLoader(assetID)
            steps.append(
                AppAttestSignatureVerificationStep(
                    status: .success,
                    title: "Original Photos resource",
                    detail: "Saved HEIC bytes loaded from Photos."
                )
            )

            let material = try requestMaterialBuilder(heicData)
            steps.append(contentsOf: material.steps)

            let requestData = try JSONEncoder.tapCaptureCanonical.encode(material.request)
            let response = try await verificationSubmitter(requestData, endpoint)
            guard response.payload.status == "valid" else {
                throw AppAttestSignatureVerificationFailure(
                    title: "Backend signature verification",
                    detail: "Backend rejected the App Attest assertion for this signing binding."
                )
            }

            steps.append(
                AppAttestSignatureVerificationStep(
                    status: .success,
                    title: "Backend signature verification",
                    detail: "Backend accepted the App Attest assertion for this signing binding."
                )
            )
            return .success(steps: steps)
        } catch {
            TAPDiagnostics.appAttest.error("capture signature verification failed error=\(TAPDiagnostics.describe(error), privacy: .public)")
            let failure = AppAttestSignatureVerificationFailure(error)
            steps.append(
                AppAttestSignatureVerificationStep(
                    status: .failure,
                    title: failure.title,
                    detail: failure.detail
                )
            )
            return .failure(steps: steps)
        }
    }

    private static func makeRequestMaterial(
        from heicData: Data
    ) throws -> AppAttestSignatureVerificationRequestMaterial {
        do {
            let manifest = try TAPDepthHEICReader.decodedManifest(from: heicData)
            let validatedHEIC = try TAPCaptureProvenanceWriter().validateSignedExportHEIC(
                heicData,
                expectedCaptureID: manifest.payload.id
            )
            let proof = try captureProof(from: validatedHEIC.manifest)
            let proofValue = try decodeProofValue(proof)
            let request = CaptureSignatureVerificationRequest(
                keyId: proofValue.keyId,
                assertionObject: proofValue.assertionObject,
                signingBinding: proofValue.signingBinding
            )
            return AppAttestSignatureVerificationRequestMaterial(
                steps: [
                    AppAttestSignatureVerificationStep(
                        status: .success,
                        title: "Local signed HEIC gate",
                        detail: "Container, Release manifest policy, App Attest proof, digest binding, and auxiliary depth passed local validation."
                    )
                ],
                request: request
            )
        } catch let failure as AppAttestSignatureVerificationFailure {
            throw failure
        } catch {
            TAPDiagnostics.appAttest.error("capture signature local validation failed error=\(TAPDiagnostics.describe(error), privacy: .public)")
            throw AppAttestSignatureVerificationFailure(
                title: "Local signed HEIC gate",
                detail: "Saved HEIC did not pass local signature, digest, manifest, and depth validation."
            )
        }
    }

    private static func captureProof(
        from manifest: TAPDepthManifest
    ) throws -> TAPDepthManifest.Proof {
        guard manifest.proofs.count == 1,
              let proof = manifest.proofs.first,
              proof.type == "appAttestAssertion",
              proof.algorithm == "TAPCam.AppAttestCaptureSignature.v1" else {
            throw AppAttestSignatureVerificationFailure(
                title: "App Attest proof",
                detail: "Saved HEIC does not contain the expected capture signature proof."
            )
        }
        return proof
    }

    private static func decodeProofValue(
        _ proof: TAPDepthManifest.Proof
    ) throws -> CaptureAssertionProofValue {
        guard let value = proof.value, !value.isEmpty else {
            throw AppAttestSignatureVerificationFailure(
                title: "App Attest proof",
                detail: "Saved HEIC does not contain the expected capture signature proof."
            )
        }

        let data = try AppAttestBase64URL.decode(value, field: "proof.value")
        return try JSONDecoder().decode(CaptureAssertionProofValue.self, from: data)
    }

    private static func submitVerification(
        requestData: Data,
        endpoint: URL
    ) async throws -> CaptureSignatureVerificationHTTPResponse {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = requestData

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AppAttestSignatureVerificationFailure(
                title: "Backend signature verification",
                detail: "Backend verification did not return a valid HTTP response."
            )
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            TAPDiagnostics.appAttest.error("capture signature verify HTTP failure status=\(httpResponse.statusCode, privacy: .public) bytes=\(data.count, privacy: .public)")
            throw AppAttestSignatureVerificationFailure(
                title: "Backend signature verification",
                detail: "Backend returned an unsuccessful HTTP status."
            )
        }

        do {
            let payload = try JSONDecoder().decode(CaptureSignatureVerificationResponse.self, from: data)
            return CaptureSignatureVerificationHTTPResponse(payload: payload)
        } catch {
            throw AppAttestSignatureVerificationFailure(
                title: "Backend signature verification",
                detail: "Backend verification response could not be decoded."
            )
        }
    }
}

nonisolated struct AppAttestSignatureVerificationReport: Equatable, Sendable {
    let summary: Summary
    let steps: [AppAttestSignatureVerificationStep]

    static let idle = AppAttestSignatureVerificationReport(
        summary: Summary(state: .idle, title: "Signature Verification"),
        steps: []
    )

    static let running = AppAttestSignatureVerificationReport(
        summary: Summary(state: .running, title: "Verifying Signature"),
        steps: [
            AppAttestSignatureVerificationStep(
                status: .info,
                title: "Verification started",
                detail: "Loading the saved HEIC, checking local proof binding, and contacting the configured backend."
            )
        ]
    )

    static func success(steps: [AppAttestSignatureVerificationStep]) -> Self {
        AppAttestSignatureVerificationReport(
            summary: Summary(state: .success, title: "Signature Verified"),
            steps: steps
        )
    }

    static func failure(steps: [AppAttestSignatureVerificationStep]) -> Self {
        AppAttestSignatureVerificationReport(
            summary: Summary(state: .failure, title: "Verification Failed"),
            steps: steps
        )
    }

    nonisolated struct Summary: Equatable, Sendable {
        enum State: Equatable, Sendable {
            case idle
            case running
            case success
            case failure
        }

        let state: State
        let title: String

        var isRunning: Bool {
            state == .running
        }
    }
}

nonisolated struct AppAttestSignatureVerificationStep: Equatable, Identifiable, Sendable {
    let id: UUID
    let status: AppAttestSignatureVerificationStatus
    let title: String
    let detail: String

    init(
        id: UUID = UUID(),
        status: AppAttestSignatureVerificationStatus,
        title: String,
        detail: String
    ) {
        self.id = id
        self.status = status
        self.title = title
        self.detail = detail
    }
}

nonisolated enum AppAttestSignatureVerificationStatus: Equatable, Sendable {
    case info
    case success
    case failure
}

nonisolated struct AppAttestSignatureVerificationRequestMaterial: Sendable {
    let steps: [AppAttestSignatureVerificationStep]
    let request: CaptureSignatureVerificationRequest
}

nonisolated struct CaptureSignatureVerificationRequest: Encodable, Equatable, Sendable {
    let keyId: String
    let assertionObject: String
    let signingBinding: CaptureSigningBinding
}

nonisolated struct CaptureSignatureVerificationResponse: Decodable, Equatable, Sendable {
    let status: String
    let keyId: String?
    let signingBindingSHA256: String?
    let reason: String?
}

nonisolated struct CaptureSignatureVerificationHTTPResponse: Equatable, Sendable {
    let payload: CaptureSignatureVerificationResponse
}

nonisolated struct AppAttestSignatureVerificationFailure: Error, LocalizedError, Sendable {
    let title: String
    let detail: String

    init(title: String, detail: String) {
        self.title = title
        self.detail = detail
    }

    init(_ error: Error) {
        if let failure = error as? AppAttestSignatureVerificationFailure {
            self = failure
        } else {
            self.title = "Verification error"
            self.detail = "Verification could not complete. See diagnostics for details."
        }
    }

    var errorDescription: String? {
        "\(title): \(detail)"
    }
}
