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
    typealias ResourceLoader = @Sendable (String) async throws -> PhotoLibraryWriter.SignatureVerificationResources
    typealias PhotoRequestMaterialBuilder = @Sendable (Data) throws -> AppAttestSignatureVerificationRequestMaterial
    typealias RequestMaterialBuilder = @Sendable (PhotoLibraryWriter.SignatureVerificationResources) throws -> AppAttestSignatureVerificationRequestMaterial
    typealias VerificationSubmitter = @Sendable (Data, URL) async throws -> CaptureSignatureVerificationHTTPResponse

    private let resourceLoader: ResourceLoader
    private let requestMaterialBuilder: RequestMaterialBuilder
    private let verificationSubmitter: VerificationSubmitter

    init(
        resourceLoader: @escaping ResourceLoader = { assetID in
            try await PhotoLibraryWriter.signatureVerificationResources(localIdentifier: assetID)
        },
        requestMaterialBuilder: @escaping RequestMaterialBuilder = Self.makeRequestMaterial(from:),
        verificationSubmitter: @escaping VerificationSubmitter = Self.submitVerification(requestData:endpoint:)
    ) {
        self.resourceLoader = resourceLoader
        self.requestMaterialBuilder = requestMaterialBuilder
        self.verificationSubmitter = verificationSubmitter
    }

    init(
        photoDataLoader: @escaping PhotoDataLoader,
        requestMaterialBuilder: @escaping PhotoRequestMaterialBuilder,
        verificationSubmitter: @escaping VerificationSubmitter = Self.submitVerification(requestData:endpoint:)
    ) {
        self.init(
            resourceLoader: { assetID in
                PhotoLibraryWriter.SignatureVerificationResources(
                    photoData: try await photoDataLoader(assetID),
                    pairedVideoURL: nil,
                    temporaryDirectoryURL: nil,
                    presentationAdjustmentResourceLabels: []
                )
            },
            requestMaterialBuilder: { resources in
                try requestMaterialBuilder(resources.photoData)
            },
            verificationSubmitter: verificationSubmitter
        )
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
            let resources = try await resourceLoader(assetID)
            defer {
                resources.removeTemporaryDirectory()
            }
            steps.append(
                AppAttestSignatureVerificationStep(
                    status: .success,
                    title: "Original Photos photo",
                    detail: "Saved photo bytes loaded from Photos."
                )
            )
            if resources.hasPairedVideo {
                steps.append(
                    AppAttestSignatureVerificationStep(
                        status: .success,
                        title: "Original Live Photo video",
                        detail: "Saved paired MOV loaded from Photos."
                    )
                )
            }

            let material = try requestMaterialBuilder(resources)
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
            return .verified(steps: steps)
        } catch {
            #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
            TAPDiagnostics.appAttest.error("capture signature verification failed error=\(TAPDiagnostics.describe(error), privacy: .public)")
            #endif
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
        from resources: PhotoLibraryWriter.SignatureVerificationResources
    ) throws -> AppAttestSignatureVerificationRequestMaterial {
        do {
            let photoData = resources.photoData
            let fileContainer = try TAPDepthPhotoFileReader.fileContainer(from: photoData)
            let manifest = try TAPDepthPhotoFileReader.decodedManifest(from: photoData)
            let expectedProfile = expectedProfile(
                fileContainer: fileContainer,
                manifest: manifest
            )
            if manifest.schema == TAPDepthManifest.Schema.livePhotoV2 {
                return try makeLivePhotoRequestMaterial(
                    from: resources,
                    manifest: manifest,
                    expectedProfile: expectedProfile
                )
            }
            guard manifest.schema == TAPDepthManifest.Schema() else {
                throw AppAttestSignatureVerificationFailure(
                    title: "Local signed photo gate",
                    detail: "Saved photo uses an unsupported TAP manifest schema."
                )
            }

            let validatedPhoto = try TAPCaptureProvenanceWriter().validateSignedExportPhoto(
                photoData,
                expectedCaptureID: manifest.payload.id,
                expectedProfile: expectedProfile
            )
            let proof = try captureProof(
                from: validatedPhoto.data,
                fileContainer: validatedPhoto.fileContainer
            )
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
                        title: "Local signed photo gate",
                        detail: "Container, Release manifest policy, App Attest proof, digest binding, and auxiliary depth passed local validation."
                    )
                ] + presentationWarningSteps(from: resources, isLivePhoto: false),
                request: request
            )
        } catch let failure as AppAttestSignatureVerificationFailure {
            throw failure
        } catch {
            #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
            TAPDiagnostics.appAttest.error("capture signature local validation failed error=\(TAPDiagnostics.describe(error), privacy: .public)")
            #endif
            throw AppAttestSignatureVerificationFailure(
                title: "Local signed photo gate",
                detail: "Saved photo did not pass local signature, digest, manifest, and depth validation."
            )
        }
    }

    private static func makeLivePhotoRequestMaterial(
        from resources: PhotoLibraryWriter.SignatureVerificationResources,
        manifest: TAPDepthManifest,
        expectedProfile: CaptureOutputProfile
    ) throws -> AppAttestSignatureVerificationRequestMaterial {
        guard let pairedVideoURL = resources.pairedVideoURL else {
            throw AppAttestSignatureVerificationFailure(
                title: "Local signed Live Photo gate",
                detail: "Saved Live Photo is missing its original paired video resource."
            )
        }

        do {
            let validatedLivePhoto = try TAPCaptureProvenanceWriter().validateSignedExportLivePhoto(
                resources.photoData,
                pairedVideoURL: pairedVideoURL,
                expectedCaptureID: manifest.payload.id,
                expectedProfile: expectedProfile
            )
            let proof = try captureProof(
                from: validatedLivePhoto.photo.data,
                fileContainer: validatedLivePhoto.photo.fileContainer
            )
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
                        title: "Local signed Live Photo gate",
                        detail: "Primary photo, paired MOV, manifest, App Attest proof, digest binding, and still-photo depth passed local validation."
                    ),
                    AppAttestSignatureVerificationStep(
                        status: .info,
                        title: "Live Photo depth scope",
                        detail: "Depth is bound to the original still photo. The paired MOV is signed as video bytes, not per-frame depth."
                    )
                ] + presentationWarningSteps(from: resources, isLivePhoto: true),
                request: request
            )
        } catch let failure as AppAttestSignatureVerificationFailure {
            throw failure
        } catch {
            #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
            TAPDiagnostics.appAttest.error("capture signature Live Photo local validation failed error=\(TAPDiagnostics.describe(error), privacy: .public)")
            #endif
            throw AppAttestSignatureVerificationFailure(
                title: "Local signed Live Photo gate",
                detail: "Saved Live Photo did not pass local signature, digest, manifest, paired MOV, and depth validation."
            )
        }
    }

    private static func expectedProfile(
        fileContainer: CapturePhotoFileContainer,
        manifest: TAPDepthManifest
    ) -> CaptureOutputProfile {
        let qualityLevel = CapturePhotoQualityLevel(
            rawValue: manifest.payload.capture.photoQualityPrioritization
        ) ?? .quality
        return CaptureOutputProfile.releasePhotoDepthProfile(
            fileContainer: fileContainer,
            photoQualityLevel: qualityLevel
        )
    }

    private static func presentationWarningSteps(
        from resources: PhotoLibraryWriter.SignatureVerificationResources,
        isLivePhoto: Bool
    ) -> [AppAttestSignatureVerificationStep] {
        guard resources.hasPresentationAdjustments else {
            return []
        }

        let resourceScope = isLivePhoto
            ? "original .photo and .pairedVideo"
            : "original .photo"
        let labels = resources.presentationAdjustmentResourceLabels.joined(separator: ", ")
        return [
            AppAttestSignatureVerificationStep(
                status: .warning,
                title: "Photos presentation warning",
                detail: "Photos has presentation resources: \(labels). Verification covers \(resourceScope) only."
            )
        ]
    }

    private static func captureProof(
        from photoData: Data,
        fileContainer: CapturePhotoFileContainer
    ) throws -> TAPDepthManifest.Proof {
        let proofData = try TAPProofSlot.proofEnvelopeData(
            from: photoData,
            fileContainer: fileContainer
        )
        let proof = try JSONDecoder().decode(TAPDepthManifest.Proof.self, from: proofData)
        guard proof.type == "appAttestAssertion",
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
            #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
            TAPDiagnostics.appAttest.error("capture signature verify HTTP failure status=\(httpResponse.statusCode, privacy: .public) bytes=\(data.count, privacy: .public)")
            #endif
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
        summary: Summary(state: .running, title: "Verifying"),
        steps: [
            AppAttestSignatureVerificationStep(
                status: .info,
                title: "Verification started",
                detail: "Loading saved original resources, checking local proof binding, and contacting the configured backend."
            )
        ]
    )

    static func success(steps: [AppAttestSignatureVerificationStep]) -> Self {
        AppAttestSignatureVerificationReport(
            summary: Summary(state: .success, title: "Verified"),
            steps: steps
        )
    }

    static func warning(steps: [AppAttestSignatureVerificationStep]) -> Self {
        AppAttestSignatureVerificationReport(
            summary: Summary(state: .warning, title: "Warnings"),
            steps: steps
        )
    }

    static func failure(steps: [AppAttestSignatureVerificationStep]) -> Self {
        AppAttestSignatureVerificationReport(
            summary: Summary(state: .failure, title: "Failed"),
            steps: steps
        )
    }

    static func verified(steps: [AppAttestSignatureVerificationStep]) -> Self {
        if steps.contains(where: { $0.status == .failure }) {
            return failure(steps: steps)
        }
        if steps.contains(where: { $0.status == .warning }) {
            return warning(steps: steps)
        }
        return success(steps: steps)
    }

    var firstAttentionStepID: UUID? {
        steps.first(where: { $0.status == .failure })?.id
            ?? steps.first(where: { $0.status == .warning })?.id
    }

    nonisolated struct Summary: Equatable, Sendable {
        enum State: Equatable, Sendable {
            case idle
            case running
            case success
            case warning
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
    case warning
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
