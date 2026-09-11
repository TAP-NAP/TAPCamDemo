import CoreMotion
import SwiftUI

/// Screen-space horizon from gravity, valid in portrait and landscape.
nonisolated struct CameraLevelReading: Equatable, Sendable {
    let horizonRadians: Double

    init?(gravityX: Double, gravityY: Double) {
        // Near face-up/down, gravity cannot reliably determine a horizon.
        guard gravityX.isFinite, gravityY.isFinite,
              hypot(gravityX, gravityY) >= 0.2 else { return nil }
        horizonRadians = atan2(-gravityX, -gravityY)
    }

    var referenceRadians: Double {
        (horizonRadians / (.pi / 2)).rounded() * (.pi / 2)
    }

    var isAligned: Bool {
        abs(horizonRadians - referenceRadians) <= .pi / 180
    }
}

struct CameraLevelView: View {
    let isActive: Bool
    let highlightColor: Color
    @AppStorage(CameraLevelPreferences.enabledKey)
    private var isEnabled = CameraLevelPreferences.defaultEnabled
    @State private var reading: CameraLevelReading?

    private var shouldUpdate: Bool {
        isEnabled && isActive
    }

    var body: some View {
        ZStack {
            if shouldUpdate, let reading {
                HStack(spacing: 64) {
                    Capsule().frame(width: 16, height: 2)
                    Capsule().frame(width: 16, height: 2)
                }
                .foregroundStyle(reading.isAligned ? highlightColor : .white.opacity(0.6))
                .rotationEffect(.radians(reading.referenceRadians))

                Capsule()
                    .fill(reading.isAligned ? highlightColor : .white)
                    .frame(width: 56, height: 2)
                    .rotationEffect(.radians(reading.horizonRadians))
            }
        }
        .frame(width: 100, height: 100)
        .shadow(color: .black.opacity(0.6), radius: 1)
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Level")
        .accessibilityValue(reading?.isAligned == true ? Text("Level aligned") : Text("Level tilted"))
        .accessibilityHidden(!shouldUpdate || reading == nil)
        .accessibilityIdentifier("camera.level")
        .task(id: shouldUpdate) { @MainActor in
            reading = nil
            guard shouldUpdate else { return }
            let motion = CMMotionManager()
            guard motion.isDeviceMotionAvailable else { return }
            motion.deviceMotionUpdateInterval = 1.0 / 15.0
            motion.startDeviceMotionUpdates()
            defer { motion.stopDeviceMotionUpdates() }

            // Pull only the latest sample: UI updates stay bounded and cannot
            // queue sensor callbacks while capture or navigation is busy.
            while !Task.isCancelled {
                if let gravity = motion.deviceMotion?.gravity {
                    reading = CameraLevelReading(gravityX: gravity.x, gravityY: gravity.y)
                }
                do {
                    try await Task.sleep(for: .milliseconds(67))
                } catch {
                    break
                }
            }
        }
    }
}
