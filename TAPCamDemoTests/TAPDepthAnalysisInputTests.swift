//
//  TAPDepthAnalysisInputTests.swift
//  TAPCamDemoTests
//

import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import TAPCamDemo

struct TAPDepthAnalysisInputTests {
    @Test func depthAnalysisInputValidationRejectsUnsafeDepthMapShapes() throws {
        let mismatchedDepthMap = TAPMetricDepthMap(
            width: 4,
            height: 4,
            samples: [1],
            calibration: TAPCamDemoTestFixtures.sampleCalibration
        )

        #expect(mismatchedDepthMap.sample(x: 0, y: 0) == nil)
        #expect(TAPDepthGeometryProjector.point(depthMap: mismatchedDepthMap, x: 0, y: 0) == nil)
        #expect(TAPDepthGeometryProjector.sampledPoints(
            from: mismatchedDepthMap,
            in: CGRect(x: 0, y: 0, width: 4, height: 4)
        ).isEmpty)
        #expect(TAPDepthGeometryProjector.stats(
            for: mismatchedDepthMap,
            in: CGRect(x: 0, y: 0, width: 4, height: 4)
        ).totalSampleCount == 0)
        #expect(TAPPlaneEstimator.estimatePlane(
            depthMap: mismatchedDepthMap,
            region: CGRect(x: 0, y: 0, width: 4, height: 4)
        ) == nil)
        #expect(TAPPlaneEstimator.detectPlanes(depthMap: mismatchedDepthMap).isEmpty)

        do {
            _ = try TAPDepthAnalysisInputValidation.validatedDepthPixelCount(for: mismatchedDepthMap)
            Issue.record("Expected mismatched depth-map samples to fail validation.")
        } catch TAPDepthAnalysisError.invalidDepthMap {
            #expect(Bool(true))
        } catch {
            Issue.record("Unexpected depth-map validation error: \(error)")
        }

        do {
            _ = try TAPDepthGeometryProjector.geometryCache(for: mismatchedDepthMap)
            Issue.record("Expected geometry cache to reject mismatched depth-map samples.")
        } catch TAPDepthAnalysisError.invalidDepthMap {
            #expect(Bool(true))
        } catch {
            Issue.record("Unexpected geometry-cache error: \(error)")
        }
    }

    @Test func depthAnalysisInputValidationRejectsOversizedBudgetsBeforeAllocation() throws {
        do {
            try TAPDepthAnalysisInputValidation.validateHEICByteCount(
                TAPDepthAnalysisInputValidation.maximumHEICByteCount + 1
            )
            Issue.record("Expected oversized photo bytes to fail validation.")
        } catch TAPDepthAnalysisError.analysisInputTooLarge {
            #expect(Bool(true))
        } catch {
            Issue.record("Unexpected HEIC byte-count error: \(error)")
        }

        do {
            _ = try TAPDepthAnalysisInputValidation.validatedDepthPixelCount(
                width: TAPDepthAnalysisInputValidation.maximumDepthPixelCount + 1,
                height: 1
            )
            Issue.record("Expected oversized depth dimensions to fail validation.")
        } catch TAPDepthAnalysisError.analysisInputTooLarge {
            #expect(Bool(true))
        } catch {
            Issue.record("Unexpected depth-pixel budget error: \(error)")
        }

        do {
            _ = try TAPDepthAnalysisInputValidation.validatedDepthPixelCount(
                width: Int.max,
                height: 2
            )
            Issue.record("Expected overflowing depth dimensions to fail validation.")
        } catch TAPDepthAnalysisError.analysisInputTooLarge {
            #expect(Bool(true))
        } catch {
            Issue.record("Unexpected depth-pixel overflow error: \(error)")
        }
    }

    @Test func depthAnalysisReaderRejectsUnsupportedInputBeforeAnalysisDecode() throws {
        do {
            _ = try TAPDepthMapReader.analysisInput(from: Data("not a heic file".utf8))
            Issue.record("Expected unsupported input to fail before analysis decode.")
        } catch {
            #expect(Bool(true))
        }
    }

    @Test func imageOrientationReaderAcceptsImageIONumericMetadataTypes() throws {
        let intProperties: [CFString: Any] = [
            kCGImagePropertyOrientation: Int(CGImagePropertyOrientation.right.rawValue)
        ]
        let numberProperties: [CFString: Any] = [
            kCGImagePropertyOrientation: NSNumber(value: CGImagePropertyOrientation.left.rawValue)
        ]

        #expect(TAPDepthMapReader.imageOrientation(from: intProperties) == .right)
        #expect(TAPDepthMapReader.imageOrientation(from: numberProperties) == .left)
    }

    @Test func depthAnalysisInputLoaderReadsPhotosSourceThenDecodesInput() async throws {
        let expectedData = Data("photos-heic".utf8)
        let expectedInput = try TAPCamDemoTestFixtures.analysisInput(depthMap: TAPMetricDepthMap(
            width: 2,
            height: 2,
            samples: [1, 1, 1, 1],
            calibration: nil
        ))
        let loader = DepthAnalysisInputLoader(
            photosDataLoader: { assetID in
                guard assetID == "asset-private-id" else {
                    throw DepthAnalysisInputLoaderTestError.unexpectedSource
                }
                return expectedData
            },
            pendingDataLoader: { _ in
                Issue.record("Photos source should not read pending storage.")
                throw DepthAnalysisInputLoaderTestError.unexpectedSource
            },
            analysisInputReader: { data in
                guard data == expectedData else {
                    throw DepthAnalysisInputLoaderTestError.unexpectedData
                }
                return expectedInput
            },
            libraryRefreshPoster: {
                Issue.record("Photos source should not post a TAP Library refresh.")
            }
        )

        let loadedInput = try await loader.loadInput(source: .photosAsset("asset-private-id"))

        #expect(loadedInput.depthMap.width == 2)
        #expect(loadedInput.depthMap.height == 2)
    }

    @Test func depthAnalysisInputLoaderReadsPendingSourceThenDecodesInput() async throws {
        let expectedData = Data("pending-signed-or-unsigned-heic".utf8)
        let expectedInput = try TAPCamDemoTestFixtures.analysisInput(depthMap: TAPMetricDepthMap(
            width: 3,
            height: 1,
            samples: [1, 2, 3],
            calibration: nil
        ))
        let loader = DepthAnalysisInputLoader(
            photosDataLoader: { _ in
                Issue.record("Pending source should not read Photos.")
                throw DepthAnalysisInputLoaderTestError.unexpectedSource
            },
            pendingDataLoader: { captureID in
                guard captureID == "pending-private-id" else {
                    throw DepthAnalysisInputLoaderTestError.unexpectedSource
                }
                return expectedData
            },
            analysisInputReader: { data in
                guard data == expectedData else {
                    throw DepthAnalysisInputLoaderTestError.unexpectedData
                }
                return expectedInput
            },
            libraryRefreshPoster: {
                Issue.record("Successful pending load should not post a TAP Library refresh.")
            }
        )

        let loadedInput = try await loader.loadInput(source: .pendingCapture("pending-private-id"))

        #expect(loadedInput.depthMap.width == 3)
        #expect(loadedInput.depthMap.height == 1)
    }

    @Test func depthAnalysisInputLoaderMapsPendingFailureToGenericUnavailableError() async throws {
        let sensitiveCaptureID = "pending/private-capture-id"
        var refreshPostCount = 0
        let loader = DepthAnalysisInputLoader(
            photosDataLoader: { _ in
                Issue.record("Pending source should not read Photos.")
                throw DepthAnalysisInputLoaderTestError.unexpectedSource
            },
            pendingDataLoader: { captureID in
                guard captureID == sensitiveCaptureID else {
                    throw DepthAnalysisInputLoaderTestError.unexpectedSource
                }
                throw DepthAnalysisInputLoaderTestError.sensitivePendingFailure(captureID)
            },
            analysisInputReader: { _ in
                Issue.record("Pending storage failure should stop before HEIC decoding.")
                throw DepthAnalysisInputLoaderTestError.unexpectedData
            },
            libraryRefreshPoster: {
                refreshPostCount += 1
            }
        )

        do {
            _ = try await loader.loadInput(source: .pendingCapture(sensitiveCaptureID))
            Issue.record("Expected pending failure to throw a generic unavailable error.")
        } catch DepthAnalysisInputLoaderError.pendingCaptureTemporarilyUnavailable {
            #expect(refreshPostCount == 1)
        } catch {
            Issue.record("Unexpected pending loader error: \(error)")
        }
    }

    @Test func depthAnalysisInputLoaderLeavesReaderFailureGenericAndDoesNotRefreshLibrary() async throws {
        var refreshPostCount = 0
        let loader = DepthAnalysisInputLoader(
            photosDataLoader: { assetID in
                guard assetID == "asset-private-id" else {
                    throw DepthAnalysisInputLoaderTestError.unexpectedSource
                }
                return Data("malformed-heic".utf8)
            },
            pendingDataLoader: { _ in
                Issue.record("Photos source should not read pending storage.")
                throw DepthAnalysisInputLoaderTestError.unexpectedSource
            },
            analysisInputReader: { _ in
                throw DepthAnalysisInputLoaderTestError.readerRejectedInput("reader://malformed-input")
            },
            libraryRefreshPoster: {
                refreshPostCount += 1
            }
        )

        do {
            _ = try await loader.loadInput(source: .photosAsset("asset-private-id"))
            Issue.record("Expected reader failure to pass through.")
        } catch DepthAnalysisInputLoaderTestError.readerRejectedInput(_) {
            #expect(refreshPostCount == 0)
        } catch {
            Issue.record("Unexpected reader failure: \(error)")
        }
    }

    @MainActor
    @Test func analysisPhotoSlotPublishesFixedPublicSafeLoadFailure() {
        let slot = AnalysisPhotoSlot(
            entry: DepthAnalysisCarouselEntry(source: .pendingCapture("private-capture-id"))
        )

        slot.applyLoadError(DepthAnalysisInputLoaderError.pendingCaptureTemporarilyUnavailable)

        #expect(slot.analysisPhase == .failed)
        #expect(slot.errorTitle == "Image unavailable")
        #expect(slot.errorMessage == "Temporarily not available. Return to TAP Library; it will refresh automatically.")
        #expect(slot.errorSystemImage == "photo.badge.exclamationmark")
        #expect(slot.errorMessage?.contains("private-capture-id") == false)
    }

}

private enum DepthAnalysisInputLoaderTestError: LocalizedError {
    case unexpectedSource
    case unexpectedData
    case readerRejectedInput(String)
    case sensitivePendingFailure(String)

    var errorDescription: String? {
        switch self {
        case .unexpectedSource:
            return "Unexpected source"
        case .unexpectedData:
            return "Unexpected HEIC data"
        case .readerRejectedInput(let url):
            return "Reader rejected input from \(url)"
        case .sensitivePendingFailure(let captureID):
            return "Raw pending capture failure for \(captureID)"
        }
    }
}
