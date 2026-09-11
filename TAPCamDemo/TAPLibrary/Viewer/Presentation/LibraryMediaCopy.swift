//
//  LibraryMediaCopy.swift
//  TAPCamDemo
//

import Foundation

nonisolated enum LibraryMediaCopy {
    private static var preferredLocale: Locale {
        AppLanguage.resolved().locale
    }

    static var storedInICloud: String {
        String(
            localized: "library.icloud.stored",
            defaultValue: "Stored in iCloud",
            locale: preferredLocale
        )
    }

    static func preparing(_ kind: LibraryMediaKind) -> String {
        switch kind {
        case .tapVideo:
            String(
                localized: "library.media.preparing.video",
                defaultValue: "Preparing video…",
                locale: preferredLocale
            )
        case .photo, .livePhoto:
            String(
                localized: "library.media.preparing.photo",
                defaultValue: "Preparing photo…",
                locale: preferredLocale
            )
        }
    }

    static var retry: String {
        String(
            localized: "library.action.retry",
            defaultValue: "Retry",
            locale: preferredLocale
        )
    }

    static var goToSettings: String {
        String(
            localized: "library.action.settings",
            defaultValue: "Open Settings",
            locale: preferredLocale
        )
    }

    static func failureTitle(_ failure: MediaFetchFailure) -> String {
        switch failure {
        case .permission:
            String(
                localized: "library.failure.permission.title",
                defaultValue: "Photos access required",
                locale: preferredLocale
            )
        case .offline:
            String(
                localized: "library.failure.offline.title",
                defaultValue: "You’re offline",
                locale: preferredLocale
            )
        case .assetRemoved:
            String(
                localized: "library.failure.removed.title",
                defaultValue: "Item no longer available",
                locale: preferredLocale
            )
        case .download:
            String(
                localized: "library.failure.download.title",
                defaultValue: "Unable to download",
                locale: preferredLocale
            )
        case .decode:
            String(
                localized: "library.failure.decode.title",
                defaultValue: "Unable to open item",
                locale: preferredLocale
            )
        }
    }

    static func failureMessage(_ failure: MediaFetchFailure) -> String {
        switch failure {
        case .permission:
            String(
                localized: "library.failure.permission.message",
                defaultValue: "Allow Photos access in Settings, then try again.",
                locale: preferredLocale
            )
        case .offline:
            String(
                localized: "library.failure.offline.message",
                defaultValue: "Connect to the internet to download this item from iCloud.",
                locale: preferredLocale
            )
        case .assetRemoved:
            String(
                localized: "library.failure.removed.message",
                defaultValue: "This item was removed from Photos or is no longer shared with this device.",
                locale: preferredLocale
            )
        case .download:
            String(
                localized: "library.failure.download.message",
                defaultValue: "The iCloud download did not finish. Try again.",
                locale: preferredLocale
            )
        case .decode:
            String(
                localized: "library.failure.decode.message",
                defaultValue: "The downloaded media could not be decoded.",
                locale: preferredLocale
            )
        }
    }
}
