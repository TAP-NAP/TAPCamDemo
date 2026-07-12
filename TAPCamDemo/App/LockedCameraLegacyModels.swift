//
//  LockedCameraLegacyModels.swift
//  TAPCamDemo
//

import Foundation
import LockedCameraCapture

// App-only compatibility models. R0 does not publish these to the capture extension.
nonisolated struct TAPCamLockedCameraLensRecord: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var displayName: String
    var numericLabel: String
    var unitLabel: String
    var equivalentFocalLength35mmMillimeters: Double
    var captureDeviceUniqueID: String
    var captureDeviceTypeRawValue: String
    var captureDevicePosition: String
    var zoomFactor: Double
}

nonisolated struct TAPCamLockedRawCaptureMetadata: Codable, Equatable, Sendable {
    var schemaVersion: Int
    var captureID: String
    var capturedAt: Date
    var artifactKind: String?
    var lensID: TAPCamLockedCameraLensRecord.ID
    var lensDisplayName: String
    var captureDeviceUniqueID: String
    var captureDeviceTypeRawValue: String
    var captureDevicePosition: String?
    var zoomFactor: Double
    var photoFileName: String
    var byteCount: Int
    var depthDataPresent: Bool?
    var depthDataType: UInt32?
    var isDepthDataFiltered: Bool?
    var resolvedPhotoWidth: Int?
    var resolvedPhotoHeight: Int?
    var source: String

    init(
        schemaVersion: Int = 1,
        captureID: String,
        capturedAt: Date,
        artifactKind: String? = nil,
        lens: TAPCamLockedCameraLensRecord,
        photoFileName: String,
        byteCount: Int,
        depthDataPresent: Bool? = nil,
        depthDataType: UInt32? = nil,
        isDepthDataFiltered: Bool? = nil,
        resolvedPhotoWidth: Int? = nil,
        resolvedPhotoHeight: Int? = nil,
        source: String = "locked-camera-capture-poc"
    ) {
        self.schemaVersion = schemaVersion
        self.captureID = captureID
        self.capturedAt = capturedAt
        self.artifactKind = artifactKind
        self.lensID = lens.id
        self.lensDisplayName = lens.displayName
        self.captureDeviceUniqueID = lens.captureDeviceUniqueID
        self.captureDeviceTypeRawValue = lens.captureDeviceTypeRawValue
        self.captureDevicePosition = lens.captureDevicePosition
        self.zoomFactor = lens.zoomFactor
        self.photoFileName = photoFileName
        self.byteCount = byteCount
        self.depthDataPresent = depthDataPresent
        self.depthDataType = depthDataType
        self.isDepthDataFiltered = isDepthDataFiltered
        self.resolvedPhotoWidth = resolvedPhotoWidth
        self.resolvedPhotoHeight = resolvedPhotoHeight
        self.source = source
    }
}

nonisolated enum TAPCamLockedCameraHandoff {
    static let activityType = NSUserActivityTypeLockedCameraCapture
    static let openOnlyActivityType = "TAP-NAP.TAPCamDemo.lockedCamera.openAppOnly"
    static let urlScheme = "tapcamdemo"
    static let urlHost = "locked-camera"
    static let urlOpenPath = "/open"
    static let urlOpenRouteName = "lockedCaptureOpen"
    static let sourceKey = "source"
    static let tapActionKey = "tapAction"
    static let reasonKey = "reason"
    static let sourceValue = "locked-camera-capture-poc"
    static let openTAPCamera = "openTAPCamera"
    static let openTAPLibrary = "openTAPLibrary"
    static let openTAPLibraryAfterLockedCapture = "openTAPLibraryAfterLockedCapture"
    static let openTAPLibraryAwaitingLockedImport = "openTAPLibraryAwaitingLockedImport"
    static let openTAPLibraryRuntimeImport = "openTAPLibraryRuntimeImport"
    static let openTAPCameraRuntimeImport = "openTAPCameraRuntimeImport"
    static let openTAPNeutralRuntimeImport = "openTAPNeutralRuntimeImport"
    static let openTAPMainAppOnly = "openTAPMainAppOnly"
    static let regenerateLockedCameraContext = "regenerateLockedCameraContext"

    static var lockedCaptureOpenURL: URL {
        URL(string: "\(urlScheme)://\(urlHost)\(urlOpenPath)")!
    }

    static func lockedCameraRoute(from url: URL) -> String? {
        guard url.scheme == urlScheme,
              url.host == urlHost,
              url.path == urlOpenPath else {
            return nil
        }
        return urlOpenRouteName
    }
}

nonisolated enum TAPCamLockedSessionContentPathPolicy {
    static let metadataFileName = "metadata.json"
    static let unsignedHEICFileName = "unsigned.heic"
    static let flatHEICFilePrefix = "TAPCam-"
    static let legacyCapturesDirectoryName = "captures"
    static let depthHEICStagingArtifactKind = "locked-depth-heic-staging"
    static let unsignedTAPArtifactKind = "locked-unsigned-tap-artifact"

    static func captureDirectory(sessionContentURL: URL, captureID: String) -> URL {
        sessionContentURL.appendingPathComponent(captureID, isDirectory: true)
    }

    static func metadataURL(in captureDirectory: URL) -> URL {
        captureDirectory.appendingPathComponent(metadataFileName)
    }

    static func unsignedPhotoURL(in captureDirectory: URL) -> URL {
        captureDirectory.appendingPathComponent(unsignedHEICFileName)
    }

    static func flatHEICFileName(captureID: String) -> String {
        "\(flatHEICFilePrefix)\(captureID).heic"
    }

    static func flatHEICURL(sessionContentURL: URL, captureID: String) -> URL {
        sessionContentURL.appendingPathComponent(flatHEICFileName(captureID: captureID))
    }

    static func legacyCapturesDirectory(sessionContentURL: URL) -> URL {
        sessionContentURL.appendingPathComponent(legacyCapturesDirectoryName, isDirectory: true)
    }
}
