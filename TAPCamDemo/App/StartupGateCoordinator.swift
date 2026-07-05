//
//  StartupGateCoordinator.swift
//  TAPCamDemo
//

import AVFoundation
import Combine
import CoreLocation
import Foundation
import Photos

nonisolated protocol StartupSecurityPreflightChecking: Sendable {
    func currentRequirementStatus() -> StartupGateRequirementStatus?
    func performRequiredPreflight() async -> StartupGateRequirementStatus
}

@MainActor
final class StartupGateCoordinator: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var securityPreflightStatus: StartupGateRequirementStatus = .idle
    @Published private(set) var cameraStatus: StartupGateRequirementStatus = .idle
    @Published private(set) var photoLibraryStatus: StartupGateRequirementStatus = .idle
    @Published private(set) var locationStatus: StartupGateRequirementStatus = .idle
    @Published private(set) var microphoneStatus: StartupGateRequirementStatus = .idle

    private let locationManager = CLLocationManager()
    private let securityPreflight: any StartupSecurityPreflightChecking
    private var locationAuthorizationContinuation: CheckedContinuation<CLAuthorizationStatus, Never>?

    init(securityPreflight: any StartupSecurityPreflightChecking = StartupBackendSecurityPreflight()) {
        self.securityPreflight = securityPreflight
        super.init()
        locationManager.delegate = self
        refreshAuthorizationStatuses()
    }

    var hasCompletedRequiredStartupChecks: Bool {
        statusSnapshot.hasCompletedRequiredStartupChecks
    }

    var hasBlockingStartupFailure: Bool {
        statusSnapshot.hasBlockingStartupFailure
    }

    var hasSecurityPreflightFailure: Bool {
        statusSnapshot.hasSecurityPreflightFailure
    }

    var hasSettingsResolvablePermissionFailure: Bool {
        statusSnapshot.hasSettingsResolvablePermissionFailure
    }

    var statusSnapshot: StartupGateStatusSnapshot {
        StartupGateStatusSnapshot(
            securityPreflight: securityPreflightStatus,
            camera: cameraStatus,
            photoLibrary: photoLibraryStatus,
            location: locationStatus,
            microphone: microphoneStatus
        )
    }

    nonisolated static func hasCompletedRequiredStartupChecks(
        securityPreflightStatus: StartupGateRequirementStatus,
        cameraStatus: StartupGateRequirementStatus,
        photoLibraryStatus: StartupGateRequirementStatus
    ) -> Bool {
        StartupGateStatusSnapshot(
            securityPreflight: securityPreflightStatus,
            camera: cameraStatus,
            photoLibrary: photoLibraryStatus,
            location: .idle,
            microphone: .idle
        ).hasCompletedRequiredStartupChecks
    }

    nonisolated static func hasBlockingStartupFailure(
        securityPreflightStatus: StartupGateRequirementStatus,
        cameraStatus: StartupGateRequirementStatus,
        photoLibraryStatus: StartupGateRequirementStatus
    ) -> Bool {
        StartupGateStatusSnapshot(
            securityPreflight: securityPreflightStatus,
            camera: cameraStatus,
            photoLibrary: photoLibraryStatus,
            location: .idle,
            microphone: .idle
        ).hasBlockingStartupFailure
    }

    func refreshAuthorizationStatuses() {
        if securityPreflightStatus == .denied {
            Task { await requestSecurityPreflight() }
        } else if securityPreflightStatus != .requesting,
                  let status = securityPreflight.currentRequirementStatus() {
            securityPreflightStatus = status
        }

        if cameraStatus != .requesting {
            cameraStatus = Self.cameraStatus()
        }

        if photoLibraryStatus != .requesting {
            photoLibraryStatus = Self.photoLibraryStatus()
        }

        if locationStatus != .requesting,
           locationStatus != .skipped {
            locationStatus = Self.locationStatus(from: locationManager.authorizationStatus)
        }

        if microphoneStatus != .requesting,
           microphoneStatus != .skipped {
            microphoneStatus = Self.microphoneStatus()
        }
    }

    func requestSecurityPreflight() async {
        guard securityPreflightStatus != .requesting else {
            return
        }

        securityPreflightStatus = .requesting
        let status = await securityPreflight.performRequiredPreflight()
        securityPreflightStatus = status
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

    func requestMicrophoneAccess() async {
        guard microphoneStatus != .requesting else {
            return
        }

        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            microphoneStatus = .granted
        case .notDetermined:
            microphoneStatus = .requesting
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            microphoneStatus = granted ? .granted : .denied
        case .denied, .restricted:
            microphoneStatus = .denied
        @unknown default:
            microphoneStatus = .denied
        }
    }

    func skipMicrophoneAccess() {
        guard microphoneStatus != .requesting else {
            return
        }
        microphoneStatus = .skipped
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

    private static func cameraStatus() -> StartupGateRequirementStatus {
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

    private static func photoLibraryStatus() -> StartupGateRequirementStatus {
        photoLibraryStatus(from: PHPhotoLibrary.authorizationStatus(for: .readWrite))
    }

    nonisolated static func photoLibraryStatus(from status: PHAuthorizationStatus) -> StartupGateRequirementStatus {
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

    private static func locationStatus(from status: CLAuthorizationStatus) -> StartupGateRequirementStatus {
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

    private static func microphoneStatus() -> StartupGateRequirementStatus {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
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
}
