//
//  TAPCamDemoTestFixtures.swift
//  TAPCamDemoTests
//

import AVFoundation
import CoreLocation
import Foundation
import Testing
import UIKit
@testable import TAPCamDemo

enum TAPCamDemoTestFixtures {
    static func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("TAPCamDemoTests.\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func ingestPendingTAPVideo(
        store: TAPPendingCaptureStore,
        captureID: String,
        packageID: UUID = UUID(uuidString: "00000000-0000-0000-0000-000000000779")!,
        hasDepth: Bool = true
    ) async throws -> TAPPendingCaptureRecord {
        let workspace = try await store.beginVideoCaptureWorkspace(captureID: captureID)
        var baseMP4 = Data([0, 0, 0, 12])
        baseMP4.append(Data("ftyp".utf8))
        baseMP4.append(Data("mp42".utf8))
        try baseMP4.write(to: workspace.artifactURL)

        let manifest = TAPVideoManifest(payload: TAPVideoManifest.Payload(
            id: captureID,
            packageID: packageID.uuidString,
            capturedAt: "2026-07-11T00:00:00Z",
            selectedCameraPlan: .init(
                deviceUniqueID: "test-device",
                deviceType: "BuiltInLiDARDepthCamera",
                localizedName: "Back Camera",
                position: "back",
                requestedFocalLengthLabel: "24mm",
                resolvedFocalLengthLabel: "24mm",
                resolvedZoomFactor: 1,
                depthCapable: true
            ),
            container: .init(
                fileType: "mp4",
                mediaType: "video/mp4",
                durationSeconds: 1,
                timeScale: 600,
                trackCount: hasDepth ? 2 : 1
            ),
            rgbTrack: .init(
                trackID: 1,
                codec: "avc1",
                width: 1_920,
                height: 1_080,
                durationSeconds: 1,
                timeScale: 600,
                nominalFrameRate: 30,
                frameCount: 30,
                transform: "rotation:0;not-mirrored"
            ),
            audioTrack: .init(
                status: .notCaptured,
                trackID: nil,
                codec: nil,
                durationSeconds: nil,
                timeScale: nil,
                sampleRate: nil,
                channelCount: nil
            ),
            depthCoverage: hasDepth ? .init(
                trackID: 3,
                trackCodec: "mebx",
                trackDurationSeconds: 1,
                trackTimeScale: 600,
                sampleCount: 1,
                format: .init(
                    kind: "depth",
                    pixelFormat: "hdep",
                    width: 256,
                    height: 192,
                    packedRowStride: 512,
                    sourceRowStride: 544,
                    bytesPerSample: 2,
                    uncompressedFrameByteCount: 98_304
                )
            ) : .none,
            spatialRegistration: .unavailable,
            synchronization: .init(
                timing: "capture-relative-presentation-timestamps",
                rgbToDepthMapping: hasDepth ? "independent-timed-metadata" : "no-depth-samples",
                maxObservedDeltaSeconds: 0,
                nominalDepthIntervalSeconds: 1.0 / 30.0
            ),
            stop: .init(reason: .userStop, recordedDurationSeconds: 1),
            software: .current
        ))
        try TAPVideoManifestBox.appendManifest(manifest, toFileAt: workspace.artifactURL)
        _ = try TAPProofSlot.ensureEmptyBMFFSlot(inFileAt: workspace.artifactURL)

        return try await store.ingestVideo(TAPPendingVideoCaptureArtifact(
            captureID: captureID,
            packageID: packageID,
            capturedAt: Date(timeIntervalSince1970: 1_779_897_600),
            videoURL: workspace.artifactURL
        ))
    }

    static let pendingVideoTestProof = Data("test-only-proof-envelope".utf8)

    /// Exercises the real store publication boundary with an opaque test
    /// proof. Queue tests inject validation; this is not a cryptographic proof.
    static func publishPendingVideoWithTestProof(
        store: TAPPendingCaptureStore,
        captureID: String
    ) async throws -> TAPPendingCaptureRecord {
        _ = try await store.updateStatus(captureID: captureID, status: .signing)
        let artifact = try await store.beginVideoSigningArtifact(captureID: captureID)
        do {
            try TAPProofSlot.writeProofEnvelope(pendingVideoTestProof, intoBMFFFileAt: artifact.fileURL)
            return try await store.publishVideoSigningArtifact(artifact)
        } catch {
            try? await store.discardVideoSigningArtifact(artifact)
            throw error
        }
    }

