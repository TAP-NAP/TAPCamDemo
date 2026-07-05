//
//  TAPVerificationExportBuilderTests.swift
//  TAPCamDemoTests
//

import Foundation
import Testing
import ZIPFoundation
@testable import TAPCamDemo

@Suite(.serialized)
struct TAPVerificationExportBuilderTests {
    @Test func stillManifestExportsOriginalPhotoFile() async throws {
        let photoData = try Self.photoData(captureID: "still-export")
        let outputDirectory = try TAPCamDemoTestFixtures.makeTemporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: outputDirectory)
        }

        let export = try TAPVerificationExportBuilder(
            temporaryDirectoryProvider: { outputDirectory },
            localValidator: Self.localValidator()
        ).export(resources: PhotoLibraryWriter.SignatureVerificationResources(
            photoData: photoData,
            pairedVideoURL: nil,
            temporaryDirectoryURL: nil,
            presentationAdjustmentResourceLabels: []
        ))

        defer {
            export.removeTemporaryDirectory()
        }
        #expect(export.kind == .stillPhoto)
        #expect(export.fileURL.lastPathComponent == "tapcam-original-photo.heic")
        #expect(try Data(contentsOf: export.fileURL) == photoData)
        #expect(export.warnings.isEmpty)
    }

    @Test func liveManifestExportsUncompressedVerificationZipWithMinimalSidecar() async throws {
        let movieData = Data("original-live-movie".utf8)
        let movieURL = try Self.movieURL(data: movieData)
        defer {
            try? FileManager.default.removeItem(at: movieURL.deletingLastPathComponent())
        }
        let photoData = try Self.photoData(captureID: "live-export", livePhoto: Self.livePhotoPayload(), schema: .livePhotoV2)
        let outputDirectory = try TAPCamDemoTestFixtures.makeTemporaryDirectory()

        let export = try TAPVerificationExportBuilder(
            temporaryDirectoryProvider: { outputDirectory },
            localValidator: Self.localValidator(expectedMovieData: movieData)
        ).export(resources: PhotoLibraryWriter.SignatureVerificationResources(
            photoData: photoData,
            pairedVideoURL: movieURL,
            temporaryDirectoryURL: nil,
            presentationAdjustmentResourceLabels: ["adjustmentData", "fullSizePairedVideo"]
        ))
        defer {
            export.removeTemporaryDirectory()
        }

        let archive = try Archive(url: export.fileURL, accessMode: .read)
        let entries = Array(archive)
        #expect(export.kind == .livePhotoPackage)
        #expect(entries.map(\.path).sorted() == [
            "paired-video.mov",
            "primary-photo.heic",
            "tapcam-export.json"
        ])
        #expect(entries.allSatisfy { !$0.isCompressed })

        let extractedDirectory = try TAPCamDemoTestFixtures.makeTemporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: extractedDirectory)
        }
        try FileManager.default.unzipItem(at: export.fileURL, to: extractedDirectory)
        #expect(try Data(contentsOf: extractedDirectory.appendingPathComponent("primary-photo.heic")) == photoData)
        #expect(try Data(contentsOf: extractedDirectory.appendingPathComponent("paired-video.mov")) == movieData)

        let sidecarURL = extractedDirectory.appendingPathComponent("tapcam-export.json")
        let sidecarData = try Data(contentsOf: sidecarURL)
        let sidecar = try JSONDecoder().decode(TAPVerificationExportSidecar.self, from: sidecarData)
        let sidecarJSON = try #require(String(data: sidecarData, encoding: .utf8))
        #expect(sidecar.schemaID == "urn:tapnap:tapcam:verification-export:v1")
        #expect(sidecar.packageKind == TAPVerificationExport.Kind.livePhotoPackage.rawValue)
        #expect(sidecar.resources.map(\.role) == ["primaryPhoto", "pairedLivePhotoVideo"])
        #expect(sidecar.warningLabels == ["adjustmentData", "fullSizePairedVideo"])
        #expect(export.warnings.first?.contains("adjustmentData") == true)
        for forbidden in ["captureID", "keyId", "keyID", "assertionObject", "bodySHA256", "proof", "hash"] {
            #expect(!sidecarJSON.localizedCaseInsensitiveContains(forbidden))
        }
    }

    @Test func liveManifestWithMissingMovieExportsPrimaryPhotoOnly() async throws {
        let photoData = try Self.photoData(captureID: "primary-only-export", livePhoto: Self.livePhotoPayload(), schema: .livePhotoV2)
        let outputDirectory = try TAPCamDemoTestFixtures.makeTemporaryDirectory()

        let export = try TAPVerificationExportBuilder(
            temporaryDirectoryProvider: { outputDirectory },
            localValidator: Self.localValidator()
        ).export(resources: PhotoLibraryWriter.SignatureVerificationResources(
            photoData: photoData,
            pairedVideoURL: nil,
            temporaryDirectoryURL: nil,
            presentationAdjustmentResourceLabels: ["adjustmentData"]
        ))
        defer {
            export.removeTemporaryDirectory()
        }

        #expect(export.kind == .primaryPhotoOnly)
        #expect(export.fileURL.lastPathComponent == "tapcam-primary-photo-only.heic")
        #expect(try Data(contentsOf: export.fileURL) == photoData)
        #expect(export.warnings.contains { $0.contains("Paired video missing") })
        #expect(export.warnings.contains { $0.contains("adjustmentData") })
    }

    @Test func localCredentialProbeReusesExportValidationWithoutCreatingShareFile() async throws {
        let photoData = try Self.photoData(captureID: "credential-probe")

        let builder = TAPVerificationExportBuilder(
            temporaryDirectoryProvider: {
                throw TAPVerificationExportTestError.unexpectedExportDirectory
            },
            localValidator: Self.localValidator()
        )
        let resources = PhotoLibraryWriter.SignatureVerificationResources(
            photoData: photoData,
            pairedVideoURL: nil,
            temporaryDirectoryURL: nil,
            presentationAdjustmentResourceLabels: []
        )

        #expect(builder.hasValidCredential(resources: resources))
    }

    @Test func liveMovieMismatchDoesNotGenerateVerificationZip() async throws {
        let signedMovieData = Data("signed-movie".utf8)
        let signedMovieURL = try Self.movieURL(data: signedMovieData)
        let mismatchedMovieURL = try Self.movieURL(data: Data("different-movie".utf8))
        defer {
            try? FileManager.default.removeItem(at: signedMovieURL.deletingLastPathComponent())
            try? FileManager.default.removeItem(at: mismatchedMovieURL.deletingLastPathComponent())
        }
        let photoData = try Self.photoData(captureID: "mismatch-export", livePhoto: Self.livePhotoPayload(), schema: .livePhotoV2)
        let outputDirectory = try TAPCamDemoTestFixtures.makeTemporaryDirectory()

        do {
            _ = try TAPVerificationExportBuilder(
                temporaryDirectoryProvider: { outputDirectory },
                localValidator: Self.localValidator(expectedMovieData: signedMovieData)
            ).export(resources: PhotoLibraryWriter.SignatureVerificationResources(
                photoData: photoData,
                pairedVideoURL: mismatchedMovieURL,
                temporaryDirectoryURL: nil,
                presentationAdjustmentResourceLabels: []
            ))
            Issue.record("Expected mismatched paired MOV to fail Live Photo export.")
        } catch {
            #expect(!FileManager.default.fileExists(atPath: outputDirectory.path))
        }
    }

    @Test func signatureVerificationPanelExposesExportWithoutRawMaterial() throws {
        let panelSource = try TAPCamDemoTestSourceInspection.source(
            relativePath: "TAPCamDemo/DepthAnalysis/AppAttestSignatureVerificationPanel.swift"
        )

        #expect(panelSource.contains("Export Originals"))
        #expect(panelSource.contains("VerificationExportActivityView"))
        #expect(!panelSource.contains("assertionObject"))
        #expect(!panelSource.contains("keyId"))
        #expect(!panelSource.contains("bodySHA256"))
    }

    private static func photoData(
        captureID: String,
        livePhoto: TAPDepthManifest.LivePhoto? = nil,
        schema: TAPDepthManifest.Schema = TAPDepthManifest.Schema()
    ) throws -> Data {
        let capturedAt = "2026-07-02T00:00:00.000Z"
        let manifest = TAPDepthManifest(
            payload: TAPCamDemoTestFixtures.samplePayload(
                id: captureID,
                capturedAt: capturedAt,
                location: nil,
                livePhoto: livePhoto
            ),
            schema: schema
        )
        return try TAPCaptureProvenanceWriter().writeManifest(
            manifest,
            into: TAPCaptureProvenanceTestFixtures.sampleHEICSourceData()
        ).data
    }

    private static func livePhotoPayload() -> TAPDepthManifest.LivePhoto {
        TAPDepthManifest.LivePhoto(
            presence: "paired-video",
            pairedVideoFilename: "paired-video.mov",
            durationSeconds: 1.4,
            photoDisplayTimeSeconds: 0.7,
            width: 1920,
            height: 1440,
            videoCodec: "hvc1",
            audio: "not-captured"
        )
    }

    private static func localValidator(
        expectedMovieData: Data? = nil
    ) -> TAPVerificationExportLocalValidator {
        TAPVerificationExportLocalValidator(
            validateStillPhoto: { photoData, _, profile in
                try validatedPhoto(from: photoData, profile: profile)
            },
            validateLivePhoto: { photoData, pairedVideoURL, _, profile in
                if let expectedMovieData,
                   try Data(contentsOf: pairedVideoURL) != expectedMovieData {
                    throw TAPVerificationExportTestError.mismatchedMovie
                }
                return ValidatedTAPLivePhoto(
                    photo: try validatedPhoto(from: photoData, profile: profile),
                    pairedVideoURL: pairedVideoURL
                )
            },
            validateLivePhotoPrimaryPhoto: { photoData, _, profile in
                try validatedPhoto(from: photoData, profile: profile)
            }
        )
    }

    private static func validatedPhoto(
        from photoData: Data,
        profile: CaptureOutputProfile
    ) throws -> ValidatedTAPDepthPhoto {
        ValidatedTAPDepthPhoto(
            data: photoData,
            manifest: try TAPDepthPhotoFileReader.decodedManifest(from: photoData),
            fileContainer: profile.fileContainer
        )
    }

    private static func movieURL(data: Data) throws -> URL {
        let directory = try TAPCamDemoTestFixtures.makeTemporaryDirectory()
        let url = directory.appendingPathComponent("paired-video.mov")
        try data.write(to: url, options: .atomic)
        return url
    }
}

private enum TAPVerificationExportTestError: Error {
    case mismatchedMovie
    case unexpectedExportDirectory
}
