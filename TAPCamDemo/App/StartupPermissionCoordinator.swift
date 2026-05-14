//
//  StartupPermissionCoordinator.swift
//  TAPCamDemo
//

import AVFoundation
import Combine
import CoreLocation
import Foundation
import Photos

enum StartupPermissionStatus: Equatable {
    case idle
    case requesting
    case granted
    case denied
    case skipped
}

enum StartupGateDefaults {
    static let didCompleteFirstInstallPermissionsKey = "TAPCamDemo.StartupGate.didCompleteFirstInstallPermissions"
}

@MainActor
final class StartupPermissionCoordinator: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var networkStatus: StartupPermissionStatus = .idle
    @Published private(set) var cameraStatus: StartupPermissionStatus = .idle
    @Published private(set) var photoLibraryStatus: StartupPermissionStatus = .idle
    @Published private(set) var locationStatus: StartupPermissionStatus = .idle

    private let locationManager = CLLocationManager()
    private var locationAuthorizationContinuation: CheckedContinuation<CLAuthorizationStatus, Never>?

    override init() {
        super.init()
        locationManager.delegate = self
        refreshAuthorizationStatuses()
    }

    var hasRequiredPermissions: Bool {
        networkStatus == .granted
            && cameraStatus == .granted
            && photoLibraryStatus == .granted
    }

    var hasBlockingDenial: Bool {
        networkStatus == .denied
            || cameraStatus == .denied
            || photoLibraryStatus == .denied
    }

    func refreshAuthorizationStatuses() {
        if networkStatus == .denied {
            Task { await requestNetworkAccess() }
        } else if networkStatus != .requesting,
           let status = NetworkPermissionPreflight.currentPermissionStatus() {
            networkStatus = status
        }

        if cameraStatus != .requesting {
            cameraStatus = Self.cameraStatus()
        }

        if photoLibraryStatus != .requesting {
            photoLibraryStatus = Self.photoLibraryStatus()
        }

        if locationStatus != .requesting {
            locationStatus = Self.locationStatus(from: locationManager.authorizationStatus)
        }
    }

    func requestNetworkAccess() async {
        guard networkStatus != .requesting else {
            return
        }

        networkStatus = .requesting
        let status = await NetworkPermissionPreflight.requestAccessBeforeAppAttest()
        networkStatus = status
    }

    func requestCameraAccess() async {
        guard cameraStatus != .requesting else {
            return
        }

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            cameraStatus = .granted
        case .notDetermined:
            cameraStatus = .requesting
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            cameraStatus = granted ? .granted : .denied
        case .denied, .restricted:
            cameraStatus = .denied
        @unknown default:
            cameraStatus = .denied
        }
    }

    func requestPhotoLibraryAccess() async {
        guard photoLibraryStatus != .requesting else {
            return
        }

        switch PHPhotoLibrary.authorizationStatus(for: .readWrite) {
        case .authorized, .limited:
            photoLibraryStatus = .granted
        case .notDetermined:
            photoLibraryStatus = .requesting
            let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
            photoLibraryStatus = Self.photoLibraryStatus(from: status)
        case .denied, .restricted:
            photoLibraryStatus = .denied
        @unknown default:
            photoLibraryStatus = .denied
        }
    }

    func requestLocationAccess() async {
        guard locationStatus != .requesting else {
            return
        }

        switch locationManager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            locationStatus = .granted
        case .notDetermined:
            locationStatus = .requesting
            let status = await withCheckedContinuation { continuation in
                locationAuthorizationContinuation = continuation
                locationManager.requestWhenInUseAuthorization()
            }
            locationStatus = Self.locationStatus(from: status)
        case .denied, .restricted:
            locationStatus = .denied
        @unknown default:
            locationStatus = .denied
        }
    }

    func skipLocationAccess() {
        guard locationStatus != .requesting else {
            return
        }
        locationStatus = .skipped
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor [weak self] in
            guard let self else { return }

            if let continuation = locationAuthorizationContinuation {
                locationAuthorizationContinuation = nil
                continuation.resume(returning: manager.authorizationStatus)
            } else if locationStatus != .skipped {
                locationStatus = Self.locationStatus(from: manager.authorizationStatus)
            }
        }
    }

    private static func cameraStatus() -> StartupPermissionStatus {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            .granted
        case .notDetermined:
            .idle
        case .denied, .restricted:
            .denied
        @unknown default:
            .denied
        }
    }

    private static func photoLibraryStatus() -> StartupPermissionStatus {
        photoLibraryStatus(from: PHPhotoLibrary.authorizationStatus(for: .readWrite))
    }

    private static func photoLibraryStatus(from status: PHAuthorizationStatus) -> StartupPermissionStatus {
        switch status {
        case .authorized, .limited:
            .granted
        case .notDetermined:
            .idle
        case .denied, .restricted:
            .denied
        @unknown default:
            .denied
        }
    }

    private static func locationStatus(from status: CLAuthorizationStatus) -> StartupPermissionStatus {
        switch status {
        case .authorizedAlways, .authorizedWhenInUse:
            .granted
        case .notDetermined:
            .idle
        case .denied, .restricted:
            .denied
        @unknown default:
            .denied
        }
    }
}

private enum NetworkPermissionPreflight {
    static func currentPermissionStatus() -> StartupPermissionStatus? {
        nil
    }

    static func requestAccessBeforeAppAttest() async -> StartupPermissionStatus {
        let maxAttempts = 30
        for _ in 1...maxAttempts {
            let requestSucceeded = await queryNetworkAvailability()
            if requestSucceeded {
                return .granted
            }

            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }

        return .denied
    }

    private static func queryNetworkAvailability() async -> Bool {
        guard let url = preflightURL() else {
            return false
        }

        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 8)
        request.httpMethod = "GET"

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                return false
            }
            return (200..<300).contains(httpResponse.statusCode)
        } catch {
            return false
        }
    }

    private static func preflightURL() -> URL? {
        if let baseURL = try? AppAttestBackendConfiguration.baseURL() {
            return baseURL.appendingPathComponent("healthz", isDirectory: false)
        }

        return nil
    }
}
