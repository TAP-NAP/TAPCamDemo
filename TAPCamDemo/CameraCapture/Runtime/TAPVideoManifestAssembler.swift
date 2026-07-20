//
//  TAPVideoManifestAssembler.swift
//  TAPCamDemo
//

@preconcurrency import AVFoundation
import Foundation

/// Pure manifest assembly over an immutable request/configuration snapshot,
/// recording metrics, and postflight media facts.
nonisolated enum TAPVideoManifestAssembler {
    static func make(
        request: TAPVideoRecordingRequest,
        sessionConfiguration: SessionConfigurationResult,
        fileFacts: TAPMediaTrackFacts,
        metrics: TAPVideoRecordingMetrics,
        nominalDepthIntervalSeconds: Double?
    ) throws -> TAPVideoManifest {
        let cadenceThresholdSeconds = max(
            2 * (nominalDepthIntervalSeconds ?? 0),
            0.1
        )
        let depthCoverage = try makeDepthCoverage(
            fileFacts: fileFacts,
            metrics: metrics,
            cadenceThresholdSeconds: cadenceThresholdSeconds
        )
        let plan = sessionConfiguration.capturePlan
        return TAPVideoManifest(payload: TAPVideoManifest.Payload(
            id: request.captureID,
            packageID: request.packageID.uuidString,
            capturedAt: TAPDateFormatting.iso8601.string(from: request.capturedAt),
            selectedCameraPlan: TAPVideoManifest.SelectedCameraPlan(
                deviceUniqueID: sessionConfiguration.device.uniqueID,
                deviceType: sessionConfiguration.device.deviceType.rawValue,
                localizedName: sessionConfiguration.device.localizedName,
                position: sessionConfiguration.device.position.tapManifestValue,
                requestedFocalLengthLabel: plan.requestedFocalLengthLabel.label,
                resolvedFocalLengthLabel: sessionConfiguration.selectionContext
                    .selectedFocalLengthLabel,
                resolvedZoomFactor: plan.zoom?.rawVideoZoomFactor,
                depthCapable: sessionConfiguration.depthDeliverySupported
            ),
            container: TAPVideoManifest.Container(
                fileType: "mp4",
                mediaType: "video/mp4",
                durationSeconds: fileFacts.durationSeconds,
                timeScale: fileFacts.timeScale,
                trackCount: fileFacts.trackCount
            ),
            rgbTrack: TAPVideoManifest.RGBTrack(
                trackID: fileFacts.video.trackID,
                codec: fileFacts.video.codec,
                width: fileFacts.video.width,
                height: fileFacts.video.height,
                durationSeconds: fileFacts.video.timing.durationSeconds,
                timeScale: fileFacts.video.timing.timeScale,
                nominalFrameRate: fileFacts.video.nominalFrameRate,
                frameCount: metrics.videoFrameCount,
                transform: TAPVideoRecordingTransform.description(
                    metrics: metrics,
                    request: request
                )
            ),
            audioTrack: makeAudioTrack(
                fileFacts: fileFacts,
                requestedAudio: request.recordsAudio
            ),
            depthCoverage: depthCoverage,
            spatialRegistration: TAPVideoSpatialRegistrationAssembler.make(
                fileFacts: fileFacts,
                metrics: metrics,
                request: request
            ),
            synchronization: TAPVideoManifest.Synchronization(
                timing: "capture-output-presentation-timestamps",
                rgbToDepthMapping: metrics.depthSampleCount > 0
                    ? "independent-timed-metadata" : "no-depth-samples",
                maxObservedDeltaSeconds: metrics.maxObservedRGBDepthDeltaSeconds,
                maxObservedDepthIntervalSeconds: metrics.maxObservedDepthIntervalSeconds,
                nominalDepthIntervalSeconds: nominalDepthIntervalSeconds
            ),
            stop: TAPVideoManifest.Stop(
                reason: metrics.stopReason,
                recordedDurationSeconds: fileFacts.durationSeconds
            ),
            software: .current
        ))
    }

    private static func makeAudioTrack(
        fileFacts: TAPMediaTrackFacts,
        requestedAudio: Bool
    ) -> TAPVideoManifest.AudioTrack {
        let status: TAPVideoManifest.AudioStatus
        if fileFacts.audio != nil {
            status = .captured
        } else {
            status = requestedAudio ? .unavailable : .notCaptured
        }
        return TAPVideoManifest.AudioTrack(
            status: status,
            trackID: fileFacts.audio?.trackID,
            codec: fileFacts.audio?.codec,
            durationSeconds: fileFacts.audio?.timing.durationSeconds,
            timeScale: fileFacts.audio?.timing.timeScale,
            sampleRate: fileFacts.audio?.sampleRate,
            channelCount: fileFacts.audio?.channelCount
        )
    }

    private static func makeDepthCoverage(
        fileFacts: TAPMediaTrackFacts,
        metrics: TAPVideoRecordingMetrics,
        cadenceThresholdSeconds: Double
    ) throws -> TAPVideoManifest.DepthCoverage {
        let gaps = metrics.finalizedDepthGaps(
            videoDurationSeconds: fileFacts.video.timing.durationSeconds,
            cadenceThresholdSeconds: cadenceThresholdSeconds
        )
        guard metrics.depthSampleCount == 0 else {
            guard let metadata = fileFacts.metadata,
                  let codec = metadata.codec else {
                throw TAPDepthCaptureError.videoRecordingFailed(
                    "finished MP4 is missing stored depth metadata track facts"
                )
            }
            return TAPVideoManifest.DepthCoverage(
                trackID: metadata.trackID,
                trackCodec: codec,
                trackDurationSeconds: metadata.timing.durationSeconds,
                trackTimeScale: metadata.timing.timeScale,
                sampleCount: metrics.depthSampleCount,
                deliveredSampleCount: metrics.depthDeliveredSampleCount,
                outputDropCount: metrics.depthOutputDropCount,
                encodingDropCount: metrics.depthEncodingDropCount,
                metadataDropCount: metrics.depthMetadataDropCount,
                gaps: gaps,
                format: metrics.firstDepthFormat
            )
        }
        return TAPVideoManifest.DepthCoverage(
            trackID: nil,
            sampleCount: 0,
            deliveredSampleCount: metrics.depthDeliveredSampleCount,
            outputDropCount: metrics.depthOutputDropCount,
            encodingDropCount: metrics.depthEncodingDropCount,
            metadataDropCount: metrics.depthMetadataDropCount,
            gaps: gaps + noDepthGap(fileFacts: fileFacts, metrics: metrics),
            format: nil
        )
    }

    private static func noDepthGap(
        fileFacts: TAPMediaTrackFacts,
        metrics: TAPVideoRecordingMetrics
    ) -> [TAPVideoManifest.DepthGap] {
        guard let firstVideoTime = metrics.firstVideoTime,
              let videoEndTime = TAPVideoCaptureTimeline.absoluteMediaEndTime(
                origin: firstVideoTime,
                durationSeconds: fileFacts.video.timing.durationSeconds,
                lastSampleTime: metrics.lastVideoTime
              ),
              let gap = TAPVideoCaptureTimeline.depthGap(
                reason: .silentCadence,
                start: firstVideoTime,
                end: videoEndTime,
                relativeTo: firstVideoTime,
                nearestStartRGBFrame: metrics.videoFrameCount > 0 ? 0 : nil,
                nearestEndRGBFrame: metrics.videoFrameCount > 0
                    ? metrics.videoFrameCount - 1 : nil
              ) else {
            return []
        }
        return [gap]
    }
}
