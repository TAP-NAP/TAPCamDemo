//
//  TAPVerificationExportBuilder.swift
//  TAPCamDemo
//

import Foundation
import ZIPFoundation

nonisolated struct TAPVerificationExport: Identifiable, Sendable {
    enum Kind: String, Sendable {
        case stillPhoto
        case livePhotoPackage
        case primaryPhotoOnly

        nonisolated var displayName: String {
            switch self {
            case .stillPhoto:
                "Original Photo"
            case .livePhotoPackage:
                "Live Photo Verification ZIP"
            case .primaryPhotoOnly:
                "Primary Photo Only"
            }
        }
    }

    let id: UUID
    let kind: Kind
    let fileURL: URL
    let temporaryDirectoryURL: URL
    let warnings: [String]

    func removeTemporaryDirectory() {
        try? FileManager.default.removeItem(at: temporaryDirectoryURL)
    }
}

nonisolated struct TAPVerificationExportBuilder: Sendable {
    typealias ResourceLoader = @Sendable (String) async throws -> PhotoLibraryWriter.SignatureVerificationResources
    typealias TemporaryDirectoryProvider = @Sendable () throws -> URL

    private static let sidecarFilename = "tapcam-export.json"
    private static let pairedVideoFilename = TAPPendingCaptureBundlePathPolicy.pairedVideoFilename
    private static let primaryPhotoBasename = "primary-photo"
    private static let originalPhotoBasename = "tapcam-original-photo"
    private static let primaryOnlyBasename = "tapcam-primary-photo-only"

    private let resourceLoader: ResourceLoader
    private let temporaryDirectoryProvider: TemporaryDirectoryProvider
    private let localValidator: TAPVerificationExportLocalValidator

    init(
        resourceLoader: @escaping ResourceLoader = { assetID in
            try await PhotoLibraryWriter.signatureVerificationResources(localIdentifier: assetID)
        },
        temporaryDirectoryProvider: @escaping TemporaryDirectoryProvider = Self.defaultTemporaryDirectory,
        localValidator: TAPVerificationExportLocalValidator = .production
    ) {
        self.resourceLoader = resourceLoader
        self.temporaryDirectoryProvider = temporaryDirectoryProvider
        self.localValidator = localValidator
    }

    func export(assetID: String) async throws -> TAPVerificationExport {
        let resources = try await resourceLoader(assetID)
        defer {
            resources.removeTemporaryDirectory()
        }

        return try export(resources: resources)
    }

    func hasValidCredential(assetID: String) async -> Bool {
        do {
            let resources = try await resourceLoader(assetID)
            defer {
                resources.removeTemporaryDirectory()
            }
            return hasValidCredential(resources: resources)
        } catch {
            return false
        }
    }

    func hasValidCredential(
        resources: PhotoLibraryWriter.SignatureVerificationResources
    ) -> Bool {
        do {
            try Self.validateCredential(
                resources: resources,
                localValidator: localValidator
            )
            return true
        } catch {
            return false
        }
    }

    func export(
        resources: PhotoLibraryWriter.SignatureVerificationResources
    ) throws -> TAPVerificationExport {
        let fileContainer = try TAPDepthPhotoFileReader.fileContainer(from: resources.photoData)
        let manifest = try TAPDepthPhotoFileReader.decodedManifest(from: resources.photoData)
        let expectedProfile = Self.expectedProfile(
            fileContainer: fileContainer,
            manifest: manifest
        )
        let outputDirectory = try temporaryDirectoryProvider()
        let warningLabels = resources.presentationAdjustmentResourceLabels

        do {
            return try Self.makeExport(
                resources: resources,
                manifest: manifest,
                expectedProfile: expectedProfile,
                warningLabels: warningLabels,
                outputDirectory: outputDirectory,
                localValidator: localValidator
            )
        } catch {
            try? FileManager.default.removeItem(at: outputDirectory)
            throw error
        }
    }

    private static func makeExport(
        resources: PhotoLibraryWriter.SignatureVerificationResources,
        manifest: TAPDepthManifest,
        expectedProfile: CaptureOutputProfile,
        warningLabels: [String],
        outputDirectory: URL,
        localValidator: TAPVerificationExportLocalValidator
    ) throws -> TAPVerificationExport {
        if manifest.schema == TAPDepthManifest.Schema.livePhotoV2 {
            if let pairedVideoURL = resources.pairedVideoURL {
                let validatedLivePhoto = try localValidator.validateLivePhoto(
                    resources.photoData,
                    pairedVideoURL,
                    manifest.payload.id,
                    expectedProfile
                )
                return try makeLivePhotoPackage(
                    validatedLivePhoto: validatedLivePhoto,
                    warningLabels: warningLabels,
                    outputDirectory: outputDirectory
                )
            }

            let validatedPrimaryPhoto = try localValidator.validateLivePhotoPrimaryPhoto(
                resources.photoData,
                manifest.payload.id,
                expectedProfile
            )
            return try makePrimaryPhotoOnlyExport(
                validatedPhoto: validatedPrimaryPhoto,
                warningLabels: warningLabels,
                outputDirectory: outputDirectory
            )
        }

        guard manifest.schema == TAPDepthManifest.Schema() else {
            throw TAPVerificationExportError.unsupportedManifestSchema
        }

        let validatedPhoto = try localValidator.validateStillPhoto(
            resources.photoData,
            manifest.payload.id,
            expectedProfile
        )
        return try makeStillPhotoExport(
            validatedPhoto: validatedPhoto,
            warningLabels: warningLabels,
            outputDirectory: outputDirectory
        )
    }

    private static func validateCredential(
        resources: PhotoLibraryWriter.SignatureVerificationResources,
        localValidator: TAPVerificationExportLocalValidator
    ) throws {
        let fileContainer = try TAPDepthPhotoFileReader.fileContainer(from: resources.photoData)
        let manifest = try TAPDepthPhotoFileReader.decodedManifest(from: resources.photoData)
        let expectedProfile = Self.expectedProfile(
            fileContainer: fileContainer,
            manifest: manifest
        )

        if manifest.schema == TAPDepthManifest.Schema.livePhotoV2 {
            if let pairedVideoURL = resources.pairedVideoURL {
                _ = try localValidator.validateLivePhoto(
                    resources.photoData,
                    pairedVideoURL,
                    manifest.payload.id,
                    expectedProfile
                )
                return
            }

            _ = try localValidator.validateLivePhotoPrimaryPhoto(
                resources.photoData,
                manifest.payload.id,
                expectedProfile
            )
            return
        }

        guard manifest.schema == TAPDepthManifest.Schema() else {
            throw TAPVerificationExportError.unsupportedManifestSchema
        }

        _ = try localValidator.validateStillPhoto(
            resources.photoData,
            manifest.payload.id,
            expectedProfile
        )
    }

    private static func makeStillPhotoExport(
        validatedPhoto: ValidatedTAPDepthPhoto,
        warningLabels: [String],
        outputDirectory: URL
    ) throws -> TAPVerificationExport {
        let photoURL = outputDirectory
            .appendingPathComponent(originalPhotoBasename)
            .appendingPathExtension(validatedPhoto.fileContainer.verificationExportFileExtension)
        try validatedPhoto.data.write(to: photoURL, options: .atomic)
        return TAPVerificationExport(
            id: UUID(),
            kind: .stillPhoto,
            fileURL: photoURL,
            temporaryDirectoryURL: outputDirectory,
            warnings: Self.warningMessages(from: warningLabels)
        )
    }

    private static func makePrimaryPhotoOnlyExport(
        validatedPhoto: ValidatedTAPDepthPhoto,
        warningLabels: [String],
        outputDirectory: URL
    ) throws -> TAPVerificationExport {
        let photoURL = outputDirectory
            .appendingPathComponent(primaryOnlyBasename)
            .appendingPathExtension(validatedPhoto.fileContainer.verificationExportFileExtension)
        try validatedPhoto.data.write(to: photoURL, options: .atomic)
        return TAPVerificationExport(
            id: UUID(),
            kind: .primaryPhotoOnly,
            fileURL: photoURL,
            temporaryDirectoryURL: outputDirectory,
            warnings: Self.warningMessages(from: warningLabels) + [
                "Paired video missing; exported primary photo only. Live Photo verification remains incomplete."
            ]
        )
    }

    private static func makeLivePhotoPackage(
        validatedLivePhoto: ValidatedTAPLivePhoto,
        warningLabels: [String],
        outputDirectory: URL
    ) throws -> TAPVerificationExport {
        let primaryPhotoFilename = primaryPhotoBasename
            + "."
            + validatedLivePhoto.photo.fileContainer.verificationExportFileExtension
        let primaryPhotoURL = outputDirectory.appendingPathComponent(primaryPhotoFilename)
        let pairedVideoURL = outputDirectory.appendingPathComponent(pairedVideoFilename)
        let sidecarURL = outputDirectory.appendingPathComponent(sidecarFilename)
        let packageURL = outputDirectory.appendingPathComponent("tapcam-live-photo-verification.zip")

        try validatedLivePhoto.photo.data.write(to: primaryPhotoURL, options: .atomic)
        try FileManager.default.copyItem(at: validatedLivePhoto.pairedVideoURL, to: pairedVideoURL)

        let warnings = Self.warningMessages(from: warningLabels)
        let sidecar = TAPVerificationExportSidecar(
            packageKind: TAPVerificationExport.Kind.livePhotoPackage.rawValue,
            resources: [
                TAPVerificationExportSidecar.Resource(
                    role: "primaryPhoto",
                    filename: primaryPhotoFilename,
                    mediaType: validatedLivePhoto.photo.fileContainer.uniformTypeIdentifier
                ),
                TAPVerificationExportSidecar.Resource(
                    role: "pairedLivePhotoVideo",
                    filename: pairedVideoFilename,
                    mediaType: "com.apple.quicktime-movie"
                )
            ],
            warningLabels: warningLabels,
            warnings: warnings
        )
        let sidecarData = try JSONEncoder.tapCaptureCanonical.encode(sidecar)
        try sidecarData.write(to: sidecarURL, options: .atomic)

        let archive = try Archive(url: packageURL, accessMode: .create)
        try archive.addEntry(with: primaryPhotoFilename, fileURL: primaryPhotoURL, compressionMethod: .none)
        try archive.addEntry(with: pairedVideoFilename, fileURL: pairedVideoURL, compressionMethod: .none)
        try archive.addEntry(with: sidecarFilename, fileURL: sidecarURL, compressionMethod: .none)

        return TAPVerificationExport(
            id: UUID(),
            kind: .livePhotoPackage,
            fileURL: packageURL,
            temporaryDirectoryURL: outputDirectory,
            warnings: warnings
        )
    }

    private static func warningMessages(from labels: [String]) -> [String] {
        guard !labels.isEmpty else {
            return []
        }

        return [
            "Photos presentation resources detected: \(labels.joined(separator: ", ")). Export uses original signed resources only."
        ]
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

    private static func defaultTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("TAPVerificationExport-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

nonisolated struct TAPVerificationExportLocalValidator: Sendable {
    typealias StillPhotoValidator = @Sendable (Data, String, CaptureOutputProfile) throws -> ValidatedTAPDepthPhoto
    typealias LivePhotoValidator = @Sendable (Data, URL, String, CaptureOutputProfile) throws -> ValidatedTAPLivePhoto
    typealias LivePhotoPrimaryValidator = @Sendable (Data, String, CaptureOutputProfile) throws -> ValidatedTAPDepthPhoto

    let validateStillPhoto: StillPhotoValidator
    let validateLivePhoto: LivePhotoValidator
    let validateLivePhotoPrimaryPhoto: LivePhotoPrimaryValidator

    static let production = TAPVerificationExportLocalValidator(
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

nonisolated enum TAPVerificationExportError: Error {
    case unsupportedManifestSchema
}

private extension CapturePhotoFileContainer {
    nonisolated var verificationExportFileExtension: String {
        switch self {
        case .heic:
            "heic"
        case .jpeg:
            "jpg"
        }
    }
}
