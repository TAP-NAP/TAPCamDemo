//
//  TAPBMFFStreamingFile.swift
//  TAPCamDemo
//

import CryptoKit
import AppAttestKit
import Darwin
import Foundation

nonisolated struct TAPFileByteRange: Equatable, Sendable {
    let offset: UInt64
    let length: UInt64

    var upperBound: UInt64 {
        let (value, overflow) = offset.addingReportingOverflow(length)
        return overflow ? UInt64.max : value
    }
}

nonisolated struct TAPBMFFTopLevelBox: Equatable, Sendable {
    let type: String
    let range: TAPFileByteRange
    let headerByteCount: UInt64
    let userType: Data?
    let usesToEndSize: Bool

    var payloadRange: TAPFileByteRange {
        let userTypeByteCount = userType == nil ? 0 : 16
        let payloadOffset = range.offset + headerByteCount + UInt64(userTypeByteCount)
        return TAPFileByteRange(
            offset: payloadOffset,
            length: range.upperBound - payloadOffset
        )
    }
}

nonisolated struct TAPVideoContainerLayout: Equatable, Sendable {
    let fileByteCount: UInt64
    let topLevelBoxes: [TAPBMFFTopLevelBox]

    static func read(from fileURL: URL) throws -> Self {
        Self(
            fileByteCount: try TAPBMFFStreamingFile.byteCount(of: fileURL),
            topLevelBoxes: try TAPBMFFStreamingFile.topLevelBoxes(at: fileURL)
        )
    }
}

