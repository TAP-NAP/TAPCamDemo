//
//  AppLanguage.swift
//  TAPCamDemo
//

import Foundation
import SwiftUI

/// The user's in-app language preference.
///
/// Keep `.system` as the default so a fresh install follows the device. Adding
/// another supported language later requires one enum case and its catalog
/// localization; persisted values remain stable because storage uses raw values.
nonisolated enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case system
    case english = "en"
    case simplifiedChinese = "zh-Hans"

    static let storageKey = "TAPCamDemo.AppLanguage"
    static let defaultValue = AppLanguage.system

    var id: String { rawValue }

    var titleKey: LocalizedStringKey {
        switch self {
        case .system:
            "System Default"
        case .english:
            "English"
        case .simplifiedChinese:
            "Simplified Chinese"
        }
    }

    var locale: Locale {
        switch self {
        case .system:
            .autoupdatingCurrent
        case .english:
            Locale(identifier: "en")
        case .simplifiedChinese:
            Locale(identifier: "zh-Hans")
        }
    }

    static func resolved(rawValue: String) -> AppLanguage {
        AppLanguage(rawValue: rawValue) ?? defaultValue
    }

    static func resolved(in userDefaults: UserDefaults = .standard) -> AppLanguage {
        resolved(
            rawValue: userDefaults.string(forKey: storageKey) ?? defaultValue.rawValue
        )
    }
}
