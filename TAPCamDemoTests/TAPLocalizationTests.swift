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
    func catalogHasSimplifiedChineseTranslations() throws {
        let catalogSource = try TAPCamDemoTestSourceInspection.source(
            relativePath: "TAPCamDemo/Localizable.xcstrings"
        )
        let data = Data(catalogSource.utf8)
        let root = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        let strings = try #require(root["strings"] as? [String: Any])
        for (key, rawEntry) in strings {
            #expect(!key.isEmpty, "Empty UI text should use a verbatim initializer")
            let entry = try #require(
                rawEntry as? [String: Any],
                "Malformed catalog entry: \(key)"
            )
            #expect(entry["extractionState"] as? String != "stale", "Review stale key usage: \(key)")
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
