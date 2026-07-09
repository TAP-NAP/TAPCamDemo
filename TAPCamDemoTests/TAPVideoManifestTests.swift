//
//  TAPVideoManifestTests.swift
//  TAPCamDemoTests
//

import Foundation
import ImageIO
import Testing
@testable import TAPCamDemo

struct TAPVideoManifestTests {
    @Test func videoManifestCanonicalPayloadIsStableAndUsesUnifiedSchema() throws {
        let payload = Self.samplePayload(depthCoverage: .none)
        let manifest = TAPVideoManifest(payload: payload)

        let first = try TAPVideoManifestEncoder.payloadDataExcludingProofs(payload)
        let second = try TAPVideoManifestEncoder.payloadDataExcludingProofs(payload)
        let decoded = try JSONDecoder().decode(TAPVideoManifest.Payload.self, from: first)
        let manifestJSON = try TAPVideoManifestEncoder.manifestJSON(manifest)
        let payloadJSON = try #require(String(data: first, encoding: .utf8))

        #expect(first == second)
        #expect(decoded == payload)
        #expect(manifest.schema.id == "urn:tapnap:tapcam:video-manifest:v1")
        #expect(manifest.schema.mediaType == "application/vnd.tapnap.video-manifest+json;version=1")
        #expect(payloadJSON.contains(#""depthCoverage":{"format":null,"gapCount":0,"gaps":[],"sampleCount":0,"track":null}"#))
        #expect(manifestJSON.contains(#""proofs":[]"#))
        #expect(!manifestJSON.contains("depth-video-manifest"))
    }

    @Test func videoManifestRecordsDepthGapRangesWithoutPerFrameBitmap() throws {
        let gap = TAPVideoManifest.DepthGap(
            startTime: "PT12.340S",
            endTime: "PT12.520S",
            nearestStartRGBFrame: 370,
            nearestEndRGBFrame: 376
        )
        let coverage = TAPVideoManifest.DepthCoverage(
            track: "tap-depth-klv",
            sampleCount: 1234,
            gaps: [gap],
            format: TAPVideoManifest.DepthFormat(
                kind: "depth",
                pixelFormat: "DepthFloat32",
                width: 256,
                height: 192,
                rowStride: 1024,
                compression: "lzfse",
                calibrationReference: "cameraCalibrationData"
            )
        )
        let payloadData = try TAPVideoManifestEncoder.payloadDataExcludingProofs(
            Self.samplePayload(depthCoverage: coverage)
        )
        let payloadJSON = try #require(String(data: payloadData, encoding: .utf8))

        #expect(payloadJSON.contains(#""gapCount":1"#))
        #expect(payloadJSON.contains(#""nearestStartRGBFrame":370"#))
        #expect(payloadJSON.contains(#""nearestEndRGBFrame":376"#))
        #expect(payloadJSON.contains(#""sampleCount":1234"#))
        #expect(!payloadJSON.contains("perFrame"))
        #expect(!payloadJSON.contains("bitmap"))
    }

    @Test func tapDepthKLVEncodesFourCCPayloadsWithZeroPadding() throws {
        let records = [
            TAPDepthKLV.Record(key: .schemaVersion, payload: Data([0x00, 0x00, 0x00, 0x01])),
            TAPDepthKLV.Record(key: .depthPayload, payload: Data([0x01, 0x02, 0x03])),
            TAPDepthKLV.Record(key: TAPDepthKLV.FourCC(rawValue: "ZZZZ"), payload: Data("unknown".utf8))
        ]

        let encoded = TAPDepthKLV.encode(records)
        let decoded = try TAPDepthKLV.decode(encoded)

        #expect(decoded == records)
        #expect(encoded.count % 4 == 0)
        #expect(encoded.contains(0x5a))
    }

