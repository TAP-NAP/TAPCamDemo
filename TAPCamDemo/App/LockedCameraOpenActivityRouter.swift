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

        TAPCamIntentHandoffStore().saveHandoff(
            TAPCamIntentHandoff(
                destination: .tapLibrary,
                tapAction: TAPCamLockedCameraOpenActivity.tapLibraryDestination,
                reason: TAPCamLockedCameraOpenActivity.sourceValue
            )
        )
        NotificationCenter.default.post(name: .tapCamIntentHandoffDidChange, object: nil)
        LockedCameraDiagnostics.logger.notice(
            "r4_app_route_published destination=\(TAPCamLockedCameraOpenActivity.tapLibraryDestination, privacy: .public)"
        )
        return true
    }
}
