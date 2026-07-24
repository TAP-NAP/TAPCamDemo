//
//  TAPVideoStreamingTests.swift
//  TAPCamDemoTests
//

import AppAttestKit
import CoreMedia
import CoreVideo
import CryptoKit
import Foundation
import Testing
@testable import TAPCamDemo

struct TAPVideoStreamingTests {
    @Test func bmffParserHandles32And64BitBoxes() throws {
        let fileURL = try Self.makeTemporaryFile(data:
            Self.box32(type: "ftyp", payload: Data("mp42".utf8))
                + Self.box64(type: "mdat", payload: Data(repeating: 0x5a, count: 37))
        )

        let boxes = try TAPBMFFStreamingFile.topLevelBoxes(at: fileURL)

        #expect(boxes.map(\.type) == ["ftyp", "mdat"])
        #expect(boxes[0].headerByteCount == 8)
        #expect(boxes[1].headerByteCount == 16)
        #expect(boxes[1].payloadRange.length == 37)
    }

    @Test func bmffParserRejectsTruncationAndDuplicateProofSlots() throws {
        var truncated = Data()
        truncated.appendUInt32BE(100)
        truncated.append(Data("mdat".utf8))
        truncated.append(Data([1, 2, 3]))
        let truncatedURL = try Self.makeTemporaryFile(data: truncated)
        #expect(throws: TAPDepthCaptureError.self) {
            try TAPBMFFStreamingFile.topLevelBoxes(at: truncatedURL)
        }

