//
//  LocationProvider.swift
//  TAPCamDemo
//
//  Created by Codex on 2026/4/25.
//

import CoreLocation
import Foundation

/// Best-effort cached location provider for capture metadata.
///
/// Location is optional by design and deliberately stays out of the shutter's
/// critical path. The camera uses a recent cached value if one exists, then
/// refreshes the cache in the background for future captures. The manifest
/// records `location: null` when no recent value is available, and the selected
/// HEIC/JPG file still contains the camera/depth data needed downstream.
@MainActor
final class LocationProvider: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var cachedLocation: CLLocation?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
    }

    /// Returns a recent cached location without starting or waiting for Core
    /// Location work. This keeps a shutter press from waiting on GPS permission
    /// or radio state.
    func cachedCaptureLocation(maxAge: TimeInterval = 300) -> CLLocation? {
        guard let cachedLocation,
              abs(cachedLocation.timestamp.timeIntervalSinceNow) <= maxAge else {
            return nil
        }

        return cachedLocation
    }

    /// Refreshes an already-authorized location without awaiting the result.
    /// The current capture uses only the cache available at shutter time.
    func warmLocationCache() {
        guard manager.authorizationStatus == .authorizedAlways
            || manager.authorizationStatus == .authorizedWhenInUse else {
            return
        }
        manager.requestLocation()
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor [weak self] in
            guard let self else { return }

            warmLocationCache()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor [weak self] in
            self?.cachedLocation = location
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}

}
