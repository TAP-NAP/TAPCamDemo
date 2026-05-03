//
//  TAPCamDemoApp.swift
//  TAPCamDemo
//
//  Created by Harold on 2026/4/24.
//

@preconcurrency import AVFoundation
import Combine
import CoreLocation
import Network
import Photos
import SwiftUI
import UIKit

/// Locks the SwiftUI scene in portrait so the camera screen behaves like a
/// camera chrome instead of a normal rotating app page.
///
/// Device rotation is still observed by `CameraChromeOrientationController`.
/// That lets individual controls rotate in place while the preview, shutter
/// rail, and overlay anchors keep their portrait layout positions.
final class TAPCamAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        .portrait
    }
}

@main
struct TAPCamDemoApp: App {
    @UIApplicationDelegateAdaptor(TAPCamAppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            FirstLaunchPermissionGate()
        }
    }
}

private struct FirstLaunchPermissionGate: View {
    @StateObject private var model = FirstLaunchPermissionModel()
    @State private var didCompleteFirstLaunchPermissions: Bool
    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        _didCompleteFirstLaunchPermissions = State(
            initialValue: userDefaults.bool(forKey: Self.didCompleteFirstLaunchPermissionsKey)
        )
    }

    var body: some View {
        if didCompleteFirstLaunchPermissions {
            if let preparedStartup = model.preparedStartup,
               let appAttestController = preparedStartup.appAttestController {
                CameraView(
                    viewModel: preparedStartup.cameraViewModel,
                    appAttestController: appAttestController,
                    autoPreparesAppAttest: false
                )
            } else {
                CameraView()
            }
        } else {
            FirstLaunchPermissionView(model: model) {
                userDefaults.set(true, forKey: Self.didCompleteFirstLaunchPermissionsKey)
                withAnimation(.easeOut(duration: 0.18)) {
                    didCompleteFirstLaunchPermissions = true
                }
            }
            .task {
                await model.prepareReusableRuntimeIfNeeded()
            }
        }
    }

    private static let didCompleteFirstLaunchPermissionsKey = "TAPCamDemo.didCompleteFirstLaunchPermissions"
}

private struct PreparedStartup {
    let cameraViewModel: CameraViewModel
    var appAttestController: AppAttestRuntimeController?
}

