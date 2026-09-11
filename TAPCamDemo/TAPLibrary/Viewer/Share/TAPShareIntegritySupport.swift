//
//  TAPShareIntegritySupport.swift
//  TAPCamDemo
//

import Foundation

/// Local byte-integrity checks for the current Viewer original when Share opens.
/// Transport builders consume the result; they do not repeat these checks.
/// These checks do not perform backend App Attest assertion verification.
nonisolated struct TAPSignedPhotoResourceValidator: Sendable {
    typealias StillPhotoValidator = @Sendable (TAPPhotoValidationInput, String) throws -> ValidatedTAPDepthPhoto
    typealias LivePhotoValidator = @Sendable (TAPPhotoValidationInput, URL, String) throws -> ValidatedTAPLivePhoto

    let validateStillPhoto: StillPhotoValidator
    let validateLivePhoto: LivePhotoValidator

    static let production = TAPSignedPhotoResourceValidator(
        validateStillPhoto: { input, captureID in
            try TAPCaptureProvenanceWriter().validateSignedExportPhoto(
                input,
                expectedCaptureID: captureID
            )
        },
        validateLivePhoto: { input, pairedVideoURL, captureID in
            try TAPCaptureProvenanceWriter().validateSignedExportLivePhoto(
                input,
                pairedVideoURL: pairedVideoURL,
                expectedCaptureID: captureID
            )
        }
    )
}

nonisolated enum TAPVerificationPackageKind: String, Sendable {
    case stillPhoto
    case livePhotoPackage
    case tapVideo
}

nonisolated struct TAPVerificationExportSidecar: Codable, Equatable, Sendable {
    nonisolated struct Resource: Codable, Equatable, Sendable {
        let role: String
        let filename: String
        let mediaType: String
    }

    let schemaID: String
    let version: Int
    let packageKind: String
    let resources: [Resource]
    let warningLabels: [String]
    let warnings: [String]
    let trustBoundary: String

    init(
        packageKind: String,
        resources: [Resource],
        warningLabels: [String],
        warnings: [String]
    ) {
        self.schemaID = "urn:tapnap:tapcam:verification-export:v1"
        self.version = 1
        self.packageKind = packageKind
        self.resources = resources
        self.warningLabels = warningLabels
        self.warnings = warnings
        self.trustBoundary = packageKind == TAPVerificationPackageKind.tapVideo.rawValue
            ? "This sidecar is not signed. Verify original video bytes against the TAP signature embedded in the video."
            : "This sidecar is not signed. Verify primary photo and paired video bytes against the TAP signature embedded in the photo."
    }
}
