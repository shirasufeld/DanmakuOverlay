import Testing

@testable import DanmakuCore

struct ClockTests {
    @Test func firstSampleJumps() {
        var clock = ClockModel()
        let decision = clock.ingest(PlaybackState(position: 10, isPlaying: true, hostTime: 100), now: 100.5)
        guard case .jump(let a) = decision else {
            Issue.record("expected jump, got \(decision)")
            return
        }
        #expect(abs(a.mediaTime - 10.5) < 1e-9)
        #expect(a.rate == 1)
    }

    @Test func consistentSamplesKeep() {
        var clock = ClockModel()
        _ = clock.ingest(PlaybackState(position: 0, isPlaying: true, hostTime: 0), now: 0)
        for i in 1...20 {
            let t = Double(i) * 0.25
            let d = clock.ingest(PlaybackState(position: t + 0.005, isPlaying: true, hostTime: t), now: t)
            #expect(d == .keep)
        }
    }

    @Test func smallDriftSlewsAndConverges() {
        var clock = ClockModel()
        _ = clock.ingest(PlaybackState(position: 0, isPlaying: true, hostTime: 0), now: 0)
        // The player is 100 ms ahead of our prediction.
        var slewed = false
        var t = 0.0
        while t < 10 {
            t += 0.25
            let d = clock.ingest(PlaybackState(position: t + 0.1, isPlaying: true, hostTime: t), now: t)
            if case .retime(let a) = d, a.rate > 1 { slewed = true }
            if case .jump = d { Issue.record("unexpected jump at \(t)") }
            _ = clock.tick(now: t)
        }
        #expect(slewed)
        #expect(abs(clock.mediaTime(at: t)! - (t + 0.1)) < 0.03)
    }

    @Test func largeErrorJumps() {
        var clock = ClockModel()
        _ = clock.ingest(PlaybackState(position: 0, isPlaying: true, hostTime: 0), now: 0)
        let d = clock.ingest(PlaybackState(position: 5, isPlaying: true, hostTime: 1), now: 1)
        guard case .jump(let a) = d else {
            Issue.record("expected jump")
            return
        }
        #expect(a.mediaTime == 5)
    }

    @Test func pauseAndRateChangesJump() {
        var clock = ClockModel()
        _ = clock.ingest(PlaybackState(position: 0, isPlaying: true, hostTime: 0), now: 0)
        let paused = clock.ingest(PlaybackState(position: 1, isPlaying: false, hostTime: 1), now: 1.2)
        guard case .jump(let p) = paused else {
            Issue.record("expected jump on pause")
            return
        }
        #expect(p.rate == 0 && p.mediaTime == 1)
        #expect(clock.mediaTime(at: 50) == 1)
        let faster = clock.ingest(PlaybackState(position: 1, rate: 1.5, isPlaying: true, hostTime: 2), now: 2)
        guard case .jump(let f) = faster else {
            Issue.record("expected jump on rate change")
            return
        }
        #expect(f.rate == 1.5)
    }

    @Test func discontinuityJumps() {
        var clock = ClockModel()
        _ = clock.ingest(PlaybackState(position: 0, isPlaying: true, hostTime: 0), now: 0)
        let d = clock.ingest(
            PlaybackState(position: 0.26, isPlaying: true, hostTime: 0.25, discontinuity: true), now: 0.25)
        if case .jump = d {} else { Issue.record("expected jump") }
    }

    @Test func tickEstimatorLocksPhase() {
        // True position = host − 0.37; VLC reports whole seconds, polled every ~110 ms.
        var est = TickPhaseEstimator()
        var h = 100.0
        var last = 0.0
        for _ in 0..<80 {
            h += 0.11
            let truth = h - 0.37 - 90
            last = est.add(hostTime: h, seconds: Int(truth.rounded(.down)))
            _ = truth
        }
        #expect(est.isLocked)
        #expect(abs(last - (h - 0.37 - 90)) < 0.06)
    }

    @Test func tickEstimatorResetsOnSeek() {
        var est = TickPhaseEstimator()
        var h = 0.0
        for _ in 0..<30 {
            h += 0.1
            _ = est.add(hostTime: h, seconds: Int(h.rounded(.down)))
        }
        // Seek forward by 60 s.
        var last = 0.0
        for _ in 0..<30 {
            h += 0.1
            last = est.add(hostTime: h, seconds: Int((h + 60.5).rounded(.down)))
        }
        #expect(abs(last - (h + 60.5)) < 0.15)
    }
}
