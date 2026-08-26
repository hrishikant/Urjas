import XCTest
@testable import StrandAnalytics

final class LiveAutoStartTests: XCTestCase {

    // Build an ascending buffer at 1 Hz ending at t=0 for the given per-second bpm values (oldest first).
    private func buf(_ bpm: [Int], endT: Double = 0) -> [LiveAutoStart.Sample] {
        let n = bpm.count
        return bpm.enumerated().map { i, v in
            LiveAutoStart.Sample(t: endT - Double(n - 1 - i), bpm: v)
        }
    }

    /// A per-second series long enough to fill the sustain window (+ a margin for the coverage proof),
    /// with a controllable elevated duty cycle via repeating 10 s blocks (`on` seconds high per 10 s).
    /// The newest sample is forced high so only the duty-cycle / coverage guards can reject a start.
    private func series(on: Int, hi: Int = 130, lo: Int = 65) -> [Int] {
        let secs = Int(LiveAutoStart.sustainMin * 60) + 61        // window + coverage margin
        var out = (0..<secs).map { ($0 % 10) < on ? hi : lo }
        out[secs - 1] = hi
        return out
    }

    private let resting = 55
    private var gate: Int { resting + LiveAutoStart.elevatedMarginBPM }   // 85
    private var windowSecs: Int { Int(LiveAutoStart.sustainMin * 60) }

    private func decideStart(_ b: [LiveAutoStart.Sample], nowT: Double = 0) -> LiveAutoStart.Decision {
        LiveAutoStart.decide(buf: b, nowT: nowT, restingBpm: resting, isRecording: false, wasAuto: false)
    }
    private func decideEnd(_ b: [LiveAutoStart.Sample], nowT: Double = 0) -> LiveAutoStart.Decision {
        LiveAutoStart.decide(buf: b, nowT: nowT, restingBpm: resting, isRecording: true, wasAuto: true)
    }

    // MARK: - Auto-start

    func testStartsAfterSustainedElevation() {
        // The whole sustain window solidly above the gate → starts, onset at the first elevated sample.
        let secs = windowSecs + 60
        let b = buf(Array(repeating: 130, count: secs))
        guard case .start(let onsetT) = decideStart(b) else { return XCTFail("expected .start") }
        XCTAssertEqual(onsetT, b.first!.t, accuracy: 0.5)
    }

    func testDoesNotStartBeforeSustainThreshold() {
        // Elevated but shorter than the sustain window (no history older than winStart) → no start yet.
        let s = Array(repeating: 130, count: windowSecs - 60)
        XCTAssertEqual(decideStart(buf(s)), .none)
    }

    func testDoesNotStartWhenBelowGate() {
        // Sitting at resting → never starts.
        let s = Array(repeating: resting + 5, count: windowSecs + 120)
        XCTAssertEqual(decideStart(buf(s)), .none)
    }

    func testDoesNotStartIfCurrentSampleDropsBelowGate() {
        // Long elevated stretch but the most recent 2 min are below gate (cooling down) → not "now".
        var s = Array(repeating: 130, count: windowSecs)
        s += Array(repeating: 70, count: 120)
        XCTAssertEqual(decideStart(buf(s)), .none)
    }

    func testStartsWhenMostlyElevated() {
        // 90% of the window above the gate (short 1 s dips) → starts.
        if case .start = decideStart(buf(series(on: 9))) {} else { XCTFail("expected .start at 90% duty") }
    }

    func testDoesNotStartWhenNotMostlyElevated() {
        // Only ~70% (and ~80%) of the window above the gate → below the 85% duty-cycle bar → no start.
        // This is the core false-start guard: intermittent everyday spikes never reach it.
        XCTAssertEqual(decideStart(buf(series(on: 7))), .none)
        XCTAssertEqual(decideStart(buf(series(on: 8))), .none)
    }

    func testBriefDipDoesNotBreakTheRun() {
        // A single short dip (< maxDipS 30) keeps duty well above 85% → still starts, onset spans the dip.
        let secs = windowSecs + 60
        var s = Array(repeating: 130, count: secs)
        for i in (secs / 2)..<(secs / 2 + 20) { s[i] = 70 }   // 20 s dip in the middle
        let b = buf(s)
        guard case .start(let onsetT) = decideStart(b) else { return XCTFail("expected .start") }
        XCTAssertEqual(onsetT, b.first!.t, accuracy: 0.5)
    }