        let proofURL = try Self.makeTemporaryFile(data: Self.syntheticMP4Data())
        let firstSlot = try TAPProofSlot.ensureEmptyBMFFSlot(inFileAt: proofURL)
        let slotBox = try TAPBMFFStreamingFile.read(
            firstSlot.containerRange,
            from: proofURL,
            maximumByteCount: TAPProofSlot.payloadByteCount + 32
        )
        try TAPBMFFStreamingFile.append(slotBox, to: proofURL)
        #expect(throws: TAPDepthCaptureError.self) {
            try TAPProofSlot.locateBMFF(inFileAt: proofURL)
        }
    }

    @Test func streamingHashIsStableAcrossChunkBoundariesAndProofRewrites() throws {
        let fileURL = try Self.makeTemporaryFile(data:
            Self.syntheticMP4Data()
                + Self.box32(type: "free", payload: Data(repeating: 0x7b, count: 8_193))
        )
        let slot = try TAPProofSlot.ensureEmptyBMFFSlot(inFileAt: fileURL)
        let hashWithTinyChunks = try TAPBMFFStreamingFile.sha256Base64URL(
            of: fileURL,
            excluding: slot.containerRange,
            chunkByteCount: 7
        )
        let hashWithLargeChunks = try TAPBMFFStreamingFile.sha256Base64URL(
            of: fileURL,
            excluding: slot.containerRange,
            chunkByteCount: 4_096
        )
        let originalByteCount = try TAPBMFFStreamingFile.byteCount(of: fileURL)

        try TAPProofSlot.writeProofEnvelope(Data("first-proof".utf8), intoBMFFFileAt: fileURL)
        #expect(try TAPProofSlot.proofEnvelopeData(fromBMFFFileAt: fileURL) == Data("first-proof".utf8))
        #expect(try TAPBMFFStreamingFile.byteCount(of: fileURL) == originalByteCount)
        #expect(try TAPBMFFStreamingFile.sha256Base64URL(of: fileURL, excluding: slot.containerRange) == hashWithTinyChunks)

        try TAPProofSlot.writeProofEnvelope(Data("replacement-proof".utf8), intoBMFFFileAt: fileURL)
        #expect(try TAPProofSlot.proofEnvelopeData(fromBMFFFileAt: fileURL) == Data("replacement-proof".utf8))
        #expect(try TAPBMFFStreamingFile.byteCount(of: fileURL) == originalByteCount)
        #expect(hashWithTinyChunks == hashWithLargeChunks)
        #expect(try TAPBMFFStreamingFile.sha256Base64URL(of: fileURL, excluding: slot.containerRange) == hashWithTinyChunks)
    }

    @Test func streamingHashDefaultUsesTheOneMiBReleaseChunk() throws {
        #expect(TAPBMFFStreamingFile.defaultChunkByteCount == 1 * 1024 * 1024)
        let fileURL = try Self.makeTemporaryFile(
            data: Self.syntheticMP4Data()
                + Self.box32(
                    type: "free",
                    payload: Data(
                        repeating: 0x7b,
                        count: TAPBMFFStreamingFile.defaultChunkByteCount + 257
                    )
                )
        )
        let slot = try TAPProofSlot.ensureEmptyBMFFSlot(inFileAt: fileURL)

        let defaultHash = try TAPBMFFStreamingFile.sha256Base64URL(
            of: fileURL,
            excluding: slot.containerRange
        )
        let explicitOneMiBHash = try TAPBMFFStreamingFile.sha256Base64URL(
            of: fileURL,
            excluding: slot.containerRange,
            chunkByteCount: 1 * 1024 * 1024
        )

        #expect(defaultHash == explicitOneMiBHash)
    }

    @Test func depthTrackValidatorFailsClosedAboveItsCombined32MiBBudget() throws {
        #expect(
            TAPVideoDepthTrackValidator.maximumCombinedFrameBufferBytes
                == 32 * 1024 * 1024
        )
        let withinBudget = TAPVideoManifest.DepthFormat(
            kind: "depth",
            pixelFormat: "fdep",
            width: 8_192,
            height: 1_024,
            packedRowStride: 8_192 * 4,
            bytesPerSample: 4,
            uncompressedFrameByteCount: 32 * 1024 * 1024
        )
        try TAPVideoDepthTrackValidator.validateDepthFormat(withinBudget)

        let overBudget = TAPVideoManifest.DepthFormat(
            kind: "depth",
            pixelFormat: "fdep",
            width: 8_193,
            height: 1_024,
            packedRowStride: 8_193 * 4,
            bytesPerSample: 4,
            uncompressedFrameByteCount: (32 * 1024 * 1024) + 4_096
        )
        #expect(throws: TAPDepthCaptureError.self) {
            try TAPVideoDepthTrackValidator.validateDepthFormat(overBudget)
        }
    }

    @Test func zstdLevelOneRoundTripsDeterministicallyAndRawFallbackIsExact() throws {
        let packed = Data(repeating: Data("depth-row-depth-row".utf8), count: 2_048)
        let first = try TAPDepthFrameCodec.encode(packed, preferredCodec: .zstd1)
        let second = try TAPDepthFrameCodec.encode(packed, preferredCodec: .zstd1)

        #expect(first.codec == .zstd1)
        #expect(first == second)
        #expect(first.payload.count < packed.count)
        #expect(try TAPDepthFrameCodec.decode(first) == packed)

        let incompressibleTinyFrame = Data([0x00, 0x7f, 0xff])
        let fallback = try TAPDepthFrameCodec.encode(incompressibleTinyFrame, preferredCodec: .zstd1)
        #expect(fallback.codec == .raw)
        #expect(fallback.payload == incompressibleTinyFrame)
        #expect(try TAPDepthFrameCodec.decode(fallback) == incompressibleTinyFrame)
    }

    @Test func depthPackingExcludesSourceRowPadding() throws {
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            3,
            2,
            kCVPixelFormatType_DepthFloat32,
            [kCVPixelBufferBytesPerRowAlignmentKey as String: 64] as CFDictionary,
            &pixelBuffer
        )
        let buffer = try #require(pixelBuffer)
        #expect(status == kCVReturnSuccess)

        CVPixelBufferLockBaseAddress(buffer, [])
        let baseAddress = try #require(CVPixelBufferGetBaseAddress(buffer))
        let sourceRowStride = CVPixelBufferGetBytesPerRow(buffer)
        memset(baseAddress, 0xee, sourceRowStride * 2)
        let expected = Data((0..<24).map(UInt8.init))
        expected.withUnsafeBytes { bytes in
            guard let source = bytes.baseAddress else { return }
            memcpy(baseAddress, source, 12)
            memcpy(baseAddress.advanced(by: sourceRowStride), source.advanced(by: 12), 12)
        }
        CVPixelBufferUnlockBaseAddress(buffer, [])

        let packed = try TAPDepthFrameCodec.pack(buffer)

        #expect(packed.sourceRowStride == sourceRowStride)
        #expect(packed.packedRowStride == 12)
        #expect(packed.bytes.count == 24)
        #expect(packed.bytes == expected)
        #expect(!packed.bytes.contains(0xee))
    }

    @Test func depthStoredLayoutIgnoresOnlyCaptureSourcePadding() {
        let first = TAPVideoManifest.DepthFormat(
            kind: "depth",
            pixelFormat: "fdep",
            width: 128,
            height: 96,
            packedRowStride: 512,
            sourceRowStride: 512,
            bytesPerSample: 4,
            uncompressedFrameByteCount: 49_152
        )
        let differentSourcePadding = TAPVideoManifest.DepthFormat(
            kind: "depth",
            pixelFormat: "fdep",
            width: 128,
            height: 96,
            packedRowStride: 512,
            sourceRowStride: 576,
            bytesPerSample: 4,
            uncompressedFrameByteCount: 49_152
        )
        let differentStoredStride = TAPVideoManifest.DepthFormat(
            kind: "depth",
            pixelFormat: "fdep",
            width: 128,
            height: 96,
            packedRowStride: 516,
            sourceRowStride: 576,
            bytesPerSample: 4,
            uncompressedFrameByteCount: 49_536
        )

        #expect(first != differentSourcePadding)
        #expect(first.hasSameStoredFrameLayout(as: differentSourcePadding))
        #expect(!first.hasSameStoredFrameLayout(as: differentStoredStride))
    }

    @Test func depthKLVFrameCarriesCodecLengthTimestampAndCalibrationIndex() throws {
        let packed = Data(repeating: 0x42, count: 2_048)
        let compressed = try TAPDepthFrameCodec.encode(packed, preferredCodec: .zstd1)
        let frame = TAPDepthKLVFrame(
            frameIndex: 17,
            timestampValue: 12_345,
            timestampTimescale: 600,
            compressionCodec: compressed.codec,
            uncompressedByteCount: compressed.uncompressedByteCount,
            calibrationIndex: 0,
            payload: compressed.payload
        )

        let decoded = try TAPDepthKLVFrame.decode(frame.encodedData())

        #expect(decoded == frame)
        #expect(decoded.calibrationIndex == 0)
        #expect(try decoded.decodedPackedBytes() == packed)
    }

    @Test func depthTimelineRejectsNegativeDuplicateAndOutOfRangePTS() throws {
        let common = (
            trackStartSeconds: 0.0,
            trackDurationSeconds: 6.0,
            presentationDurationSeconds: 6.0,
            nominalDepthIntervalSeconds: Optional(1.0),
            gaps: [TAPVideoManifest.DepthGap](),
            timestampToleranceSeconds: 1.0 / 600.0
        )

        #expect(throws: TAPDepthCaptureError.self) {
            try TAPVideoDepthTimelineValidationPolicy.validate(
                sampleTimesSeconds: [-0.01],
                trackStartSeconds: common.trackStartSeconds,
                trackDurationSeconds: common.trackDurationSeconds,
                presentationDurationSeconds: common.presentationDurationSeconds,
                nominalDepthIntervalSeconds: common.nominalDepthIntervalSeconds,
                reportedMaxObservedDepthIntervalSeconds: nil,
                gaps: common.gaps,
                timestampToleranceSeconds: common.timestampToleranceSeconds
            )
        }
        #expect(throws: TAPDepthCaptureError.self) {
            try TAPVideoDepthTimelineValidationPolicy.validate(
                sampleTimesSeconds: [0, 0],
                trackStartSeconds: common.trackStartSeconds,
                trackDurationSeconds: common.trackDurationSeconds,
                presentationDurationSeconds: common.presentationDurationSeconds,
                nominalDepthIntervalSeconds: common.nominalDepthIntervalSeconds,
                reportedMaxObservedDepthIntervalSeconds: 1,
                gaps: common.gaps,
                timestampToleranceSeconds: common.timestampToleranceSeconds
            )
        }
        #expect(throws: TAPDepthCaptureError.self) {
            try TAPVideoDepthTimelineValidationPolicy.validate(
                sampleTimesSeconds: [0, 7],
                trackStartSeconds: common.trackStartSeconds,
                trackDurationSeconds: common.trackDurationSeconds,
                presentationDurationSeconds: common.presentationDurationSeconds,
                nominalDepthIntervalSeconds: common.nominalDepthIntervalSeconds,
                reportedMaxObservedDepthIntervalSeconds: 7,
                gaps: common.gaps,
                timestampToleranceSeconds: common.timestampToleranceSeconds
            )
        }
    }

    @Test func depthTimelineRequiresDeclaredCoverageForActualFiveSecondGap() throws {
        #expect(throws: TAPDepthCaptureError.self) {
            try TAPVideoDepthTimelineValidationPolicy.validate(
                sampleTimesSeconds: [0, 5],
                trackStartSeconds: 0,
                trackDurationSeconds: 6,
                presentationDurationSeconds: 6,
                nominalDepthIntervalSeconds: 1,
                reportedMaxObservedDepthIntervalSeconds: 5,
                gaps: [],
                timestampToleranceSeconds: 1.0 / 600.0
            )
        }

        try TAPVideoDepthTimelineValidationPolicy.validate(
            sampleTimesSeconds: [0, 5],
            trackStartSeconds: 0,
            trackDurationSeconds: 6,
            presentationDurationSeconds: 6,
            nominalDepthIntervalSeconds: 1,
            reportedMaxObservedDepthIntervalSeconds: 5,
            gaps: [Self.gap(
                reason: .silentCadence,
                startValue: 600,
                endValue: 3_000
            )],
            timestampToleranceSeconds: 1.0 / 600.0
        )
    }

    @Test func depthTimelineAcceptsCoveredLeadingInterFrameAndTrailingMissingCores() throws {
        try TAPVideoDepthTimelineValidationPolicy.validate(
            sampleTimesSeconds: [3, 7],
            trackStartSeconds: 0,
            trackDurationSeconds: 10,
            presentationDurationSeconds: 10,
            nominalDepthIntervalSeconds: 1,
            reportedMaxObservedDepthIntervalSeconds: 4,
            gaps: [
                Self.gap(reason: .silentCadence, startValue: 0, endValue: 1_800),
                Self.gap(reason: .boundedAggregation, startValue: 2_400, endValue: 4_200),
                Self.gap(reason: .metadataBackpressure, startValue: 4_800, endValue: 6_000)
            ],
            timestampToleranceSeconds: 1.0 / 600.0
        )
    }

    @Test func signedFileValidationAuthenticatesBeforeActualTrackScan() async throws {
        var phases: [TAPVideoSignedFileValidationOrder.Phase] = []
        try await TAPVideoSignedFileValidationOrder.run(
            validatesDepthTrack: true,
            authenticate: {
                phases.append(.authenticateProofAndContentBinding)
            },
            validateActualTracks: {
                phases.append(.validateActualTracks)
            }
        )
        #expect(phases == [
            .authenticateProofAndContentBinding,
            .validateActualTracks
        ])

        phases.removeAll()
        try await TAPVideoSignedFileValidationOrder.run(
            validatesDepthTrack: false,
            authenticate: {
                phases.append(.authenticateProofAndContentBinding)
            },
            validateActualTracks: {
                phases.append(.validateActualTracks)
            }
        )
        #expect(phases == [.authenticateProofAndContentBinding])

        phases.removeAll()
        await #expect(throws: ExpectedSignedValidationFailure.self) {
            try await TAPVideoSignedFileValidationOrder.run(
                validatesDepthTrack: true,
                authenticate: {
                    phases.append(.authenticateProofAndContentBinding)
                    throw ExpectedSignedValidationFailure.rejected
                },
                validateActualTracks: {
                    phases.append(.validateActualTracks)
                }
            )
        }
        #expect(phases == [.authenticateProofAndContentBinding])
    }

    @Test func videoSigningBindsExactBytesWithoutRequiringSemanticTrackScan() async throws {
        let rootURL = try TAPCamDemoTestFixtures.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let store = TAPPendingCaptureStore(rootURL: rootURL)
        let record = try await TAPCamDemoTestFixtures.ingestPendingTAPVideo(
            store: store,
            captureID: "byte-binding-only-video"
        )
        let videoURL = try await store.videoArtifactURL(captureID: record.captureID)
        let signer = SuccessfulVideoCaptureAssertionSigner()
        let writer = TAPCaptureProvenanceWriter()

        let signed = try await writer.signedVideoFile(
            at: videoURL,
            expectedCaptureID: record.captureID,
            expectedPackageID: record.packageID,
            assertionSigner: signer
        )
        let validated = try await writer.validateSignedExportVideoFile(
            at: videoURL,
            expectedCaptureID: record.captureID,
            expectedPackageID: record.packageID
        )

        #expect(signed.fileURL == videoURL)
        #expect(validated.manifest.payload.id == record.captureID)
        #expect(await signer.lastDigest()?.assetHash.fileContainer == "mp4")

        await #expect(throws: Error.self) {
            _ = try await writer.validateSignedExportVideoFile(
                at: videoURL,
                expectedCaptureID: record.captureID,
                expectedPackageID: record.packageID,
                validatesDepthTrack: true
            )
        }
    }

    @Test func signedVideoValidationRejectsAnyMutationOutsideProofSlot() async throws {
        let rootURL = try TAPCamDemoTestFixtures.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let store = TAPPendingCaptureStore(rootURL: rootURL)
        let record = try await TAPCamDemoTestFixtures.ingestPendingTAPVideo(
            store: store,
            captureID: "mutated-signed-video"
        )
        let videoURL = try await store.videoArtifactURL(captureID: record.captureID)
        let writer = TAPCaptureProvenanceWriter()

        _ = try await writer.signedVideoFile(
            at: videoURL,
            expectedCaptureID: record.captureID,
            expectedPackageID: record.packageID,
            assertionSigner: SuccessfulVideoCaptureAssertionSigner()
        )

        let fileHandle = try FileHandle(forUpdating: videoURL)
        try fileHandle.seek(toOffset: 11)
        try fileHandle.write(contentsOf: Data([0x33]))
        try fileHandle.close()

        await #expect(throws: TAPDepthCaptureError.self) {
            _ = try await writer.validateSignedExportVideoFile(
                at: videoURL,
                expectedCaptureID: record.captureID,
                expectedPackageID: record.packageID
            )
        }
    }

    @Test func depthGapAccumulatorMergesAdjacentEventsAndStaysBounded() throws {
        var adjacent = TAPDepthGapAccumulator()
        adjacent.record(
            Self.gap(reason: .outputDrop, startValue: 0, endValue: 0),
            mergeToleranceSeconds: 0.1
        )
        adjacent.record(
            Self.gap(reason: .outputDrop, startValue: 30, endValue: 30),
            mergeToleranceSeconds: 0.1
        )
        #expect(adjacent.gaps.count == 1)
        #expect(adjacent.gaps.first?.startPTS.value == 0)
        #expect(adjacent.gaps.first?.endPTS.value == 30)

        var bounded = TAPDepthGapAccumulator()
        for index in 0..<(TAPDepthGapAccumulator.maximumGapCount + 8) {
            let reason: TAPVideoManifest.DepthGapReason = index.isMultiple(of: 2)
                ? .outputDrop
                : .encodingFailure
            bounded.record(
                Self.gap(
                    reason: reason,
                    startValue: Int64(index * 600),
                    endValue: Int64(index * 600 + 1)
                ),
                mergeToleranceSeconds: 0
            )
        }
        #expect(bounded.gaps.count == TAPDepthGapAccumulator.maximumGapCount)
        #expect(bounded.gaps.last?.reason == .boundedAggregation)
        #expect(
            bounded.gaps.last?.endPTS.value
                == Int64((TAPDepthGapAccumulator.maximumGapCount + 7) * 600 + 1)
        )
    }

    @Test func videoCaptureTimelineRebasesKLVAndGapPTSFromFirstRGBFrame() throws {
        let firstVideoTime = CMTime(value: 48_000, timescale: 600)
        let firstDepthTime = CMTime(value: 48_120, timescale: 600)
        let lastDepthTime = CMTime(value: 49_140, timescale: 600)
        let lastVideoTime = CMTime(value: 49_260, timescale: 600)

        let firstDepthPTS = try #require(
            TAPVideoCaptureTimeline.relativeMediaTime(
                firstDepthTime,
                from: firstVideoTime
            )
        )
        #expect(firstDepthPTS == .init(value: 120, timescale: 600))

        let leadingGap = try #require(TAPVideoCaptureTimeline.depthGap(
            reason: .silentCadence,
            start: firstVideoTime,
            end: firstDepthTime,
            relativeTo: firstVideoTime,
            nearestStartRGBFrame: 0,
            nearestEndRGBFrame: 6
        ))
        #expect(leadingGap.startPTS == .init(value: 0, timescale: 600))
        #expect(leadingGap.endPTS == .init(value: 120, timescale: 600))

        let trailingGap = try #require(TAPVideoCaptureTimeline.depthGap(
            reason: .silentCadence,
            start: lastDepthTime,
            end: lastVideoTime,
            relativeTo: firstVideoTime,
            nearestStartRGBFrame: 62,
            nearestEndRGBFrame: 69
        ))
        #expect(trailingGap.startPTS == .init(value: 1_140, timescale: 600))
        #expect(trailingGap.endPTS == .init(value: 1_260, timescale: 600))

        let fileEndTime = try #require(TAPVideoCaptureTimeline.absoluteMediaEndTime(
            origin: firstVideoTime,
            durationSeconds: 2.25,
            lastSampleTime: lastVideoTime
        ))
        #expect(fileEndTime == CMTime(value: 49_350, timescale: 600))
    }

    @Test func videoCaptureTimelineClampsPreRollPTSAndRejectsReversedGaps() throws {
        let firstVideoTime = CMTime(value: 6_000, timescale: 600)
        let preRollTime = CMTime(value: 5_940, timescale: 600)

        let relative = try #require(
            TAPVideoCaptureTimeline.relativeMediaTime(preRollTime, from: firstVideoTime)
        )
        #expect(relative == .init(value: 0, timescale: 600))
        #expect(TAPVideoCaptureTimeline.depthGap(
            reason: .silentCadence,
            start: firstVideoTime,
            end: preRollTime,
            relativeTo: firstVideoTime,
            nearestStartRGBFrame: 0,
            nearestEndRGBFrame: 0
        ) == nil)
    }

    @Test func videoCalibrationTableDeduplicatesAndRemainsBounded() throws {
        func calibration(_ index: Int) -> TAPVideoManifest.CameraCalibration {
            TAPVideoManifest.CameraCalibration(
                intrinsicMatrix: [1, 0, 0, 0, 1, 0, Float(index), 1, 1],
                intrinsicMatrixReferenceDimensions: .init(width: 256, height: 192),
                extrinsicMatrix: [1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0],
                pixelSizeMillimeters: 0.001,
                lensDistortionCenter: .init(x: Double(index), y: 96),
                lensDistortionLookupTable: nil,
                inverseLensDistortionLookupTable: nil
            )
        }

        var table = TAPVideoCalibrationTable()
        #expect(table.index(for: calibration(0)) == 0)
        #expect(table.index(for: calibration(0)) == 0)
        for index in 1..<TAPVideoCalibrationTable.maximumEntryCount {
            #expect(table.index(for: calibration(index)) == UInt32(index))
        }
        #expect(table.entries.count == TAPVideoCalibrationTable.maximumEntryCount)
        #expect(table.index(for: calibration(TAPVideoCalibrationTable.maximumEntryCount)) == nil)
        #expect(table.didOverflow)
        #expect(table.entries.count == TAPVideoCalibrationTable.maximumEntryCount)
        #expect(table.index(for: nil) == nil)
    }

    @Test func videoCalibrationReservationDoesNotMutateCommittedTable() throws {
        let calibration = TAPVideoManifest.CameraCalibration(
            intrinsicMatrix: [1, 0, 0, 0, 1, 0, 0, 0, 1],
            intrinsicMatrixReferenceDimensions: .init(width: 256, height: 192),
            extrinsicMatrix: [1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0],
            pixelSizeMillimeters: 0.001,
            lensDistortionCenter: .init(x: 128, y: 96),
            lensDistortionLookupTable: nil,
            inverseLensDistortionLookupTable: nil
        )
        let committedTable = TAPVideoCalibrationTable()
        var reservation = committedTable

        #expect(reservation.index(for: calibration) == 0)
        #expect(committedTable.entries.isEmpty)
        #expect(!committedTable.didOverflow)
        #expect(reservation.entries == [calibration])
    }

    @Test func verifierGoldenVectorMatchesPinnedZstdAndKLVBytes() throws {
        let raw = try #require(Data(
            base64Encoded: "VEFQX0RFUFRIX1ZFQ1RPUl9WMjpUQVBfREVQVEhfVkVDVE9SX1YyOg=="
        ))
        let encoded = try TAPDepthFrameCodec.encode(raw, preferredCodec: .zstd1)
        #expect(encoded.codec == .zstd1)
        #expect(encoded.payload.base64EncodedString() == "KLUv/SAo1QAAoFRBUF9ERVBUSF9WRUNUT1JfVjI6AQCOnkw=")

        let frame = TAPDepthKLVFrame(
            frameIndex: 17,
            timestampValue: 12_345,
            timestampTimescale: 600,
            compressionCodec: encoded.codec,
            uncompressedByteCount: encoded.uncompressedByteCount,
            calibrationIndex: 0,
            payload: encoded.payload
        )
        #expect(
            try frame.encodedData().base64EncodedString()
                == "VFZFUgAAAAQAAAACRlJBTQAAAAQAAAARUFRTIAAAAAwAAAAAAAAwOQAAAlhDT01QAAAABXpzdGQxAAAAVUxFTgAAAAQAAAAoQ0FMSQAAAAQAAAAARFBUSAAAACMotS/9ICjVAACgVEFQX0RFUFRIX1ZFQ1RPUl9WMjoBAI6eTAA="
        )
        #expect(try frame.decodedPackedBytes() == raw)
    }

    #if DEBUG || TAP_ENABLE_RELEASE_DIAGNOSTICS
    @Test func codecBenchmarkComparesAllCandidatesAndAppliesLockedFallbackOrder() throws {
        let frames = (0..<8).map { frameIndex in
            Data(repeating: UInt8(frameIndex), count: 32 * 1024)
        }
        let report = try TAPDepthCodecBenchmark.run(
            frames: frames,
            nominalDepthIntervalSeconds: 10,
            dropCountersBefore: .zero,
            dropCountersAfter: .zero
        )

        #expect(report.results.map(\.candidate) == TAPDepthCodecBenchmarkCandidate.allCases)
        let allBitExact = report.results.allSatisfy { $0.bitExactRoundTrip }
        #expect(allBitExact)
        #expect(report.recommendedSelection == .zstd1)

        let reportWithAddedDrop = try TAPDepthCodecBenchmark.run(
            frames: frames,
            nominalDepthIntervalSeconds: 10,
            dropCountersBefore: .zero,
            dropCountersAfter: .init(rgb: 0, audio: 0, depth: 1)
        )
        #expect(reportWithAddedDrop.recommendedSelection == .raw)
    }
    #endif

    private static func syntheticMP4Data() -> Data {
        box32(type: "ftyp", payload: Data("mp42".utf8))
            + box32(type: "moov", payload: Data(repeating: 0x4d, count: 127))
            + box32(type: "mdat", payload: Data(repeating: 0xa5, count: 1_031))
    }

    private actor SuccessfulVideoCaptureAssertionSigner: CaptureAssertionSigning {
        private var recordedDigest: CaptureContentDigest?

        func lastDigest() -> CaptureContentDigest? {
            recordedDigest
        }

        func sign(contentDigest: CaptureContentDigest) async throws -> CaptureAssertionProof {
            recordedDigest = contentDigest
            let proofValue = CaptureAssertionProofValue(
                contentDigest: contentDigest,
                keyId: "video-test-key-id",
                assertionObject: Data([0xA1, 0x01]).appAttestBase64URL,
                signingBinding: try CaptureSigningBinding(contentDigest: contentDigest)
            )
            let proof = TAPDepthManifest.Proof(
                type: "appAttestAssertion",
                algorithm: "TAPCam.AppAttestCaptureSignature.v1",
                keyID: "video-test-key-id",
                createdAt: contentDigest.capturedAt,
                value: try proofValue.canonicalJSONData().appAttestBase64URL
            )
            return CaptureAssertionProof(proof: proof, keyID: "video-test-key-id")
        }
    }

    private enum ExpectedSignedValidationFailure: Error {
        case rejected
    }

    private static func gap(
        reason: TAPVideoManifest.DepthGapReason,
        startValue: Int64,
        endValue: Int64
    ) -> TAPVideoManifest.DepthGap {
        TAPVideoManifest.DepthGap(
            reason: reason,
            startPTS: .init(value: startValue, timescale: 600),
            endPTS: .init(value: endValue, timescale: 600),
            nearestStartRGBFrame: nil,
            nearestEndRGBFrame: nil
        )
    }

    private static func box32(type: String, payload: Data) -> Data {
        var data = Data()
        data.appendUInt32BE(UInt32(8 + payload.count))
        data.append(Data(type.utf8))
        data.append(payload)
        return data
    }

    private static func box64(type: String, payload: Data) -> Data {
        var data = Data()
        data.appendUInt32BE(1)
        data.append(Data(type.utf8))
        data.appendUInt64BE(UInt64(16 + payload.count))
        data.append(payload)
        return data
    }

    private static func makeTemporaryFile(data: Data) throws -> URL {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("TAPVideoStreamingTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let fileURL = directoryURL.appendingPathComponent("artifact.mp4")
        try data.write(to: fileURL)
        return fileURL
    }
}

private extension Data {
    init(repeating pattern: Data, count: Int) {
        self.init()
        reserveCapacity(pattern.count * count)
        for _ in 0..<count {
            append(pattern)
        }
    }

    mutating func appendUInt32BE(_ value: UInt32) {
        append(contentsOf: [
            UInt8((value >> 24) & 0xff),
            UInt8((value >> 16) & 0xff),
            UInt8((value >> 8) & 0xff),
            UInt8(value & 0xff)
        ])
    }

    mutating func appendUInt64BE(_ value: UInt64) {
        append(contentsOf: (0..<8).reversed().map { shift in
            UInt8((value >> UInt64(shift * 8)) & 0xff)
        })
    }
}
