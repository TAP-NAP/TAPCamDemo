//
//  TAPVideoManifestBox.swift
//  TAPCamDemo
//

import Foundation

/// TAP-private top-level BMFF `uuid` box that stores the video manifest JSON.
///
/// The manifest box is part of the signed MP4 byte stream. Only the separate
/// TAP proof slot is excluded from the content hash.
nonisolated enum TAPVideoManifestBox {
    private static let uuid = Data("TAPCAMVIDEOMANF1".utf8)

    static func appendingManifest(_ manifest: TAPVideoManifest, to data: Data) throws -> Data {
        do {
            _ = try locate(in: data)
            throw TAPDepthCaptureError.invalidTAPManifest("expected no existing TAP video manifest box")
        } catch TAPDepthCaptureError.xmpManifestMissing {
            let manifestData = try TAPVideoManifestEncoder.manifestData(manifest)
            return data + bmffUUIDBox(payload: manifestData)
        } catch {
            throw error
        }
    }

    static func decodedManifest(from data: Data) throws -> TAPVideoManifest {
        let manifestData = try manifestData(from: data)
        return try JSONDecoder().decode(TAPVideoManifest.self, from: manifestData)
    }

    static func manifestData(from data: Data) throws -> Data {
        let range = try locate(in: data)
        return data.subdata(in: range)
    }

    private static func bmffUUIDBox(payload: Data) -> Data {
        var box = Data()
        box.appendUInt32BE(UInt32(8 + uuid.count + payload.count))
        box.append(Data("uuid".utf8))
        box.append(uuid)
        box.append(payload)
        return box
    }

    private static func locate(in data: Data) throws -> Range<Int> {
        var offset = 0
        var matches = [Range<Int>]()

        while offset + 8 <= data.count {
            let boxStart = offset
            let size32 = data.readUInt32BE(at: offset)
            let typeStart = offset + 4
            let type = data.subdata(in: typeStart..<(typeStart + 4))
            offset += 8

            let boxSize: Int
            if size32 == 1 {
                guard offset + 8 <= data.count else { break }
                let largeSize = data.readUInt64BE(at: offset)
                guard largeSize <= UInt64(Int.max) else { break }
                boxSize = Int(largeSize)
                offset += 8
            } else if size32 == 0 {
                boxSize = data.count - boxStart
            } else {
                boxSize = Int(size32)
            }

            guard boxSize >= offset - boxStart,
                  boxStart + boxSize <= data.count else {
                break
            }

            if type == Data("uuid".utf8),
               offset + uuid.count <= boxStart + boxSize,
               data.subdata(in: offset..<(offset + uuid.count)) == uuid {
                matches.append((offset + uuid.count)..<(boxStart + boxSize))
            }

            offset = boxStart + boxSize
        }

        guard !matches.isEmpty else {
            throw TAPDepthCaptureError.xmpManifestMissing
        }
        guard matches.count == 1, let match = matches.first else {
            throw TAPDepthCaptureError.invalidTAPManifest("expected exactly one TAP video manifest box")
        }
        return match
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

    nonisolated func readUInt32BE(at offset: Int) -> UInt32 {
        (UInt32(self[offset]) << 24)
            | (UInt32(self[offset + 1]) << 16)
            | (UInt32(self[offset + 2]) << 8)
            | UInt32(self[offset + 3])
    }

    nonisolated func readUInt64BE(at offset: Int) -> UInt64 {
        var value: UInt64 = 0
        for index in 0..<8 {
            value = (value << 8) | UInt64(self[offset + index])
        }
        return value
    }
}
