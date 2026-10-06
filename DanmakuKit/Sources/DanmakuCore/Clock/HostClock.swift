import Darwin

/// Monotonic host time in seconds, on the same time base as `CACurrentMediaTime()` (mach absolute time).
public enum HostClock {
    public static func now() -> Double {
        Double(clock_gettime_nsec_np(CLOCK_UPTIME_RAW)) / 1_000_000_000
    }
}
