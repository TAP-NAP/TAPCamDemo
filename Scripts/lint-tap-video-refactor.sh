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
    "TAPCamDemo/CameraCapture/Output/TAPMediaTrackFacts.swift"
    "TAPCamDemo/CameraCapture/Output/TAPMediaTrackFactsReader.swift"
    "TAPCamDemo/CameraCapture/Output/TAPVideoContainerValidator.swift"
    "TAPCamDemo/CameraCapture/Output/TAPVideoDepthSampleValidator.swift"
    "TAPCamDemo/CameraCapture/Output/TAPVideoDepthTimelineValidator.swift"
    "TAPCamDemo/CameraCapture/Output/TAPVideoDepthTrackValidator.swift"
    "TAPCamDemo/CameraCapture/Output/TAPVideoDepthValidationContract.swift"
    "TAPCamDemo/CameraCapture/Output/TAPVideoManifestBox.swift"
    "TAPCamDemo/CameraCapture/Output/TAPVideoManifestSchema.swift"
    "TAPCamDemo/CameraCapture/Runtime/TAPVideoDepthMetadataEncoder.swift"
    "TAPCamDemo/CameraCapture/Runtime/TAPVideoManifestAssembler.swift"
    "TAPCamDemo/CameraCapture/Runtime/TAPVideoRecorder.swift"
    "TAPCamDemo/CameraCapture/Runtime/TAPVideoRecorderCaptureCallbacks.swift"
    "TAPCamDemo/CameraCapture/Runtime/TAPVideoRecorderDiagnostics.swift"
    "TAPCamDemo/CameraCapture/Runtime/TAPVideoRecordingMetrics.swift"
    "TAPCamDemo/CameraCapture/Runtime/TAPVideoSpatialRegistrationAssembler.swift"
    "TAPCamDemo/CameraCapture/Runtime/TAPVideoWriterSession.swift"
    "TAPCamDemo/CameraCapture/UI/CameraViewModel+VideoCapture.swift"
    "TAPCamDemo/DepthAnalysis/AnalysisPhotoSlot+Analysis.swift"
    "TAPCamDemo/DepthAnalysis/AnalysisPhotoSlot+DisplayFetch.swift"
    "TAPCamDemo/DepthAnalysis/AnalysisPhotoSlot+Selection.swift"
    "TAPCamDemo/DepthAnalysis/AnalysisPhotoSlot.swift"
    "TAPCamDemo/DepthAnalysis/DepthAlbumPickerNavigationSupport.swift"
    "TAPCamDemo/DepthAnalysis/DepthAlbumPickerView.swift"
    "TAPCamDemo/DepthAnalysis/DepthAlbumPickerViewModel.swift"
    "TAPCamDemo/DepthAnalysis/DepthAlbumRouteAdapter.swift"
    "TAPCamDemo/DepthAnalysis/DepthAlbumThumbnailPipeline.swift"
    "TAPCamDemo/DepthAnalysis/DepthAnalysisCarouselState.swift"
    "TAPCamDemo/DepthAnalysis/Playback/Depth/TAPDepthFrameDecoder.swift"
    "TAPCamDemo/DepthAnalysis/Playback/Depth/TAPDepthFrameRenderer.swift"
    "TAPCamDemo/DepthAnalysis/Playback/Depth/TAPVideoDepthDecodeAdmission.swift"
    "TAPCamDemo/DepthAnalysis/Playback/Depth/TAPVideoDepthDisplayOrientation.swift"
    "TAPCamDemo/DepthAnalysis/Playback/Depth/TAPVideoDepthFrameCache.swift"
    "TAPCamDemo/DepthAnalysis/Playback/Depth/TAPVideoDepthMetadataDecodeWorker.swift"
    "TAPCamDemo/DepthAnalysis/Playback/Depth/TAPVideoDepthMetadataOutput.swift"
    "TAPCamDemo/DepthAnalysis/Playback/Depth/TAPVideoDepthMetadataReader.swift"
    "TAPCamDemo/DepthAnalysis/Playback/Depth/TAPVideoDepthOverlay.swift"
    "TAPCamDemo/DepthAnalysis/Playback/Depth/TAPVideoDepthPipeline.swift"
    "TAPCamDemo/DepthAnalysis/Playback/Depth/TAPVideoDepthRegistration.swift"
    "TAPCamDemo/DepthAnalysis/Playback/Depth/TAPVideoRegistrationProjection.swift"
    "TAPCamDemo/DepthAnalysis/Playback/TAPVideoPlaybackDeletion.swift"
    "TAPCamDemo/DepthAnalysis/Playback/TAPVideoPlaybackFetchState.swift"
    "TAPCamDemo/DepthAnalysis/Playback/TAPVideoPlaybackPlayerLifecycle.swift"
    "TAPCamDemo/DepthAnalysis/Playback/TAPVideoPlaybackResourceLoader.swift"
    "TAPCamDemo/DepthAnalysis/Playback/TAPVideoPlaybackRoute.swift"
    "TAPCamDemo/DepthAnalysis/Playback/TAPVideoPlaybackScreen.swift"
    "TAPCamDemo/DepthAnalysis/Playback/TAPVideoPlaybackSession.swift"
    "TAPCamDemo/DepthAnalysis/Playback/TAPVideoPlaybackTransportModel.swift"
    "TAPCamDemo/DepthAnalysis/Playback/TAPVideoPlaybackTransportView.swift"
    "TAPCamDemo/DepthAnalysis/Playback/TAPVideoPlayerSurface.swift"
    "TAPCamDemo/DepthAnalysis/Playback/TAPVideoPlayerSurfaceUIView.swift"
    "TAPCamDemo/DepthAnalysis/Playback/TAPVideoViewerChrome.swift"
    "TAPCamDemo/DepthAnalysis/TAPLibraryItemCell.swift"
    "TAPCamDemo/DepthAnalysis/TAPVideoDepthPlaybackView.swift"
    "TAPCamDemo/MediaLibrary/LibraryMediaFetching.swift"
    "TAPCamDemo/MediaLibrary/LibraryMediaCopy.swift"
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
    "TAPCamDemo/TAPLibrary/TAPPendingCaptureMaintenance.swift"
    "TAPCamDemo/TAPLibrary/TAPPendingCaptureOperations.swift"
    "TAPCamDemo/TAPLibrary/TAPPendingCaptureProcessor.swift"
    "TAPCamDemo/TAPLibrary/TAPPendingCaptureStore.swift"
    "TAPCamDemo/TAPLibrary/TAPPendingLockedCaptureImporter.swift"
    "TAPCamDemo/TAPLibrary/TAPPendingVideoIngestValidator.swift"
    "TAPCamDemo/TAPLibrary/TAPPendingVideoRecordTransitions.swift"
    "TAPCamDemo/TAPLibrary/TAPPendingVideoWorkspaceCoordinator.swift"
    "TAPCamDemo/TAPLibrary/TAPVideoPhotosReadbackValidator.swift"
    "TAPCamDemo/Support/TAPVideoPerformanceTrace.swift"
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