@MainActor
private final class FirstLaunchPermissionModel: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var cameraStatus: AVAuthorizationStatus
    @Published private(set) var photosStatus: PHAuthorizationStatus
    @Published private(set) var locationStatus: CLAuthorizationStatus
    @Published private(set) var networkStatus: NWPath.Status = .requiresConnection
    @Published private(set) var didCheckNetwork = false
    @Published private(set) var isCheckingNetwork = false
    @Published private(set) var preparedStartup: PreparedStartup?
    @Published private(set) var isCameraPreconfiguring = false
    @Published private(set) var isCameraPreconfigured = false
    @Published private(set) var isPhotoPickerPrewarming = false
    @Published private(set) var didPrewarmPhotoPicker = false

    private let locationManager = CLLocationManager()
    private let networkMonitorQueue = DispatchQueue(label: "tapcam.first-launch.network")
    private var networkMonitor: NWPathMonitor?
    private var cameraPreconfigurationTask: Task<Void, Never>?
    private var appAttestPreparationTask: Task<Void, Never>?
    private var photoPickerPrewarmTask: Task<Void, Never>?

    override init() {
        self.cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
        self.photosStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        self.locationStatus = CLLocationManager().authorizationStatus
        super.init()
        locationManager.delegate = self
    }

    deinit {
        networkMonitor?.cancel()
        cameraPreconfigurationTask?.cancel()
        appAttestPreparationTask?.cancel()
        photoPickerPrewarmTask?.cancel()
    }

    var requiredPermissionsReady: Bool {
        isCameraReady && isPhotosReady && isNetworkReady
    }

    var canBeginCameraConfiguration: Bool {
        isCameraReady && isNetworkReady
    }

    var isCameraReady: Bool {
        cameraStatus == .authorized
    }

    var isPhotosReady: Bool {
        photosStatus == .authorized || photosStatus == .limited
    }

    var isLocationReady: Bool {
        locationStatus == .authorizedAlways || locationStatus == .authorizedWhenInUse
    }

    var isNetworkReady: Bool {
        didCheckNetwork && networkStatus == .satisfied
    }

    func prepareReusableRuntimeIfNeeded() async {
        guard preparedStartup == nil else {
            return
        }

        await Task.yield()
        preparedStartup = PreparedStartup(
            cameraViewModel: CameraViewModel()
        )
        startCameraPreconfigurationIfPossible()
        startAppAttestPreparationAfterNetworkSelectionIfPossible()
        startPhotoPickerPrewarmIfPossible()
    }

    func requestCameraAccess() {
        switch cameraStatus {
        case .authorized:
            startCameraPreconfigurationIfPossible()
        case .notDetermined:
            Task {
                let granted = await AVCaptureDevice.requestAccess(for: .video)
                cameraStatus = granted ? .authorized : AVCaptureDevice.authorizationStatus(for: .video)
                startCameraPreconfigurationIfPossible()
            }
        case .denied, .restricted:
            openAppSettings()
        @unknown default:
            openAppSettings()
        }
    }

    func requestPhotosAccess() {
        switch photosStatus {
        case .authorized, .limited:
            startPhotoPickerPrewarmIfPossible()
        case .notDetermined:
            Task {
                photosStatus = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
                startPhotoPickerPrewarmIfPossible()
            }
        case .denied, .restricted:
            openAppSettings()
        @unknown default:
            openAppSettings()
        }
    }

    func requestLocationAccess() {
        switch locationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            return
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            openAppSettings()
        @unknown default:
            openAppSettings()
        }
    }

    func checkNetworkAccess() {
        didCheckNetwork = true
        isCheckingNetwork = true
        let wasMonitoringNetwork = networkMonitor != nil
        let monitor = startNetworkMonitorIfNeeded()
        if wasMonitoringNetwork {
            handleNetworkPathStatus(monitor.currentPath.status)
        }
    }

    func refreshAuthorizationStates() {
        cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
        photosStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        locationStatus = locationManager.authorizationStatus
        startCameraPreconfigurationIfPossible()
        startPhotoPickerPrewarmIfPossible()
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor [weak self] in
            self?.locationStatus = manager.authorizationStatus
        }
    }

    private func startNetworkMonitorIfNeeded() -> NWPathMonitor {
        if let networkMonitor {
            return networkMonitor
        }

        let networkMonitor = NWPathMonitor()
        self.networkMonitor = networkMonitor
        networkMonitor.pathUpdateHandler = { [weak self] path in
            let status = path.status
            guard let model = self else {
                return
            }

            Task { @MainActor [model, status] in
                model.handleNetworkPathStatus(status)
            }
        }
        networkMonitor.start(queue: networkMonitorQueue)
        return networkMonitor
    }

    private func handleNetworkPathStatus(_ status: NWPath.Status) {
        networkStatus = status
        isCheckingNetwork = false
        startCameraPreconfigurationIfPossible()
        startAppAttestPreparationAfterNetworkSelectionIfPossible()
    }

    private func startCameraPreconfigurationIfPossible() {
        guard canBeginCameraConfiguration,
              !isCameraPreconfigured,
              !isCameraPreconfiguring,
              let preparedStartup else {
            return
        }

        isCameraPreconfiguring = true
        cameraPreconfigurationTask = Task { @MainActor in
            await preparedStartup.cameraViewModel.start()
            guard !Task.isCancelled else {
                return
            }
            isCameraPreconfigured = true
            isCameraPreconfiguring = false
        }
    }

    private func startAppAttestPreparationAfterNetworkSelectionIfPossible() {
        guard isNetworkReady,
              appAttestPreparationTask == nil,
              let appAttestController = ensurePreparedAppAttestController() else {
            return
        }

        appAttestPreparationTask = Task { @MainActor [appAttestController] in
            await appAttestController.preparePhotoCredentialAfterFirstInstallLaunch()
        }
    }

    private func ensurePreparedAppAttestController() -> AppAttestRuntimeController? {
        guard var startup = preparedStartup else {
            return nil
        }

        if let appAttestController = startup.appAttestController {
            return appAttestController
        }

        let appAttestController = AppAttestRuntimeController()
        startup.appAttestController = appAttestController
        preparedStartup = startup
        return appAttestController
    }

    private func startPhotoPickerPrewarmIfPossible() {
        guard isPhotosReady,
              !isPhotoPickerPrewarming,
              !didPrewarmPhotoPicker else {
            return
        }

        isPhotoPickerPrewarming = true
        photoPickerPrewarmTask = Task { @MainActor in
            await DepthAlbumPickerPrewarmer.prewarm()
            guard !Task.isCancelled else {
                return
            }
            didPrewarmPhotoPicker = true
            isPhotoPickerPrewarming = false
        }
    }

    private func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else {
            return
        }
        UIApplication.shared.open(url)
    }
}

