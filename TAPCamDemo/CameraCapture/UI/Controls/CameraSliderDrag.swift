import Foundation

/// One touch's presentation state. Values are normalized; capture modes and
/// device writes remain owned by the existing adjustment callbacks.
nonisolated struct CameraSliderDrag {
    static let autoEntryDistance = 22.0
    static let autoExitDistance = 6.0
    static let slowSpeed = 180.0 // points per second
    static let steadyInterval = 0.07
    static let catchUpThreshold = 0.08
    static let catchUpRate = 4.0 // full manual ranges per second

    let id = UUID()
    var isTouching = true
    private(set) var isAutomatic: Bool
    private(set) var pointerX = 0.0
    private(set) var target = 0.0
    private(set) var applied: Double?
    private var speed = 0.0
    private var sampleTime = 0.0
    private var slowSince: Double?
    private var isCatchingUp = false
    private var automaticTarget: Double?

    init(isAutomatic: Bool) {
        self.isAutomatic = isAutomatic
    }

    mutating func move(x: Double, width: Double, velocity: Double, time: Double, hasAuto: Bool) {
        guard x.isFinite, width.isFinite, width > 0, time.isFinite else { return }
        pointerX = x
        let pointerTarget = min(max(x / width, 0), 1)
        speed = velocity.isFinite ? abs(velocity) : .infinity
        sampleTime = time
        if speed > Self.slowSpeed {
            slowSince = nil
        } else if slowSince == nil {
            slowSince = time
        }
        if hasAuto {
            if isAutomatic, x <= width + Self.autoExitDistance {
                isAutomatic = false
                applied = nil
                automaticTarget = nil
            } else if !isAutomatic, x >= width + Self.autoEntryDistance {
                isAutomatic = true
                applied = nil
            }
        }
        target = automaticTarget ?? pointerTarget
    }

    mutating func beginManual(at position: Double) {
        guard position.isFinite else { return }
        applied = min(max(position, 0), 1)
        isCatchingUp = false
    }

    mutating func approachAutomatic(from position: Double, to destination: Double) {
        guard isAutomatic, position.isFinite, destination.isFinite else { return }
        target = min(max(destination, 0), 1)
        automaticTarget = target
        beginManual(at: position)
        isCatchingUp = true
    }

    mutating func finishAutomatic() {
        automaticTarget = nil
        applied = nil
    }

    /// Fast sweeps only move the cursor. A quiet finger also counts as settled,
    /// since DragGesture produces no further events while it is stationary.
    mutating func advance(
        at time: Double, elapsed: Double, smoothsChanges: Bool, riskEV: Double = 0
    ) -> Double? {
        guard !isAutomatic || automaticTarget != nil, let applied else { return nil }
        let risk = riskEV.isFinite ? min(max(riskEV, 0), 4) : 0
        let steadyInterval = Self.steadyInterval + risk * 0.04
        if smoothsChanges, isTouching, !isAutomatic {
            let isQuiet = time - sampleTime >= steadyInterval
            let isSlow = speed <= Self.slowSpeed
                && slowSince.map { time - $0 >= steadyInterval } == true
            guard isQuiet || isSlow else { return nil }
        }
        let distance = target - applied
        guard distance != 0 else { return nil }
        let next: Double
        if smoothsChanges, abs(distance) > Self.catchUpThreshold || isCatchingUp || risk > 0 {
            let travel = max(0, min(elapsed, 0.05)) * Self.catchUpRate / (1 + risk)
            guard travel > 0 else { return nil }
            next = abs(distance) <= travel ? target : applied + (distance > 0 ? travel : -travel)
            isCatchingUp = next != target
        } else {
            next = target
        }
        self.applied = next
        return next
    }

    var hasReachedTarget: Bool { applied == target }

    static func crossedTick(
        from previous: Double, to position: Double, intervals: Int, zeroPosition: Double? = nil
    ) -> Double? {
        guard intervals > 0, previous != position else { return nil }
        if let zeroPosition,
           (previous < zeroPosition && position >= zeroPosition)
            || (previous > zeroPosition && position <= zeroPosition) {
            return zeroPosition
        }
        let count = Double(intervals)
        let index = position > previous ? floor(position * count) : ceil(position * count)
        let tick = index / count
        guard (position > previous && tick > previous) || (position < previous && tick < previous) else {
            return nil
        }
        return tick
    }

    func cursorX(width: Double) -> Double {
        guard pointerX > width else { return max(pointerX, 0) }
        // Compress travel beyond the manual limit before the Auto detent snaps.
        let extra = pointerX - width
        return width + extra / (1 + extra / Self.autoEntryDistance)
    }
}
