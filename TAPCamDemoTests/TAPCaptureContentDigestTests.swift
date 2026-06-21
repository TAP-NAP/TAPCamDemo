//
//  TAPCaptureContentDigestTests.swift
//  TAPCamDemoTests
//

import Foundation
import Testing
@testable import TAPCamDemo

struct TAPCaptureContentDigestTests {
    @Test func captureContentDigestCanonicalJSONIsStable() throws {
        let digest = TAPCaptureProvenanceTestFixtures.sampleContentDigest()
        let first = try digest.canonicalJSONData()
        let second = try digest.canonicalJSONData()
        let decoded = try JSONDecoder().decode(CaptureContentDigest.self, from: first)
        let json = try #require(String(data: first, encoding: .utf8))

        #expect(first == second)
        #expect(decoded == digest)
        #expect(json.contains("\"captureID\":\"sample-capture\""))
        #expect(json.contains("\"schemaID\":\"urn:tapnap:tapcam:capture-content-digest:v1\""))
    }
}
