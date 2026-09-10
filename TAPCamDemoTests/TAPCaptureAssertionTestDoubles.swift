//
//  TAPCaptureAssertionTestDoubles.swift
//  TAPCamDemoTests
//

import Foundation
@testable import TAPCamDemo

enum CaptureAssertionTestError: Error {
    case unused
}

struct CaptureAssertionDeviceServiceCall: Equatable, Sendable {
    let keyId: String
    let clientDataHash: Data
}

final class SucceedingAssertionAppAttestClient: AppAttestClient, @unchecked Sendable {
    private let lock = NSLock()
    private var operationLog: [String] = []

    func operations() -> [String] {
        lock.withLock { operationLog }
    }

    func prepare(credentialName: String) async throws -> AppAttestCredential {
        throw CaptureAssertionTestError.unused
    }

    func prepareIfNeeded(credentialName: String) async throws -> AppAttestCredential {
        lock.withLock {
            operationLog.append("prepareIfNeeded:\(credentialName)")
        }
        return AppAttestCredential(
            credentialName: credentialName,
            keyId: "test-key-id"
        )
    }

    func validateCredential(credentialName: String) async throws {
        throw CaptureAssertionTestError.unused
    }

    func reset(credentialName: String) async throws {
        throw CaptureAssertionTestError.unused
    }
}

final class FailingPrepareIfNeededAppAttestClient: AppAttestClient, @unchecked Sendable {
    private let lock = NSLock()
    private var operationLog: [String] = []

    func operations() -> [String] {
        lock.withLock { operationLog }
    }

    func prepare(credentialName: String) async throws -> AppAttestCredential {
        throw CaptureAssertionTestError.unused
    }

    func prepareIfNeeded(credentialName: String) async throws -> AppAttestCredential {
        lock.withLock {
            operationLog.append("prepareIfNeeded:\(credentialName)")
        }
        throw CaptureAssertionTestError.unused
    }

    func validateCredential(credentialName: String) async throws {
        throw CaptureAssertionTestError.unused
    }

    func reset(credentialName: String) async throws {
        throw CaptureAssertionTestError.unused
    }
}

actor CountingCaptureAssertionSigner: CaptureAssertionSigning {
    private var callCount = 0

    func signCallCount() -> Int {
        callCount
    }

    func sign(contentDigest: CaptureContentDigest) async throws -> CaptureAssertionProof {
        callCount += 1
        throw CaptureAssertionTestError.unused
    }
}

final class RecordingCaptureAssertionDeviceService: AppAttestDeviceService, @unchecked Sendable {
    let isSupported = true

    private let lock = NSLock()
    private var calls: [CaptureAssertionDeviceServiceCall] = []

    func generateAssertionCalls() -> [CaptureAssertionDeviceServiceCall] {
        lock.withLock { calls }
    }

    func generateKey() async throws -> String {
        throw CaptureAssertionTestError.unused
    }

    func attestKey(_ keyId: String, clientDataHash: Data) async throws -> Data {
        throw CaptureAssertionTestError.unused
    }

    func generateAssertion(_ keyId: String, clientDataHash: Data) async throws -> Data {
        lock.withLock {
            calls.append(CaptureAssertionDeviceServiceCall(keyId: keyId, clientDataHash: clientDataHash))
        }
        return Data([0xA1, 0x01])
    }
}
