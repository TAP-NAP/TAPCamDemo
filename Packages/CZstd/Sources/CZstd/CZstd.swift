import Foundation
import CZstdC

/// Narrow, allocation-bounded access to the pinned Zstandard dependency.
///
/// TAP Video intentionally does not expose arbitrary compression levels or raw
/// C entry points. Callers must provide explicit input and output limits for
/// every operation.
public enum CZstd {
    public static let sourceVersion = "1.5.7"
    public static let expectedRuntimeVersionNumber: UInt32 = 10_507
    public static let compressionLevel: Int32 = 1
    private static let runtimeVersionNumber = ZSTD_versionNumber()

    public static func compressBound(
        sourceByteCount: Int,
        maximumInputByteCount: Int
    ) throws -> Int {
        try validateRuntimeVersion()
        try validateCount(
            sourceByteCount,
            maximum: maximumInputByteCount,
            kind: .input
        )
        let bound = ZSTD_compressBound(sourceByteCount)
        guard bound >= 0 else {
            throw CZstdError.sizeOverflow
        }
        return bound
    }

    public static func compress(
        _ source: Data,
        maximumInputByteCount: Int,
        maximumOutputByteCount: Int
    ) throws -> Data {
        try validateRuntimeVersion()
        try validateCount(
            source.count,
            maximum: maximumInputByteCount,
            kind: .input
        )
        try validateLimit(maximumOutputByteCount)

        var output = Data(count: maximumOutputByteCount)
        let written = output.withUnsafeMutableBytes { destination in
            source.withUnsafeBytes { input in
                ZSTD_compress(
                    destination.baseAddress,
                    destination.count,
                    input.baseAddress,
                    input.count,
                    compressionLevel
                )
            }
        }
        try validateZstdResult(written)
        guard written <= maximumOutputByteCount else {
            throw CZstdError.outputExceedsLimit(
                actual: written,
                limit: maximumOutputByteCount
            )
        }
        output.removeSubrange(written..<output.count)
        return output
    }

    public static func decompress(
        _ source: Data,
        originalByteCount: Int,
        maximumCompressedByteCount: Int,
        maximumOutputByteCount: Int
    ) throws -> Data {
        try validateRuntimeVersion()
        try validateCount(
            source.count,
            maximum: maximumCompressedByteCount,
            kind: .input
        )
        try validateCount(
            originalByteCount,
            maximum: maximumOutputByteCount,
            kind: .output
        )

        var output = Data(count: originalByteCount)
        let written = output.withUnsafeMutableBytes { destination in
            source.withUnsafeBytes { input in
                ZSTD_decompress(
                    destination.baseAddress,
                    destination.count,
                    input.baseAddress,
                    input.count
                )
            }
        }
        try validateZstdResult(written)
        guard written == originalByteCount else {
            throw CZstdError.decodedByteCountMismatch(
                expected: originalByteCount,
                actual: written
            )
        }
        return output
    }

    private enum CountKind {
        case input
        case output
    }

    private static func validateCount(
        _ count: Int,
        maximum: Int,
        kind: CountKind
    ) throws {
        try validateLimit(maximum)
        guard count >= 0 else {
            throw CZstdError.negativeByteCount
        }
        guard count <= maximum else {
            switch kind {
            case .input:
                throw CZstdError.inputExceedsLimit(actual: count, limit: maximum)
            case .output:
                throw CZstdError.outputExceedsLimit(actual: count, limit: maximum)
            }
        }
    }

    private static func validateLimit(_ limit: Int) throws {
        guard limit >= 0 else {
            throw CZstdError.negativeByteCount
        }
    }

    private static func validateRuntimeVersion() throws {
        guard runtimeVersionNumber == expectedRuntimeVersionNumber else {
            throw CZstdError.runtimeVersionMismatch(
                expected: expectedRuntimeVersionNumber,
                actual: runtimeVersionNumber
            )
        }
    }

    private static func validateZstdResult(_ result: Int) throws {
        guard ZSTD_isError(result) == 0 else {
            throw CZstdError.codecFailure(code: result)
        }
    }
}

public enum CZstdError: Error, Equatable, Sendable {
    case negativeByteCount
    case sizeOverflow
    case runtimeVersionMismatch(expected: UInt32, actual: UInt32)
    case inputExceedsLimit(actual: Int, limit: Int)
    case outputExceedsLimit(actual: Int, limit: Int)
    case decodedByteCountMismatch(expected: Int, actual: Int)
    case codecFailure(code: Int)
}
