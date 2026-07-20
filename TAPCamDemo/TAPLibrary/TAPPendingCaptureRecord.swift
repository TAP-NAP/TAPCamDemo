//
//  TAPPendingCaptureRecord.swift
//  TAPCamDemo
//

import CoreLocation
import Foundation

nonisolated enum TAPPendingCaptureStatus: String, Codable, Equatable, Sendable {
    case pending
    case waitingNetwork
    case signing
    case signed
    case exporting
    case exported
    case failedRetryable
    case failedTerminal
}

nonisolated enum TAPPendingCaptureArtifactKind: String, Codable, Equatable, Sendable {
    case photoDepth
    case tapVideo
}

nonisolated enum TAPPendingVideoArtifactState: String, Codable, Equatable, Sendable {
    case unsigned
    case signed
}

/// Durable boundary around the non-transactional handoff to Photos.
///
/// `preCommitIntent` is safe to repeat because Photos asset creation has not
/// started. Once `commitAmbiguous` is persisted, a crash may have happened on
/// either side of the Photos commit and recovery must never create again.
nonisolated enum TAPPendingVideoPhotosExportPhase: String, Codable, Equatable, Sendable {
    case preCommitIntent
    case commitAmbiguous
    case committed
}

nonisolated enum TAPPendingCaptureFailureCode: String, Codable, Equatable, Sendable {
    case missingDepthData
    case invalidVideoArtifact
    case proofExternalMutation
    case proofValidationFailed
    case photosReadbackFailed
}

nonisolated struct TAPPendingCaptureLocation: Codable, Equatable, Sendable {
    let latitude: Double
    let longitude: Double
    let altitude: Double
    let horizontalAccuracy: Double
    let verticalAccuracy: Double
    let timestamp: Date

    init(_ location: CLLocation) {
        self.latitude = location.coordinate.latitude
        self.longitude = location.coordinate.longitude
        self.altitude = location.altitude
        self.horizontalAccuracy = location.horizontalAccuracy
        self.verticalAccuracy = location.verticalAccuracy
        self.timestamp = location.timestamp
    }

    var clLocation: CLLocation {
        CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
            altitude: altitude,
            horizontalAccuracy: horizontalAccuracy,
            verticalAccuracy: verticalAccuracy,
            timestamp: timestamp
        )
    }
}

