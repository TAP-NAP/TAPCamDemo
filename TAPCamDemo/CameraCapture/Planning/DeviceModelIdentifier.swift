//
//  DeviceModelIdentifier.swift
//  TAPCamDemo
//
//  Created by Codex on 2026/4/27.
//

@preconcurrency import AVFoundation
import CoreGraphics
import CoreMedia
import Darwin
import Foundation

/// Resolves the current hardware model identifier used by the focal-label catalog.
nonisolated enum DeviceModelIdentifier {
    static let current: String = {
        var systemInfo = utsname()
        uname(&systemInfo)
        return withUnsafePointer(to: &systemInfo.machine) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: 1) { charPointer in
                String(validatingUTF8: charPointer) ?? "unknown"
            }
        }
    }()
}

extension AVCaptureDevice {
    nonisolated func containsConstituent(_ source: AVCaptureDevice) -> Bool {
        constituentDevices.contains { $0.uniqueID == source.uniqueID }
    }
}
