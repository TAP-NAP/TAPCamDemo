//
//  AppAttestRuntimeTests.swift
//  TAPCamDemoTests
//

import AppAttestKit
import Foundation
import Testing
@testable import TAPCamDemo

struct AppAttestRuntimeTests {
    #if DEBUG
    @Test @MainActor func debugRuntimeUsesLocalDebugBackendWithSharedChallenge() async throws {
        let runtime = try AppAttestRuntimeFactory.make()

        #expect(runtime.backendDescription == "Local Debug Backend: TapTapNapNap123123")
        #expect(runtime.debugBackend != nil)

        let attestationChallenge = try await runtime.debugBackend?.requestChallenge(
            AppAttestChallengeRequest(purpose: .attestation, credentialName: "demo-attestation")
        )
        let assertionChallenge = try await runtime.debugBackend?.requestChallenge(
            AppAttestChallengeRequest(purpose: .assertion, credentialName: "demo-assertion")
        )

        #expect(attestationChallenge?.challengeId == "TapTapNapNap123123")
        #expect(String(data: attestationChallenge?.challenge ?? Data(), encoding: .utf8) == "TapTapNapNap123123")
        #expect(assertionChallenge?.challengeId == "TapTapNapNap123123")
        #expect(String(data: assertionChallenge?.challenge ?? Data(), encoding: .utf8) == "TapTapNapNap123123")
    }

    @Test func backendSelectionBuildsDefaultLocalDebugMode() throws {
        let mode = try AppAttestRuntimeDefaults.mode(
            selection: .localDebug,
            httpBaseURLText: "https://api.example.com"
        )

        guard case .localDebug(let challenge) = mode else {
            Issue.record("Expected local debug backend mode.")
            return
        }
        #expect(challenge == "TapTapNapNap123123")
    }
    #endif

    @Test func backendSelectionBuildsHTTPMode() throws {
        let mode = try AppAttestRuntimeDefaults.mode(
            selection: .http,
            httpBaseURLText: " https://api.example.com "
        )

        guard case .http(let baseURL) = mode else {
            Issue.record("Expected HTTP backend mode.")
            return
        }
        #expect(baseURL.absoluteString == "https://api.example.com")
    }
}
