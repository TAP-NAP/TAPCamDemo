//
//  LibraryMediaCopy.swift
//  TAPCamDemo
//

import Foundation

nonisolated enum LibraryMediaCopy {
    static var loadingFromICloud: String {
        String(localized: "library.icloud.loading", defaultValue: "Loading from iCloud…")
    }

    static func loadingFromICloud(progress: Double?) -> String {
        guard let progress else {
            return loadingFromICloud
        }
        let percent = Int((min(max(progress, 0), 1) * 100).rounded())
        return "\(loadingFromICloud) \(percent)%"
    }

    static var storedInICloud: String {
        String(localized: "library.icloud.stored", defaultValue: "Stored in iCloud")
    }

    static func preparing(_ kind: LibraryMediaKind) -> String {
        switch kind {
        case .tapVideo:
            String(localized: "library.media.preparing.video", defaultValue: "Preparing video…")
        case .photo, .livePhoto:
            String(localized: "library.media.preparing.photo", defaultValue: "Preparing photo…")
        }
    }

    static var cancel: String {
        String(localized: "library.action.cancel", defaultValue: "Cancel")
    }

    static var retry: String {
        String(localized: "library.action.retry", defaultValue: "Retry")
    }

    static var goToSettings: String {
        String(localized: "library.action.settings", defaultValue: "Open Settings")
    }

    static func failureTitle(_ failure: MediaFetchFailure) -> String {
        switch failure {
        case .permission:
            String(localized: "library.failure.permission.title", defaultValue: "Photos access required")
        case .offline:
            String(localized: "library.failure.offline.title", defaultValue: "You’re offline")
        case .assetRemoved:
            String(localized: "library.failure.removed.title", defaultValue: "Item no longer available")
        case .download:
            String(localized: "library.failure.download.title", defaultValue: "Unable to download")
        case .decode:
            String(localized: "library.failure.decode.title", defaultValue: "Unable to open item")
        }
    }

    static func failureMessage(_ failure: MediaFetchFailure) -> String {
        switch failure {
        case .permission:
            String(localized: "library.failure.permission.message", defaultValue: "Allow Photos access in Settings, then try again.")
        case .offline:
            String(localized: "library.failure.offline.message", defaultValue: "Connect to the internet to download this item from iCloud.")
        case .assetRemoved:
            String(localized: "library.failure.removed.message", defaultValue: "This item was removed from Photos or is no longer shared with this device.")
        case .download:
            String(localized: "library.failure.download.message", defaultValue: "The iCloud download did not finish. Try again.")
        case .decode:
            String(localized: "library.failure.decode.message", defaultValue: "The downloaded media could not be decoded.")
        }
    }
}
