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
    "TAPCamDemo/CameraCapture/Output/TAPVideoContainerValidator.swift"
    "TAPCamDemo/CameraCapture/Output/TAPVideoCaptureTelemetry.swift"
    "TAPCamDemo/CameraCapture/Output/TAPVideoDepthSampleValidator.swift"
    "TAPCamDemo/CameraCapture/Output/TAPVideoDepthTimelineValidator.swift"
    "TAPCamDemo/CameraCapture/Output/TAPVideoDepthTrackValidator.swift"
    "TAPCamDemo/CameraCapture/Output/TAPVideoDepthValidationContract.swift"
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
    "TAPCamDemo/CameraCapture/UI/CameraViewModel+VideoCapture.swift"
    "TAPCamDemo/Viewer/Photo/AnalysisPhotoSlot+Analysis.swift"
    "TAPCamDemo/Viewer/Photo/AnalysisPhotoSlot+DisplayFetch.swift"
    "TAPCamDemo/Viewer/Photo/AnalysisPhotoSlot+Selection.swift"
    "TAPCamDemo/Viewer/Photo/AnalysisPhotoSlot.swift"
    "TAPCamDemo/Viewer/Library/DepthAlbumPickerView.swift"
    "TAPCamDemo/Viewer/Library/DepthAlbumPickerViewModel.swift"
    "TAPCamDemo/Viewer/Library/DepthAlbumRouteAdapter.swift"
    "TAPCamDemo/MediaLibrary/DepthAlbumThumbnailPipeline.swift"
    "TAPCamDemo/Viewer/Photo/DepthAnalysisCarouselState.swift"
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
    "TAPCamDemo/DepthAnalysis/Video/TAPVideoPointCloudHistory.swift"
    "TAPCamDemo/DepthAnalysis/Video/TAPVideoPointCloudMotion.swift"
    "TAPCamDemo/DepthAnalysis/Video/TAPVideoPointCloudProjection.swift"
    "TAPCamDemo/DepthAnalysis/Video/TAPVideoPointCloudRegistration.swift"
    "TAPCamDemo/DepthAnalysis/Video/TAPVideoPointCloudView.swift"
    "TAPCamDemo/DepthAnalysis/Video/TAPVideoRegistrationProjection.swift"
    "TAPCamDemo/Viewer/Playback/TAPVideoPlaybackDeletion.swift"
    "TAPCamDemo/Viewer/Playback/TAPVideoPlaybackFetchState.swift"
    "TAPCamDemo/Viewer/Playback/TAPVideoPlaybackPlayerLifecycle.swift"
    "TAPCamDemo/Viewer/Playback/TAPVideoPlaybackResourceLoader.swift"
    "TAPCamDemo/Viewer/Playback/TAPVideoPlaybackRoute.swift"
    "TAPCamDemo/Viewer/Playback/TAPVideoPlaybackScreen.swift"
    "TAPCamDemo/Viewer/Playback/TAPVideoPlaybackSession.swift"
    "TAPCamDemo/Viewer/Playback/TAPVideoPlaybackTransportModel.swift"
    "TAPCamDemo/Viewer/Playback/TAPVideoPlaybackTransportView.swift"
    "TAPCamDemo/Viewer/Playback/TAPVideoPlayerSurface.swift"
    "TAPCamDemo/Viewer/Playback/TAPVideoPlayerSurfaceUIView.swift"
    "TAPCamDemo/Viewer/Playback/TAPVideoViewerChrome.swift"
    "TAPCamDemo/Viewer/Library/TAPLibraryItemCell.swift"
    "TAPCamDemo/Viewer/Playback/TAPVideoDepthPlaybackView.swift"
    "TAPCamDemo/MediaLibrary/LibraryMediaFetching.swift"
    "TAPCamDemo/Viewer/Presentation/LibraryMediaCopy.swift"
    "TAPCamDemo/MediaLibrary/LibraryVideoPosterService.swift"
    "TAPCamDemo/MediaLibrary/PhotoKitImageRequest.swift"
    "TAPCamDemo/MediaLibrary/PhotoKitLibraryMediaFetcher.swift"
    "TAPCamDemo/MediaLibrary/PhotoKitLivePhotoRequest.swift"
    "TAPCamDemo/MediaLibrary/PhotoKitMediaFetchFailure.swift"
    "TAPCamDemo/MediaLibrary/PhotoKitRequestLifecycle.swift"
    "TAPCamDemo/MediaLibrary/PhotoKitResourceRequest.swift"
    "TAPCamDemo/TAPLibrary/AppAttestPendingCaptureSigner.swift"
    "TAPCamDemo/TAPLibrary/PhotoLibraryPendingCaptureExporter.swift"
    "TAPCamDemo/TAPLibrary/TAPLibraryNotifications.swift"
    "TAPCamDemo/TAPLibrary/TAPPendingCaptureArtifacts.swift"
    "TAPCamDemo/TAPLibrary/TAPPendingCaptureOperations.swift"
    "TAPCamDemo/TAPLibrary/TAPPendingCaptureProcessor.swift"
    "TAPCamDemo/TAPLibrary/TAPPendingCaptureStore.swift"
    "TAPCamDemo/TAPLibrary/TAPPendingVideoIngestValidator.swift"
    "TAPCamDemo/TAPLibrary/TAPPendingVideoRecordTransitions.swift"
    "TAPCamDemo/TAPLibrary/TAPPendingVideoWorkspaceCoordinator.swift"
    "TAPCamDemo/TAPLibrary/TAPVideoPhotosReadbackValidator.swift"
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
