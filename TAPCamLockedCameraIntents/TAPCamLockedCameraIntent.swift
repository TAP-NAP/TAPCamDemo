//
//  TAPCamLockedCameraIntent.swift
//  TAPCamDemo
//

import AppIntents
import Foundation
import LockedCameraCapture
import OSLog

nonisolated enum TAPCamLockedCameraDiagnostics {
    static let subsystem = "TAP-NAP.TAPCamDemo"

    static func logger(category: String = "LockedCameraCapture") -> Logger {
        Logger(subsystem: subsystem, category: category)
    }
}

nonisolated struct TAPCamLockedCameraDefaults: Codable, Equatable, Sendable {
    var outputFormat: String
    var photoQuality: String
    var livePhotoEnabled: Bool
    var flashMode: String

    static let phaseOne = TAPCamLockedCameraDefaults(
        outputFormat: "heic",
        photoQuality: "quality",
        livePhotoEnabled: false,
        flashMode: "off"
    )
}

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

nonisolated struct TAPCamLockedCameraContext: Codable, Equatable, Sendable {
    var schemaVersion: Int
    var generatedAt: Date
    var launchID: String
    var defaults: TAPCamLockedCameraDefaults
    var selectedLensID: TAPCamLockedCameraLensRecord.ID?
    var lenses: [TAPCamLockedCameraLensRecord]
    var unavailableReason: String?

    init(
        schemaVersion: Int = 1,
        generatedAt: Date = Date(),
        launchID: String = UUID().uuidString,
        defaults: TAPCamLockedCameraDefaults = .phaseOne,
        selectedLensID: TAPCamLockedCameraLensRecord.ID? = nil,
        lenses: [TAPCamLockedCameraLensRecord] = [],
        unavailableReason: String? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.generatedAt = generatedAt
        self.launchID = launchID
        self.defaults = defaults
        self.selectedLensID = selectedLensID
        self.lenses = lenses
        self.unavailableReason = unavailableReason
    }

    var selectedLens: TAPCamLockedCameraLensRecord? {
        if let selectedLensID,
           let lens = lenses.first(where: { $0.id == selectedLensID }) {
            return lens
        }
        return lenses.first
    }
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
}

nonisolated enum TAPCamLockedCameraViewState: Equatable, Sendable {
    case starting(String)
    case live(String)
    case capturing(String)
    case recovering(String)
    case unavailable(String)

    var title: String {
        switch self {
        case .starting:
            "Starting Camera"
        case .live:
            "Ready"
        case .capturing:
            "Saving"
        case .recovering:
            "Recovering Camera"
        case .unavailable:
            "Camera Unavailable"
        }
    }

    var message: String {
        switch self {
        case .starting(let message),
             .live(let message),
             .capturing(let message),
             .recovering(let message),
             .unavailable(let message):
            message
        }
    }

    var canCapture: Bool {
        if case .live = self {
            return true
        }
        return false
    }

    var showsPreview: Bool {
        switch self {
        case .unavailable:
            false
        default:
            true
        }
    }

    var showsStatusOverlay: Bool {
        switch self {
        case .live:
            false
        default:
            true
        }
    }

    var isRecovering: Bool {
        switch self {
        case .starting, .recovering, .capturing:
            true
        case .live, .unavailable:
            false
        }
    }

    var isUnavailable: Bool {
        if case .unavailable = self {
            return true
        }
        return false
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

nonisolated struct TAPCamLockedCameraIntent: CameraCaptureIntent {
    private static let logger = TAPCamLockedCameraDiagnostics.logger(
        category: "LockedCameraCaptureIntent"
    )

    typealias AppContext = TAPCamLockedCameraContext

    static let title: LocalizedStringResource = "TAPCam Camera"
    static let description = IntentDescription("Capture photos with TAPCam from the Lock Screen.")
    static var authenticationPolicy: IntentAuthenticationPolicy { .alwaysAllowed }

    @MainActor
    func perform() async throws -> some IntentResult {
        Self.logger.info("locked_camera_intent_perform")
        return .result()
    }
}
