//
//  TAPCamIntentHandoff.swift
//  TAPCamDemo
//

import Foundation

nonisolated enum TAPCamIntentHandoffDestination: String, Codable, Equatable, Sendable {
    case camera
    case tapLibrary
}

nonisolated struct TAPCamIntentHandoff: Codable, Equatable, Sendable {
    static let defaultTimeToLive: TimeInterval = 5 * 60

    let destination: TAPCamIntentHandoffDestination
    let requestedAt: Date

    init(
        destination: TAPCamIntentHandoffDestination,
        requestedAt: Date = Date()
    ) {
        self.destination = destination
        self.requestedAt = requestedAt
    }

    func isFresh(
        now: Date = Date(),
        timeToLive: TimeInterval = defaultTimeToLive
    ) -> Bool {
        now.timeIntervalSince(requestedAt) <= timeToLive
            && requestedAt <= now.addingTimeInterval(60)
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
