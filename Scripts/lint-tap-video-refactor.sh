#!/usr/bin/env bash

set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
configuration_path="$repository_root/.swiftlint-tap-video.yml"

if ! command -v swiftlint >/dev/null 2>&1; then
    echo "error: swiftlint is required to run the TAP Video refactor gate" >&2
    exit 127
fi

# Keep this allowlist explicit. It covers the scoped TAP Video production
# structure gate without expanding into unrelated
# legacy code. Tests, UI tests, Debug fixtures, benchmarks, and resolved remote
# package sources are intentionally outside this structural gate.
production_files=(
    "TAPCamDemo/CameraCapture/Output/TAPBMFFStreamingFile.swift"
    "TAPCamDemo/CameraCapture/Output/TAPDepthFrameCodec.swift"
    "TAPCamDemo/CameraCapture/Output/TAPDepthKLV.swift"
    "TAPCamDemo/CameraCapture/Output/TAPDepthInlineCalibration.swift"
    "TAPCamDemo/CameraCapture/Output/TAPMediaTrackFacts.swift"
    "TAPCamDemo/CameraCapture/Output/TAPMediaTrackFactsReader.swift"
    "TAPCamDemo/CameraCapture/Output/TAPVideoCaptureTelemetry.swift"
    "TAPCamDemo/CameraCapture/Output/TAPVideoManifestBox.swift"
    "TAPCamDemo/CameraCapture/Output/TAPVideoManifestSchema.swift"
    "TAPCamDemo/CameraCapture/Runtime/TAPVideoDepthMetadataEncoder.swift"
    "TAPCamDemo/CameraCapture/Runtime/TAPVideoManifestAssembler.swift"
    "TAPCamDemo/CameraCapture/Runtime/TAPVideoMotionRecorder.swift"
    "TAPCamDemo/CameraCapture/Runtime/TAPVideoRecorder.swift"
    "TAPCamDemo/CameraCapture/Runtime/TAPVideoRecorderCaptureCallbacks.swift"
    "TAPCamDemo/CameraCapture/Runtime/TAPVideoRecorderDiagnostics.swift"
    "TAPCamDemo/CameraCapture/Runtime/TAPVideoRecordingMetrics.swift"
    "TAPCamDemo/CameraCapture/Runtime/TAPVideoSpatialRegistrationAssembler.swift"
    "TAPCamDemo/CameraCapture/Runtime/TAPVideoWriterSession.swift"
    "TAPCamDemo/CameraCapture/UI/ViewModel/CameraViewModel+VideoCapture.swift"
    "TAPCamDemo/TAPLibrary/Viewer/Photo/AnalysisPhotoSlot+Analysis.swift"
    "TAPCamDemo/TAPLibrary/Viewer/Photo/AnalysisPhotoSlot+DisplayFetch.swift"
    "TAPCamDemo/TAPLibrary/Viewer/Photo/AnalysisPhotoSlot+Selection.swift"
    "TAPCamDemo/TAPLibrary/Viewer/Photo/AnalysisPhotoSlot.swift"
    "TAPCamDemo/TAPLibrary/Grid/TAPLibraryView.swift"
    "TAPCamDemo/TAPLibrary/Grid/TAPLibraryViewModel.swift"
    "TAPCamDemo/TAPLibrary/Grid/TAPLibraryRouteAdapter.swift"
    "TAPCamDemo/TAPLibrary/Media/Thumbnails/LibraryThumbnailPipeline.swift"
    "TAPCamDemo/TAPLibrary/Viewer/Photo/DepthAnalysisCarouselState.swift"
    "TAPCamDemo/DepthAnalysis/Video/TAPDepthFrameDecoder.swift"
    "TAPCamDemo/DepthAnalysis/Video/TAPDepthFrameRenderer.swift"
    "TAPCamDemo/DepthAnalysis/Video/TAPVideoDepthDecodeAdmission.swift"
    "TAPCamDemo/DepthAnalysis/Video/TAPVideoDepthDisplayOrientation.swift"
    "TAPCamDemo/DepthAnalysis/Video/TAPVideoDepthFrameCache.swift"
    "TAPCamDemo/DepthAnalysis/Video/TAPVideoDepthMetadataDecodeWorker.swift"
    "TAPCamDemo/DepthAnalysis/Video/TAPVideoDepthMetadataOutput.swift"
    "TAPCamDemo/DepthAnalysis/Video/TAPVideoDepthMetadataReader.swift"
    "TAPCamDemo/DepthAnalysis/Video/TAPVideoDepthOverlay.swift"
    "TAPCamDemo/DepthAnalysis/Video/TAPVideoDepthPipeline.swift"
    "TAPCamDemo/DepthAnalysis/Video/TAPVideoDepthRegistration.swift"
    "TAPCamDemo/DepthAnalysis/Video/TAPVideoPointCloudPlayback.swift"
    "TAPCamDemo/DepthAnalysis/Video/TAPVideoPointCloudProjection.swift"
    "TAPCamDemo/DepthAnalysis/Video/TAPVideoPointCloudView.swift"
    "TAPCamDemo/DepthAnalysis/Video/TAPVideoRegistrationProjection.swift"
    "TAPCamDemo/TAPLibrary/Viewer/Playback/TAPVideoPlaybackDeletion.swift"
    "TAPCamDemo/TAPLibrary/Viewer/Playback/TAPVideoPlaybackFetchState.swift"
    "TAPCamDemo/TAPLibrary/Viewer/Playback/TAPVideoPlaybackPlayerLifecycle.swift"
    "TAPCamDemo/TAPLibrary/Viewer/Playback/TAPVideoPlaybackResourceLoader.swift"
    "TAPCamDemo/TAPLibrary/Viewer/Playback/TAPVideoPlaybackRoute.swift"
    "TAPCamDemo/TAPLibrary/Viewer/Playback/TAPVideoPlaybackScreen.swift"
    "TAPCamDemo/TAPLibrary/Viewer/Playback/TAPVideoPlaybackSession.swift"
    "TAPCamDemo/TAPLibrary/Viewer/Playback/TAPVideoPlaybackTransportModel.swift"
    "TAPCamDemo/TAPLibrary/Viewer/Playback/TAPVideoPlaybackTransportView.swift"
    "TAPCamDemo/TAPLibrary/Viewer/Playback/TAPVideoPlayerSurface.swift"
    "TAPCamDemo/TAPLibrary/Viewer/Playback/TAPVideoPlayerSurfaceUIView.swift"
    "TAPCamDemo/TAPLibrary/Viewer/Playback/TAPVideoViewerChrome.swift"
    "TAPCamDemo/TAPLibrary/Grid/TAPLibraryItemCell.swift"
    "TAPCamDemo/TAPLibrary/Viewer/Photo/DepthAnalysisView.swift"
    "TAPCamDemo/TAPLibrary/Media/LibraryMediaFetching.swift"
    "TAPCamDemo/TAPLibrary/Viewer/Presentation/LibraryMediaCopy.swift"
    "TAPCamDemo/TAPLibrary/Media/Thumbnails/LibraryVideoPosterService.swift"
    "TAPCamDemo/TAPLibrary/Media/PhotoKit/PhotoKitImageRequest.swift"
    "TAPCamDemo/TAPLibrary/Media/PhotoKit/PhotoKitLibraryMediaFetcher.swift"
    "TAPCamDemo/TAPLibrary/Media/PhotoKit/PhotoKitLivePhotoRequest.swift"
    "TAPCamDemo/TAPLibrary/Media/PhotoKit/PhotoKitMediaFetchFailure.swift"
    "TAPCamDemo/TAPLibrary/Media/PhotoKit/PhotoKitRequestLifecycle.swift"
    "TAPCamDemo/TAPLibrary/Media/PhotoKit/PhotoKitResourceRequest.swift"
    "TAPCamDemo/PendingCaptureQueue/Processing/AppAttestPendingCaptureSigner.swift"
    "TAPCamDemo/PendingCaptureQueue/Processing/PhotoLibraryPendingCaptureExporter.swift"
    "TAPCamDemo/TAPLibrary/Catalog/TAPLibraryNotifications.swift"
    "TAPCamDemo/PendingCaptureQueue/Ingest/TAPPendingCaptureArtifacts.swift"
    "TAPCamDemo/PendingCaptureQueue/Processing/TAPPendingCaptureProcessingSteps.swift"
    "TAPCamDemo/PendingCaptureQueue/Processing/TAPPendingCaptureProcessor.swift"
    "TAPCamDemo/PendingCaptureQueue/Storage/TAPPendingCaptureStore.swift"
    "TAPCamDemo/PendingCaptureQueue/Ingest/TAPPendingVideoIngestValidator.swift"
    "TAPCamDemo/PendingCaptureQueue/Storage/TAPPendingVideoRecordTransitions.swift"
    "TAPCamDemo/PendingCaptureQueue/Ingest/TAPPendingVideoWorkspaceCoordinator.swift"
    "TAPCamDemo/PendingCaptureQueue/Processing/TAPVideoPhotosReadbackValidator.swift"
    "TAPCamDemo/Diagnostics/TAPVideoPerformanceTrace.swift"
)

missing_files=()
for relative_path in "${production_files[@]}"; do
    if [[ ! -f "$repository_root/$relative_path" ]]; then
        missing_files+=("$relative_path")
    fi
done

if (( ${#missing_files[@]} > 0 )); then
    printf 'error: TAP Video lint scope references a missing production file: %s\n' \
        "${missing_files[@]}" >&2
    exit 2
fi

cd "$repository_root"
swiftlint lint \
    --config "$configuration_path" \
    --strict \
    --no-cache \
    --force-exclude \
    --quiet \
    "${production_files[@]}"
