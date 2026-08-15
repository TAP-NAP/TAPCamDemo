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
    @Published private(set) var requiredPermissionSnapshot: RequiredPermissionSnapshot = .unresolved

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
        CameraCaptureDataUsePreferences.migrateLegacyMicrophonePreferenceIfNeeded()

        refreshSecurityPreflightStatus()
        refreshRequiredPermissionStatuses()

        if locationStatus != .requesting,
           locationStatus != .skipped {
            locationStatus = Self.locationStatus(from: locationManager.authorizationStatus)
        }

        if microphoneStatus != .requesting,
           microphoneStatus != .skipped {
            microphoneStatus = Self.microphoneStatus()
            if microphoneStatus == .granted {
                CameraCaptureDataUsePreferences.enableMicrophoneDataAfterFirstAuthorizationIfNeeded()
            }
        }
    }

    /// Preserves the current frozen Network-row behavior exactly. Permission
    /// recovery paths call the targeted methods below and never call this.
    func refreshSecurityPreflightStatus() {
        if securityPreflightStatus == .denied {
            Task { await requestSecurityPreflight() }
        } else if securityPreflightStatus != .requesting,
                  let status = securityPreflight.currentRequirementStatus() {
            securityPreflightStatus = status
        }
    }

    /// Passive Camera/Photos snapshot used by the root route reducer.
    func refreshRequiredPermissionStatuses() {
        if cameraStatus != .requesting {
            publishCameraPermissionStatus(
                Self.cameraPermissionStatus(
                    from: AVCaptureDevice.authorizationStatus(for: .video)
                )
            )
        }

        if photoLibraryStatus != .requesting {
            publishPhotoLibraryPermissionStatus(
                Self.photoLibraryPermissionStatus(
                    from: PHPhotoLibrary.authorizationStatus(for: .readWrite)
                )
            )
        }
    }

    /// Refreshes only the row that owned a Settings boundary. Network is
    /// intentionally absent so Required Permission Check cannot restart it.
    func refreshAuthorizationStatus(for requirement: StartupGateRequirementKind) {
        switch requirement {
        case .securityPreflight:
            refreshSecurityPreflightStatus()
        case .camera:
            guard cameraStatus != .requesting else { return }
            publishCameraPermissionStatus(
                Self.cameraPermissionStatus(
                    from: AVCaptureDevice.authorizationStatus(for: .video)
                )
            )
        case .photoLibrary:
            guard photoLibraryStatus != .requesting else { return }
            publishPhotoLibraryPermissionStatus(
                Self.photoLibraryPermissionStatus(
                    from: PHPhotoLibrary.authorizationStatus(for: .readWrite)
                )
            )
        case .location:
            guard locationStatus != .requesting,
                  locationStatus != .skipped else { return }
            locationStatus = Self.locationStatus(from: locationManager.authorizationStatus)
        case .microphone:
            guard microphoneStatus != .requesting,
                  microphoneStatus != .skipped else { return }
            microphoneStatus = Self.microphoneStatus()
            if microphoneStatus == .granted {
                CameraCaptureDataUsePreferences.enableMicrophoneDataAfterFirstAuthorizationIfNeeded()
            }
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
            publishCameraPermissionStatus(.authorized)
        case .notDetermined:
            cameraStatus = .requesting
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            publishCameraPermissionStatus(granted ? .authorized : .denied)
        case .denied:
            publishCameraPermissionStatus(.denied)
        case .restricted:
            publishCameraPermissionStatus(.restricted)
        @unknown default:
            publishCameraPermissionStatus(.unknown)
        }
    }

    func requestPhotoLibraryAccess() async {
        guard photoLibraryStatus != .requesting else {
            return
        }

        switch PHPhotoLibrary.authorizationStatus(for: .readWrite) {
        case .authorized:
            publishPhotoLibraryPermissionStatus(.authorized)
        case .limited:
            publishPhotoLibraryPermissionStatus(.limited)
        case .notDetermined:
            photoLibraryStatus = .requesting
            let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
            publishPhotoLibraryPermissionStatus(
                Self.photoLibraryPermissionStatus(from: status)
            )
        case .denied:
            publishPhotoLibraryPermissionStatus(.denied)
        case .restricted:
            publishPhotoLibraryPermissionStatus(.restricted)
        @unknown default:
            publishPhotoLibraryPermissionStatus(.unknown)
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
        case .denied:
            locationStatus = .denied
        case .restricted:
            locationStatus = .restricted
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
            CameraCaptureDataUsePreferences.enableMicrophoneDataAfterFirstAuthorizationIfNeeded()
        case .notDetermined:
            microphoneStatus = .requesting
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            microphoneStatus = granted ? .granted : .denied
            if granted {
                CameraCaptureDataUsePreferences.enableMicrophoneDataAfterFirstAuthorizationIfNeeded()
            }
        case .denied:
            microphoneStatus = .denied
        case .restricted:
            microphoneStatus = .restricted
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

    nonisolated static func cameraPermissionStatus(
        from status: AVAuthorizationStatus
    ) -> RequiredPermissionStatus {
        switch status {
        case .authorized:
            .authorized
        case .notDetermined:
            .notDetermined
        case .denied:
            .denied
        case .restricted:
            .restricted
        @unknown default:
            .unknown
        }
    }

    nonisolated static func photoLibraryPermissionStatus(
        from status: PHAuthorizationStatus
    ) -> RequiredPermissionStatus {
        switch status {
        case .authorized:
            .authorized
        case .limited:
            .limited
        case .notDetermined:
            .notDetermined
        case .denied:
            .denied
        case .restricted:
            .restricted
        @unknown default:
            .unknown
        }
    }

    nonisolated static func photoLibraryStatus(from status: PHAuthorizationStatus) -> StartupGateRequirementStatus {
        requirementStatus(from: photoLibraryPermissionStatus(from: status))
    }

    nonisolated private static func requirementStatus(
        from status: RequiredPermissionStatus
    ) -> StartupGateRequirementStatus {
        switch status {
        case .authorized, .limited:
            .granted
        case .notDetermined:
            .idle
        case .denied, .unknown:
            .denied
        case .restricted:
            .restricted
        }
    }

    private static func locationStatus(from status: CLAuthorizationStatus) -> StartupGateRequirementStatus {
        switch status {
        case .authorizedAlways, .authorizedWhenInUse:
            .granted
        case .notDetermined:
            .idle
        case .denied:
            .denied
        case .restricted:
            .restricted
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
        case .denied:
            .denied
        case .restricted:
            .restricted
        @unknown default:
            .denied
        }
    }

    private func publishCameraPermissionStatus(_ status: RequiredPermissionStatus) {
        cameraStatus = Self.requirementStatus(from: status)
        requiredPermissionSnapshot = RequiredPermissionSnapshot(
            camera: status,
            photoLibrary: requiredPermissionSnapshot.photoLibrary
        )
    }

    private func publishPhotoLibraryPermissionStatus(_ status: RequiredPermissionStatus) {
        photoLibraryStatus = Self.requirementStatus(from: status)
        requiredPermissionSnapshot = RequiredPermissionSnapshot(
            camera: requiredPermissionSnapshot.camera,
            photoLibrary: status
        )
    }
}