nonisolated enum TAPBMFFStreamingFile {
    static let defaultChunkByteCount = 1 * 1024 * 1024
    static let maximumManifestByteCount = 1 * 1024 * 1024
    static let maximumTopLevelBoxCount = 4_096

    static func topLevelBoxes(at fileURL: URL) throws -> [TAPBMFFTopLevelBox] {
        let fileByteCount = try byteCount(of: fileURL)
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer {
            try? handle.close()
        }

        var boxes: [TAPBMFFTopLevelBox] = []
        var offset: UInt64 = 0
        while offset < fileByteCount {
            guard boxes.count < maximumTopLevelBoxCount else {
                throw TAPDepthCaptureError.invalidTAPManifest("BMFF top-level box count exceeds limit")
            }
            guard fileByteCount - offset >= 8 else {
                throw TAPDepthCaptureError.invalidTAPManifest("truncated BMFF box header")
            }
            try handle.seek(toOffset: offset)
            let baseHeader = try readExactly(8, from: handle)
            let size32 = baseHeader.tapUInt32BE(at: 0)
            guard let type = String(data: baseHeader.subdata(in: 4..<8), encoding: .ascii) else {
                throw TAPDepthCaptureError.invalidTAPManifest("invalid BMFF box type")
            }

            let headerByteCount: UInt64
            let boxByteCount: UInt64
            switch size32 {
            case 0:
                headerByteCount = 8
                boxByteCount = fileByteCount - offset
            case 1:
                guard fileByteCount - offset >= 16 else {
                    throw TAPDepthCaptureError.invalidTAPManifest("truncated BMFF large-size header")
                }
                let extendedSize = try readExactly(8, from: handle).tapUInt64BE(at: 0)
                headerByteCount = 16
                boxByteCount = extendedSize
            default:
                headerByteCount = 8
                boxByteCount = UInt64(size32)
            }

            guard boxByteCount >= headerByteCount,
                  boxByteCount <= fileByteCount - offset else {
                throw TAPDepthCaptureError.invalidTAPManifest("invalid BMFF box length")
            }

            let userType: Data?
            if type == "uuid" {
                guard boxByteCount >= headerByteCount + 16 else {
                    throw TAPDepthCaptureError.invalidTAPManifest("truncated BMFF uuid box")
                }
                userType = try readExactly(16, from: handle)
            } else {
                userType = nil
            }

            boxes.append(TAPBMFFTopLevelBox(
                type: type,
                range: TAPFileByteRange(offset: offset, length: boxByteCount),
                headerByteCount: headerByteCount,
                userType: userType,
                usesToEndSize: size32 == 0
            ))
            offset += boxByteCount
        }
        return boxes
    }

    static func byteCount(of fileURL: URL) throws -> UInt64 {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer {
            try? handle.close()
        }
        var fileStatus = stat()
        guard Darwin.fstat(handle.fileDescriptor, &fileStatus) == 0,
              fileStatus.st_size >= 0 else {
            throw TAPDepthCaptureError.pendingCaptureDataMissing
        }
        return UInt64(fileStatus.st_size)
    }

    static func read(
        _ range: TAPFileByteRange,
        from fileURL: URL,
        maximumByteCount: Int
    ) throws -> Data {
        guard range.length <= UInt64(maximumByteCount), range.length <= UInt64(Int.max) else {
            throw TAPDepthCaptureError.invalidTAPManifest("BMFF payload exceeds bounded read limit")
        }
        let fileByteCount = try byteCount(of: fileURL)
        guard range.upperBound <= fileByteCount else {
            throw TAPDepthCaptureError.invalidTAPManifest("BMFF payload range exceeds file")
        }
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer {
            try? handle.close()
        }
        try handle.seek(toOffset: range.offset)
        return try readExactly(Int(range.length), from: handle)
    }

    static func append(_ data: Data, to fileURL: URL) throws {
        let handle = try FileHandle(forWritingTo: fileURL)
        defer {
            try? handle.close()
        }
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
        try handle.synchronize()
    }

    static func overwrite(
        _ data: Data,
        in range: TAPFileByteRange,
        at fileURL: URL
    ) throws {
        guard UInt64(data.count) == range.length else {
            throw TAPDepthCaptureError.pendingCaptureProofInvalid("fixed proof payload length mismatch")
        }
        let fileByteCount = try byteCount(of: fileURL)
        guard range.upperBound <= fileByteCount else {
            throw TAPDepthCaptureError.pendingCaptureProofInvalid("proof payload range exceeds file")
        }
        guard range.offset <= UInt64(Int64.max),
              UInt64(data.count) <= UInt64(Int64.max) - range.offset else {
            throw TAPDepthCaptureError.pendingCaptureProofInvalid("proof payload offset exceeds platform file limits")
        }
        let handle = try FileHandle(forWritingTo: fileURL)
        defer {
            try? handle.close()
        }
        let descriptor = handle.fileDescriptor
        try data.withUnsafeBytes { bytes in
            guard let baseAddress = bytes.baseAddress else {
                return
            }
            var writtenByteCount = 0
            while writtenByteCount < data.count {
                let result = Darwin.pwrite(
                    descriptor,
                    baseAddress.advanced(by: writtenByteCount),
                    data.count - writtenByteCount,
                    off_t(range.offset) + off_t(writtenByteCount)
                )
                if result < 0, errno == EINTR {
                    continue
                }
                guard result > 0 else {
                    throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
                }
                writtenByteCount += result
            }
        }
        guard Darwin.fsync(descriptor) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }

    static func sha256Base64URL(
        of fileURL: URL,
        excluding excludedRange: TAPFileByteRange,
        chunkByteCount: Int = defaultChunkByteCount
    ) throws -> String {
        guard chunkByteCount > 0 else {
            throw TAPDepthCaptureError.pendingCaptureProofInvalid("hash chunk size must be positive")
        }
        let fileByteCount = try byteCount(of: fileURL)
        guard excludedRange.upperBound <= fileByteCount else {
            throw TAPDepthCaptureError.pendingCaptureProofInvalid("proof range exceeds file")
        }
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer {
            try? handle.close()
        }

        var hasher = SHA256()
        try update(
            &hasher,
            from: handle,
            range: TAPFileByteRange(offset: 0, length: excludedRange.offset),
            chunkByteCount: chunkByteCount
        )
        try update(
            &hasher,
            from: handle,
            range: TAPFileByteRange(
                offset: excludedRange.upperBound,
                length: fileByteCount - excludedRange.upperBound
            ),
            chunkByteCount: chunkByteCount
        )
        return Data(hasher.finalize()).appAttestBase64URL
    }

    private static func update(
        _ hasher: inout SHA256,
        from handle: FileHandle,
        range: TAPFileByteRange,
        chunkByteCount: Int
    ) throws {
        guard range.length > 0 else {
            return
        }
        try handle.seek(toOffset: range.offset)
        var remaining = range.length
        while remaining > 0 {
            let requestedByteCount = Int(min(UInt64(chunkByteCount), remaining))
            let chunk = try readExactly(requestedByteCount, from: handle)
            hasher.update(data: chunk)
            remaining -= UInt64(chunk.count)
        }
    }

    private static func readExactly(_ byteCount: Int, from handle: FileHandle) throws -> Data {
        guard byteCount >= 0 else {
            throw TAPDepthCaptureError.invalidTAPManifest("negative bounded read size")
        }
        var data = Data()
        data.reserveCapacity(byteCount)
        while data.count < byteCount {
            let remaining = byteCount - data.count
            guard let chunk = try handle.read(upToCount: remaining), !chunk.isEmpty else {
                throw TAPDepthCaptureError.invalidTAPManifest("unexpected end of BMFF file")
            }
            data.append(chunk)
        }
        return data
    }
}

private extension Data {
    nonisolated func tapUInt32BE(at offset: Int) -> UInt32 {
        (UInt32(self[offset]) << 24)
            | (UInt32(self[offset + 1]) << 16)
            | (UInt32(self[offset + 2]) << 8)
            | UInt32(self[offset + 3])
    }

    nonisolated func tapUInt64BE(at offset: Int) -> UInt64 {
        var value: UInt64 = 0
        for index in 0..<8 {
            value = (value << 8) | UInt64(self[offset + index])
        }
        return value
    }
}
