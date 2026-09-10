//
//  TAPVideoManifestTests.swift
//  TAPCamDemoTests
//

import CryptoKit
import Foundation
import ImageIO
import Testing
@testable import TAPCamDemo

struct TAPVideoManifestTests {
    @Test func adoptedExtensionsMatchSharedExactByteVectors() throws {
        let url = try #require(Bundle(for: TAPVideoExtensionFixtureBundle.self)
            .url(forResource: "tap-video-extensions-v1", withExtension: "json"))
        let corpus = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let context = try #require(corpus["context"] as? [String: Any])
        let vectors = try #require(corpus["cases"] as? [[String: Any]])
        var payload = try #require(JSONSerialization.jsonObject(
            with: JSONEncoder.tapCaptureCanonical.encode(Self.samplePayload(depthCoverage: .none))) as? [String: Any])
        for key in ["container", "rgbTrack"] {
            var track = try #require(payload[key] as? [String: Any])
            track["durationSeconds"] = context["durationSeconds"]
            track["timeScale"] = context["timeScale"]
            payload[key] = track
        }
        var coverage = try #require(payload["depthCoverage"] as? [String: Any])
        coverage["deliveredSampleCount"] = context["deliveredDepthSampleCount"]
        payload["depthCoverage"] = coverage
        let manifest = TAPVideoManifest(payload: try JSONDecoder().decode(TAPVideoManifest.Payload.self,
            from: JSONSerialization.data(withJSONObject: payload)))
        for vector in vectors {
            let id = try #require(vector["id"] as? String)
            let base64 = try #require(vector["utf8Base64"] as? String)
            let data = try #require(Data(base64Encoded: base64))
            #expect(data.count == vector["utf8ByteCount"] as? Int)
            #expect(SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() == vector["utf8SHA256"] as? String)
            func decode() throws {
                if vector["extension"] as? String == "cald" {
                    _ = try TAPDepthInlineCalibration.decode(data)
                } else {
                    let file = try Self.makeTemporaryFile(data: Self.bmffBox(
                        type: "uuid", payload: TAPVideoCaptureTelemetryBox.uuid + data))
                    defer { try? FileManager.default.removeItem(at: file) }
                    _ = try #require(try TAPVideoCaptureTelemetryBox.read(from: file, manifest: manifest))
                }
            }
            if vector["expectedDecision"] as? String == "accept" {
                try decode()
            } else {
                #expect(throws: (any Error).self, "Must reject \(id)") { try decode() }
            }
        }
    }

    @Test func captureTelemetryPreservesLegacyAndRejectsInvalidProvenance() throws {
        let manifest = TAPVideoManifest(payload: Self.samplePayload(depthCoverage: .none))
        let fileURL = try Self.makeTemporaryFile(data: Self.bmffBox(type: "ftyp", payload: Data("isomtap ".utf8)))
        #expect(try TAPVideoCaptureTelemetryBox.read(from: fileURL, manifest: manifest) == nil)
        let telemetry = TAPVideoCaptureTelemetry(
            filtering: .init(requestedEnabled: true),
            motion: .init(status: .unavailable)
        )
        try TAPVideoCaptureTelemetryBox.append(telemetry, manifest: manifest, to: fileURL)
        #expect(try TAPVideoCaptureTelemetryBox.read(from: fileURL, manifest: manifest) == telemetry)
        let encoded = try JSONEncoder.tapCaptureCanonical.encode(telemetry)
        #expect(String(decoding: encoded, as: UTF8.self).contains("\"motionToCaptureOffsetSeconds\":null"))
        #expect(throws: TAPDepthCaptureError.self) {
            try TAPVideoCaptureTelemetryBox.append(telemetry, manifest: manifest, to: fileURL)
        }
        #expect(throws: TAPDepthCaptureError.self) {
            try TAPVideoCaptureTelemetry(
                filtering: .init(requestedEnabled: true, filteredSampleCount: 1),
                motion: .init(status: .unavailable)
            ).validate(manifest: manifest)
        }
        var observedMotion = TAPVideoCaptureTelemetry.Motion(
            status: .available,
            motionToCaptureOffsetSeconds: -100,
            samples: [.init(ptsSeconds: 0.1, quaternion: [0, 0, 0, 1], rotationRate: [0, 0, 0], gravity: [0, -1, 0], userAcceleration: [0, 0, 0])]
        )
        try TAPVideoCaptureTelemetry(filtering: .init(requestedEnabled: false), motion: observedMotion).validate(manifest: manifest)
        observedMotion.samples.append(observedMotion.samples[0])
        #expect(throws: TAPDepthCaptureError.self) {
            try TAPVideoCaptureTelemetry(filtering: .init(requestedEnabled: false), motion: observedMotion).validate(manifest: manifest)
        }
        observedMotion.samples = []
        #expect(throws: TAPDepthCaptureError.self) {
            try TAPVideoCaptureTelemetry(filtering: .init(requestedEnabled: false), motion: observedMotion).validate(manifest: manifest)
        }
    }

    @MainActor @Test func videoPreferencesUseShippingDefaultsAndDebugOverrides() throws {
        let suite = "TAPVideoPreferencesTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(!DepthAnalyzerPreferences.appleDepthFilteringEnabled(defaults: defaults))
        #expect(DepthAnalyzerPreferences.playbackSmoothingEnabled(defaults: defaults))
        defaults.set(true, forKey: DepthAnalyzerPreferences.appleDepthFilteringEnabledKey)
        defaults.set(false, forKey: DepthAnalyzerPreferences.playbackSmoothingEnabledKey)
        let request = TAPVideoRecordingRequest(
            outputURL: URL(fileURLWithPath: "/tmp/preferences-test.mp4"),
            videoRotationAngle: 0, isVideoMirrored: false, recordsAudio: false,
            depthFilteringEnabled: DepthAnalyzerPreferences.appleDepthFilteringEnabled(defaults: defaults)
        )
        defaults.set(false, forKey: DepthAnalyzerPreferences.appleDepthFilteringEnabledKey)
        #if DEBUG
        #expect(request.depthFilteringEnabled)
        #expect(!DepthAnalyzerPreferences.playbackSmoothingEnabled(defaults: defaults))
        #else
        #expect(!request.depthFilteringEnabled)
        #expect(DepthAnalyzerPreferences.playbackSmoothingEnabled(defaults: defaults))
        #endif
    }

    @Test func captureTelemetryAcceptsNumberSpellingsButRejectsNoncanonicalStructure() throws {
        let manifest = TAPVideoManifest(payload: Self.samplePayload(depthCoverage: .none))
        let telemetry = TAPVideoCaptureTelemetry(
            filtering: .init(requestedEnabled: false),
            motion: .init(
                status: .available,
                motionToCaptureOffsetSeconds: -100,
                samples: [.init(ptsSeconds: 0.1, quaternion: [0, 0, 0, 1], rotationRate: [0, 0, 0], gravity: [0, -1, 0], userAcceleration: [0, 0, 0])]
            )
        )
        let data = try JSONEncoder.tapCaptureCanonical.encode(telemetry)
        let canonical = String(decoding: data, as: UTF8.self)
        func read(_ json: String) throws -> TAPVideoCaptureTelemetry? {
            let url = try Self.makeTemporaryFile(data: Self.bmffBox(
                type: "uuid", payload: TAPVideoCaptureTelemetryBox.uuid + Data(json.utf8)
            ))
            return try TAPVideoCaptureTelemetryBox.read(from: url, manifest: manifest)
        }
        let equivalentNumbers = canonical
            .replacingOccurrences(of: "\"ptsSeconds\":0.1", with: "\"ptsSeconds\":1e-1")
            .replacingOccurrences(of: "\"gravity\":[0,-1,0]", with: "\"gravity\":[0.0,-1.0,0e0]")
        #expect(equivalentNumbers != canonical)
        #expect(try read(equivalentNumbers) == telemetry)
        for malformed in [
            " " + canonical,
            canonical.replacingOccurrences(of: "\"filteredSampleCount\":0", with: "\"filteredSampleCount\":0.0"),
            canonical.replacingOccurrences(of: "\"requestedEnabled\":false", with: "\"requestedEnabled\":false,\"requestedEnabled\":false"),
            "{\"alien\":0," + canonical.dropFirst()
        ] {
            #expect(throws: (any Error).self) { try read(malformed) }
        }
    }

    @Test func calibrationCoverageRejectsOverflowWithoutTrapping() {
        let coverage = TAPVideoManifest.CalibrationCoverage(
            indexedSampleCount: .max,
            missingCalibrationSampleCount: 1,
            overflowUnindexedSampleCount: 0,
            tableOverflowed: false
        )

        #expect(coverage.accountedSampleCount == nil)
    }

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
        #expect(manifest.schema.version == 1)
        #expect(manifest.schema.mediaType == "application/vnd.tapnap.video-manifest+json;version=1")
        #expect(payloadJSON.contains(#""depthCoverage":{"deliveredSampleCount":0,"encodingDropCount":0,"format":null,"gapCount":0,"gaps":[],"metadataDropCount":0,"outputDropCount":0,"sampleCount":0,"trackCodec":null,"trackDurationSeconds":null,"trackID":null,"trackTimeScale":null}"#))
        #expect(manifestJSON.contains(#""proofs":[]"#))
        #expect(!manifestJSON.contains("depth-video-manifest"))
    }

    @Test func videoManifestRecordsDepthGapRangesWithoutPerFrameBitmap() throws {
        let gap = TAPVideoManifest.DepthGap(
            reason: .metadataBackpressure,
            startPTS: TAPVideoManifest.MediaTime(value: 7_404, timescale: 600),
            endPTS: TAPVideoManifest.MediaTime(value: 7_512, timescale: 600),
            nearestStartRGBFrame: 370,
            nearestEndRGBFrame: 376
        )
        let coverage = TAPVideoManifest.DepthCoverage(
            trackID: 3,
            trackCodec: "mebx",
            trackDurationSeconds: 9.98,
            trackTimeScale: 600,
            sampleCount: 1234,
            gaps: [gap],
            format: TAPVideoManifest.DepthFormat(
                kind: "depth",
                pixelFormat: "DepthFloat32",
                width: 256,
                height: 192,
                packedRowStride: 1_024,
                sourceRowStride: 1_088,
                bytesPerSample: 4,
                uncompressedFrameByteCount: 196_608
            )
        )
        let payloadData = try TAPVideoManifestEncoder.payloadDataExcludingProofs(
            Self.samplePayload(depthCoverage: coverage)
        )
        let payloadJSON = try #require(String(data: payloadData, encoding: .utf8))

        #expect(payloadJSON.contains(#""gapCount":1"#))
        #expect(payloadJSON.contains(#""nearestStartRGBFrame":370"#))
        #expect(payloadJSON.contains(#""nearestEndRGBFrame":376"#))
        #expect(payloadJSON.contains(#""reason":"metadataBackpressure""#))
        #expect(payloadJSON.contains(#""startPTS":{"timescale":600,"value":7404}"#))
        #expect(payloadJSON.contains(#""compressionPolicy":"per-frame:zstd1|raw""#))
        #expect(payloadJSON.contains(#""packedRowStride":1024"#))
        #expect(payloadJSON.contains(#""sourceRowStride":1088"#))
        #expect(payloadJSON.contains(#""sampleCount":1234"#))
        #expect(payloadJSON.contains(#""trackCodec":"mebx""#))
        #expect(payloadJSON.contains(#""trackDurationSeconds":9.98"#))
        #expect(payloadJSON.contains(#""trackTimeScale":600"#))
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

    @Test func depthFramesPreserveChangingCalibrationAfterTheSixteenEntryTableFills() throws {
        var table = TAPVideoCalibrationTable()
        for index in 0..<32 {
            let calibration = Self.inlineCalibration(index: index)
            let reference = table.index(for: calibration)
            let frame = TAPDepthKLVFrame(
                frameIndex: UInt32(index), timestampValue: Int64(index * 20), timestampTimescale: 600,
                compressionCodec: .raw, uncompressedByteCount: 4, calibrationIndex: reference,
                payload: Data([0, 0, 128, 63]),
                inlineCalibration: reference == nil ? TAPDepthInlineCalibration.bounded(calibration) : nil
            )
            let encoded = try frame.encodedData()
            let decoded = try TAPDepthKLVFrame.decode(encoded)
            let recovered = decoded.inlineCalibration ?? decoded.calibrationIndex.map { table.entries[Int($0)] }
            #expect(recovered == calibration)
            #expect(try decoded.decodedPackedBytes() == frame.payload)
            #expect((decoded.inlineCalibration != nil) == (index >= 16))
        }
        #expect(table.entries.count == 16)
        #expect(table.didOverflow)
    }

    @Test func inlineCalibrationAcceptsOptionalNullAndNumberSpellings() throws {
        let calibration = Self.inlineCalibration(index: 0)
        let data = try TAPDepthInlineCalibration.encodedData(calibration)
        let json = String(decoding: data, as: UTF8.self)
        #expect(try TAPDepthInlineCalibration.decode(data) == calibration)
        let equivalent = json.replacingOccurrences(of: "\"width\":1920", with: "\"width\":1.92e3")
        #expect(equivalent != json)
        #expect(try TAPDepthInlineCalibration.decode(Data(equivalent.utf8)) == calibration)

        let withoutTables = Self.inlineCalibration(index: 0, lookupTable: nil)
        let omitted = String(decoding: try TAPDepthInlineCalibration.encodedData(withoutTables), as: UTF8.self)
        let explicitNull = omitted
            .replacingOccurrences(of: "\"lensDistortionCenter\":", with: "\"inverseLensDistortionLookupTable\":null,\"lensDistortionCenter\":")
            .replacingOccurrences(of: "\"pixelSizeMillimeters\":", with: "\"lensDistortionLookupTable\":null,\"pixelSizeMillimeters\":")
        #expect(try TAPDepthInlineCalibration.decode(Data(explicitNull.utf8)) == withoutTables)
    }

    @Test func inlineCalibrationRejectsInvalidStructureAndPreservesDepthWhenTooLarge() throws {
        let calibration = Self.inlineCalibration(index: 0)
        let json = String(decoding: try TAPDepthInlineCalibration.encodedData(calibration), as: UTF8.self)
        for invalid in [
            " " + json,
            json.replacingOccurrences(of: "\"schemaVersion\":1", with: "\"schemaVersion\":1.0"),
            json.replacingOccurrences(of: "\"schemaVersion\":1", with: "\"schemaVersion\":1,\"schemaVersion\":1"),
            json.replacingOccurrences(of: "\"calibration\":{", with: "\"calibration\":{\"alien\":0,"),
            json.replacingOccurrences(of: "\"width\":1920", with: "\"width\":1e999"),
            json.replacingOccurrences(of: "\"intrinsicMatrix\":[", with: "\"intrinsicMatrix\":[1,"),
            json.replacingOccurrences(of: "\"lensDistortionLookupTable\":\"", with: "\"lensDistortionLookupTable\":\"!")
        ] {
            #expect(throws: (any Error).self) { try TAPDepthInlineCalibration.decode(Data(invalid.utf8)) }
        }
        let oversized = Self.inlineCalibration(index: 0, lookupTable: Data(repeating: 0, count: 3_072))
        #expect(TAPDepthInlineCalibration.bounded(oversized) == nil)
        #expect(throws: TAPDepthCaptureError.self) { try TAPDepthInlineCalibration.encodedData(oversized) }
        let frame = TAPDepthKLVFrame(
            frameIndex: 17, timestampValue: 340, timestampTimescale: 600,
            compressionCodec: .raw, uncompressedByteCount: 4, calibrationIndex: nil,
            payload: Data([0, 0, 128, 63]), inlineCalibration: TAPDepthInlineCalibration.bounded(oversized)
        )
        #expect(try TAPDepthKLVFrame.decode(frame.encodedData()).decodedPackedBytes() == frame.payload)
    }

    @Test func depthKLVRejectsDuplicateOrConflictingInlineCalibration() throws {
        let calibration = Self.inlineCalibration(index: 0)
        let indexed = TAPDepthKLVFrame(
            frameIndex: 0, timestampValue: 0, timestampTimescale: 600,
            compressionCodec: .raw, uncompressedByteCount: 4, calibrationIndex: 0,
            payload: Data([0, 0, 128, 63])
        )
        var conflicting = indexed
        conflicting.inlineCalibration = calibration
        #expect(throws: TAPDepthCaptureError.self) { try conflicting.encodedData() }
        let inlineRecord = TAPDepthKLV.Record(key: .inlineCalibration, payload: try TAPDepthInlineCalibration.encodedData(calibration))
        let records = try TAPDepthKLV.decode(indexed.encodedData())
        #expect(throws: TAPDepthCaptureError.self) { try TAPDepthKLVFrame.decode(TAPDepthKLV.encode(records + [inlineRecord])) }
        let withoutIndex = records.filter { $0.key != .calibrationIndex }
        #expect(throws: TAPDepthCaptureError.self) {
            try TAPDepthKLVFrame.decode(TAPDepthKLV.encode(withoutIndex + [inlineRecord, inlineRecord]))
        }
        let unknown = TAPDepthKLV.Record(key: .init(rawValue: "NEXT"), payload: Data([1]))
        #expect(try TAPDepthKLVFrame.decode(TAPDepthKLV.encode(withoutIndex + [inlineRecord, unknown])).inlineCalibration == calibration)
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
        let fileURL = try Self.makeTemporaryFile(
            data: Self.bmffBox(type: "ftyp", payload: Data("isomtap ".utf8))
        )

        try TAPVideoManifestBox.appendManifest(manifest, toFileAt: fileURL)
        let document = try TAPVideoManifestBox.decodedManifestDocument(fromFileAt: fileURL)
        let standalonePayloadData = try TAPVideoManifestEncoder.payloadDataExcludingProofs(
            manifest.payload
        )

        #expect(document.manifest == manifest)
        #expect(document.rawPayloadData == standalonePayloadData)
        #expect(throws: TAPDepthCaptureError.self) {
            try TAPVideoManifestBox.appendManifest(manifest, toFileAt: fileURL)
        }
    }

    @Test func videoManifestBoxRejectsOversizedPayloadBeforeMutatingFile() throws {
        let calibration = TAPVideoManifest.CameraCalibration(
            intrinsicMatrix: [1, 0, 0, 0, 1, 0, 0, 0, 1],
            intrinsicMatrixReferenceDimensions: .init(width: 1_920, height: 1_080),
            extrinsicMatrix: [1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0],
            pixelSizeMillimeters: 0.0014,
            lensDistortionCenter: .init(x: 960, y: 540),
            lensDistortionLookupTable: Data(
                repeating: 0xab,
                count: TAPBMFFStreamingFile.maximumManifestByteCount
            ),
            inverseLensDistortionLookupTable: nil
        )
        let registration = TAPVideoManifest.SpatialRegistration(
            status: .registered,
            mapping: "oversized-test",
            rgbReferenceDimensions: .init(width: 1_920, height: 1_080),
            depthReferenceDimensions: .init(width: 256, height: 192),
            rgbCleanAperture: .init(x: 0, y: 0, width: 1_920, height: 1_080),
            recordedTransform: "rotation:0;not-mirrored",
            calibration: calibration
        )
        let manifest = TAPVideoManifest(payload: Self.samplePayload(
            depthCoverage: .none,
            spatialRegistration: registration
        ))
        let fileURL = try Self.makeTemporaryFile(
            data: Self.bmffBox(type: "ftyp", payload: Data("isomtap ".utf8))
        )
        let originalByteCount = try TAPBMFFStreamingFile.byteCount(of: fileURL)

        #expect(throws: TAPDepthCaptureError.self) {
            try TAPVideoManifestBox.appendManifest(manifest, toFileAt: fileURL)
        }
        #expect(try TAPBMFFStreamingFile.byteCount(of: fileURL) == originalByteCount)
    }

    @Test func videoManifestCarriesConcreteSpatialCalibration() throws {
        let calibration = TAPVideoManifest.CameraCalibration(
            intrinsicMatrix: [1, 0, 0, 0, 1, 0, 12, 14, 1],
            intrinsicMatrixReferenceDimensions: .init(width: 1_920, height: 1_080),
            extrinsicMatrix: [1, 0, 0, 0, 1, 0, 0, 0, 1, 2, 3, 4],
            pixelSizeMillimeters: 0.0014,
            lensDistortionCenter: .init(x: 960, y: 540),
            lensDistortionLookupTable: Data([1, 2]),
            inverseLensDistortionLookupTable: Data([3, 4])
        )
        let registration = TAPVideoManifest.SpatialRegistration(
            status: .registered,
            mapping: "AVDepthData.cameraCalibrationData",
            rgbReferenceDimensions: .init(width: 1_920, height: 1_080),
            depthReferenceDimensions: .init(width: 256, height: 192),
            rgbCleanAperture: .init(x: 0, y: 0, width: 1_920, height: 1_080),
            recordedTransform: "rotation:90",
            calibration: calibration
        )
        let payload = Self.samplePayload(depthCoverage: .none, spatialRegistration: registration)

        let decoded = try JSONDecoder().decode(
            TAPVideoManifest.Payload.self,
            from: TAPVideoManifestEncoder.payloadDataExcludingProofs(payload)
        )

        #expect(decoded.spatialRegistration == registration)
        #expect(decoded.spatialRegistration.calibration?.extrinsicMatrix.count == 12)
        #expect(decoded.spatialRegistration.calibrationTable == [calibration])
    }

    @Test func videoManifestSeparates2DRegistrationFromMetricCalibrationCoverage() throws {
        let registration = TAPVideoManifest.SpatialRegistration(
            status: .registered,
            mapping: TAPVideoManifest.RegistrationDescriptor.schemaID,
            rgbReferenceDimensions: .init(width: 1_920, height: 1_080),
            depthReferenceDimensions: .init(width: 256, height: 192),
            rgbCleanAperture: .init(x: 0, y: 0, width: 1_920, height: 1_080),
            recordedTransform: "rotation:0;not-mirrored",
            calibrationTable: [],
            calibrationCoverage: .init(
                indexedSampleCount: 0,
                missingCalibrationSampleCount: 5,
                overflowUnindexedSampleCount: 0,
                tableOverflowed: false
            ),
            descriptor: TAPVideoManifest.RegistrationDescriptor(
                alignedRGBCodedDimensions: .init(width: 1_920, height: 1_080),
                encodedRGBCodedDimensions: .init(width: 1_920, height: 1_080),
                depthDimensions: .init(width: 256, height: 192),
                depthToAlignedRGBPixelCenterAffine: [
                    7.5, 0, 3.25,
                    0, 5.625, 2.3125
                ],
                connectionTransform: "rotation:0;not-mirrored",
                isEncodedHorizontallyMirrored: false,
                rgbCleanAperture: .init(x: 0, y: 0, width: 1_920, height: 1_080),
                videoStabilizationMode: "off"
            )
        )
        let payload = Self.samplePayload(
            depthCoverage: TAPVideoManifest.DepthCoverage(
                trackID: 2,
                sampleCount: 5,
                format: TAPVideoManifest.DepthFormat(
                    kind: "depth",
                    pixelFormat: "fdep",
                    width: 256,
                    height: 192,
                    packedRowStride: 1_024,
                    bytesPerSample: 4,
                    uncompressedFrameByteCount: 196_608
                )
            ),
            spatialRegistration: registration
        )

        let decoded = try JSONDecoder().decode(
            TAPVideoManifest.Payload.self,
            from: TAPVideoManifestEncoder.payloadDataExcludingProofs(payload)
        )

        #expect(decoded.spatialRegistration.status == .registered)
        #expect(decoded.spatialRegistration.calibrationTable.isEmpty)
        #expect(decoded.spatialRegistration.calibrationCoverage.accountedSampleCount == 5)
        #expect(!decoded.spatialRegistration.calibrationCoverage.tableOverflowed)
        #expect(decoded.spatialRegistration.descriptor != nil)
    }

    @Test func verifierGoldenVectorCarriesPerTrackTimingAndMetadataCodec() throws {
        let url = try #require(Bundle(for: TAPVideoExtensionFixtureBundle.self)
            .url(forResource: "TAPVideoManifestV1GoldenVectors", withExtension: "json"))
        let data = try Data(contentsOf: url)
        let root = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        let manifest = try #require(root["manifest"] as? [String: Any])
        let payload = try #require(manifest["payload"] as? [String: Any])
        let rgbTrack = try #require(payload["rgbTrack"] as? [String: Any])
        let audioTrack = try #require(payload["audioTrack"] as? [String: Any])
        let depthCoverage = try #require(payload["depthCoverage"] as? [String: Any])

        #expect(rgbTrack["durationSeconds"] as? Int == 1)
        #expect(rgbTrack["timeScale"] as? Int == 600)
        #expect(audioTrack["durationSeconds"] is NSNull)
        #expect(audioTrack["timeScale"] is NSNull)
        #expect(depthCoverage["trackCodec"] as? String == "mebx")
        #expect(depthCoverage["trackDurationSeconds"] as? Int == 1)
        #expect(depthCoverage["trackTimeScale"] as? Int == 600)

        let decodedManifest = try JSONDecoder().decode(
            TAPVideoManifest.self,
            from: JSONSerialization.data(withJSONObject: manifest)
        )
        let calibrationCoverage = decodedManifest.payload.spatialRegistration
            .calibrationCoverage
        #expect(calibrationCoverage.indexedSampleCount == 1)
        #expect(calibrationCoverage.accountedSampleCount == 1)
        #expect(decodedManifest.payload.spatialRegistration.calibrationTable.count == 1)

        let depthFrame = try #require(root["depthFrame"] as? [String: Any])
        let klvBase64 = try #require(depthFrame["klvV1Base64"] as? String)
        let klvData = try #require(Data(base64Encoded: klvBase64))
        let frame = try TAPDepthKLVFrame.decode(klvData)
        let calibrationIndex = try #require(frame.calibrationIndex)
        #expect(Int(calibrationIndex) < decodedManifest.payload.spatialRegistration.calibrationTable.count)
    }

    private static func inlineCalibration(index: Int, lookupTable: Data? = Data([0, 0, 0, 0])) -> TAPVideoManifest.CameraCalibration {
        .init(
            intrinsicMatrix: [1_000 + Float(index), 0, 0, 0, 1_000, 0, 960, 540, 1],
            intrinsicMatrixReferenceDimensions: .init(width: 1920, height: 1080),
            extrinsicMatrix: [1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0],
            pixelSizeMillimeters: 0.001,
            lensDistortionCenter: .init(x: 960, y: 540),
            lensDistortionLookupTable: lookupTable,
            inverseLensDistortionLookupTable: lookupTable
        )
    }

    private static func samplePayload(
        depthCoverage: TAPVideoManifest.DepthCoverage,
        spatialRegistration: TAPVideoManifest.SpatialRegistration = .unavailable
    ) -> TAPVideoManifest.Payload {
        TAPVideoManifest.Payload(
            id: "video-capture",
            packageID: "00000000-0000-0000-0000-000000000777",
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
                durationSeconds: 10,
                timeScale: 600,
                nominalFrameRate: 30,
                frameCount: 300,
                transform: "identity"
            ),
            audioTrack: TAPVideoManifest.AudioTrack(
                status: .notCaptured,
                trackID: nil,
                codec: nil,
                durationSeconds: nil,
                timeScale: nil,
                sampleRate: nil,
                channelCount: nil
            ),
            depthCoverage: depthCoverage,
            spatialRegistration: spatialRegistration,
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

    private static func makeTemporaryFile(data: Data) throws -> URL {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("TAPVideoManifestTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let fileURL = directoryURL.appendingPathComponent("artifact.mp4")
        try data.write(to: fileURL)
        return fileURL
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

private final class TAPVideoExtensionFixtureBundle: NSObject {}
