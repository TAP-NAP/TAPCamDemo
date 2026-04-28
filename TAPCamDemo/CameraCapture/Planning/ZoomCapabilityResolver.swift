//
//  ZoomCapabilityResolver.swift
//  TAPCamDemo
//
//  Created by Codex on 2026/4/27.
//

@preconcurrency import AVFoundation
import CoreGraphics
import CoreMedia
import Darwin
import Foundation

/// Resolves zoom support for the current RGB-depth pairing.
///
/// The resolver consumes the active candidate format and returns profiles for
/// UI. It never calls `lockForConfiguration` or changes `videoZoomFactor`; those
/// mutations remain in `CaptureSessionController`.
nonisolated enum ZoomCapabilityResolver {
    /// Produces depth-safe zoom profiles for one planned RGB/depth pairing.
    ///
    /// Release FOV labels may request raw zoom values outside the fixed Debug
    /// chip list; `selectedZoomFactor` keeps those values alive for capture.
    ///
    /// - Tag: ResolveDepthSafeZoom
    static func resolve(
        rgbSource: CameraProfile,
        depthProfile: DepthProfile?,
        selectedZoomID: String?,
        selectedZoomFactor: Double? = nil
    ) -> ZoomCapability {
        let resolvedDevice = depthProfile?.resolvedDevice ?? rgbSource.device
        let videoFormat = depthProfile?.formatSelection?.videoFormat ?? resolvedDevice.activeFormat
        let depthRanges = depthProfile?.compatibility == .compatible
            ? videoFormat.supportedVideoZoomRangesForDepthDataDelivery.map { Double($0.lowerBound)...Double($0.upperBound) }
            : []
        let allowsOutsideDepthRanges = depthProfile?.compatibility == .compatible
            ? videoFormat.zoomFactorsOutsideOfVideoZoomRangesForDepthDeliverySupported
            : true
        let requiresDepthSafeZoom = depthProfile?.compatibility == .compatible
        let minimumZoom = Double(resolvedDevice.minAvailableVideoZoomFactor)
        let maximumZoom = Double(min(resolvedDevice.maxAvailableVideoZoomFactor, videoFormat.videoMaxZoomFactor))
        var profiles = CameraCapabilityResolver.makeZoomProfiles(
            minimumZoom: minimumZoom,
            maximumZoom: maximumZoom,
            depthDeliveryRanges: depthRanges,
            allowsZoomOutsideDepthDeliveryRanges: allowsOutsideDepthRanges,
            requiresDepthSafeZoom: requiresDepthSafeZoom
        )
        /*
         The fixed Debug zoom chips are 0.5/1/2/3x, but Release FOV labels may
         need a raw value outside that list. For example, if a depth-capable
         virtual format exposes 24mm at raw 2.0, then the semantic 48mm slot
         needs raw 4.0. Appending the selected factor here lets the plan carry
         the exact value through validation and into `CaptureSessionController`.
         */
        if let selectedZoomFactor,
           profiles.contains(where: { $0.matchesRawVideoZoomFactor(selectedZoomFactor) }) == false {
            profiles.append(
                CameraCapabilityResolver.makeZoomProfile(
                    zoom: selectedZoomFactor,
                    minimumZoom: minimumZoom,
                    maximumZoom: maximumZoom,
                    depthDeliveryRanges: depthRanges,
                    allowsZoomOutsideDepthDeliveryRanges: allowsOutsideDepthRanges,
                    requiresDepthSafeZoom: requiresDepthSafeZoom
                )
            )
            profiles.sort { $0.requestedZoomFactor < $1.requestedZoomFactor }
        }
        let selected = selectedZoomID.flatMap { id in profiles.first(where: { $0.id == id && $0.isEnabled }) }
            ?? selectedZoomFactor.flatMap { zoom in profiles.first(where: { $0.matchesRawVideoZoomFactor(zoom) && $0.isEnabled }) }
            ?? profiles.first(where: \.isEnabled)
        let recommendedRange = videoFormat.systemRecommendedVideoZoomRange.map { Double($0.lowerBound)...Double($0.upperBound) }
        let isContinuous = depthRanges.contains { $0.lowerBound != $0.upperBound }
        let isDiscrete = !depthRanges.isEmpty && depthRanges.allSatisfy { $0.lowerBound == $0.upperBound }

        return ZoomCapability(
            available: profiles.contains(where: \.isEnabled),
            currentZoomFactor: selected?.rawVideoZoomFactor,
            videoMaxZoomFactor: Double(videoFormat.videoMaxZoomFactor),
            minAvailableVideoZoomFactor: minimumZoom,
            maxAvailableVideoZoomFactor: maximumZoom,
            systemRecommendedVideoZoomRange: recommendedRange,
            supportedVideoZoomRangesForDepthDataDelivery: depthRanges,
            zoomFactorsOutsideOfVideoZoomRangesForDepthDeliverySupported: allowsOutsideDepthRanges,
            virtualDeviceSwitchOverVideoZoomFactors: resolvedDevice.virtualDeviceSwitchOverVideoZoomFactors.map(\.doubleValue),
            depthSafeZoomRanges: depthRanges,
            isContinuous: isContinuous,
            isDiscrete: isDiscrete,
            zoomProfiles: profiles
        )
    }
}