    static var sampleLocation: TAPDepthManifest.Location {
        TAPDepthManifest.Location(
            latitude: 31.2304,
            longitude: 121.4737,
            altitude: 12.0,
            horizontalAccuracy: 5.0,
            verticalAccuracy: 8.0,
            timestamp: "2026-04-25T00:00:00.000Z"
        )
    }

    static var sampleHighPrecisionLocation: TAPDepthManifest.Location {
        TAPDepthManifest.Location(
            latitude: 12.34567890123456,
            longitude: 65.43210987654321,
            altitude: 123.45678901234567,
            horizontalAccuracy: 98.76543210987654,
            verticalAccuracy: 87.65432109876544,
            timestamp: "2035-01-01T00:00:00.000Z"
        )
    }

    static func samplePayload(
        id: String = "sample-capture",
        capturedAt: String = "2026-04-25T00:00:00.000Z",
        location: TAPDepthManifest.Location?,
        depthAvailability: CaptureDepthAvailability = .available,
        livePhoto: TAPDepthManifest.LivePhoto? = nil
    ) -> TAPDepthManifest.Payload {
        let hasDepth = depthAvailability == .available

        return TAPDepthManifest.Payload(
            id: id,
            capturedAt: capturedAt,
            camera: TAPDepthManifest.Camera(
                localizedName: "Back Triple Camera",
                uniqueID: "com.apple.test-camera",
                modelID: "iPhone",
                deviceType: "AVCaptureDeviceTypeBuiltInTripleCamera",
                position: "back",
                activePrimaryConstituentDeviceType: "AVCaptureDeviceTypeBuiltInWideAngleCamera",
                activePrimaryConstituentDeviceName: "Back Wide Camera",
                activeFormat: TAPDepthManifest.CameraFormat(
                    mediaSubType: "420v",
                    width: 4032,
                    height: 3024,
                    maxFrameRate: 30
                ),
                activeDepthFormat: TAPDepthManifest.CameraFormat(
                    mediaSubType: "hdep",
                    width: 256,
                    height: 192,
                    maxFrameRate: 30
                ),
                lensPosition: 0.35,
                minimumFocusDistanceMillimeters: 120,
                nominalFocalLengthIn35mmFilmMillimeters: 24
            ),
            photo: TAPDepthManifest.Photo(
                width: 4032,
                height: 3024,
                orientation: "cgImagePropertyOrientation:1",
                metadataKeys: ["{Exif}", "{TIFF}"]
            ),
            depth: TAPDepthManifest.Depth(
                availability: depthAvailability,
                auxiliaryDataKind: hasDepth ? "depth" : "none",
                depthDataType: hasDepth ? "hdep" : "none",
                metricUnit: hasDepth ? "meters" : "none",
                conversionPath: hasDepth ? "nativeDepthMeters" : "depthUnavailable",
                width: hasDepth ? 256 : 0,
                height: hasDepth ? 192 : 0,
                pixelFormat: hasDepth ? "hdep" : "none",
                orientation: hasDepth ? "appleAuxiliaryDepthNative" : "unavailable",
                accuracy: hasDepth ? "absolute" : "unavailable",
                quality: hasDepth ? "high" : "unavailable",
                isFiltered: hasDepth,
                source: TAPDepthManifest.DepthSource(
                    captureDeviceType: "AVCaptureDeviceTypeBuiltInTripleCamera",
                    captureDeviceName: "Back Triple Camera",
                    sensingMethod: "multiCameraStereoOrComputational",
                    lidarParticipation: "notAsserted"
                ),
                cameraCalibration: nil
            ),
            location: location,
            software: TAPDepthManifest.Software(
                appName: "TAPCamDemo",
                bundleIdentifier: "TAP-NAP.TAPCamDemo",
                version: "1.0",
                build: "1"
            ),
            livePhoto: livePhoto
        )
    }

    static func analysisInput(depthMap: TAPMetricDepthMap) throws -> TAPDepthAnalysisInput {
        let rgbaPixel = [UInt8(20), UInt8(20), UInt8(20), UInt8(255)]
        let image = try TAPDepthRGBAImageRenderer.image(
            pixels: Array(repeating: rgbaPixel, count: depthMap.samples.count).flatMap { $0 },
            width: depthMap.width,
            height: depthMap.height
        )

        return TAPDepthAnalysisInput(
            manifest: nil,
            image: image,
            imageOrientation: .up,
            depthMap: depthMap,
            depthAccuracy: "unknown",
            depthQuality: "unknown",
            heatmap: try TAPDepthHeatmapRenderer.heatmap(for: depthMap)
        )
    }

