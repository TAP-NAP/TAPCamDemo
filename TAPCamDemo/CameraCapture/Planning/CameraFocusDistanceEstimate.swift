//
//  CameraFocusDistanceEstimate.swift
//  TAPCamDemo
//

import Foundation

/// An approximate focus distance inferred from earlier AF/depth observations.
/// This is a lens-position reference, not a current target measurement.
nonisolated struct CameraFocusDistanceEstimate: Equatable, Sendable {
    nonisolated enum Basis: Equatable, Sendable {
        case nearObservation
        case interpolated
    }

    let meters: Double
    let basis: Basis

    /// The caller supplies the localized "about" prefix and meter unit.
    static func formattedMeters(_ meters: Double) -> String? {
        guard meters.isFinite, meters >= 0.000_000_001 else { return nil }
        let fractionalDigits: Int
        if meters >= 10 {
            fractionalDigits = 0
        } else if meters >= 1 {
            fractionalDigits = 1
        } else {
            fractionalDigits = Int(1 - floor(log10(meters)))
        }
        var value = String(
            format: "%.\(fractionalDigits)f",
            locale: Locale(identifier: "en_US_POSIX"),
            meters
        )
        if value.contains(".") {
            while value.hasSuffix("0") { value.removeLast() }
            if value.hasSuffix(".") { value.removeLast() }
        }
        return value
    }
}

