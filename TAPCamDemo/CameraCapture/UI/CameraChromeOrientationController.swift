//
//  CameraChromeOrientationController.swift
//  TAPCamDemo
//
//  Created by Codex on 2026/4/27.
//

import Combine
import SwiftUI
import UIKit

/// Converts physical device orientation into an in-place rotation for camera UI.
///
/// The app's interface orientation stays portrait so the viewfinder and control
/// anchors do not relayout when the user rotates the phone. This controller only
/// publishes the angle that "camera chrome" elements should apply to their own
/// content, matching the behavior of camera apps where buttons rotate but the
/// screen structure remains stable.
@MainActor
final class CameraChromeOrientationController: ObservableObject {
    @Published private(set) var orientation: CameraChromeOrientation = .portrait

    private var notificationToken: NSObjectProtocol?
    private var lastStableOrientation: UIDeviceOrientation = .portrait

    var angle: Angle {
        orientation.angle
    }

    func start() {
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        update(from: UIDevice.current.orientation)

        notificationToken = NotificationCenter.default.addObserver(
            forName: UIDevice.orientationDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.update(from: UIDevice.current.orientation)
            }
        }
    }

    func stop() {
        if let notificationToken {
            NotificationCenter.default.removeObserver(notificationToken)
            self.notificationToken = nil
        }
        UIDevice.current.endGeneratingDeviceOrientationNotifications()
    }

    private func update(from orientation: UIDeviceOrientation) {
        guard orientation.isCameraChromeStable else {
            updateAngle(for: lastStableOrientation)
            return
        }

        lastStableOrientation = orientation
        updateAngle(for: orientation)
    }

    private func updateAngle(for orientation: UIDeviceOrientation) {
        let newOrientation = orientation.cameraChromeOrientation
        guard newOrientation != self.orientation else { return }

        withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
            self.orientation = newOrientation
        }
    }
}

/// Orientation-aware rotation rules for user-facing chrome.
///
/// The SwiftUI window remains portrait, while selected user-facing controls
/// rotate their contents for readability. Debug instrumentation intentionally
/// does not use these values; debug panels stay fixed in portrait preview
/// coordinates so their positions remain stable while inspecting the pipeline.
enum CameraChromeOrientation: Equatable {
    case portrait
    case landscapeLeft
    case landscapeRight
    case portraitUpsideDown

    var angle: Angle {
        switch self {
        case .portrait:
            return .degrees(0)
        case .landscapeLeft:
            return .degrees(90)
        case .landscapeRight:
            return .degrees(-90)
        case .portraitUpsideDown:
            return .degrees(180)
        }
    }
}

private extension UIDeviceOrientation {
    var isCameraChromeStable: Bool {
        switch self {
        case .portrait, .portraitUpsideDown, .landscapeLeft, .landscapeRight:
            return true
        case .unknown, .faceUp, .faceDown:
            return false
        @unknown default:
            return false
        }
    }

    var cameraChromeOrientation: CameraChromeOrientation {
        /*
         The interface remains portrait. The mapping below rotates controls into
         the user's physical reading direction without asking UIKit to rotate the
         whole window. `landscapeLeft` and `landscapeRight` intentionally mirror
         UIKit's device-orientation naming, not the capture connection naming.
         */
        switch self {
        case .portrait:
            return .portrait
        case .landscapeLeft:
            return .landscapeLeft
        case .landscapeRight:
            return .landscapeRight
        case .portraitUpsideDown:
            return .portraitUpsideDown
        case .unknown, .faceUp, .faceDown:
            return .portrait
        @unknown default:
            return .portrait
        }
    }
}