    static var sampleCalibration: TAPDepthManifest.CameraCalibration {
        TAPDepthManifest.CameraCalibration(
            intrinsicMatrixReferenceWidth: 8,
            intrinsicMatrixReferenceHeight: 8,
            pixelSizeMillimeters: 0.001,
            lensDistortionLookupTablePresent: false,
            inverseLensDistortionLookupTablePresent: false,
            lensDistortionCenterX: 4,
            lensDistortionCenterY: 4,
            intrinsicMatrix: [100, 0, 0, 0, 100, 0, 4, 4, 1],
            extrinsicMatrix: [1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0]
        )
    }

    static func sampleManualControlCapability(
        deviceID: String = "device-1",
        deviceDisplayName: String = "Wide",
        deviceTypeRawValue: String = "built-in-wide",
        supportsContinuousAutoExposure: Bool = true,
        supportsLockedExposure: Bool = true,
        supportsCustomExposure: Bool = true,
        supportsAutoFocus: Bool = true,
        supportsContinuousAutoFocus: Bool = true,
        supportsLockedFocus: Bool = true,
        supportsCustomLensPosition: Bool = true,
        supportsFocusPointOfInterest: Bool = true,
        supportsLockedWhiteBalance: Bool = true,
        supportsContinuousAutoWhiteBalance: Bool = true,
        minimumFocusDistanceMillimeters: Int? = 120,
        exposureBiasRange: CameraControlCapabilitySnapshot.DoubleRange = .init(minimum: -2, maximum: 2),
        isoRange: CameraControlCapabilitySnapshot.DoubleRange = .init(minimum: 32, maximum: 1_600),
        shutterDurationRangeSeconds: CameraControlCapabilitySnapshot.DoubleRange = .init(
            minimum: 1.0 / 12_000.0,
            maximum: 1
        ),
        currentISO: Double = 100,
        currentShutterDurationSeconds: Double = 1.0 / 120.0,
        currentExposureTargetOffset: Double = 0,
        currentLensPosition: Double = 0.5,
        zoomRange: CameraControlCapabilitySnapshot.DoubleRange = .init(minimum: 1, maximum: 15)
    ) -> CameraControlCapabilitySnapshot {
        CameraControlCapabilitySnapshot(
            deviceID: deviceID,
            deviceDisplayName: deviceDisplayName,
            deviceTypeRawValue: deviceTypeRawValue,
            exposure: CameraControlCapabilitySnapshot.Exposure(
                supportsContinuousAutoExposure: supportsContinuousAutoExposure,
                supportsLockedExposure: supportsLockedExposure,
                supportsCustomExposure: supportsCustomExposure,
                exposureBiasRange: exposureBiasRange,
                isoRange: isoRange,
                shutterDurationRangeSeconds: shutterDurationRangeSeconds,
                currentISO: currentISO,
                currentShutterDurationSeconds: currentShutterDurationSeconds,
                currentExposureTargetOffset: currentExposureTargetOffset
            ),
            focus: CameraControlCapabilitySnapshot.Focus(
                supportsAutoFocus: supportsAutoFocus,
                supportsContinuousAutoFocus: supportsContinuousAutoFocus,
                supportsLockedFocus: supportsLockedFocus,
                supportsCustomLensPosition: supportsCustomLensPosition,
                supportsFocusPointOfInterest: supportsFocusPointOfInterest,
                supportsSmoothAutoFocus: true,
                minimumFocusDistanceMillimeters: minimumFocusDistanceMillimeters,
                currentLensPosition: currentLensPosition
            ),
            whiteBalance: CameraControlCapabilitySnapshot.WhiteBalance(
                supportsContinuousAutoWhiteBalance: supportsContinuousAutoWhiteBalance,
                supportsLockedWhiteBalance: supportsLockedWhiteBalance,
                maximumGain: 4
            ),
            aperture: CameraControlCapabilitySnapshot.Aperture(fixedLensAperture: 1.78),
            zoom: CameraControlCapabilitySnapshot.Zoom(range: zoomRange)
        )
    }