private struct FirstLaunchPermissionView: View {
    @ObservedObject var model: FirstLaunchPermissionModel
    let continueAction: () -> Void
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 18) {
                header

                VStack(spacing: 10) {
                    PermissionSetupRow(
                        title: "Network",
                        subtitle: "Required for internet services",
                        systemImage: "network",
                        requirement: "Required",
                        state: networkRowState,
                        buttonTitle: networkButtonTitle,
                        action: model.checkNetworkAccess
                    )

                    PermissionSetupRow(
                        title: "Camera",
                        subtitle: "Required for capture",
                        systemImage: "camera",
                        requirement: "Required",
                        state: cameraRowState,
                        buttonTitle: cameraButtonTitle,
                        action: model.requestCameraAccess
                    )

                    PermissionSetupRow(
                        title: "Photos",
                        subtitle: "Required for saving and analysis",
                        systemImage: "photo.on.rectangle",
                        requirement: "Required",
                        state: photosRowState,
                        buttonTitle: photosButtonTitle,
                        action: model.requestPhotosAccess
                    )

                    PermissionSetupRow(
                        title: "Location",
                        subtitle: "Optional capture metadata",
                        systemImage: "location",
                        requirement: "Optional",
                        state: locationRowState,
                        buttonTitle: locationButtonTitle,
                        action: model.requestLocationAccess
                    )

                }

                if model.isCameraPreconfiguring {
                    Label("Preparing camera...", systemImage: "camera.aperture")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.78))
                } else if model.isCameraPreconfigured {
                    Label("Camera ready", systemImage: "checkmark.circle.fill")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.green)
                }

                if model.isPhotoPickerPrewarming {
                    Label("Preparing photo picker...", systemImage: "photo.stack")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.78))
                }

                Spacer(minLength: 0)

                if model.requiredPermissionsReady {
                    Button {
                        continueAction()
                    } label: {
                        Label("Continue", systemImage: "arrow.right")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                } else {
                    Text("Camera, Photos, and Network are required.")
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.62))
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 28)
            .frame(maxWidth: 560, alignment: .leading)
        }
        .onChange(of: scenePhase) { _, newValue in
            guard newValue == .active else {
                return
            }
            model.refreshAuthorizationStates()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Prepare TAPCam")
                .font(.title2.weight(.bold))
                .foregroundStyle(.white)

            Text("Grant the required access once, then TAPCam will open directly to the camera next time.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.68))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var cameraRowState: PermissionSetupRow.State {
        switch model.cameraStatus {
        case .authorized:
            .ready("Granted")
        case .notDetermined:
            .needsAction("Not requested")
        case .denied, .restricted:
            .blocked("Open Settings")
        @unknown default:
            .blocked("Unknown")
        }
    }

    private var photosRowState: PermissionSetupRow.State {
        switch model.photosStatus {
        case .authorized:
            .ready("Granted")
        case .limited:
            .ready("Limited")
        case .notDetermined:
            .needsAction("Not requested")
        case .denied, .restricted:
            .blocked("Open Settings")
        @unknown default:
            .blocked("Unknown")
        }
    }

    private var locationRowState: PermissionSetupRow.State {
        switch model.locationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            .ready("Granted")
        case .notDetermined:
            .optional("Not requested")
        case .denied, .restricted:
            .optional("Skipped")
        @unknown default:
            .optional("Unknown")
        }
    }

    private var networkRowState: PermissionSetupRow.State {
        if model.isCheckingNetwork {
            return .needsAction("Checking")
        }

        guard model.didCheckNetwork else {
            return .needsAction("Not checked")
        }

        switch model.networkStatus {
        case .satisfied:
            return .ready("Available")
        case .unsatisfied, .requiresConnection:
            return .blocked("Unavailable")
        @unknown default:
            return .blocked("Unknown")
        }
    }

    private var cameraButtonTitle: String {
        switch model.cameraStatus {
        case .authorized:
            "Done"
        case .denied, .restricted:
            "Settings"
        default:
            "Allow"
        }
    }

    private var photosButtonTitle: String {
        switch model.photosStatus {
        case .authorized, .limited:
            "Done"
        case .denied, .restricted:
            "Settings"
        default:
            "Allow"
        }
    }

    private var locationButtonTitle: String {
        switch model.locationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            "Done"
        case .denied, .restricted:
            "Settings"
        default:
            "Allow"
        }
    }

    private var networkButtonTitle: String {
        if model.isNetworkReady {
            return "Done"
        } else if model.isCheckingNetwork {
            return "Checking"
        } else if model.didCheckNetwork {
            return "Retry"
        } else {
            return "Allow"
        }
    }
}

