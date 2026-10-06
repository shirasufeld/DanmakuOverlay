import Foundation

/// Recovers sub-second playback position from a player that only reports whole seconds (VLC's AppleScript).
///
/// While playing at rate `r`, position = (host − c) · r for an unknown phase `c`. A sample reporting `n` whole
/// seconds at host time `h` bounds `c` to an interval; intersecting the intervals of successive samples narrows
/// `c` to roughly the polling interval as soon as a second boundary is observed.
public struct TickPhaseEstimator: Sendable {
    /// `false`: the player truncates (n = ⌊p⌋); `true`: it rounds (n = round(p)).
    public var rounds: Bool
    public private(set) var rate: Double
    private var lower = -Double.infinity
    private var upper = Double.infinity

    public init(rate: Double = 1, rounds: Bool = false) {
        self.rate = rate
        self.rounds = rounds
    }

    public var isLocked: Bool { upper - lower < 0.2 / max(rate, 0.01) }

    public mutating func reset(rate: Double? = nil) {
        if let rate { self.rate = rate }
        lower = -.infinity
        upper = .infinity
    }

    /// Adds a sample and returns the estimated position at `hostTime`.
    /// - Parameter uncertainty: half the round-trip time of the query, in seconds.
    public mutating func add(hostTime h: Double, seconds n: Int, uncertainty u: Double = 0) -> Double {
        let r = max(rate, 0.01)
        let shift = rounds ? -0.5 : 0
        let lo = h - (Double(n) + 1 + shift) / r - u
        let hi = h - (Double(n) + shift) / r + u
        let newLower = max(lower, lo)
        let newUpper = min(upper, hi)
        if newLower > newUpper {
            // Inconsistent with history: seek, rate change or stall. Start over from this sample.
            lower = lo
            upper = hi
        } else {
            lower = newLower
            upper = newUpper
        }
        return (h - (lower + upper) / 2) * r
    }
}
