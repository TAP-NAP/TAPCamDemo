import Foundation
import Testing
@testable import TAPCamDemo

@Suite(.serialized)
struct NativeAppAttestClientTests {
    @Test func registrationPreservesHTTPContractAndSavesAcceptedCredential() async throws {
        let store = NativeAttestTestStore()
        let device = NativeAttestTestDevice()
        let http = NativeAttestTestHTTP([.challenge, .accepted])
        let client = try makeClient(store: store, device: device, http: http)
        let credential = try await client.prepare(credentialName: "photo_keyid")

        #expect(credential.keyId == "native-test-key")
        #expect(try store.credential(named: "photo_keyid")?.keyId == credential.keyId)
        #expect(await device.attestationHash?.appAttestBase64URL == "vkXLJgW_Nr695oSEGijw_UPGmFCj3OX-26aZKO46iZE")
        let requests = http.requests
        #expect(requests.map(\.path) == ["/app-attest/challenges", "/app-attest/attestations"])
        #expect(requests.allSatisfy { $0.method == "POST" && $0.contentType == "application/json" && $0.accept == "application/json" })
        #expect(String(decoding: requests[0].body, as: UTF8.self) == #"{"credentialName":"photo_keyid","purpose":"attestation"}"#)
        #expect(String(decoding: requests[1].body, as: UTF8.self) == #"{"attestationObject":"-_8","challengeId":"challenge-1","credentialName":"photo_keyid","keyId":"native-test-key"}"#)
    }

    @Test func healthAssertionMatchesTheExistingProtocolHash() async throws {
        let store = NativeAttestTestStore()
        try store.save(AppAttestCredential(credentialName: "photo_keyid", keyId: "existing-key"))
        let device = NativeAttestTestDevice()
        let http = NativeAttestTestHTTP([.challenge])
        let client = try makeClient(store: store, device: device, http: http)
        try await client.validateCredential(credentialName: "photo_keyid")

        // Fixed protocol vector for challenge bytes 0...15 and the health request.
        #expect(await device.assertionKey == "existing-key")
        #expect(await device.assertionHash?.appAttestBase64URL == "x7qlYZj-nvGPt_-wmr_yx-cYqtasPnz66BcxdEnVtD4")
        #expect(http.requests.count == 1)
        #expect(String(decoding: http.requests[0].body, as: UTF8.self) == #"{"credentialName":"photo_keyid","purpose":"assertion"}"#)
    }

    @Test func rejectedRegistrationDoesNotSaveCredential() async throws {
        let store = NativeAttestTestStore()
        let http = NativeAttestTestHTTP([.challenge, .init(body: #"{"status":"rejected"}"#)])
        let client = try makeClient(store: store, device: NativeAttestTestDevice(), http: http)
        await #expect(throws: AppAttestError.attestationRejected("Backend registration returned rejected.")) {
            try await client.prepare(credentialName: "photo_keyid")
        }
        #expect(try store.credential(named: "photo_keyid") == nil)
    }

    private func makeClient(
        store: NativeAttestTestStore, device: NativeAttestTestDevice, http: NativeAttestTestHTTP
    ) throws -> NativeAppAttestClient {
        try NativeAppAttestClient(
            baseURL: #require(URL(string: "https://attestation.example.test")),
            credentialStore: store, deviceService: device, urlSession: http.session()
        )
    }
}

nonisolated private final class NativeAttestTestStore: AppAttestCredentialStore, @unchecked Sendable {
    private let lock = NSLock()
    private var credentials: [String: AppAttestCredential] = [:]

    func credential(named name: String) throws -> AppAttestCredential? { lock.withLock { credentials[name] } }
    func save(_ credential: AppAttestCredential) throws { lock.withLock { credentials[credential.credentialName] = credential } }
    func delete(credentialName: String) throws { lock.withLock { _ = credentials.removeValue(forKey: credentialName) } }
}

private actor NativeAttestTestDevice: AppAttestDeviceService {
    nonisolated let isSupported = true
    private(set) var attestationHash: Data?
    private(set) var assertionKey: String?
    private(set) var assertionHash: Data?

    func generateKey() async throws -> String { "native-test-key" }
    func attestKey(_ keyId: String, clientDataHash: Data) async throws -> Data {
        attestationHash = clientDataHash
        return Data([0xfb, 0xff])
    }
    func generateAssertion(_ keyId: String, clientDataHash: Data) async throws -> Data {
        assertionKey = keyId
        assertionHash = clientDataHash
        return Data([1, 2, 3])
    }
}

nonisolated private final class NativeAttestTestHTTP: @unchecked Sendable {
    struct Response: Sendable {
        var status = 200
        let body: String
        static let challenge = Self(body: #"{"challengeId":"challenge-1","challenge":"AAECAwQFBgcICQoLDA0ODw","expiresAt":"2100-01-01T00:00:00Z"}"#)
        static let accepted = Self(body: #"{"status":"accepted"}"#)
    }
    struct Request: Sendable {
        let path: String
        let method: String?
        let contentType: String?
        let accept: String?
        let body: Data
    }
    private let lock = NSLock()
    private var responses: [Response]
    private var recorded: [Request] = []
    var requests: [Request] { lock.withLock { recorded } }

    init(_ responses: [Response]) { self.responses = responses }

    func session() -> URLSession {
        NativeAttestTestURLProtocol.setHandler { [self] request in try respond(to: request) }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [NativeAttestTestURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private func respond(to request: URLRequest) throws -> Response {
        var body = request.httpBody ?? Data()
        if let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 1024)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                body.append(contentsOf: buffer.prefix(count))
            }
        }
        return try lock.withLock {
            recorded.append(Request(
                path: request.url?.path ?? "", method: request.httpMethod,
                contentType: request.value(forHTTPHeaderField: "Content-Type"),
                accept: request.value(forHTTPHeaderField: "Accept"), body: body
            ))
            guard !responses.isEmpty else { throw URLError(.unsupportedURL) }
            return responses.removeFirst()
        }
    }
}

nonisolated private final class NativeAttestTestURLProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var handler: (@Sendable (URLRequest) throws -> NativeAttestTestHTTP.Response)?

    static func setHandler(_ value: @escaping @Sendable (URLRequest) throws -> NativeAttestTestHTTP.Response) {
        lock.withLock { handler = value }
    }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            guard let handle = Self.lock.withLock({ Self.handler }), let url = request.url else {
                throw URLError(.unsupportedURL)
            }
            let result = try handle(request)
            guard let response = HTTPURLResponse(url: url, statusCode: result.status, httpVersion: nil, headerFields: nil) else {
                throw URLError(.badServerResponse)
            }
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(result.body.utf8))
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}