/// A bounded reference learned from successful autofocus locks.
///
/// The caller must pair the selected region's valid absolute depth with settled
/// AF and its subsequent locked lens position. Raw actuator position alone does
/// not determine meters, including at 1.0. Nearby samples permit a rough local
/// interpolation in reciprocal distance; they are not an optical calibration.
nonisolated struct CameraFocusDistanceModel: Equatable, Sendable {
    nonisolated struct Context: Equatable, Sendable {
        let deviceID: String
        let controlSurfaceSignature: CameraManualControlCommandPlan.ControlSurfaceSignature
        /// Must change when the device, active format, zoom, or session changes.
        let generation: Int
    }

    nonisolated struct Observation: Codable, Equatable, Sendable {
        let lensPosition: Double
        /// Nil preserves a conflicting region until a new calibration replaces it.
        let meters: Double?
    }

    nonisolated struct Calibration: Codable, Equatable, Sendable {
        let deviceID: String
        let observations: [Observation]
    }

    private static let maximumObservations = 16
    private static let nearbyPositionTolerance = 0.005
    private static let maximumInterpolationSpan = 0.15
    private static let maximumInterpolationDistanceRatio = 3.0
    private static let minimumInterpolationDistanceRatio = 1.05
    private static let maximumNearbyDistanceRatio = 1.25

    private(set) var context: Context?
    private var observations: [Observation] = []

    var observationCount: Int { observations.count }

    /// Only device identity and observations persist. Runtime tokens never do.
    var calibration: Calibration? {
        guard let context, !context.deviceID.isEmpty,
              Self.areValidObservations(observations) else { return nil }
        return Calibration(deviceID: context.deviceID, observations: observations)
    }

    mutating func reset(context: Context?) {
        self.context = context
        observations.removeAll(keepingCapacity: true)
    }

    /// The caller uses this only for the same fixed PRO LiDAR 1x optical path.
    /// Rebinding to today's context permits Photo/Video reuse while late runtime
    /// callbacks still fail the full context comparison in record and estimate.
    @discardableResult
    mutating func restore(_ calibration: Calibration, context: Context) -> Bool {
        guard !context.deviceID.isEmpty, calibration.deviceID == context.deviceID,
              Self.areValidObservations(calibration.observations) else { return false }
        self.context = context
        observations = calibration.observations
        return true
    }

    /// Returns false for invalid, stale, or locally contradictory observations.
    @discardableResult
    mutating func recordAutofocusLock(
        lensPosition: Double,
        measuredTargetMeters: Double,
        context: Context
    ) -> Bool {
        guard self.context == context,
              Self.isValidPosition(lensPosition),
              measuredTargetMeters.isFinite, measuredTargetMeters > 0 else {
            return false
        }

        let nearby = observations.indices.filter {
            abs(observations[$0].lensPosition - lensPosition) <= Self.nearbyPositionTolerance
        }
        if nearby.contains(where: { observations[$0].meters == nil }) {
            return false
        }
        if let conflicting = nearby.first(where: {
            guard let meters = observations[$0].meters else { return true }
            return Self.distanceRatio(meters, measuredTargetMeters) > Self.maximumNearbyDistanceRatio
        }) {
            observations[conflicting] = Observation(
                lensPosition: observations[conflicting].lensPosition,
                meters: nil
            )
            return false
        }

        // Replace only a nearby observation, retaining the actual latest pair.
        if let nearest = nearby.min(by: {
            abs(observations[$0].lensPosition - lensPosition)
                < abs(observations[$1].lensPosition - lensPosition)
        }) {
            observations.remove(at: nearest)
        } else if observations.count == Self.maximumObservations {
            // Keep conflict markers: eviction must not silently trust that region.
            guard let oldestValid = observations.firstIndex(where: { $0.meters != nil }) else {
                return false
            }
            observations.remove(at: oldestValid)
        }
        observations.append(Observation(lensPosition: lensPosition, meters: measuredTargetMeters))
        return true
    }

    func estimate(lensPosition: Double, context: Context) -> CameraFocusDistanceEstimate? {
        guard self.context == context, Self.isValidPosition(lensPosition) else { return nil }
        let ordered = observations.sorted { $0.lensPosition < $1.lensPosition }
        let nearby = ordered.filter {
            abs($0.lensPosition - lensPosition) <= Self.nearbyPositionTolerance
        }
        guard !nearby.contains(where: { $0.meters == nil }) else { return nil }
        if let nearest = nearby.min(by: {
            abs($0.lensPosition - lensPosition) < abs($1.lensPosition - lensPosition)
        }), let meters = nearest.meters {
            return CameraFocusDistanceEstimate(meters: meters, basis: .nearObservation)
        }

        guard let lower = ordered.last(where: { $0.lensPosition < lensPosition }),
              let upper = ordered.first(where: { $0.lensPosition > lensPosition }),
              Self.canInterpolate(lower, upper),
              let lowerMeters = lower.meters, let upperMeters = upper.meters else {
            return nil
        }

        let fraction = (lensPosition - lower.lensPosition) / (upper.lensPosition - lower.lensPosition)
        let reciprocalMeters = (1 - fraction) / lowerMeters + fraction / upperMeters
        let meters = 1 / reciprocalMeters
        guard meters.isFinite, meters > 0 else { return nil }
        return CameraFocusDistanceEstimate(meters: meters, basis: .interpolated)
    }

    private static func canInterpolate(_ lower: Observation, _ upper: Observation) -> Bool {
        guard let lowerMeters = lower.meters, let upperMeters = upper.meters else { return false }
        let positionSpan = upper.lensPosition - lower.lensPosition
        let distanceRatio = upperMeters / lowerMeters
        // A flat or reversed pair is not evidence for a distance curve.
        return positionSpan > 0 && positionSpan <= maximumInterpolationSpan
            && distanceRatio >= minimumInterpolationDistanceRatio
            && distanceRatio <= maximumInterpolationDistanceRatio
    }

    private static func areValidObservations(_ values: [Observation]) -> Bool {
        guard !values.isEmpty, values.count <= maximumObservations,
              values.allSatisfy({
                  isValidPosition($0.lensPosition)
                      && ($0.meters.map { $0.isFinite && $0 > 0 } ?? true)
              }) else { return false }
        for index in values.indices {
            for other in values[..<index] {
                let positionGap = abs(values[index].lensPosition - other.lensPosition)
                guard positionGap > 0 else { return false }
                if positionGap <= nearbyPositionTolerance,
                   let meters = values[index].meters, let otherMeters = other.meters,
                   distanceRatio(meters, otherMeters) > maximumNearbyDistanceRatio {
                    return false
                }
            }
        }
        return true
    }

    private static func isValidPosition(_ value: Double) -> Bool {
        value.isFinite && (0...1).contains(value)
    }

    private static func distanceRatio(_ first: Double, _ second: Double) -> Double {
        max(first, second) / min(first, second)
    }
}

/// Stores one most-recent physical LiDAR device's fixed PRO 1x calibration.
nonisolated enum CameraFocusDistancePreferences {
    static let storageKey = "CameraFocusDistanceCalibration.v1"

    static func load(
        context: CameraFocusDistanceModel.Context,
        in userDefaults: UserDefaults = .standard
    ) -> CameraFocusDistanceModel? {
        guard let data = userDefaults.data(forKey: storageKey), data.count <= 16_384,
              let calibration = try? JSONDecoder().decode(CameraFocusDistanceModel.Calibration.self, from: data) else {
            return nil
        }
        var model = CameraFocusDistanceModel()
        return model.restore(calibration, context: context) ? model : nil
    }

    @discardableResult
    static func save(_ model: CameraFocusDistanceModel, in userDefaults: UserDefaults = .standard) -> Bool {
        guard let calibration = model.calibration,
              let data = try? JSONEncoder().encode(calibration), data.count <= 16_384 else { return false }
        userDefaults.set(data, forKey: storageKey)
        return true
    }
}
