import Foundation

nonisolated enum AppAttestBase64URL {
    static func encode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func decode(_ string: String) -> Data? {
        let base64 = string.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let padding = (4 - base64.count % 4) % 4
        return Data(base64Encoded: base64 + String(repeating: "=", count: padding))
    }

    static func decode(_ string: String, field: String) throws -> Data {
        guard let data = decode(string) else {
            throw AppAttestError.invalidBase64URL(field: field)
        }
        return data
    }
}

nonisolated extension Data {
    var appAttestBase64URL: String { AppAttestBase64URL.encode(self) }
}
