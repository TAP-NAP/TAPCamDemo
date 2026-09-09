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

        do {
            _ = try TAPPlaneEstimator.growPlaneRegion(
                depthMap: mismatchedDepthMap,
                seed: CGPoint(x: 1, y: 1),
                strictness: 0.68
            )
            Issue.record("Expected plane growth to reject mismatched depth-map samples.")
        } catch TAPDepthAnalysisError.invalidDepthMap {
            #expect(Bool(true))
        } catch {
            Issue.record("Unexpected plane-growth error: \(error)")
        }

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
