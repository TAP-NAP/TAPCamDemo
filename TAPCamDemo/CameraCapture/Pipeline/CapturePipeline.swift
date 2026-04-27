//
//  CapturePipeline.swift
//  TAPCamDemo
//
//  Created by Codex on 2026/4/27.
//

import Foundation

/// Backpressure gate for foreground shutter taps.
///
/// Preview remains live while jobs are packaging and writing in the background,
/// but the queue refuses new work when too many captures are pending. This keeps
/// memory pressure bounded without blocking the viewfinder for every write.
actor CaptureJobQueue {
    private var pendingJobCount = 0
    private let maximumPendingJobs: Int

    init(maximumPendingJobs: Int = 3) {
        self.maximumPendingJobs = maximumPendingJobs
    }

    func beginJob() throws -> Int {
        guard pendingJobCount < maximumPendingJobs else {
            throw TAPDepthCaptureError.captureBackpressureLimitReached
        }
        pendingJobCount += 1
        return pendingJobCount
    }

    func finishJob() -> Int {
        pendingJobCount = max(0, pendingJobCount - 1)
        return pendingJobCount
    }

    func pendingCount() -> Int {
        pendingJobCount
    }
}

/// Coordinates SingleCam capture, logical package build, physical packaging,
/// hook processing, writing, and diagnostics.
///
/// The pipeline owns orchestration only. It does not mutate AVFoundation session
/// configuration; the active `SessionConfigurationResult` must already exist
/// before a job reaches this type.
nonisolated final class CapturePipeline: @unchecked Sendable {
    private let registry: CaptureSourceRegistry
    private let packager: any CapturePackager
    private let hookPipeline: ArtifactHookPipeline
    private let writer: any CaptureArtifactWriter
    private let metricsStore: MetricsStore

    init(
        registry: CaptureSourceRegistry,
        packager: any CapturePackager = EmbeddedPhotoPackager(),
        hookPipeline: ArtifactHookPipeline = ArtifactHookPipeline(),
        writer: any CaptureArtifactWriter = PhotoLibraryCaptureArtifactWriter(),
        metricsStore: MetricsStore
    ) {
        self.registry = registry
        self.packager = packager
        self.hookPipeline = hookPipeline
        self.writer = writer
        self.metricsStore = metricsStore
    }

    func runSingleCamJob(
        job: CaptureJob,
        context: CaptureSourceContext,
        pendingJobCount: Int,
        queueWaitDuration: TimeInterval?
    ) async -> Result<CaptureWriteResult, Error> {
        let totalStart = Date()
        var captureDuration: TimeInterval?
        var packageBuildDuration: TimeInterval?
        var packagingDuration: TimeInterval?
        var hookPipelineDuration: TimeInterval?
        var writeDuration: TimeInterval?

        do {
            let captureStart = Date()
            let captureResult = try await registry.singleCamPhotoProvider.capturePhotoDepth(job: job, context: context)
            captureDuration = Date().timeIntervalSince(captureStart)

            let packageBuildStart = Date()
            let capturePackage = try CapturePackageBuilder.makePackage(
                job: job,
                context: context,
                captureResult: captureResult
            )
            packageBuildDuration = Date().timeIntervalSince(packageBuildStart)

            let packagingStart = Date()
            let artifact = try await packager.package(capturePackage)
            packagingDuration = Date().timeIntervalSince(packagingStart)

            let hooksStart = Date()
            let processedArtifact = try await hookPipeline.process(artifact)
            hookPipelineDuration = Date().timeIntervalSince(hooksStart)

            let writeStart = Date()
            let writeResult = try await writer.write(processedArtifact)
            writeDuration = Date().timeIntervalSince(writeStart)

            await metricsStore.record(metrics(
                id: job.id,
                context: context,
                captureDuration: captureDuration,
                rgbCaptureDuration: captureDuration,
                depthCaptureDuration: captureDuration,
                rawCaptureDuration: nil,
                packageBuildDuration: packageBuildDuration,
                packagingDuration: packagingDuration,
                hookPipelineDuration: hookPipelineDuration,
                writeDuration: writeDuration,
                totalDuration: Date().timeIntervalSince(totalStart),
                queueWaitDuration: queueWaitDuration,
                pendingJobCount: pendingJobCount,
                status: .succeeded,
                failureReason: nil
            ))

            return .success(writeResult)
        } catch {
            await metricsStore.record(metrics(
                id: job.id,
                context: context,
                captureDuration: captureDuration,
                rgbCaptureDuration: captureDuration,
                depthCaptureDuration: captureDuration,
                rawCaptureDuration: nil,
                packageBuildDuration: packageBuildDuration,
                packagingDuration: packagingDuration,
                hookPipelineDuration: hookPipelineDuration,
                writeDuration: writeDuration,
                totalDuration: Date().timeIntervalSince(totalStart),
                queueWaitDuration: queueWaitDuration,
                pendingJobCount: pendingJobCount,
                status: .failed,
                failureReason: error.localizedDescription
            ))

            return .failure(error)
        }
    }

    private func metrics(
        id: UUID,
        context: CaptureSourceContext,
        captureDuration: TimeInterval?,
        rgbCaptureDuration: TimeInterval?,
        depthCaptureDuration: TimeInterval?,
        rawCaptureDuration: TimeInterval?,
        packageBuildDuration: TimeInterval?,
        packagingDuration: TimeInterval?,
        hookPipelineDuration: TimeInterval?,
        writeDuration: TimeInterval?,
        totalDuration: TimeInterval,
        queueWaitDuration: TimeInterval?,
        pendingJobCount: Int,
        status: CaptureJobStatus,
        failureReason: String?
    ) -> CaptureJobMetrics {
        let plan = context.sessionConfiguration.capturePlan
        return CaptureJobMetrics(
            id: id,
            captureDuration: captureDuration,
            rgbCaptureDuration: rgbCaptureDuration,
            depthCaptureDuration: depthCaptureDuration,
            rawCaptureDuration: rawCaptureDuration,
            packageBuildDuration: packageBuildDuration,
            packagingDuration: packagingDuration,
            hookPipelineDuration: hookPipelineDuration,
            writeDuration: writeDuration,
            totalDuration: totalDuration,
            queueWaitDuration: queueWaitDuration,
            pendingJobCount: pendingJobCount,
            status: status,
            failureReason: failureReason,
            pairingMode: plan.pairingMode.rawValue,
            selectedRGBSource: plan.rgbSource.displayName,
            selectedDepthSource: plan.depthSource?.displayName,
            currentZoomFactor: plan.zoom?.actualVideoZoomFactor,
            cropMode: plan.cropPolicy.mode,
            cropRectNormalized: plan.cropPolicy.cropRectNormalized
        )
    }
}
