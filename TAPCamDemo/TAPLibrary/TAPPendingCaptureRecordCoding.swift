//
//  TAPPendingCaptureRecordCoding.swift
//  TAPCamDemo
//

import Foundation

nonisolated enum TAPPendingCaptureRecordCoding {
    static func encode(_ record: TAPPendingCaptureRecord) throws -> Data {
        try encoder().encode(record)
    }

    static func decode(from data: Data) throws -> TAPPendingCaptureRecord {
        try decoder().decode(TAPPendingCaptureRecord.self, from: data)
    }

    private static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