nonisolated struct TAPPendingCaptureRecord: Codable, Equatable, Identifiable, Sendable {
    let captureID: String
    let packageID: UUID
    let capturedAt: Date
    let createdAt: Date
    var updatedAt: Date
    var status: TAPPendingCaptureStatus
    var artifactKind: TAPPendingCaptureArtifactKind
    var photoFileContainer: CapturePhotoFileContainer
    var photoQualityLevel: CapturePhotoQualityLevel
    var captureScoreSummary: CaptureScoreSummary
    var unsignedPhotoFilename: String?
    var signedPhotoFilename: String?
    var videoArtifactFilename: String?
    var videoFormatRevision: Int?
    var videoArtifactState: TAPPendingVideoArtifactState?
    var videoPhotosExportPhase: TAPPendingVideoPhotosExportPhase?
    var posterRevision: Int?
    var exportResourceFilename: String?
    var preSignContentBinding: CaptureContentBinding?
    var failureCode: TAPPendingCaptureFailureCode?
    var duplicateExportWarning: String?
    var pairedVideoFilename: String?
    var thumbnailFilename: String?
    var assetLocalIdentifier: String?
    var failureReason: String?
    var retryCount: Int
    var location: TAPPendingCaptureLocation?

    var id: String {
        captureID
    }

    var isVisiblePendingItem: Bool {
        status != .exported
    }

    var outputProfile: CaptureOutputProfile {
        CaptureOutputProfile.releasePhotoDepthProfile(
            fileContainer: photoFileContainer,
            photoQualityLevel: photoQualityLevel
        )
    }

    /// Legacy HEIC field retained for older tests and decoded records.
    var unsignedHEICFilename: String? {
        get { photoFileContainer == .heic ? unsignedPhotoFilename : nil }
        set {
            photoFileContainer = .heic
            unsignedPhotoFilename = newValue
        }
    }

    /// Legacy HEIC field retained for older tests and decoded records.
    var signedHEICFilename: String? {
        get { photoFileContainer == .heic ? signedPhotoFilename : nil }
        set {
            photoFileContainer = .heic
            signedPhotoFilename = newValue
        }
    }

    init(
        captureID: String,
        packageID: UUID,
        capturedAt: Date,
        createdAt: Date,
        updatedAt: Date,
        status: TAPPendingCaptureStatus,
        artifactKind: TAPPendingCaptureArtifactKind = .photoDepth,
        photoFileContainer: CapturePhotoFileContainer = .heic,
        photoQualityLevel: CapturePhotoQualityLevel = .quality,
        captureScoreSummary: CaptureScoreSummary = .unknown,
        unsignedPhotoFilename: String? = nil,
        signedPhotoFilename: String? = nil,
        videoArtifactFilename: String? = nil,
        videoFormatRevision: Int? = nil,
        videoArtifactState: TAPPendingVideoArtifactState? = nil,
        videoPhotosExportPhase: TAPPendingVideoPhotosExportPhase? = nil,
        posterRevision: Int? = nil,
        exportResourceFilename: String? = nil,
        preSignContentBinding: CaptureContentBinding? = nil,
        failureCode: TAPPendingCaptureFailureCode? = nil,
        duplicateExportWarning: String? = nil,
        pairedVideoFilename: String? = nil,
        unsignedHEICFilename: String? = nil,
        signedHEICFilename: String? = nil,
        thumbnailFilename: String?,
        assetLocalIdentifier: String?,
        failureReason: String?,
        retryCount: Int,
        location: TAPPendingCaptureLocation?
    ) {
        self.captureID = captureID
        self.packageID = packageID
        self.capturedAt = capturedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.status = status
        self.artifactKind = artifactKind
        self.photoFileContainer = photoFileContainer
        self.photoQualityLevel = photoQualityLevel
        self.captureScoreSummary = captureScoreSummary
        self.unsignedPhotoFilename = unsignedPhotoFilename ?? unsignedHEICFilename
        self.signedPhotoFilename = signedPhotoFilename ?? signedHEICFilename
        self.videoArtifactFilename = videoArtifactFilename
        self.videoFormatRevision = videoFormatRevision
        self.videoArtifactState = videoArtifactState
        self.videoPhotosExportPhase = videoPhotosExportPhase
        self.posterRevision = posterRevision
        self.exportResourceFilename = exportResourceFilename
        self.preSignContentBinding = preSignContentBinding
        self.failureCode = failureCode
        self.duplicateExportWarning = duplicateExportWarning
        self.pairedVideoFilename = pairedVideoFilename
        self.thumbnailFilename = thumbnailFilename
        self.assetLocalIdentifier = assetLocalIdentifier
        self.failureReason = failureReason
        self.retryCount = retryCount
        self.location = location
    }

    private enum CodingKeys: String, CodingKey {
        case captureID
        case packageID
        case capturedAt
        case createdAt
        case updatedAt
        case status
        case artifactKind
        case photoFileContainer
        case photoQualityLevel
        case captureScoreSummary
        case unsignedPhotoFilename
        case signedPhotoFilename
        case videoArtifactFilename
        case videoFormatRevision
        case videoArtifactState
        case videoPhotosExportPhase
        case posterRevision
        case exportResourceFilename
        case preSignContentBinding
        case failureCode
        case duplicateExportWarning
        case pairedVideoFilename
        case unsignedHEICFilename
        case signedHEICFilename
        case thumbnailFilename
        case assetLocalIdentifier
        case failureReason
        case retryCount
        case location
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let photoFileContainer = try container.decodeIfPresent(
            CapturePhotoFileContainer.self,
            forKey: .photoFileContainer
        ) ?? .heic

        self.init(
            captureID: try container.decode(String.self, forKey: .captureID),
            packageID: try container.decode(UUID.self, forKey: .packageID),
            capturedAt: try container.decode(Date.self, forKey: .capturedAt),
            createdAt: try container.decode(Date.self, forKey: .createdAt),
            updatedAt: try container.decode(Date.self, forKey: .updatedAt),
            status: try container.decode(TAPPendingCaptureStatus.self, forKey: .status),
            artifactKind: try container.decodeIfPresent(
                TAPPendingCaptureArtifactKind.self,
                forKey: .artifactKind
            ) ?? .photoDepth,
            photoFileContainer: photoFileContainer,
            photoQualityLevel: try container.decodeIfPresent(
                CapturePhotoQualityLevel.self,
                forKey: .photoQualityLevel
            ) ?? .quality,
            captureScoreSummary: try container.decodeIfPresent(
                CaptureScoreSummary.self,
                forKey: .captureScoreSummary
            ) ?? .unknown,
            unsignedPhotoFilename: try container.decodeIfPresent(String.self, forKey: .unsignedPhotoFilename),
            signedPhotoFilename: try container.decodeIfPresent(String.self, forKey: .signedPhotoFilename),
            videoArtifactFilename: try container.decodeIfPresent(String.self, forKey: .videoArtifactFilename),
            videoFormatRevision: try container.decodeIfPresent(Int.self, forKey: .videoFormatRevision),
            videoArtifactState: try container.decodeIfPresent(TAPPendingVideoArtifactState.self, forKey: .videoArtifactState),
            videoPhotosExportPhase: try container.decodeIfPresent(
                TAPPendingVideoPhotosExportPhase.self,
                forKey: .videoPhotosExportPhase
            ),
            posterRevision: try container.decodeIfPresent(Int.self, forKey: .posterRevision),
            exportResourceFilename: try container.decodeIfPresent(String.self, forKey: .exportResourceFilename),
            preSignContentBinding: try container.decodeIfPresent(CaptureContentBinding.self, forKey: .preSignContentBinding),
            failureCode: try container.decodeIfPresent(TAPPendingCaptureFailureCode.self, forKey: .failureCode),
            duplicateExportWarning: try container.decodeIfPresent(String.self, forKey: .duplicateExportWarning),
            pairedVideoFilename: try container.decodeIfPresent(String.self, forKey: .pairedVideoFilename),
            unsignedHEICFilename: try container.decodeIfPresent(String.self, forKey: .unsignedHEICFilename),
            signedHEICFilename: try container.decodeIfPresent(String.self, forKey: .signedHEICFilename),
            thumbnailFilename: try container.decodeIfPresent(String.self, forKey: .thumbnailFilename),
            assetLocalIdentifier: try container.decodeIfPresent(String.self, forKey: .assetLocalIdentifier),
            failureReason: try container.decodeIfPresent(String.self, forKey: .failureReason),
            retryCount: try container.decode(Int.self, forKey: .retryCount),
            location: try container.decodeIfPresent(TAPPendingCaptureLocation.self, forKey: .location)
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(captureID, forKey: .captureID)
        try container.encode(packageID, forKey: .packageID)
        try container.encode(capturedAt, forKey: .capturedAt)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encode(status, forKey: .status)
        try container.encode(artifactKind, forKey: .artifactKind)
        try container.encode(photoFileContainer, forKey: .photoFileContainer)
        try container.encode(photoQualityLevel, forKey: .photoQualityLevel)
        try container.encode(captureScoreSummary, forKey: .captureScoreSummary)
        try container.encodeIfPresent(unsignedPhotoFilename, forKey: .unsignedPhotoFilename)
        try container.encodeIfPresent(signedPhotoFilename, forKey: .signedPhotoFilename)
        try container.encodeIfPresent(videoArtifactFilename, forKey: .videoArtifactFilename)
        try container.encodeIfPresent(videoFormatRevision, forKey: .videoFormatRevision)
        try container.encodeIfPresent(videoArtifactState, forKey: .videoArtifactState)
        try container.encodeIfPresent(videoPhotosExportPhase, forKey: .videoPhotosExportPhase)
        try container.encodeIfPresent(posterRevision, forKey: .posterRevision)
        try container.encodeIfPresent(exportResourceFilename, forKey: .exportResourceFilename)
        try container.encodeIfPresent(preSignContentBinding, forKey: .preSignContentBinding)
        try container.encodeIfPresent(failureCode, forKey: .failureCode)
        try container.encodeIfPresent(duplicateExportWarning, forKey: .duplicateExportWarning)
        try container.encodeIfPresent(pairedVideoFilename, forKey: .pairedVideoFilename)
        try container.encodeIfPresent(thumbnailFilename, forKey: .thumbnailFilename)
        try container.encodeIfPresent(assetLocalIdentifier, forKey: .assetLocalIdentifier)
        try container.encodeIfPresent(failureReason, forKey: .failureReason)
        try container.encode(retryCount, forKey: .retryCount)
        try container.encodeIfPresent(location, forKey: .location)
    }
}