private struct PermissionSetupRow: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let requirement: String
    let state: State
    let buttonTitle: String
    let action: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.white.opacity(0.86))
                .frame(width: 26, height: 34)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 7) {
                    Text(title)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.white)
                    Text(requirement)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white.opacity(0.72))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(.white.opacity(0.12), in: Capsule())
                }

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.60))
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 6) {
                Image(systemName: state.systemImage)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(state.tint)
                    .accessibilityLabel(state.accessibilityLabel)

                Button(buttonTitle) {
                    action()
                }
                .font(.caption.weight(.semibold))
                .buttonStyle(.bordered)
                .tint(.white)
                .disabled((state.isReady && buttonTitle == "Done") || buttonTitle == "Checking")
            }
            .frame(width: 84, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: 78, alignment: .leading)
        .background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(.white.opacity(0.14), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(state.text)")
    }

    enum State {
        case ready(String)
        case needsAction(String)
        case optional(String)
        case blocked(String)

        var text: String {
            switch self {
            case .ready(let text), .needsAction(let text), .optional(let text), .blocked(let text):
                text
            }
        }

        var isReady: Bool {
            if case .ready = self {
                return true
            }
            return false
        }

        var systemImage: String {
            switch self {
            case .ready:
                "checkmark.circle.fill"
            case .blocked:
                "exclamationmark.circle.fill"
            case .needsAction, .optional:
                "circle"
            }
        }

        var tint: Color {
            switch self {
            case .ready:
                .green
            case .blocked:
                .yellow
            case .needsAction, .optional:
                .white.opacity(0.46)
            }
        }

        var accessibilityLabel: String {
            switch self {
            case .ready:
                "Granted"
            case .blocked:
                "Needs attention"
            case .needsAction:
                "Not granted"
            case .optional:
                "Optional"
            }
        }
    }
}
