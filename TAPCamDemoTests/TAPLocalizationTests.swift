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
    func localeOverrideUsesPresentationOnlyRootInjection() throws {
        let appSource = try TAPCamDemoTestSourceInspection.source(
            relativePath: "TAPCamDemo/App/TAPCamDemoApp.swift"
        )
        let languageSource = try TAPCamDemoTestSourceInspection.source(
            relativePath: "TAPCamDemo/App/AppLanguage.swift"
        )
        let settingsSource = try TAPCamDemoTestSourceInspection.source(
            relativePath: "TAPCamDemo/DepthAnalysis/DepthAnalyzerSettingsView.swift"
        )
        let languageSection = try #require(
            TAPCamDemoTestSourceInspection.substring(
                in: settingsSource,
                from: "private var languageSettingsSection",
                to: "private var cameraSettingsSection"
            )
        )

        #expect(appSource.contains("@AppStorage(AppLanguage.storageKey)"))
        #expect(appSource.contains(#"\.locale"#))
        #expect(appSource.contains("AppLanguage.resolved(rawValue: appLanguageRawValue).locale"))
        #expect(!appSource.contains(".id(appLanguage"))
        #expect(!appSource.contains("configureCurrentSelection"))
        #expect(!appSource.contains("configurePhotographerMode"))
        #expect(languageSection.contains(#"Picker("App Language", selection: appLanguageSelection)"#))
        #expect(languageSection.contains("AppLanguage.resolved(rawValue: appLanguageRawValue).rawValue"))
        #expect(languageSection.contains("AppLanguage.allCases"))
        #expect(!languageSection.contains(".onChange"))
        #expect(!languageSection.contains(".task"))
        #expect(!languageSection.contains(".onAppear"))
        #expect(!languageSource.contains("scenePhase"))
        #expect(!languageSource.contains("configureCurrentSelection"))
        #expect(!languageSource.contains("CaptureSession"))
    }

    @Test(.enabled(if: TAPCamDemoTestSourceInspection.isSourceTreeAvailable, "Source tree is unavailable on this runtime."))
    func viewfinderStaysEnglishWithoutChangingCameraLifecycle() throws {
        let cameraSource = try TAPCamDemoTestSourceInspection.source(
            relativePath: "TAPCamDemo/CameraCapture/UI/CameraView.swift"
        )
        let cameraRootSection = try #require(
            TAPCamDemoTestSourceInspection.substring(
                in: cameraSource,
                from: "private var cameraRootView",
                to: "private var cameraLifecycleObservers"
            )
        )

        #expect(
            cameraRootSection.contains(
                """
                cameraSurface
                                .environment(\\.locale, AppLanguage.english.locale)
                """
            )
        )
        #expect(
            cameraRootSection.components(
                separatedBy: "AppLanguage.english.locale"
            ).count == 2
        )
        #expect(cameraRootSection.contains("DepthAlbumPickerView("))
        #expect(cameraRootSection.contains(".sheet(isPresented: $isShowingSettings)"))
        #expect(cameraRootSection.contains("DepthAnalyzerSettingsView("))
        #expect(cameraRootSection.contains(".cameraScreenLifecycle("))
        #expect(!cameraRootSection.contains(".id("))
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
            "Photo Integrity",
            "Protection Readiness",
            "Not Ready",
            "Preparation Failed",
            "Interaction Haptics",
            "Silent Shutter",
            "Silent shutter is unavailable on this device or in this region.",
            "Analysis Animation",
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
            "share.option.sticker.title",
            "share.option.sticker.subtitle",
            "share.option.link.title",
            "share.option.link.subtitle",
            "share.badge.recommended",
            "share.badge.members",
            "share.badge.comingSoon",
            "share.badge.membersComingSoon",
            "share.progress.accessibilityValue",
            "share.error.title",
            "share.error.message",
            "share.integrity.checking.accessibility",
            "share.warning.localIntegrityFailed",
            "Delete",
            "Coming soon",
            "3D projection",
            "Median depth",
            "Near %@",
            "Valid depth",
            "Views",
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
    func depthAnalysisStaticCopyUsesCatalogWithoutTreatingRuntimeValuesAsKeys() throws {
        let sharedInspectorSource = try TAPCamDemoTestSourceInspection.source(
            relativePath: "TAPCamDemo/DepthAnalysis/DepthAnalysisInspectors.swift"
        )
        let panelSource = try TAPCamDemoTestSourceInspection.source(
            relativePath: "TAPCamDemo/DepthAnalysis/DepthAnalysisPanelLayer.swift"
        )
        let stripSource = try TAPCamDemoTestSourceInspection.source(
            relativePath: "TAPCamDemo/DepthAnalysis/DepthAnalysisInspectorStrip.swift"
        )
        let regionSource = try TAPCamDemoTestSourceInspection.source(
            relativePath: "TAPCamDemo/DepthAnalysis/DepthAnalysisRegionInspectorContent.swift"
        )
        let planeSource = try TAPCamDemoTestSourceInspection.source(
            relativePath: "TAPCamDemo/DepthAnalysis/DepthAnalysisPlaneFilterInspectorContent.swift"
        )

        #expect(sharedInspectorSource.contains("Text(LocalizedStringKey(text))"))
        #expect(sharedInspectorSource.contains("Text(LocalizedStringKey(title))"))
        #expect(sharedInspectorSource.contains(".help(Text(LocalizedStringKey(explanation)))"))
        #expect(sharedInspectorSource.contains("Text(value)"))
        #expect(!sharedInspectorSource.contains("Text(LocalizedStringKey(value))"))
        #expect(sharedInspectorSource.contains("Text(verbatim: label)"))

        #expect(panelSource.contains("Text(LocalizedStringKey(title))"))
        #expect(stripSource.contains(".accessibilityLabel(Text(LocalizedStringKey(item.title)))"))
        #expect(stripSource.contains(".help(Text(LocalizedStringKey(item.detailedExplanation)))"))
        #expect(stripSource.contains("Text(LocalizedStringKey(hint.title))"))

        #expect(regionSource.contains("Text(LocalizedStringKey(stateText))"))
        #expect(regionSource.contains("Text(LocalizedStringKey(title))"))
        #expect(regionSource.contains("Label(heatmapErrorMessage.text"))
        #expect(!regionSource.contains("LocalizedStringKey(heatmapErrorMessage.text)"))
        #expect(planeSource.contains("Text(LocalizedStringKey(text))"))
        #expect(planeSource.contains("Label(errorMessage.text"))
        #expect(!planeSource.contains("LocalizedStringKey(errorMessage.text)"))
    }

    @Test(.enabled(if: TAPCamDemoTestSourceInspection.isSourceTreeAvailable, "Source tree is unavailable on this runtime."))
    func dynamicMainPathCopyLocalizesKnownProductMessagesAndKeepsUnknownValuesVerbatim() throws {
        let welcomeSource = try TAPCamDemoTestSourceInspection.source(
            relativePath: "TAPCamDemo/App/WelcomeStartupSetupView.swift"
        )
        let libraryModelSource = try TAPCamDemoTestSourceInspection.source(
            relativePath: "TAPCamDemo/DepthAnalysis/DepthAlbumPickerViewModel.swift"
        )
        let librarySource = try TAPCamDemoTestSourceInspection.source(
            relativePath: "TAPCamDemo/DepthAnalysis/DepthAlbumPickerView.swift"
        )
        let readinessSource = try TAPCamDemoTestSourceInspection.source(
            relativePath: "TAPCamDemo/CameraCapture/UI/CameraInitialReadinessGate.swift"
        )
        let transitionSource = try TAPCamDemoTestSourceInspection.source(
            relativePath: "TAPCamDemo/CameraCapture/UI/CameraViewfinderTransitionOverlayView.swift"
        )

        #expect(welcomeSource.contains("let title: LocalizedStringKey"))
        #expect(welcomeSource.contains("let message: LocalizedStringKey"))
        #expect(welcomeSource.contains("let actionTitle: LocalizedStringKey"))
        #expect(welcomeSource.contains("Text(actionTitle)"))
        #expect(welcomeSource.contains("Text(secondaryActionTitle)"))

        #expect(libraryModelSource.contains("enum DepthAlbumLoadingPresentation"))
        #expect(libraryModelSource.contains(#"case library = "Loading TAP Library...""#))
        #expect(libraryModelSource.contains(#"case lockedCaptureImport = "Importing locked captures...""#))
        #expect(librarySource.contains("LocalizedStringKey(viewModel.loadingPresentation.rawValue)"))
        #expect(librarySource.contains("albumErrorDescription(errorMessage)"))
        #expect(librarySource.contains("Text(verbatim: message)"))

        #expect(readinessSource.contains("CameraInitialReadinessMessageText(message: message)"))
        #expect(readinessSource.contains("Text(LocalizedStringKey(message))"))
        #expect(readinessSource.contains("readyPairingKey(in: message)"))
        #expect(readinessSource.contains("Text(verbatim: message)"))

        #expect(transitionSource.contains("CameraViewfinderTransitionCopy.text(for: message)"))
        #expect(transitionSource.contains("CameraViewfinderTransitionCopy.text(for: recoveryActionTitle)"))
        #expect(transitionSource.contains("Text(LocalizedStringKey(message))"))
        #expect(transitionSource.contains("Text(verbatim: message)"))
    }

    @Test(.enabled(if: TAPCamDemoTestSourceInspection.isSourceTreeAvailable, "Source tree is unavailable on this runtime."))
    func permissionPromptsAreLocalizedPerBundle() throws {
        let mainChinese = try TAPCamDemoTestSourceInspection.source(
            relativePath: "TAPCamDemo/zh-Hans.lproj/InfoPlist.strings"
        )
        let captureChinese = try TAPCamDemoTestSourceInspection.source(
            relativePath: "TAPCamLockedCameraCaptureExtension/zh-Hans.lproj/InfoPlist.strings"
        )
        let controlChinese = try TAPCamDemoTestSourceInspection.source(
            relativePath: "TAPCamLockedCameraControlExtension/zh-Hans.lproj/InfoPlist.strings"
        )
        let captureInterfaceChinese = try TAPCamDemoTestSourceInspection.source(
            relativePath: "TAPCamLockedCameraCaptureExtension/zh-Hans.lproj/Localizable.strings"
        )
        let controlInterfaceChinese = try TAPCamDemoTestSourceInspection.source(
            relativePath: "TAPCamLockedCameraControlExtension/zh-Hans.lproj/Localizable.strings"
        )

        #expect(mainChinese.contains("\"NSCameraUsageDescription\""))
        #expect(mainChinese.contains("\"NSLocationWhenInUseUsageDescription\""))
        #expect(mainChinese.contains("\"NSMicrophoneUsageDescription\""))
        #expect(mainChinese.contains("\"NSPhotoLibraryUsageDescription\""))
        #expect(captureChinese.contains("\"NSCameraUsageDescription\""))
        #expect(controlChinese.contains("\"CFBundleDisplayName\""))
        #expect(captureInterfaceChinese.contains(#""Starting Camera" = "正在启动相机";"#))
        #expect(captureInterfaceChinese.contains(#""Capture" = "拍摄";"#))
        #expect(captureInterfaceChinese.contains(#""TAPCam Camera" = "TAPCam 相机";"#))
        #expect(controlInterfaceChinese.contains(#""Open TAPCam" = "打开 TAPCam";"#))
        #expect(controlInterfaceChinese.contains("从锁定屏幕打开 TAPCam"))
    }

    @Test(.enabled(if: TAPCamDemoTestSourceInspection.isSourceTreeAvailable, "Source tree is unavailable on this runtime."))
    func noOpLiDARFocusAssistPreferenceIsRemovedWithoutTouchingManualFocusAssist() throws {
        let settingsSource = try TAPCamDemoTestSourceInspection.source(
            relativePath: "TAPCamDemo/DepthAnalysis/DepthAnalyzerSettingsView.swift"
        )
        let preferenceSource = try TAPCamDemoTestSourceInspection.source(
            relativePath: "TAPCamDemo/CameraCapture/UI/CameraUXPreferences.swift"
        )
        let cameraSource = try TAPCamDemoTestSourceInspection.source(
            relativePath: "TAPCamDemo/CameraCapture/UI/CameraView.swift"
        )

        #expect(!settingsSource.contains("LiDAR Focus Assist"))
        #expect(!settingsSource.contains("CameraLiDARFocusAssistPreferences"))
        #expect(!preferenceSource.contains("CameraLiDARFocusAssistPreferences"))
        #expect(cameraSource.contains("manualFocusTapAssistAtPreviewPoint"))
        #expect(cameraSource.contains("performManualFocusTapAssist"))
    }
}
