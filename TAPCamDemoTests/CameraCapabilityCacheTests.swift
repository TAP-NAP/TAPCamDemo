import AVFoundation
import Foundation
import Testing
@testable import TAPCamDemo

struct CameraCapabilityCacheTests {
    @Test(.enabled(
        if: AVCaptureDevice.authorizationStatus(for: .video) == .authorized
            && !CameraCapabilityResolver.depthDevices(in: CameraCapabilityResolver.availableDevices()).isEmpty,
        "Requires an authorized physical iPhone depth camera; no session or capture is started."
    ))
    func nativeCapabilitiesRoundTripWithoutRewritingCache() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("camera-capability-roundtrip-\(UUID().uuidString).cache")
        defer { try? FileManager.default.removeItem(at: url) }
        let cache = CameraCapabilityCache(cacheURL: url)
        let discovered = cache.discoverAndCache()
        let bytes = try Data(contentsOf: url)
        for _ in 0..<2 {
            let restored = try #require(cache.loadCached())
            expectSameCapabilities(discovered, restored)
            #expect(try Data(contentsOf: url) == bytes)
        }
    }

    @Test func cachedFormatFactsPreserveSelectionAndStrictFallback() throws {
        let formats = [
            facts(video: 2, score: 10, ranges: []),
            facts(video: 5, score: 20, ranges: [2...4]),
            facts(video: 8, score: 20, ranges: [2...4]),
            facts(video: 9, score: 30, ranges: [6...6, 8...8])
        ]
        let restored = try JSONDecoder().decode(
            [DepthFormatFacts].self,
            from: JSONEncoder().encode(formats)
        )
        #expect(restored == formats)
        for candidates in [formats, restored] {
            #expect(DepthFormatFacts.bestIndex(in: candidates) == 3)
            #expect(DepthFormatFacts.bestIndex(in: candidates, preferredZoomFactor: 1) == 0)
            #expect(DepthFormatFacts.bestIndex(in: candidates, preferredZoomFactor: 4) == 1)
            #expect(DepthFormatFacts.bestIndex(in: candidates, preferredZoomFactor: 2.375) == 1)
            #expect(DepthFormatFacts.bestIndex(in: candidates, preferredZoomFactor: 7) == 3)
            #expect(DepthFormatFacts.bestIndex(
                in: candidates, preferredZoomFactor: 7, requiresPreferredZoomSupport: true
            ) == nil)
            #expect(DepthFormatFacts.bestIndex(
                in: candidates, requiresPreferredZoomSupport: true
            ) == nil)
        }
        #expect(DepthFormatFacts.bestIndex(in: []) == nil)
    }

    @Test func persistedCapabilitiesRequireExactRuntimeAndDeviceIdentity() throws {
        let identity = identity()
        let snapshot = CameraCapabilityCache.Snapshot(
            identity: identity,
            candidates: [],
            photographerModeFacts: unavailablePhotographerFacts()
        )
        let data = try snapshot.encoded()
        #expect(CameraCapabilityCache.Snapshot.decode(data, matching: identity) != nil)

        let changed = [
            self.identity(bundle: "another.bundle"),
            self.identity(version: "2"),
            self.identity(build: "101"),
            self.identity(initializationSchema: 2),
            self.identity(os: "Version 26.1 (Build B)"),
            self.identity(model: "iPhone-other"),
            self.identity(deviceGenerationID: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!),
            self.identity(deviceID: "replacement-camera")
        ]
        for mismatch in changed {
            #expect(CameraCapabilityCache.Snapshot.decode(data, matching: mismatch) == nil)
        }
        let empty = CameraCapabilityCache.Identity(
            runtime: identity.runtime,
            operatingSystem: identity.operatingSystem,
            deviceModel: identity.deviceModel,
            deviceGenerationID: identity.deviceGenerationID,
            devices: []
        )
        #expect(CameraCapabilityCache.Snapshot.decode(data, matching: empty) == nil)
    }

    @Test func corruptOrUnsupportedCacheCannotSupplyCapabilities() throws {
        let identity = identity()
        #expect(CameraCapabilityCache.Snapshot.decode(Data("{broken".utf8), matching: identity) == nil)
        var snapshot = CameraCapabilityCache.Snapshot(
            identity: identity,
            candidates: [],
            photographerModeFacts: unavailablePhotographerFacts()
        )
        snapshot.schemaVersion = 2
        #expect(CameraCapabilityCache.Snapshot.decode(
            try snapshot.encoded(), matching: identity
        ) == nil)
        snapshot.schemaVersion = 1
        let intact = try snapshot.encoded()
        let changedPayload = String(decoding: intact.dropFirst(32), as: UTF8.self)
            .replacingOccurrences(of: "test-camera", with: "replacement-camera")
        let damaged = Data(intact.prefix(32)) + Data(changedPayload.utf8)
        #expect(CameraCapabilityCache.Snapshot.decode(
            damaged, matching: self.identity(deviceID: "replacement-camera")
        ) == nil)
    }

    @Test func cancelledPreparationDoesNotPersistAnEmptyResult() async {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("camera-capability-cancelled-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        await Task {
            withUnsafeCurrentTask { $0?.cancel() }
            let cache = CameraCapabilityCache(cacheURL: url)
            #expect(cache.loadCached() == nil)
            let matrix = cache.discoverAndCache()
            #expect(matrix.rgbSources.isEmpty)
            #expect(matrix.depthCandidates.isEmpty)
        }.value
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    private func expectSameCapabilities(_ original: CapabilityMatrix, _ restored: CapabilityMatrix) {
        #expect(original.rgbSources.map(\.id) == restored.rgbSources.map(\.id))
        #expect(original.photographerModeFacts == restored.photographerModeFacts)
        let originalPRO = original.photographerModeCapturePlan()
        let restoredPRO = restored.photographerModeCapturePlan()
        #expect(originalPRO?.rgbSource.id == restoredPRO?.rgbSource.id)
        #expect(originalPRO?.zoom == restoredPRO?.zoom)
        expectSameFormats(originalPRO?.formatSelection, restoredPRO?.formatSelection)

        let originalFOVs = original.focalLengthOptions()
        let restoredFOVs = restored.focalLengthOptions()
        #expect(originalFOVs.count == restoredFOVs.count)
        for (lhs, rhs) in zip(originalFOVs, restoredFOVs) {
            #expect(lhs.id == rhs.id)
            #expect(lhs.displayName == rhs.displayName)
            #expect(lhs.rgbSource.id == rhs.rgbSource.id)
            #expect(lhs.depthSource?.kind == rhs.depthSource?.kind)
            #expect(lhs.depthSource?.compatibility == rhs.depthSource?.compatibility)
            #expect(lhs.zoom == rhs.zoom)
            #expect(lhs.isEnabled == rhs.isEnabled)
            #expect(lhs.disabledReason == rhs.disabledReason)
            expectSameFormats(lhs.depthSource?.formatSelection, rhs.depthSource?.formatSelection)
        }
        let originalDebug = original.debugDepthDeviceOptions()
        let restoredDebug = restored.debugDepthDeviceOptions()
        #expect(originalDebug.count == restoredDebug.count)
        for (lhs, rhs) in zip(originalDebug, restoredDebug) {
            #expect(lhs.id == rhs.id)
            #expect(lhs.rgbSource?.id == rhs.rgbSource?.id)
            #expect(lhs.isSelectable == rhs.isSelectable)
            #expect(lhs.disabledReason == rhs.disabledReason)
            expectSameFormats(lhs.formatSelection, rhs.formatSelection)
        }
        #expect(original.depthCandidates.count == restored.depthCandidates.count)
        for (lhs, rhs) in zip(original.depthCandidates, restored.depthCandidates) {
            #expect(lhs.kind == rhs.kind)
            #expect(lhs.device.uniqueID == rhs.device.uniqueID)
            #expect(lhs.formats.map(\.facts) == rhs.formats.map(\.facts))
            expectSameFormats(lhs.formatSelection, rhs.formatSelection)
            let rangeZooms = lhs.formats.flatMap { candidate in
                candidate.facts.depthSafeZoomRanges.flatMap { range in
                    [range.lowerBound, range.upperBound, (range.lowerBound + range.upperBound) / 2]
                }
            }
            for zoom in [0.5, 1, 2, 2.375, 3, 4] + rangeZooms {
                for strict in [false, true] {
                    expectSameFormats(
                        lhs.bestFormatSelection(preferredZoomFactor: zoom, requiresPreferredZoomSupport: strict),
                        rhs.bestFormatSelection(preferredZoomFactor: zoom, requiresPreferredZoomSupport: strict)
                    )
                }
            }
        }
    }

    private func expectSameFormats(_ lhs: PhotoDepthFormatSelection?, _ rhs: PhotoDepthFormatSelection?) {
        #expect(lhs.map { CameraCapabilityCache.VideoFingerprint($0.videoFormat) }
            == rhs.map { CameraCapabilityCache.VideoFingerprint($0.videoFormat) })
        #expect(lhs.map { CameraCapabilityCache.FormatFingerprint($0.depthFormat) }
            == rhs.map { CameraCapabilityCache.FormatFingerprint($0.depthFormat) })
    }

    private func facts(video: Int, score: Double, ranges: [ClosedRange<Double>]) -> DepthFormatFacts {
        DepthFormatFacts(
            videoFormatIndex: video,
            depthFormatIndex: 0,
            score: score,
            depthSafeZoomRanges: ranges
        )
    }

    private func identity(
        bundle: String = "test.camera",
        version: String = "1",
        build: String = "100",
        initializationSchema: Int = 1,
        os: String = "Version 26.0 (Build A)",
        model: String = "iPhone-test",
        deviceGenerationID: UUID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
        deviceID: String = "test-camera"
    ) -> CameraCapabilityCache.Identity {
        CameraCapabilityCache.Identity(
            runtime: StartupInitializationRuntimeIdentity(
                bundleIdentifier: bundle,
                shortVersion: version,
                buildVersion: build,
                initializationSchemaVersion: initializationSchema
            ),
            operatingSystem: os,
            deviceModel: model,
            deviceGenerationID: deviceGenerationID,
            devices: [CameraCapabilityCache.DeviceIdentity(
                id: deviceID, type: "test-wide", position: 1, constituentIDs: []
            )]
        )
    }

    private func unavailablePhotographerFacts() -> PhotographerModeCapabilityFacts {
        PhotographerModeCapabilityFacts(
            isRearLiDARDevice: false,
            hasOneXDepthFormat: false,
            supportsPhotoDepthDelivery: false,
            supportsCustomExposure: false,
            hasAdjustableISORange: false,
            hasAdjustableShutterRange: false,
            supportsLockedFocus: false,
            supportsCustomLensPosition: false
        )
    }
}
