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
    static let maximumRecordCount = 32
    static let maximumEncodedFrameByteCount = TAPDepthFrameCodec.maximumFrameByteCount + 4_096
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
        nonisolated static let calibrationIndex = FourCC(rawValue: "CALI")
        nonisolated static let uncompressedLength = FourCC(rawValue: "ULEN")
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
        guard data.count <= maximumEncodedFrameByteCount else {
            throw TAPDepthCaptureError.invalidTAPManifest("TAP depth KLV frame exceeds size limit")
        }
        var records: [Record] = []
        var offset = 0
        while offset < data.count {
            guard records.count < maximumRecordCount else {
                throw TAPDepthCaptureError.invalidTAPManifest("TAP depth KLV record count exceeds limit")
            }
            let (headerEnd, headerOverflow) = offset.addingReportingOverflow(8)
            guard !headerOverflow, headerEnd <= data.count else {
                throw TAPDepthCaptureError.invalidTAPManifest("truncated TAP depth KLV header")
            }
            let keyData = data.subdata(in: offset..<(offset + 4))
            guard let key = String(data: keyData, encoding: .ascii) else {
                throw TAPDepthCaptureError.invalidTAPManifest("invalid TAP depth KLV key")
            }
            let payloadLength = Int(data.uint32BE(at: offset + 4))
            offset += 8

            let (payloadEnd, payloadOverflow) = offset.addingReportingOverflow(payloadLength)
            guard payloadLength >= 0,
                  !payloadOverflow,
                  payloadEnd <= data.count else {
                throw TAPDepthCaptureError.invalidTAPManifest("truncated TAP depth KLV payload")
            }
            let payload = data.subdata(in: offset..<payloadEnd)
            offset = payloadEnd

            let padding = paddingByteCount(for: payloadLength)
            let (paddingEnd, paddingOverflow) = offset.addingReportingOverflow(padding)
            guard !paddingOverflow, paddingEnd <= data.count else {
                throw TAPDepthCaptureError.invalidTAPManifest("truncated TAP depth KLV padding")
            }
            if padding > 0 {
                let paddingRange = offset..<paddingEnd
                guard data[paddingRange].allSatisfy({ $0 == 0 }) else {
                    throw TAPDepthCaptureError.invalidTAPManifest("non-zero TAP depth KLV padding")
                }
                offset = paddingEnd
            }

            records.append(Record(key: FourCC(rawValue: key), payload: payload))
        }
        return records
    }

    private nonisolated static func paddingByteCount(for payloadLength: Int) -> Int {
        (4 - (payloadLength % 4)) % 4
    }
}

