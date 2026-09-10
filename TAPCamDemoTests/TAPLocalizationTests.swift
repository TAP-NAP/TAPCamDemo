//
//  TAPLocalizationTests.swift
//  TAPCamDemoTests
//

import Foundation
import Testing
@testable import TAPCamDemo

@Suite("TAP localization")
struct TAPLocalizationTests {
    @Test func appLanguageDefaultsToSystemAndFallsBackSafely() throws {
        let suiteName = "TAPLocalizationTests-\(UUID().uuidString)"
        let userDefaults = try #require(UserDefaults(suiteName: suiteName))
        defer {
            userDefaults.removePersistentDomain(forName: suiteName)
        }

        #expect(AppLanguage.defaultValue == .system)
        #expect(AppLanguage.resolved(rawValue: "unsupported-language") == .system)
        #expect(AppLanguage.resolved(in: userDefaults) == .system)

        userDefaults.set(AppLanguage.simplifiedChinese.rawValue, forKey: AppLanguage.storageKey)
        #expect(AppLanguage.resolved(in: userDefaults) == .simplifiedChinese)
        #expect(AppLanguage.simplifiedChinese.locale.identifier == "zh-Hans")
        #expect(AppLanguage.english.locale.identifier == "en")
    }

    @Test(.enabled(if: TAPCamDemoTestSourceInspection.isSourceTreeAvailable, "Source tree is unavailable on this runtime."))
    func catalogHasSimplifiedChineseForPrioritySurfaces() throws {
        let catalogSource = try TAPCamDemoTestSourceInspection.source(
            relativePath: "TAPCamDemo/Localizable.xcstrings"
        )
        let data = Data(catalogSource.utf8)
        let root = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        let strings = try #require(root["strings"] as? [String: Any])
        let priorityKeys = [
            "App Language",
            "System Default",
            "Simplified Chinese",
            "Settings",
            "Camera Settings",
            "Interface",
            "Data & Permissions",
            "Reference Image status",
            "Online Verifier",
            "Not Ready",
            "Preparation Failed",
            "Interaction Haptics",
            "Silent Shutter",
            "Silent shutter is unavailable on this device or in this region.",
            "Acknowledgements",
            "Location Data",
            "Use When Capturing",
            "Adds capture location to photo metadata.",
            "Records sound for Live Photos and videos.",
            "Optional. Used to record sound for Live Photos and videos.",
            "Photographer Mode Startup",
            "TAP Library",
            "Share",
            "share.status.title",
            "share.status.verified",
            "share.status.retry",
            "share.status.failed",
            "share.option.package.title",
            "share.option.package.subtitle",
            "share.option.package.locked",
            "share.option.image.title",
            "share.option.image.subtitle",
            "share.option.media.unverifiable",
            "share.option.link.title",
            "share.option.link.subtitle",
            "share.badge.recommended",
            "share.badge.comingSoon",
            "share.progress.accessibilityValue",
            "share.error.title",
            "share.error.message",
            "share.integrity.checking.accessibility",
            "share.warning.localIntegrityFailed",
            "Delete",
            "Coming soon",
            "3D projection",
            "Near %@",
            "Valid depth",
            "Network Access",
            "Loading TAP Library...",
            "Preparing capture session...",
            "Ready · %@ · crop metadata",
            "Starting Pro mode…",
            "Unable to restore the camera.",
            "Shows numeric depth measurements for the selected region, including median depth, range, valid samples, and any local plane estimate.",
            "library.failure.permission.title"
        ]

        for key in priorityKeys {
            let entry = try #require(strings[key] as? [String: Any], "Missing key: \(key)")
            let localizations = try #require(
                entry["localizations"] as? [String: Any],
                "Missing localizations: \(key)"
            )
            let simplifiedChinese = try #require(
                localizations["zh-Hans"] as? [String: Any],
                "Missing zh-Hans: \(key)"
            )
            let stringUnit = try #require(
                simplifiedChinese["stringUnit"] as? [String: Any],
                "Missing zh-Hans string unit: \(key)"
            )
            let value = try #require(stringUnit["value"] as? String)
            #expect(!value.isEmpty)
        }

        for (key, rawEntry) in strings {
            let entry = try #require(
                rawEntry as? [String: Any],
                "Malformed catalog entry: \(key)"
            )
            let localizations = try #require(
                entry["localizations"] as? [String: Any],
                "Missing localizations: \(key)"
            )
            let simplifiedChinese = try #require(
                localizations["zh-Hans"] as? [String: Any],
                "Missing zh-Hans: \(key)"
            )
            let stringUnit = try #require(
                simplifiedChinese["stringUnit"] as? [String: Any],
                "Missing zh-Hans string unit: \(key)"
            )
            let value = try #require(stringUnit["value"] as? String)
            #expect(!value.isEmpty, "Empty zh-Hans value: \(key)")
        }
    }

    @Test(.enabled(if: TAPCamDemoTestSourceInspection.isSourceTreeAvailable, "Source tree is unavailable on this runtime."))
    func mainPermissionPromptsAreLocalized() throws {
        let mainChinese = try TAPCamDemoTestSourceInspection.source(
            relativePath: "TAPCamDemo/zh-Hans.lproj/InfoPlist.strings"
        )

        #expect(mainChinese.contains("\"NSCameraUsageDescription\""))
        #expect(mainChinese.contains("\"NSLocationWhenInUseUsageDescription\""))
        #expect(mainChinese.contains("\"NSMicrophoneUsageDescription\""))
        #expect(mainChinese.contains("\"NSPhotoLibraryUsageDescription\""))
    }

}
