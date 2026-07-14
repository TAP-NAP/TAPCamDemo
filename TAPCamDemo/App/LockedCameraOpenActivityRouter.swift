//
//  LockedCameraOpenActivityRouter.swift
//  TAPCamDemo
//

import Foundation
import OSLog

@MainActor
enum LockedCameraOpenActivityRouter {
    @discardableResult
    static func handle(_ activity: NSUserActivity) -> Bool {
        guard TAPCamLockedCameraOpenActivity.requestsTapLibrary(activity) else {
            LockedCameraDiagnostics.logger.notice(
                "r4_app_activity_ignored activityType=\(activity.activityType, privacy: .public)"
            )
            return false
        }

        let source = activity.userInfo?[TAPCamLockedCameraOpenActivity.sourceKey] as? String
            ?? "none"
        LockedCameraDiagnostics.logger.notice(
            "r4_app_activity_received destination=\(TAPCamLockedCameraOpenActivity.tapLibraryDestination, privacy: .public) source=\(source, privacy: .public)"
        )

        LockedCameraDiagnostics.logger.notice(
            "r4c_app_activity_validated destination=\(TAPCamLockedCameraOpenActivity.tapLibraryDestination, privacy: .public) routeSideEffects=none"
        )
        return true
    }
}
