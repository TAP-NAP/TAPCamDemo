//
//  TAPShareIntegritySupport.swift
//  TAPCamDemo
//

import Foundation

/// Local byte-integrity validators shared by Viewer resource resolution and
/// on-demand TAPNAP preparation. Passing one of these checks does not perform
/// backend App Attest assertion verification.
nonisolated struct TAPSignedPhotoResourceValidator: Sendable {
    typealias StillPhotoValidator = @Sendable (Data, String, CaptureOutputProfile) throws -> ValidatedTAPDepthPhoto
    typealias LivePhotoValidator = @Sendable (Data, URL, String, CaptureOutputProfile) throws -> ValidatedTAPLivePhoto
    typealias LivePhotoPrimaryValidator = @Sendable (Data, String, CaptureOutputProfile) throws -> ValidatedTAPDepthPhoto

    let validateStillPhoto: StillPhotoValidator
    let validateLivePhoto: LivePhotoValidator
    let validateLivePhotoPrimaryPhoto: LivePhotoPrimaryValidator

    static let production = TAPSignedPhotoResourceValidator(
        validateStillPhoto: { photoData, captureID, profile in
            try TAPCaptureProvenanceWriter().validateSignedExportPhoto(
                photoData,
                expectedCaptureID: captureID,
                expectedProfile: profile
            )
        },
        validateLivePhoto: { photoData, pairedVideoURL, captureID, profile in
            try TAPCaptureProvenanceWriter().validateSignedExportLivePhoto(
                photoData,
                pairedVideoURL: pairedVideoURL,
                expectedCaptureID: captureID,
                expectedProfile: profile
            )
        },
        validateLivePhotoPrimaryPhoto: { photoData, captureID, profile in
            try TAPCaptureProvenanceWriter().validateSignedExportLivePhotoPrimaryPhoto(
                photoData,
                expectedCaptureID: captureID,
                expectedProfile: profile
            )
        }
    )
}

nonisolated enum TAPVerificationPackageKind: String, Sendable {
    case stillPhoto
    case livePhotoPackage
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
        self.trustBoundary = "This sidecar is not signed. Verify primary photo and paired video bytes against the TAP signature embedded in the photo."
    }
}
