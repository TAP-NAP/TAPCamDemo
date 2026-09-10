import Foundation

/// Bounded, same-frame calibration after the manifest's calibration table fills.
nonisolated enum TAPDepthInlineCalibration {
    static let maximumByteCount = 3_072

    private struct Envelope: Codable {
        let calibration: TAPVideoManifest.CameraCalibration
        var schemaVersion = 1
    }

    /// An unavailable or oversized calibration must not discard valid depth.
    static func bounded(_ calibration: TAPVideoManifest.CameraCalibration?) -> TAPVideoManifest.CameraCalibration? {
        guard let calibration, (try? encodedData(calibration)) != nil else { return nil }
        return calibration
    }

    static func encodedData(_ calibration: TAPVideoManifest.CameraCalibration) throws -> Data {
        try validate(calibration)
        let data = try JSONEncoder.tapCaptureCanonical.encode(Envelope(calibration: calibration))
        guard data.count <= maximumByteCount else { throw invalid("CALD exceeds size limit") }
        return data
    }

    static func decode(_ data: Data) throws -> TAPVideoManifest.CameraCalibration {
        guard data.count <= maximumByteCount,
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(object.keys) == ["calibration", "schemaVersion"],
              let calibration = object["calibration"] as? [String: Any] else {
            throw invalid("invalid CALD envelope")
        }
        let required: Set<String> = ["intrinsicMatrix", "extrinsicMatrix", "intrinsicMatrixReferenceDimensions",
                                     "lensDistortionCenter", "pixelSizeMillimeters"]
        let allowed = required.union(["lensDistortionLookupTable", "inverseLensDistortionLookupTable"])
        guard required.isSubset(of: Set(calibration.keys)), Set(calibration.keys).isSubset(of: allowed),
              let dimensions = calibration["intrinsicMatrixReferenceDimensions"] as? [String: Any],
              Set(dimensions.keys) == ["width", "height"],
              let center = calibration["lensDistortionCenter"] as? [String: Any],
              Set(center.keys) == ["x", "y"] else {
            throw invalid("CALD must use the exact calibration schema")
        }
        for key in ["lensDistortionLookupTable", "inverseLensDistortionLookupTable"] {
            if let value = calibration[key], !(value is NSNull) {
                guard let text = value as? String,
                      let decoded = Data(base64Encoded: text),
                      decoded.base64EncodedString() == text else { throw invalid("invalid CALD base64") }
            }
        }
        // Preserve optional nulls and accept every finite JSON number spelling.
        // Comparing canonical structure also rejects duplicate keys and whitespace.
        let canonical = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
        guard try normalizedStructure(data) == normalizedStructure(canonical) else {
            throw invalid("CALD must use canonical JSON structure")
        }
        let envelope = try JSONDecoder().decode(Envelope.self, from: data)
        guard envelope.schemaVersion == 1 else { throw invalid("unsupported CALD schema") }
        try validate(envelope.calibration)
        return envelope.calibration
    }

    private static func validate(_ calibration: TAPVideoManifest.CameraCalibration) throws {
        let dimensions = calibration.intrinsicMatrixReferenceDimensions
        let center = calibration.lensDistortionCenter
        guard calibration.intrinsicMatrix.count == 9, calibration.extrinsicMatrix.count == 12,
              calibration.intrinsicMatrix.allSatisfy(\.isFinite), calibration.extrinsicMatrix.allSatisfy(\.isFinite),
              calibration.pixelSizeMillimeters.isFinite,
              [dimensions.width, dimensions.height, center.x, center.y].allSatisfy(\.isFinite) else {
            throw invalid("invalid CALD calibration values")
        }
    }

    private static func normalizedStructure(_ data: Data) throws -> String {
        guard let text = String(data: data, encoding: .utf8) else { throw invalid("invalid CALD UTF-8") }
        let tokens = try NSRegularExpression(pattern: #""(?:[^"\\]|\\.)*"|-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?"#)
        let source = text as NSString
        var result = ""
        var previousString = ""
        var cursor = 0
        for match in tokens.matches(in: text, range: NSRange(location: 0, length: source.length)) {
            result += source.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            let token = source.substring(with: match.range)
            if token.first == "\"" {
                previousString = token
                result += token
            } else if previousString == "\"schemaVersion\"" {
                guard token == "1" else { throw invalid("unsupported CALD schema") }
                result += token
            } else {
                guard let value = Double(token), value.isFinite else { throw invalid("nonfinite CALD number") }
                result += "0"
            }
            cursor = NSMaxRange(match.range)
        }
        return result + source.substring(from: cursor)
    }

    private static func invalid(_ message: String) -> TAPDepthCaptureError {
        .invalidTAPManifest(message)
    }
}
