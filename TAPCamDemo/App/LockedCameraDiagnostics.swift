//
//  LockedCameraDiagnostics.swift
//  TAPCamDemo
//

import OSLog

nonisolated enum LockedCameraDiagnostics {
    static let logger = Logger(
        subsystem: "TAP-NAP.TAPCamDemo",
        category: "LockedCameraApp"
    )
}
