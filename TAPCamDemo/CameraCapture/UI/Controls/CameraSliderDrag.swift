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

    init(isAutomatic: Bool) {
        self.isAutomatic = isAutomatic
    }

    mutating func move(x: Double, width: Double, velocity: Double, time: Double, hasAuto: Bool) {
        guard x.isFinite, width.isFinite, width > 0, time.isFinite else { return }
        pointerX = x
        target = min(max(x / width, 0), 1)
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
            } else if !isAutomatic, x >= width + Self.autoEntryDistance {
                isAutomatic = true
                applied = nil
            }
        }
    }

    mutating func beginManual(at position: Double) {
        guard position.isFinite else { return }
        applied = min(max(position, 0), 1)
        isCatchingUp = false
    }

    /// Fast sweeps only move the cursor. A quiet finger also counts as settled,
    /// since DragGesture produces no further events while it is stationary.
    mutating func advance(at time: Double, elapsed: Double, smoothsChanges: Bool) -> Double? {
        guard !isAutomatic, let applied else { return nil }
        if smoothsChanges, isTouching {
            let isQuiet = time - sampleTime >= Self.steadyInterval
            let isSlow = speed <= Self.slowSpeed
                && slowSince.map { time - $0 >= Self.steadyInterval } == true
            guard isQuiet || isSlow else { return nil }
        }
        let distance = target - applied
        guard distance != 0 else { return nil }
        let next: Double
        if smoothsChanges, abs(distance) > Self.catchUpThreshold || isCatchingUp {
            let travel = max(0, min(elapsed, 0.05)) * Self.catchUpRate
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

    var allowsTickFeedback: Bool { speed <= Self.slowSpeed && applied != nil }

    func cursorX(width: Double) -> Double {
        guard pointerX > width else { return max(pointerX, 0) }
        // Compress travel beyond the manual limit before the Auto detent snaps.
        let extra = pointerX - width
        return width + extra / (1 + extra / Self.autoEntryDistance)
    }
}
