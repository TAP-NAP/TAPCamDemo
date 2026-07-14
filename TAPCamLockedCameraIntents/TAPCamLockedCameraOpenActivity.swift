//
//  TAPCamLockedCameraOpenActivity.swift
//  TAPCamDemo
//

import Foundation
import LockedCameraCapture

nonisolated enum TAPCamLockedCameraOpenActivity {
    static let destinationKey = "TAPCamLockedCameraDestination"
    static let tapLibraryDestination = "tapLibrary"
    static let sourceKey = "TAPCamLockedCameraSource"
    static let sourceValue = "locked-camera-r4"

    static func makeTapLibraryActivity() -> NSUserActivity {
        let activity = NSUserActivity(activityType: NSUserActivityTypeLockedCameraCapture)
        activity.title = "Open TAP Library"
        activity.userInfo = [
            destinationKey: tapLibraryDestination,
            sourceKey: sourceValue
        ]
        return activity
    }

    static func requestsTapLibrary(_ activity: NSUserActivity) -> Bool {
        activity.activityType == NSUserActivityTypeLockedCameraCapture
            && activity.userInfo?[destinationKey] as? String == tapLibraryDestination
    }
}
