//
//  TAPDepthCodecBenchmark.swift
//  TAPCamDemo
//

#if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
import Compression
import Foundation

nonisolated enum TAPDepthCodecBenchmarkCandidate: String, Codable, CaseIterable, Sendable {
    case zstd1
    case lzfse
    case lz4
    case raw
}

nonisolated enum TAPDepthCodecProductionSelection: String, Codable, Sendable {
    case zstd1
    case lzfse
    case raw
}

nonisolated struct TAPVideoDropCounters: Codable, Equatable, Sendable {
    let rgb: Int
    let audio: Int
    let depth: Int

    static let zero = TAPVideoDropCounters(rgb: 0, audio: 0, depth: 0)

    func hasNoIncrease(comparedWith baseline: Self) -> Bool {
        rgb <= baseline.rgb && audio <= baseline.audio && depth <= baseline.depth
    }
}

nonisolated struct TAPDepthCodecBenchmarkResult: Codable, Equatable, Sendable {
    let candidate: TAPDepthCodecBenchmarkCandidate
    let frameCount: Int
    let originalByteCount: Int
    let encodedByteCount: Int
    let encodeP50Milliseconds: Double
    let encodeP95Milliseconds: Double
    let decodeP95Milliseconds: Double
    let bitExactRoundTrip: Bool
    let meetsEncodeBudget: Bool

    var compressionRatio: Double {
        guard originalByteCount > 0 else { return 1 }
        return Double(encodedByteCount) / Double(originalByteCount)
    }
}

nonisolated struct TAPDepthCodecBenchmarkReport: Codable, Equatable, Sendable {
    let nominalDepthIntervalSeconds: Double
    let dropCountersBefore: TAPVideoDropCounters
    let dropCountersAfter: TAPVideoDropCounters
    let results: [TAPDepthCodecBenchmarkResult]
    let productionSelection: TAPDepthCodecProductionSelection

    var hasNoCompressionInducedDrops: Bool {
        dropCountersAfter.hasNoIncrease(comparedWith: dropCountersBefore)
    }
}

