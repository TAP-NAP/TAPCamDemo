import Foundation
import Testing
@testable import CZstd

@Suite("CZstd bounded wrapper")
struct CZstdTests {
    @Test func pinnedGoldenVectorFitsRawFallbackBound() throws {
        let source = Data("TAP_DEPTH_VECTOR_V2:TAP_DEPTH_VECTOR_V2:".utf8)

        let destinationCapacity = try CZstd.compressBound(
            sourceByteCount: source.count,
            maximumInputByteCount: 1_024
        )
        let compressed = try CZstd.compress(
            source,
            maximumInputByteCount: 1_024,
            maximumOutputByteCount: destinationCapacity
        )

        #expect(compressed.count == 35)
        #expect(try CZstd.decompress(
            compressed,
            originalByteCount: source.count,
            maximumCompressedByteCount: 1_024,
            maximumOutputByteCount: 1_024
        ) == source)
    }

    @Test func levelOneRoundTripIsBitExact() throws {
        let source = Data(repeating: 0x5a, count: 32 * 1024)
        let compressed = try CZstd.compress(
            source,
            maximumInputByteCount: source.count,
            maximumOutputByteCount: source.count - 1
        )
        let decoded = try CZstd.decompress(
            compressed,
            originalByteCount: source.count,
            maximumCompressedByteCount: source.count,
            maximumOutputByteCount: source.count
        )

        #expect(compressed.count < source.count)
        #expect(decoded == source)
    }

    @Test func operationsRejectCountsOutsideCallerLimits() throws {
        let source = Data(repeating: 1, count: 32)

        #expect(throws: CZstdError.inputExceedsLimit(actual: 32, limit: 31)) {
            try CZstd.compress(
                source,
                maximumInputByteCount: 31,
                maximumOutputByteCount: 31
            )
        }
        #expect(throws: CZstdError.outputExceedsLimit(actual: 32, limit: 31)) {
            try CZstd.decompress(
                Data(),
                originalByteCount: 32,
                maximumCompressedByteCount: 32,
                maximumOutputByteCount: 31
            )
        }
    }
}
