//
//  LocationProvider.swift
//  TAPCamDemo
//
//  Created by Codex on 2026/4/25.
//

import CoreLocation
import Foundation

/// Best-effort one-shot location provider for capture metadata.
///
/// Location is optional by design: lack of permission or a timeout should never
/// convert a valid depth photo into a failed capture. The manifest records
/// `location: null` in that case, and the HEIC still contains all camera/depth
/// data needed by downstream tooling.
@MainActor
final class LocationProvider: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocation?, Never>?
    private var timeoutTask: Task<Void, Never>?

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

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard continuation != nil else { return }

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
