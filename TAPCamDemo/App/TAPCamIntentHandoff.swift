//
//  TAPCamIntentHandoff.swift
//  TAPCamDemo
//

import Foundation

nonisolated enum TAPCamIntentHandoffDestination: String, Codable, Equatable, Sendable {
    case camera
    case tapLibrary
    case tapLibraryAwaitingLockedImport
}

nonisolated struct TAPCamIntentHandoff: Codable, Equatable, Sendable {
    static let defaultTimeToLive: TimeInterval = 5 * 60

    let destination: TAPCamIntentHandoffDestination
    let requestedAt: Date
    let tapAction: String?
    let reason: String?

    init(
        destination: TAPCamIntentHandoffDestination,
        requestedAt: Date = Date(),
        tapAction: String? = nil,
        reason: String? = nil
    ) {
        self.destination = destination
        self.requestedAt = requestedAt
        self.tapAction = tapAction
        self.reason = reason
    }

    func isFresh(
        now: Date = Date(),
        timeToLive: TimeInterval = defaultTimeToLive
    ) -> Bool {
        now.timeIntervalSince(requestedAt) <= timeToLive
            && requestedAt <= now.addingTimeInterval(60)
    }

    var shouldRegenerateLockedCameraContext: Bool {
        tapAction == TAPCamLockedCameraHandoff.regenerateLockedCameraContext
    }

    var shouldDelayAppearanceForLockedContent: Bool {
        reason == "saved"
            || tapAction == TAPCamLockedCameraHandoff.openTAPLibraryAfterLockedCapture
            || tapAction == TAPCamLockedCameraHandoff.openTAPLibraryAwaitingLockedImport
    }
}

extension TAPCamIntentHandoff {
    init?(
        lockedCameraActivity activity: NSUserActivity,
        requestedAt: Date = Date()
    ) {
        guard activity.activityType == TAPCamLockedCameraHandoff.activityType else {
            return nil
        }

        let tapAction = activity.userInfo?[TAPCamLockedCameraHandoff.tapActionKey] as? String
        let reason = activity.userInfo?[TAPCamLockedCameraHandoff.reasonKey] as? String
        let destination: TAPCamIntentHandoffDestination
        switch tapAction {
        case TAPCamLockedCameraHandoff.openTAPCamera:
            destination = .camera
        case TAPCamLockedCameraHandoff.openTAPLibrary:
            destination = .tapLibrary
        case TAPCamLockedCameraHandoff.openTAPLibraryAwaitingLockedImport:
            destination = .tapLibraryAwaitingLockedImport
        case TAPCamLockedCameraHandoff.openTAPLibraryRuntimeImport:
            destination = .tapLibraryAwaitingLockedImport
        case TAPCamLockedCameraHandoff.openTAPCameraRuntimeImport:
            destination = .camera
        case TAPCamLockedCameraHandoff.openTAPLibraryAfterLockedCapture:
            destination = .tapLibrary
        case TAPCamLockedCameraHandoff.regenerateLockedCameraContext:
            destination = .camera
        default:
            destination = .camera
        }

        self.init(
            destination: destination,
            requestedAt: requestedAt,
            tapAction: tapAction,
            reason: reason
        )
    }
}

nonisolated struct TAPCamIntentHandoffStore {
    static let storageKey = "TAPCamIntentPendingHandoff"

    private let userDefaults: UserDefaults
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(
        userDefaults: UserDefaults = .standard,
        encoder: JSONEncoder = JSONEncoder(),
        decoder: JSONDecoder = JSONDecoder()
    ) {
        self.userDefaults = userDefaults
        self.encoder = encoder
        self.decoder = decoder
    }

    func saveHandoff(_ handoff: TAPCamIntentHandoff) {
        guard let data = try? encoder.encode(handoff) else {
            return
        }
        userDefaults.set(data, forKey: Self.storageKey)
    }

    func loadAndClearHandoff(now: Date = Date()) -> TAPCamIntentHandoff? {
        defer {
            userDefaults.removeObject(forKey: Self.storageKey)
        }

        guard let data = userDefaults.data(forKey: Self.storageKey),
              let handoff = try? decoder.decode(TAPCamIntentHandoff.self, from: data),
              handoff.isFresh(now: now) else {
            return nil
        }
        return handoff
    }
}

extension Notification.Name {
    static let tapCamIntentHandoffDidChange = Notification.Name("tapCamIntentHandoffDidChange")
}