    @Test func tapDepthKLVRejectsNonZeroPadding() throws {
        var encoded = TAPDepthKLV.encode([
            TAPDepthKLV.Record(key: .depthPayload, payload: Data([0x01, 0x02, 0x03]))
        ])
        encoded[encoded.count - 1] = 0x01

        #expect(throws: TAPDepthCaptureError.self) {
            try TAPDepthKLV.decode(encoded)
        }
    }

    @Test func videoDepthDisplayOrientationMapsRecordedTransform() throws {
        #expect(TAPVideoDepthDisplayOrientation.cgImageOrientation(from: nil) == .up)
        #expect(TAPVideoDepthDisplayOrientation.cgImageOrientation(from: "identity") == .up)
        #expect(TAPVideoDepthDisplayOrientation.cgImageOrientation(from: "rotation:90") == .right)
        #expect(TAPVideoDepthDisplayOrientation.cgImageOrientation(from: "rotation:180") == .down)
        #expect(TAPVideoDepthDisplayOrientation.cgImageOrientation(from: "rotation:270") == .left)
        #expect(TAPVideoDepthDisplayOrientation.cgImageOrientation(from: "rotation:90;mirrored") == .rightMirrored)
        #expect(TAPVideoDepthDisplayOrientation.cgImageOrientation(from: "rotation:270;mirrored") == .leftMirrored)
    }

    @Test func videoManifestBoxAppendsAndReadsSingleBMFFUUIDBox() throws {
        let manifest = TAPVideoManifest(payload: Self.samplePayload(depthCoverage: .none))
        let baseMP4 = Self.bmffBox(type: "ftyp", payload: Data("isomtap ".utf8))

        let withManifest = try TAPVideoManifestBox.appendingManifest(manifest, to: baseMP4)
        let decoded = try TAPVideoManifestBox.decodedManifest(from: withManifest)

        #expect(decoded == manifest)
        #expect(withManifest.count > baseMP4.count)
        #expect(throws: TAPDepthCaptureError.self) {
            _ = try TAPVideoManifestBox.appendingManifest(manifest, to: withManifest)
        }
    }

    private static func samplePayload(
        depthCoverage: TAPVideoManifest.DepthCoverage
    ) -> TAPVideoManifest.Payload {
        TAPVideoManifest.Payload(
            id: "video-capture",
            capturedAt: "2026-07-09T12:00:00Z",
            selectedCameraPlan: TAPVideoManifest.SelectedCameraPlan(
                deviceUniqueID: "device-1",
                deviceType: "BuiltInLiDARDepthCamera",
                localizedName: "Back Camera",
                position: "back",
                requestedFocalLengthLabel: "24mm",
                resolvedFocalLengthLabel: "24mm",
                resolvedZoomFactor: 1,
                depthCapable: true
            ),
            container: TAPVideoManifest.Container(
                fileType: "mp4",
                mediaType: "video/mp4",
                durationSeconds: 10,
                timeScale: 600,
                trackCount: depthCoverage.sampleCount > 0 ? 2 : 1
            ),
            rgbTrack: TAPVideoManifest.RGBTrack(
                trackID: 1,
                codec: "avc1",
                width: 1920,
                height: 1080,
                nominalFrameRate: 30,
                frameCount: 300,
                transform: "identity"
            ),
            audioTrack: TAPVideoManifest.AudioTrack(
                status: .notCaptured,
                trackID: nil,
                codec: nil,
                sampleRate: nil,
                channelCount: nil
            ),
            depthCoverage: depthCoverage,
            synchronization: TAPVideoManifest.Synchronization(
                timing: "sample-timestamps",
                rgbToDepthMapping: "nearest-rgb-frame",
                maxObservedDeltaSeconds: nil
            ),
            stop: TAPVideoManifest.Stop(
                reason: .userStop,
                recordedDurationSeconds: 10
            ),
            software: TAPVideoManifest.Software(
                appIdentifier: "net.tapcam.demo",
                appVersion: "1.0",
                buildNumber: "1",
                schemaWriter: "TAPVideoManifestEncoder"
            )
        )
    }

    private static func bmffBox(type: String, payload: Data) -> Data {
        var data = Data()
        data.appendUInt32BE(UInt32(8 + payload.count))
        data.append(Data(type.utf8))
        data.append(payload)
        return data
    }
}

private extension Data {
    mutating func appendUInt32BE(_ value: UInt32) {
        append(contentsOf: [
            UInt8((value >> 24) & 0xff),
            UInt8((value >> 16) & 0xff),
            UInt8((value >> 8) & 0xff),
            UInt8(value & 0xff)
        ])
    }
}
