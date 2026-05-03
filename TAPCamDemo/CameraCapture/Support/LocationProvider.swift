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
/// records `location: null` when no recent value is available, and the HEIC
/// still contains all camera/depth data needed by downstream tooling.
@MainActor
final class LocationProvider: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocation?, Never>?
    private var timeoutTask: Task<Void, Never>?
    private var cachedLocation: CLLocation?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
    }

    func requestOneShotLocation(timeout: TimeInterval = 2.0) async -> CLLocation? {
        if continuation != nil {
            finish(with: nil)
        }

        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            self.timeoutTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                await MainActor.run {
                    self?.finish(with: nil)
                }
            }

            requestLocationForCurrentAuthorizationStatus(shouldRequestAuthorization: true)
        }
    }

    /// Returns a recent cached location without starting or waiting for Core
    /// Location work. This keeps a shutter press from waiting on GPS permission,
    /// radio state, or the timeout used by the legacy one-shot helper.
    func cachedCaptureLocation(maxAge: TimeInterval = 300) -> CLLocation? {
        guard let cachedLocation,
              abs(cachedLocation.timestamp.timeIntervalSinceNow) <= maxAge else {
            return nil
        }

        return cachedLocation
    }

    /// Starts a one-shot Core Location refresh without awaiting the result.
    /// Existing callers can request permission on a user gesture, but the current
    /// capture uses only the cache that was already available at shutter time.
    func warmLocationCache(shouldRequestAuthorization: Bool = false) {
        guard continuation == nil else {
            return
        }

        requestLocationForCurrentAuthorizationStatus(shouldRequestAuthorization: shouldRequestAuthorization)
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor [weak self] in
            guard let self else { return }

            requestLocationForCurrentAuthorizationStatus(shouldRequestAuthorization: false)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor [weak self] in
            self?.finish(with: locations.last)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor [weak self] in
            self?.finish(with: nil)
        }
    }

    private func finish(with location: CLLocation?) {
        if let location {
            cachedLocation = location
        }

        timeoutTask?.cancel()
        timeoutTask = nil
        continuation?.resume(returning: location)
        continuation = nil
    }

    private func requestLocationForCurrentAuthorizationStatus(shouldRequestAuthorization: Bool) {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            manager.requestLocation()
        case .notDetermined:
            if shouldRequestAuthorization {
                manager.requestWhenInUseAuthorization()
            }
        case .denied, .restricted:
            finish(with: nil)
        @unknown default:
            finish(with: nil)
        }
    }
}
