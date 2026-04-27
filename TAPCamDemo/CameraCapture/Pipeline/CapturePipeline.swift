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
    static let defaultMaximumPendingJobs = 3

    private var pendingJobCount = 0
    private let maximumPendingJobs: Int

    init(maximumPendingJobs: Int = CaptureJobQueue.defaultMaximumPendingJobs) {
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
    private let photoDepthProvider: any SingleCamPhotoCaptureProvider
    private let packager: any CapturePackager
    private let writer: any CaptureArtifactWriter
    private let metricsStore: MetricsStore

    init(
        photoDepthProvider: any SingleCamPhotoCaptureProvider,
        packager: any CapturePackager = EmbeddedPhotoPackager(),
        writer: any CaptureArtifactWriter = PhotoLibraryCaptureArtifactWriter(),
        metricsStore: MetricsStore
    ) {
        self.photoDepthProvider = photoDepthProvider
        self.packager = packager
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
        var writeDuration: TimeInterval?

        do {
            let captureStart = Date()
            let captureResult = try await photoDepthProvider.capturePhotoDepth(job: job, context: context)
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

            let writeStart = Date()
            let writeResult = try await writer.write(artifact)
            writeDuration = Date().timeIntervalSince(writeStart)

            await metricsStore.record(metrics(
                id: job.id,
                context: context,
                captureDuration: captureDuration,
                packageBuildDuration: packageBuildDuration,
                packagingDuration: packagingDuration,
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
                packageBuildDuration: packageBuildDuration,
                packagingDuration: packagingDuration,
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
        packageBuildDuration: TimeInterval?,
        packagingDuration: TimeInterval?,
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
            packageBuildDuration: packageBuildDuration,
            packagingDuration: packagingDuration,
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
