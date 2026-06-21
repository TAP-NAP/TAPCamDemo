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
    var unsignedHEICFilename: String?
    var signedHEICFilename: String?
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
}
