//
//  StartupGateCoordinator.swift
//  TAPCamDemo
//

import AVFoundation
import Combine
import CoreLocation
import Foundation
import Network
import Photos

@MainActor
final class StartupGateCoordinator: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var networkStatus: StartupGateRequirementStatus = .idle
    @Published private(set) var cameraStatus: StartupGateRequirementStatus = .idle
    @Published private(set) var photoLibraryStatus: StartupGateRequirementStatus = .idle
    @Published private(set) var locationStatus: StartupGateRequirementStatus = .idle
    @Published private(set) var microphoneStatus: StartupGateRequirementStatus = .idle
    @Published private(set) var requiredPermissionSnapshot: RequiredPermissionSnapshot = .unresolved

    private let locationManager = CLLocationManager()
    private var locationAuthorizationContinuation: CheckedContinuation<CLAuthorizationStatus, Never>?
    private var networkConnection: NWConnection?
    private var networkMonitor: NWPathMonitor?
    private let userDefaults: UserDefaults
    private static let lastKnownNetworkAccessKey = "startup.lastKnownNetworkAccess"
    private let startNetworkMonitor: (NWPathMonitor) -> Void
    private let startNetworkConnection: (NWConnection) -> Void

    init(
        userDefaults: UserDefaults = .standard,
        startNetworkConnection: @escaping (NWConnection) -> Void = { $0.start(queue: .main) },
        startNetworkMonitor: @escaping (NWPathMonitor) -> Void = { $0.start(queue: .main) }
    ) {
        self.userDefaults = userDefaults
        self.startNetworkConnection = startNetworkConnection
        self.startNetworkMonitor = startNetworkMonitor
        super.init()
        locationManager.delegate = self
        // Restore presentation only; system observations replace this last-known result.
        if let granted = userDefaults.object(forKey: Self.lastKnownNetworkAccessKey) as? Bool {
            networkStatus = granted ? .granted : .denied
        }
        refreshAuthorizationStatuses()
    }

    deinit {
        networkMonitor?.cancel()
        networkConnection?.cancel()
    }

    var hasCompletedRequiredStartupChecks: Bool {
        statusSnapshot.hasCompletedRequiredStartupChecks
    }

    var hasBlockingStartupFailure: Bool {
        statusSnapshot.hasBlockingStartupFailure
    }

    var statusSnapshot: StartupGateStatusSnapshot {
        StartupGateStatusSnapshot(
            camera: cameraStatus,
            photoLibrary: photoLibraryStatus,
            location: locationStatus,
            microphone: microphoneStatus
        )
    }

    func refreshAuthorizationStatuses() {
        refreshRequiredPermissionStatuses()

        if locationStatus != .requesting {
            locationStatus = Self.locationStatus(from: locationManager.authorizationStatus)
        }

        if microphoneStatus != .requesting {
            microphoneStatus = Self.microphoneStatus()
            if microphoneStatus == .granted {
                CameraCaptureDataUsePreferences.enableMicrophoneDataAfterFirstAuthorizationIfNeeded()
            }
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

    /// Resume observation only after a previous system result. First use stays
    /// behind Network Continue, including monitor creation.
    func refreshNetworkAccessStatus() {
        if networkMonitor == nil {
            guard networkStatus == .granted || networkStatus == .denied else { return }
            startNetworkObservationIfNeeded()
        }
        guard let path = networkMonitor?.currentPath else { return }
        updateNetworkAccessStatus(pathStatus: path.status, reason: path.unsatisfiedReason)
    }

    private func startNetworkObservationIfNeeded() {
        guard networkMonitor == nil else { return }
        let monitor = NWPathMonitor()
        networkMonitor = monitor
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor [weak self] in
                self?.updateNetworkAccessStatus(
                    pathStatus: path.status, reason: path.unsatisfiedReason
                )
            }
        }
        startNetworkMonitor(monitor)
    }

    /// An explicit connection lets iOS present its first-use network prompt.
    /// Its success or failure does not determine the permission label.
    func requestNetworkAccess() {
        guard networkConnection == nil else { return }
        startNetworkObservationIfNeeded()
        guard let url = try? AppAttestBackendConfiguration.baseURL(),
              let host = url.host,
              let portNumber = UInt16(exactly: url.port ?? 443),
              let port = NWEndpoint.Port(rawValue: portNumber) else {
            return
        }

        let connection = NWConnection(host: .init(host), port: port, using: .tcp)
        networkConnection = connection
        if networkStatus == .idle { networkStatus = .requesting }
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            Task { @MainActor [weak self, weak connection] in
                guard let self, let connection, self.networkConnection === connection else { return }
                switch state {
                case .ready, .failed:
                    self.cancelNetworkAccessRequest()
                default:
                    break
                }
            }
        }
        startNetworkConnection(connection)
    }

    func cancelNetworkAccessRequest() {
        networkConnection?.cancel()
        networkConnection = nil
        if networkStatus == .requesting { networkStatus = .idle }
    }

    func updateNetworkAccessStatus(pathStatus: NWPath.Status, reason: NWPath.UnsatisfiedReason) {
        let status: StartupGateRequirementStatus
        switch (pathStatus, reason) {
        case (.satisfied, _):
            status = .granted
        case (.unsatisfied, .wifiDenied), (.unsatisfied, .cellularDenied):
            status = .denied
        default:
            // Offline or unknown paths do not replace a known permission result.
            return
        }
        if networkStatus != status {
            networkStatus = status
            userDefaults.set(status == .granted, forKey: Self.lastKnownNetworkAccessKey)
        }
        if status == .granted { cancelNetworkAccessRequest() }
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

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor [weak self] in
            guard let self else { return }

            if let continuation = locationAuthorizationContinuation {
                locationAuthorizationContinuation = nil
                continuation.resume(returning: manager.authorizationStatus)
            } else {
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