nonisolated struct TAPDepthKLVFrame: Equatable, Sendable {
    static let schemaVersion: UInt32 = 1

    let frameIndex: UInt32
    let timestampValue: Int64
    let timestampTimescale: Int32
    let compressionCodec: TAPDepthCompressionCodec
    let uncompressedByteCount: Int
    let calibrationIndex: UInt32?
    let payload: Data

    func encodedData() throws -> Data {
        guard uncompressedByteCount >= 0, uncompressedByteCount <= Int(UInt32.max) else {
            throw TAPDepthCaptureError.invalidTAPManifest("depth frame byte count is out of range")
        }

        var schemaData = Data()
        schemaData.appendUInt32BE(Self.schemaVersion)
        var frameData = Data()
        frameData.appendUInt32BE(frameIndex)
        var timestampData = Data()
        timestampData.appendInt64BE(timestampValue)
        timestampData.appendInt32BE(timestampTimescale)
        var lengthData = Data()
        lengthData.appendUInt32BE(UInt32(uncompressedByteCount))
        var records = [
            TAPDepthKLV.Record(key: .schemaVersion, payload: schemaData),
            TAPDepthKLV.Record(key: .frameIndex, payload: frameData),
            TAPDepthKLV.Record(key: .presentationTime, payload: timestampData),
            TAPDepthKLV.Record(key: .compression, payload: Data(compressionCodec.rawValue.utf8)),
            TAPDepthKLV.Record(key: .uncompressedLength, payload: lengthData)
        ]
        if let calibrationIndex {
            var calibrationData = Data()
            calibrationData.appendUInt32BE(calibrationIndex)
            records.append(TAPDepthKLV.Record(key: .calibrationIndex, payload: calibrationData))
        }
        records.append(TAPDepthKLV.Record(key: .depthPayload, payload: payload))
        return TAPDepthKLV.encode(records)
    }

    static func decode(_ data: Data) throws -> TAPDepthKLVFrame {
        let records = try TAPDepthKLV.decode(data)
        var payloadByKey: [TAPDepthKLV.FourCC: Data] = [:]
        for record in records {
            guard payloadByKey.updateValue(record.payload, forKey: record.key) == nil else {
                throw TAPDepthCaptureError.invalidTAPManifest(
                    "duplicate TAP depth KLV record \(record.key.rawValue)"
                )
            }
        }

        guard let schemaData = payloadByKey[.schemaVersion], schemaData.count == 4,
              schemaData.uint32BE(at: 0) == Self.schemaVersion else {
            throw TAPDepthCaptureError.invalidTAPManifest("unsupported TAP depth KLV schema")
        }
        guard let frameData = payloadByKey[.frameIndex], frameData.count == 4 else {
            throw TAPDepthCaptureError.invalidTAPManifest("missing TAP depth frame index")
        }
        guard let timestampData = payloadByKey[.presentationTime], timestampData.count == 12 else {
            throw TAPDepthCaptureError.invalidTAPManifest("missing TAP depth frame timestamp")
        }
        guard let compressionData = payloadByKey[.compression],
              let compressionValue = String(data: compressionData, encoding: .ascii),
              let compressionCodec = TAPDepthCompressionCodec(rawValue: compressionValue) else {
            throw TAPDepthCaptureError.invalidTAPManifest("unsupported TAP depth compression codec")
        }
        guard let lengthData = payloadByKey[.uncompressedLength], lengthData.count == 4 else {
            throw TAPDepthCaptureError.invalidTAPManifest("missing TAP depth frame byte count")
        }
        guard let payload = payloadByKey[.depthPayload] else {
            throw TAPDepthCaptureError.invalidTAPManifest("missing TAP depth frame payload")
        }

        let calibrationIndex: UInt32?
        if let calibrationData = payloadByKey[.calibrationIndex] {
            guard calibrationData.count == 4 else {
                throw TAPDepthCaptureError.invalidTAPManifest("invalid TAP depth calibration index")
            }
            calibrationIndex = calibrationData.uint32BE(at: 0)
        } else {
            calibrationIndex = nil
        }

        return TAPDepthKLVFrame(
            frameIndex: frameData.uint32BE(at: 0),
            timestampValue: timestampData.int64BE(at: 0),
            timestampTimescale: timestampData.int32BE(at: 8),
            compressionCodec: compressionCodec,
            uncompressedByteCount: Int(lengthData.uint32BE(at: 0)),
            calibrationIndex: calibrationIndex,
            payload: payload
        )
    }

    func decodedPackedBytes() throws -> Data {
        try TAPDepthFrameCodec.decode(
            TAPEncodedDepthFrame(
                codec: compressionCodec,
                uncompressedByteCount: uncompressedByteCount,
                payload: payload
            )
        )
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

    nonisolated mutating func appendInt32BE(_ value: Int32) {
        appendUInt32BE(UInt32(bitPattern: value))
    }

    nonisolated mutating func appendInt64BE(_ value: Int64) {
        let rawValue = UInt64(bitPattern: value)
        append(contentsOf: [
            UInt8((rawValue >> 56) & 0xff),
            UInt8((rawValue >> 48) & 0xff),
            UInt8((rawValue >> 40) & 0xff),
            UInt8((rawValue >> 32) & 0xff),
            UInt8((rawValue >> 24) & 0xff),
            UInt8((rawValue >> 16) & 0xff),
            UInt8((rawValue >> 8) & 0xff),
            UInt8(rawValue & 0xff)
        ])
    }

    nonisolated func uint32BE(at offset: Int) -> UInt32 {
        UInt32(self[offset]) << 24
            | UInt32(self[offset + 1]) << 16
            | UInt32(self[offset + 2]) << 8
            | UInt32(self[offset + 3])
    }

    nonisolated func int32BE(at offset: Int) -> Int32 {
        Int32(bitPattern: uint32BE(at: offset))
    }

    nonisolated func int64BE(at offset: Int) -> Int64 {
        var value: UInt64 = 0
        for index in 0..<8 {
            value = (value << 8) | UInt64(self[offset + index])
        }
        return Int64(bitPattern: value)
    }
}
