//
//  CaptureSourceRegistry.swift
//  TAPCamDemo
//
//  Created by Codex on 2026/4/27.
//

import Foundation

/// Registry for capture providers used by the pipeline.
///
/// The default app registers only `AVFoundationSingleCamPhotoProvider`. The
/// explicit slots keep the future external-integration story honest: callers
/// can replace data producers without receiving arbitrary access to mutate the
/// managed AVFoundation session graph.
nonisolated struct CaptureSourceRegistry: Sendable {
    let singleCamPhotoProvider: any SingleCamPhotoCaptureProvider
    let rgbProvider: (any RGBCaptureProvider)?
    let depthProvider: (any DepthCaptureProvider)?
    let rawProvider: (any RawCaptureProvider)?

    nonisolated init(
        singleCamPhotoProvider: any SingleCamPhotoCaptureProvider,
        rgbProvider: (any RGBCaptureProvider)? = nil,
        depthProvider: (any DepthCaptureProvider)? = nil,
        rawProvider: (any RawCaptureProvider)? = nil
    ) {
        self.singleCamPhotoProvider = singleCamPhotoProvider
        self.rgbProvider = rgbProvider
        self.depthProvider = depthProvider
        self.rawProvider = rawProvider
    }
}