    func testDoesNotStartWithCoverageGap() {
        // A long dropout (no samples) inside the window means we never observed a continuous effort.
        var b = buf(Array(repeating: 130, count: windowSecs + 60))
        b.removeAll { $0.t > -300 && $0.t < -180 }             // 120 s hole > coverageGapS
        XCTAssertEqual(decideStart(b), .none)
    }

    func testUsesDefaultRestingWhenNil() {
        // gate = 60 + 30 = 90. Full window at 120 → starts even without a nightly RHR.
        let s = Array(repeating: 120, count: windowSecs + 60)
        let d = LiveAutoStart.decide(buf: buf(s), nowT: 0, restingBpm: nil,
                                     isRecording: false, wasAuto: false)
        if case .start = d {} else { XCTFail("expected .start, got \(d)") }
    }

    // MARK: - Auto-end

    func testEndsAfterSustainedRecovery() {
        let s = Array(repeating: 65, count: 360)              // 6 min below gate
        XCTAssertEqual(decideEnd(buf(s)), .end)
    }

    func testDoesNotEndWhileStillElevated() {
        XCTAssertEqual(decideEnd(buf(Array(repeating: 130, count: 360))), .none)
    }

    func testDoesNotEndBeforeCooldownElapses() {
        // Only 3 min of below-gate data (< endCooldownMin 5) → keep going.
        XCTAssertEqual(decideEnd(buf(Array(repeating: 65, count: 180))), .none)
    }

    func testStrayCoolDownSpikeStillEnds() {
        // A genuine cool-down with ONE stray elevated sample must STILL end — a lone noisy reading no
        // longer keeps a session alive for hours (the old "every sample below gate" rule failed here).
        var s = Array(repeating: 65, count: 360)
        s[120] = 130                                          // one stray spike, newest still calm
        XCTAssertEqual(decideEnd(buf(s)), .end)
    }

    func testDoesNotEndIfNewestSampleStillElevated() {
        // Calm window but the most recent reading is a spike → don't end mid-spike.
        var s = Array(repeating: 65, count: 360)
        s[s.count - 1] = 130
        XCTAssertEqual(decideEnd(buf(s)), .none)
    }

    func testDoesNotEndIfCoolDownStillBusy() {
        // ~30% of the window above the gate (> endMaxElevatedFrac) → not a real cool-down, keep going.
        let s = (0..<360).map { ($0 % 10) < 3 ? 130 : 65 }
        XCTAssertEqual(decideEnd(buf(s)), .none)
    }

    func testNeverAutoEndsAManualSession() {
        // Recording but NOT auto-started → the live monitor must never end it, even fully recovered.
        let s = Array(repeating: 65, count: 600)
        let d = LiveAutoStart.decide(buf: buf(s), nowT: 0, restingBpm: resting,
                                     isRecording: true, wasAuto: false)
        XCTAssertEqual(d, .none)
    }

    /// Regression: `now` trails the newest sample by a fraction of a second on a live stream.
    func testEndsWhenNowTrailsSamplesByFractionOfASecond() {
        let b = buf(Array(repeating: 65, count: 360), endT: 0)
        XCTAssertEqual(decideEnd(b, nowT: 0.004), .end)
    }

    func testDoesNotEndWithoutFullWindowOfHistory() {
        // Only ~2 min of below-gate history exists (stream just started) → not yet a full cool-down.
        XCTAssertEqual(decideEnd(buf(Array(repeating: 65, count: 120), endT: 0), nowT: 0.004), .none)
    }

    func testEmptyBufferIsNone() {
        XCTAssertEqual(LiveAutoStart.decide(buf: [], nowT: 0, restingBpm: resting,
                                            isRecording: false, wasAuto: false), .none)
    }

    // MARK: - Coverage helper

    func testIsDenselyCoveredDetectsGap() {
        let dense = buf(Array(repeating: 100, count: 120))    // 1 Hz, no gaps
        XCTAssertTrue(LiveAutoStart.isDenselyCovered(dense, from: -119, to: 0))
        var sparse = dense
        sparse.removeAll { $0.t > -80 && $0.t < -20 }         // 60 s hole
        XCTAssertFalse(LiveAutoStart.isDenselyCovered(sparse, from: -119, to: 0))
    }
}