    static func samplePendingRecord(
        captureID: String,
        capturedAt: Date,
        status: TAPPendingCaptureStatus = .pending,
        unsignedPhotoFilename: String? = "unsigned.heic",
        signedPhotoFilename: String? = nil,
        pairedVideoFilename: String? = nil,
        thumbnailFilename: String? = nil,
        assetLocalIdentifier: String? = nil,
        failureReason: String? = nil,
        photoQualityLevel: CapturePhotoQualityLevel = .quality,
        captureScoreSummary: CaptureScoreSummary = .unknown,
        location: TAPPendingCaptureLocation? = nil
    ) -> TAPPendingCaptureRecord {
        TAPPendingCaptureRecord(
            captureID: captureID,
            packageID: UUID(uuidString: "00000000-0000-0000-0000-000000000456")!,
            capturedAt: capturedAt,
            createdAt: capturedAt,
            updatedAt: capturedAt,
            status: status,
            photoQualityLevel: photoQualityLevel,
            captureScoreSummary: captureScoreSummary,
            unsignedPhotoFilename: status == .exported ? nil : unsignedPhotoFilename,
            signedPhotoFilename: signedPhotoFilename,
            pairedVideoFilename: pairedVideoFilename,
            thumbnailFilename: thumbnailFilename,
            assetLocalIdentifier: assetLocalIdentifier,
            failureReason: failureReason,
            retryCount: 0,
            location: location
        )
    }

    static func samplePendingVideoRecord(
        captureID: String,
        capturedAt: Date,
        status: TAPPendingCaptureStatus = .pending,
        videoArtifactState: TAPPendingVideoArtifactState = .unsigned,
        assetLocalIdentifier: String? = nil
    ) -> TAPPendingCaptureRecord {
        TAPPendingCaptureRecord(
            captureID: captureID,
            packageID: UUID(uuidString: "00000000-0000-0000-0000-000000000457")!,
            capturedAt: capturedAt,
            createdAt: capturedAt,
            updatedAt: capturedAt,
            status: status,
            artifactKind: .tapVideo,
            unsignedPhotoFilename: nil,
            signedPhotoFilename: nil,
            videoArtifactFilename: TAPPendingCaptureBundlePaths.videoArtifactFilename,
            videoArtifactState: videoArtifactState,
            thumbnailFilename: nil,
            assetLocalIdentifier: assetLocalIdentifier,
            failureReason: nil,
            retryCount: 0,
            location: nil
        )
    }

    static func samplePendingArtifact(
        photoData: Data,
        fileContainer: CapturePhotoFileContainer = .heic,
        photoQualityLevel: CapturePhotoQualityLevel = .quality,
        captureID: String = "sample-capture",
        capturedAt: Date = Date(timeIntervalSince1970: 0),
        livePhotoMovie: PackagedLivePhotoMovie? = nil
    ) -> PackagedCaptureArtifact {
        PackagedCaptureArtifact(
            packageID: UUID(uuidString: "00000000-0000-0000-0000-000000000123")!,
            photoData: photoData,
            fileContainer: fileContainer,
            photoQualityLevel: photoQualityLevel,
            manifest: TAPDepthManifest(payload: samplePayload(
                id: captureID,
                capturedAt: TAPDateFormatting.iso8601.string(from: capturedAt),
                location: sampleLocation
            )),
            livePhotoMovie: livePhotoMovie,
            signatureStatus: .unsigned(reason: "test"),
            depthAvailability: .available,
            captureScoreSummary: CaptureScoreSummary.make(
                depthAvailability: .available,
                fileContainer: fileContainer,
                photoQualityLevel: photoQualityLevel,
                signatureStatus: .unsigned(reason: "test")
            ),
            packagingMetrics: CapturePackagingMetrics(),
            capturedAt: capturedAt,
            location: CLLocation(
                coordinate: CLLocationCoordinate2D(latitude: 31.2304, longitude: 121.4737),
                altitude: 12,
                horizontalAccuracy: 5,
                verticalAccuracy: 8,
                timestamp: Date(timeIntervalSince1970: 0)
            )
        )
    }

    static func sampleThumbnailSourceData() -> Data {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 16, height: 16))
        return renderer.jpegData(withCompressionQuality: 0.9) { context in
            let rect = CGRect(x: 0, y: 0, width: 16, height: 16)
            context.cgContext.setFillColor(UIColor.systemTeal.cgColor)
            context.cgContext.fill(rect)
        }
    }

    static func pendingCaptureBundleJSON(rootURL: URL, captureID: String) throws -> String {
        let data = try Data(
            contentsOf: rootURL
                .appendingPathComponent(captureID, isDirectory: true)
                .appendingPathComponent("bundle.json")
        )
        return try #require(String(data: data, encoding: .utf8))
    }

    static func writePendingRecord(
        _ record: TAPPendingCaptureRecord,
        rootURL: URL,
        bundleCaptureID: String? = nil
    ) throws {
        let bundleURL = rootURL.appendingPathComponent(
            bundleCaptureID ?? record.captureID,
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: bundleURL, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(record)
        try data.write(to: bundleURL.appendingPathComponent("bundle.json"), options: Data.WritingOptions.atomic)
    }
}
