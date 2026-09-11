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
    @Published private(set) var angle: Angle = .zero

    private let notificationCenter: NotificationCenter
    private let readOrientation: @MainActor () -> UIDeviceOrientation
    private let setOrientationNotificationsEnabled: @MainActor (Bool) -> Void
    private var notificationToken: NSObjectProtocol?

    init(
        notificationCenter: NotificationCenter = .default,
        readOrientation: @escaping @MainActor () -> UIDeviceOrientation = { UIDevice.current.orientation },
        setOrientationNotificationsEnabled: @escaping @MainActor (Bool) -> Void = { isEnabled in
            if isEnabled {
                UIDevice.current.beginGeneratingDeviceOrientationNotifications()
            } else {
                UIDevice.current.endGeneratingDeviceOrientationNotifications()
            }
        }
    ) {
        self.notificationCenter = notificationCenter
        self.readOrientation = readOrientation
        self.setOrientationNotificationsEnabled = setOrientationNotificationsEnabled
    }

    func start() {
        guard notificationToken == nil else { return }
        setOrientationNotificationsEnabled(true)
        update(from: readOrientation())

        notificationToken = notificationCenter.addObserver(
            forName: UIDevice.orientationDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.notificationToken != nil else { return }
                self.update(from: self.readOrientation())
            }
        }
    }

    func stop() {
        guard let notificationToken else { return }
        notificationCenter.removeObserver(notificationToken)
        self.notificationToken = nil
        setOrientationNotificationsEnabled(false)
    }

    private func update(from orientation: UIDeviceOrientation) {
        guard let newAngle = orientation.cameraChromeAngle else { return }

        // Keep the nearest equivalent angle so crossing 180° never unwinds 270°.
        let delta = (newAngle.degrees - angle.degrees).remainder(dividingBy: 360)
        guard delta != 0 else { return }
        angle += .degrees(delta)
    }
}

/// Rotates chrome content inside a stable frame using the frame center.
///
/// The outer frame remains part of the portrait-locked layout. Only the
/// content inside rotates, so text or icon intrinsic bounds cannot shift the
/// apparent rotation anchor. The animation is scoped to rotation so child
/// layout changes do not inherit its spring.
struct CenterAnchoredChromeRotation<Content: View>: View {
    let rotation: Angle
    let width: CGFloat
    let height: CGFloat
    private let content: Content

    init(
        rotation: Angle,
        width: CGFloat,
        height: CGFloat,
        @ViewBuilder content: () -> Content
    ) {
        self.rotation = rotation
        self.width = width
        self.height = height
        self.content = content()
    }

    var body: some View {
        content
            .frame(width: width, height: height, alignment: .center)
            .animation(.spring(response: 0.28, dampingFraction: 0.86)) { content in
                content.rotationEffect(rotation, anchor: .center)
            }
    }
}

private extension UIDeviceOrientation {
    var cameraChromeAngle: Angle? {
        /*
         The interface remains portrait. The mapping below rotates controls into
         the user's physical reading direction without asking UIKit to rotate the
         whole window. `landscapeLeft` and `landscapeRight` intentionally mirror
         UIKit's device-orientation naming, not the capture connection naming.
         */
        switch self {
        case .portrait:
            return .degrees(0)
        case .landscapeLeft:
            return .degrees(90)
        case .landscapeRight:
            return .degrees(-90)
        case .portraitUpsideDown:
            return .degrees(180)
        case .unknown, .faceUp, .faceDown:
            return nil
        @unknown default:
            return nil
        }
    }
}