/// Runs the same bounded, per-frame codec policy used by TAP Video against a
/// caller-supplied depth corpus. The app does not ship a synthetic result as a
/// substitute for paired-device evidence: real Float16/Float32 packed frames
/// and before/after writer drop counters must be supplied by the fixture or
/// device harness.
nonisolated enum TAPDepthCodecBenchmark {
    static func run(
        frames: [Data],
        nominalDepthIntervalSeconds: Double,
        dropCountersBefore: TAPVideoDropCounters = .zero,
        dropCountersAfter: TAPVideoDropCounters = .zero
    ) throws -> TAPDepthCodecBenchmarkReport {
        guard !frames.isEmpty,
              nominalDepthIntervalSeconds.isFinite,
              nominalDepthIntervalSeconds > 0,
              frames.allSatisfy({ $0.count <= TAPDepthFrameCodec.maximumFrameByteCount }) else {
            throw TAPDepthCaptureError.invalidTAPManifest("invalid depth codec benchmark corpus")
        }

        let encodeBudgetSeconds = nominalDepthIntervalSeconds * 0.25
        let results = try TAPDepthCodecBenchmarkCandidate.allCases.map { candidate in
            try measure(
                candidate,
                frames: frames,
                encodeBudgetSeconds: encodeBudgetSeconds
            )
        }
        let resultByCandidate = Dictionary(uniqueKeysWithValues: results.map { ($0.candidate, $0) })
        let noAddedDrops = dropCountersAfter.hasNoIncrease(comparedWith: dropCountersBefore)

        let selection: TAPDepthCodecProductionSelection
        if noAddedDrops,
           resultByCandidate[.zstd1]?.bitExactRoundTrip == true,
           resultByCandidate[.zstd1]?.meetsEncodeBudget == true {
            selection = .zstd1
        } else if noAddedDrops,
                  resultByCandidate[.lzfse]?.bitExactRoundTrip == true,
                  resultByCandidate[.lzfse]?.meetsEncodeBudget == true {
            selection = .lzfse
        } else {
            selection = .raw
        }

        return TAPDepthCodecBenchmarkReport(
            nominalDepthIntervalSeconds: nominalDepthIntervalSeconds,
            dropCountersBefore: dropCountersBefore,
            dropCountersAfter: dropCountersAfter,
            results: results,
            productionSelection: selection
        )
    }

    private static func measure(
        _ candidate: TAPDepthCodecBenchmarkCandidate,
        frames: [Data],
        encodeBudgetSeconds: Double
    ) throws -> TAPDepthCodecBenchmarkResult {
        var encodeDurations: [Double] = []
        var decodeDurations: [Double] = []
        var encodedByteCount = 0
        var originalByteCount = 0
        var isBitExact = true
        encodeDurations.reserveCapacity(frames.count)
        decodeDurations.reserveCapacity(frames.count)

        for frame in frames {
            try Task.checkCancellation()
            let encodeStart = DispatchTime.now().uptimeNanoseconds
            let encoded = try encode(frame, candidate: candidate)
            let encodeEnd = DispatchTime.now().uptimeNanoseconds
            let decoded = try decode(encoded, candidate: candidate, originalByteCount: frame.count)
            let decodeEnd = DispatchTime.now().uptimeNanoseconds

            encodeDurations.append(seconds(from: encodeStart, to: encodeEnd))
            decodeDurations.append(seconds(from: encodeEnd, to: decodeEnd))
            encodedByteCount += encoded.count
            originalByteCount += frame.count
            isBitExact = isBitExact && decoded == frame
        }

        let encodeP50 = percentile(encodeDurations, percentile: 0.50)
        let encodeP95 = percentile(encodeDurations, percentile: 0.95)
        return TAPDepthCodecBenchmarkResult(
            candidate: candidate,
            frameCount: frames.count,
            originalByteCount: originalByteCount,
            encodedByteCount: encodedByteCount,
            encodeP50Milliseconds: encodeP50 * 1_000,
            encodeP95Milliseconds: encodeP95 * 1_000,
            decodeP95Milliseconds: percentile(decodeDurations, percentile: 0.95) * 1_000,
            bitExactRoundTrip: isBitExact,
            meetsEncodeBudget: encodeP95 <= encodeBudgetSeconds
        )
    }

    private static func encode(
        _ data: Data,
        candidate: TAPDepthCodecBenchmarkCandidate
    ) throws -> Data {
        switch candidate {
        case .zstd1:
            return try TAPDepthFrameCodec.encode(data, preferredCodec: .zstd1).payload
        case .lzfse:
            return try TAPDepthFrameCodec.encode(data, preferredCodec: .lzfse).payload
        case .lz4:
            return compressionEncode(data, algorithm: COMPRESSION_LZ4) ?? data
        case .raw:
            return data
        }
    }

    private static func decode(
        _ data: Data,
        candidate: TAPDepthCodecBenchmarkCandidate,
        originalByteCount: Int
    ) throws -> Data {
        switch candidate {
        case .zstd1:
            // Production may choose raw for an incompressible frame.
            let codec: TAPDepthCompressionCodec = data.count < originalByteCount ? .zstd1 : .raw
            return try TAPDepthFrameCodec.decode(.init(
                codec: codec,
                uncompressedByteCount: originalByteCount,
                payload: data
            ))
        case .lzfse:
            let codec: TAPDepthCompressionCodec = data.count < originalByteCount ? .lzfse : .raw
            return try TAPDepthFrameCodec.decode(.init(
                codec: codec,
                uncompressedByteCount: originalByteCount,
                payload: data
            ))
        case .lz4:
            guard data.count < originalByteCount else { return data }
            guard let decoded = compressionDecode(
                data,
                originalByteCount: originalByteCount,
                algorithm: COMPRESSION_LZ4
            ) else {
                throw TAPDepthCaptureError.invalidTAPManifest("LZ4 benchmark round-trip failed")
            }
            return decoded
        case .raw:
            return data
        }
    }

    private static func compressionEncode(
        _ data: Data,
        algorithm: compression_algorithm
    ) -> Data? {
        guard !data.isEmpty else { return Data() }
        var destination = Data(count: data.count)
        let written = destination.withUnsafeMutableBytes { output in
            data.withUnsafeBytes { input in
                guard let outputBase = output.bindMemory(to: UInt8.self).baseAddress,
                      let inputBase = input.bindMemory(to: UInt8.self).baseAddress else {
                    return 0
                }
                return compression_encode_buffer(
                    outputBase,
                    output.count,
                    inputBase,
                    input.count,
                    nil,
                    algorithm
                )
            }
        }
        guard written > 0, written < data.count else { return nil }
        destination.removeSubrange(written..<destination.count)
        return destination
    }

    private static func compressionDecode(
        _ data: Data,
        originalByteCount: Int,
        algorithm: compression_algorithm
    ) -> Data? {
        var output = Data(count: originalByteCount)
        let written = output.withUnsafeMutableBytes { destination in
            data.withUnsafeBytes { source in
                guard let destinationBase = destination.bindMemory(to: UInt8.self).baseAddress,
                      let sourceBase = source.bindMemory(to: UInt8.self).baseAddress else {
                    return 0
                }
                return compression_decode_buffer(
                    destinationBase,
                    destination.count,
                    sourceBase,
                    source.count,
                    nil,
                    algorithm
                )
            }
        }
        return written == originalByteCount ? output : nil
    }

    private static func seconds(from start: UInt64, to end: UInt64) -> Double {
        Double(end &- start) / 1_000_000_000
    }

    private static func percentile(_ values: [Double], percentile: Double) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let index = max(0, min(sorted.count - 1, Int(ceil(percentile * Double(sorted.count))) - 1))
        return sorted[index]
    }
}
#endif
