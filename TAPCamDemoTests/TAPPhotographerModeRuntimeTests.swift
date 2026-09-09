//
//  TAPPhotographerModeRuntimeTests.swift
//  TAPCamDemoTests
//

import Foundation
import Testing
@testable import TAPCamDemo

struct TAPPhotographerModeRuntimeTests {
    @Test func photographerModeRequiresTheCompleteLiDARManualControlContract() {
        #expect(PhotographerModeAvailability.resolve(eligibleFacts()) == .available)

        #expect(PhotographerModeAvailability.resolve(
            eligibleFacts(isRearLiDARDevice: false)
        ) == .unavailable(.rearLiDARUnavailable))
        #expect(PhotographerModeAvailability.resolve(
            eligibleFacts(hasOneXDepthFormat: false)
        ) == .unavailable(.oneXDepthFormatUnavailable))
        #expect(PhotographerModeAvailability.resolve(
            eligibleFacts(supportsPhotoDepthDelivery: false)
        ) == .unavailable(.photoDepthDeliveryUnavailable))
        #expect(PhotographerModeAvailability.resolve(
            eligibleFacts(supportsCustomExposure: false)
        ) == .unavailable(.customExposureUnavailable))
        #expect(PhotographerModeAvailability.resolve(
            eligibleFacts(hasAdjustableISORange: false)
        ) == .unavailable(.customExposureUnavailable))
        #expect(PhotographerModeAvailability.resolve(
            eligibleFacts(hasAdjustableShutterRange: false)
        ) == .unavailable(.customExposureUnavailable))
        #expect(PhotographerModeAvailability.resolve(
            eligibleFacts(supportsLockedFocus: false)
        ) == .unavailable(.manualFocusUnavailable))
        #expect(PhotographerModeAvailability.resolve(
            eligibleFacts(supportsCustomLensPosition: false)
        ) == .unavailable(.manualFocusUnavailable))
    }

    @Test func photographerModeStateKeepsTransitionAndRecoveredModeExplicit() {
        #expect(PhotographerModeState.activating.isTransitioning)
        #expect(PhotographerModeState.deactivating.isTransitioning)
        #expect(!PhotographerModeState.standard.isTransitioning)
        #expect(!PhotographerModeState.active.isTransitioning)

        #expect(!PhotographerModeState.activating.isActive)
        #expect(PhotographerModeState.deactivating.isActive)
        #expect(PhotographerModeState.active.effectiveMode == .photographer)

        let recoveredStandard = PhotographerModeState.failed(
            recoveredMode: .standard,
            reason: .configurationFailed
        )
        let recoveredPhotographer = PhotographerModeState.failed(
            recoveredMode: .photographer,
            reason: .configurationFailed
        )
        #expect(!recoveredStandard.isActive)
        #expect(recoveredStandard.effectiveMode == .standard)
        #expect(!recoveredStandard.requiresStandardRecovery)
        #expect(recoveredPhotographer.isActive)
        #expect(recoveredPhotographer.effectiveMode == .photographer)
        #expect(!recoveredPhotographer.requiresStandardRecovery)

        let unrecovered = PhotographerModeState.failed(
            recoveredMode: .unconfigured,
            reason: .configurationFailed
        )
        #expect(!unrecovered.isActive)
        #expect(unrecovered.effectiveMode == .unconfigured)
        #expect(unrecovered.requiresStandardRecovery)
    }

    private func eligibleFacts(
        isRearLiDARDevice: Bool = true,
        hasOneXDepthFormat: Bool = true,
        supportsPhotoDepthDelivery: Bool = true,
        supportsCustomExposure: Bool = true,
        hasAdjustableISORange: Bool = true,
        hasAdjustableShutterRange: Bool = true,
        supportsLockedFocus: Bool = true,
        supportsCustomLensPosition: Bool = true
    ) -> PhotographerModeCapabilityFacts {
        PhotographerModeCapabilityFacts(
            isRearLiDARDevice: isRearLiDARDevice,
            hasOneXDepthFormat: hasOneXDepthFormat,
            supportsPhotoDepthDelivery: supportsPhotoDepthDelivery,
            supportsCustomExposure: supportsCustomExposure,
            hasAdjustableISORange: hasAdjustableISORange,
            hasAdjustableShutterRange: hasAdjustableShutterRange,
            supportsLockedFocus: supportsLockedFocus,
            supportsCustomLensPosition: supportsCustomLensPosition
        )
    }
}
