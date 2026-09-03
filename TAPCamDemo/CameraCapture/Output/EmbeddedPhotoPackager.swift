//
//  EmbeddedPhotoPackager.swift
//  TAPCamDemo
//
//  Created by Codex on 2026/4/27.
//

@preconcurrency import AVFoundation
import Foundation
import OSLog

/// Default Release-safe packager.
///
/// It preserves Apple's photo-depth output using
/// `AVCapturePhoto.fileDataRepresentation(with:)`, then injects TAP's XMP
/// manifest without creating sidecars. This is the only packaging strategy used
/// by the app in Release.
nonisolated struct EmbeddedPhotoPackager: Sendable {
    private let provenanceWriter: TAPCaptureProvenanceWriter

    init(provenanceWriter: TAPCaptureProvenanceWriter = TAPCaptureProvenanceWriter()) {
        self.provenanceWriter = provenanceWriter
    }

    /// Converts a logical package into the single Release depth-photo artifact.
    ///
    /// Apple auxiliary depth remains in the photo file, and TAP-specific metadata is
    /// injected into XMP without emitting sidecar files.
    ///
    /// - Tag: PackageEmbeddedDepthPhoto
    func package(_ capturePackage: CapturePackage) throws -> PackagedCaptureArtifact {
        try capturePackage.resolvedOutput.validateForEmbeddedPhotoDepthPackaging()
        let fileContainer = capturePackage.resolvedOutput.fileContainer
        let livePhotoMovie = capturePackage.livePhotoMovie.map {
            PackagedLivePhotoMovie(
                fileURL: $0.fileURL,
                durationSeconds: max(0, $0.duration.seconds),
                photoDisplayTimeSeconds: max(0, $0.photoDisplayTime.seconds),
                width: $0.dimensions.width,
                height: $0.dimensions.height,
                codec: $0.codec,
                capturesAudio: $0.capturesAudio
            )
        }

        var packagingMetrics = CapturePackagingMetrics()

        let manifestBuildStart = Date()
        let unsignedManifest = try TAPDepthManifestBuilder.makeManifest(capturePackage: capturePackage)
        packagingMetrics.manifestBuildDuration = Date().timeIntervalSince(manifestBuildStart)

        let customizer = TAPPhotoFileMetadataCustomizer(
            capturedAt: capturePackage.sourceContext.capturedAt,
            location: capturePackage.sourceContext.location,
            device: capturePackage.sourceContext.sessionConfiguration.device
        )

        let basePhotoStart = Date()
        guard let basePhotoData = capturePackage.photo.fileDataRepresentation(with: customizer) else {
            throw TAPDepthCaptureError.unableToCreatePhotoData
        }
        packagingMetrics.baseHEICDuration = Date().timeIntervalSince(basePhotoStart)
        #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
        TAPDiagnostics.cameraCapture.info("base photo materialized profile=\(capturePackage.resolvedOutput.profileID, privacy: .public) container=\(fileContainer.rawValue, privacy: .public) selectedDimensions=\(capturePackage.resolvedOutput.maxPhotoDimensions?.debugDescription ?? "none", privacy: .public) bytes=\(basePhotoData.count, privacy: .public)")
        #endif

        let writeResult = try provenanceWriter.writeManifest(unsignedManifest, into: basePhotoData)
        packagingMetrics.xmpInjectDuration = writeResult.xmpInjectDuration
        packagingMetrics.xmpVerifyDuration = writeResult.xmpVerifyDuration
        #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
        TAPDiagnostics.cameraCapture.info("unsigned photo packaged profile=\(capturePackage.resolvedOutput.profileID, privacy: .public) container=\(fileContainer.rawValue, privacy: .public) selectedDimensions=\(capturePackage.resolvedOutput.maxPhotoDimensions?.debugDescription ?? "none", privacy: .public) bytes=\(writeResult.data.count, privacy: .public)")
        #endif

        return PackagedCaptureArtifact(
            packageID: capturePackage.job.id,
            photoData: writeResult.data,
            fileContainer: fileContainer,
            photoQualityLevel: capturePackage.resolvedOutput.photoQualityPolicy.requested,
            manifest: unsignedManifest,
            livePhotoMovie: livePhotoMovie,
            signatureStatus: TAPCaptureProvenanceWriter.unsignedCaptureStatus,
            depthAvailability: capturePackage.depthAvailability,
            captureScoreSummary: CaptureScoreSummary.make(
                depthAvailability: capturePackage.depthAvailability,
                fileContainer: fileContainer,
                photoQualityLevel: capturePackage.resolvedOutput.photoQualityPolicy.requested,
                signatureStatus: TAPCaptureProvenanceWriter.unsignedCaptureStatus
            ),
            packagingMetrics: packagingMetrics,
            capturedAt: capturePackage.sourceContext.capturedAt,
            location: capturePackage.sourceContext.location
        )
    }
}
