//
//  TAPDepthKLV.swift
//  TAPCamDemo
//

import Foundation

/// Minimal GPMF-style KLV payload support for TAP private depth samples.
///
/// Each record is `[fourCC:4][payloadLength:4][payload][zero padding]`, where
/// the payload is padded to a 32-bit boundary. Unknown keys remain skippable.
nonisolated enum TAPDepthKLV {
    nonisolated struct Record: Equatable, Sendable {
        let key: FourCC
        let payload: Data

        init(key: FourCC, payload: Data) {
            self.key = key
            self.payload = payload
        }
    }

    nonisolated struct FourCC: RawRepresentable, Codable, Hashable, Sendable, CustomStringConvertible {
        let rawValue: String

        init(rawValue: String) {
            precondition(rawValue.utf8.count == 4, "FourCC must be four ASCII bytes")
            self.rawValue = rawValue
        }

        var description: String {
            rawValue
        }

        nonisolated static let schemaVersion = FourCC(rawValue: "TVER")
        nonisolated static let frameIndex = FourCC(rawValue: "FRAM")
        nonisolated static let presentationTime = FourCC(rawValue: "PTS ")
        nonisolated static let depthKind = FourCC(rawValue: "DKND")
        nonisolated static let pixelFormat = FourCC(rawValue: "PIXF")
        nonisolated static let dimensions = FourCC(rawValue: "DIM ")
        nonisolated static let rowStride = FourCC(rawValue: "RSTR")
        nonisolated static let compression = FourCC(rawValue: "COMP")
        nonisolated static let calibrationReference = FourCC(rawValue: "CALR")
        nonisolated static let depthPayload = FourCC(rawValue: "DPTH")
    }

    nonisolated static func encode(_ records: [Record]) -> Data {
        var data = Data()
        for record in records {
            data.append(Data(record.key.rawValue.utf8))
            data.appendUInt32BE(UInt32(record.payload.count))
            data.append(record.payload)
            data.append(contentsOf: Array(repeating: UInt8(0), count: paddingByteCount(for: record.payload.count)))
        }
        return data
    }

    nonisolated static func decode(_ data: Data) throws -> [Record] {
        var records: [Record] = []
        var offset = 0
        while offset < data.count {
            guard offset + 8 <= data.count else {
                throw TAPDepthCaptureError.invalidTAPManifest("truncated TAP depth KLV header")
            }
            let keyData = data.subdata(in: offset..<(offset + 4))
            guard let key = String(data: keyData, encoding: .ascii) else {
                throw TAPDepthCaptureError.invalidTAPManifest("invalid TAP depth KLV key")
            }
            let payloadLength = Int(data.uint32BE(at: offset + 4))
            offset += 8

            guard payloadLength >= 0,
                  offset + payloadLength <= data.count else {
                throw TAPDepthCaptureError.invalidTAPManifest("truncated TAP depth KLV payload")
            }
            let payload = data.subdata(in: offset..<(offset + payloadLength))
            offset += payloadLength

            let padding = paddingByteCount(for: payloadLength)
            guard offset + padding <= data.count else {
                throw TAPDepthCaptureError.invalidTAPManifest("truncated TAP depth KLV padding")
            }
            if padding > 0 {
                let paddingRange = offset..<(offset + padding)
                guard data[paddingRange].allSatisfy({ $0 == 0 }) else {
                    throw TAPDepthCaptureError.invalidTAPManifest("non-zero TAP depth KLV padding")
                }
                offset += padding
            }

            records.append(Record(key: FourCC(rawValue: key), payload: payload))
        }
        return records
    }

    private nonisolated static func paddingByteCount(for payloadLength: Int) -> Int {
        (4 - (payloadLength % 4)) % 4
    }
}

private extension Data {
    nonisolated mutating func appendUInt32BE(_ value: UInt32) {
        append(contentsOf: [
            UInt8((value >> 24) & 0xff),
            UInt8((value >> 16) & 0xff),
            UInt8((value >> 8) & 0xff),
            UInt8(value & 0xff)
        ])
    }

    nonisolated func uint32BE(at offset: Int) -> UInt32 {
        UInt32(self[offset]) << 24
            | UInt32(self[offset + 1]) << 16
            | UInt32(self[offset + 2]) << 8
            | UInt32(self[offset + 3])
    }
}
