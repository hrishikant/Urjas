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

    private let resting = 55
    private var gate: Int { resting + LiveAutoStart.elevatedMarginBPM }   // 85

    // MARK: - Auto-start

    func testStartsAfterSustainedElevation() {
        // 4 minutes solidly above the gate → should start, onset at the first elevated sample.
        let secs = Int(LiveAutoStart.sustainMin * 60) + 60      // 240 s
        let series = Array(repeating: 130, count: secs)
        let b = buf(series)
        let d = LiveAutoStart.decide(buf: b, nowT: 0, restingBpm: resting,
                                     isRecording: false, wasAuto: false)
        guard case .start(let onsetT) = d else { return XCTFail("expected .start, got \(d)") }
        XCTAssertEqual(onsetT, b.first!.t, accuracy: 0.5)
    }

    func testDoesNotStartBeforeSustainThreshold() {
        // Only 2 minutes elevated (< 3 min) → no start yet.
        let series = Array(repeating: 130, count: 120)
        let d = LiveAutoStart.decide(buf: buf(series), nowT: 0, restingBpm: resting,
                                     isRecording: false, wasAuto: false)
        XCTAssertEqual(d, .none)
    }

    func testDoesNotStartWhenBelowGate() {
        // Sitting at resting → never starts.
        let series = Array(repeating: resting + 5, count: 600)
        let d = LiveAutoStart.decide(buf: buf(series), nowT: 0, restingBpm: resting,
                                     isRecording: false, wasAuto: false)
        XCTAssertEqual(d, .none)
    }

    func testDoesNotStartIfCurrentSampleDropsBelowGate() {
        // Long elevated stretch but the most recent 2 min are below gate (cooling down) → not "now".
        var series = Array(repeating: 130, count: 300)
        series += Array(repeating: 70, count: 120)
        let d = LiveAutoStart.decide(buf: buf(series), nowT: 0, restingBpm: resting,
                                     isRecording: false, wasAuto: false)
        XCTAssertEqual(d, .none)
    }

    func testBriefDipDoesNotBreakTheRun() {
        // 3.5 min elevated with a single 60 s dip (< maxDipS 90) in the middle → still starts, onset spans the dip.
        var series = Array(repeating: 130, count: 90)   // oldest elevated
        series += Array(repeating: 70, count: 60)        // 60 s tolerated dip
        series += Array(repeating: 130, count: 90)        // recent elevated → newest above gate
        // total 240 s, onset should reach back across the dip to the first elevated sample.
        let b = buf(series)
        let d = LiveAutoStart.decide(buf: b, nowT: 0, restingBpm: resting,
                                     isRecording: false, wasAuto: false)
        guard case .start(let onsetT) = d else { return XCTFail("expected .start, got \(d)") }
        XCTAssertEqual(onsetT, b.first!.t, accuracy: 0.5)
    }

    func testLongDipBreaksTheRun() {
        // A 2 min dip (> maxDipS) means the onset only counts the recent 2 min elevated stretch (< 3 min) → no start.
        var series = Array(repeating: 130, count: 200)
        series += Array(repeating: 70, count: 120)        // 120 s dip > 90 s → breaks
        series += Array(repeating: 130, count: 120)        // only 2 min recent elevated
        let d = LiveAutoStart.decide(buf: buf(series), nowT: 0, restingBpm: resting,
                                     isRecording: false, wasAuto: false)
        XCTAssertEqual(d, .none)
    }

    func testUsesDefaultRestingWhenNil() {
        // gate = 60 + 30 = 90. 4 min at 120 → starts even without a nightly RHR.
        let series = Array(repeating: 120, count: 240)
        let d = LiveAutoStart.decide(buf: buf(series), nowT: 0, restingBpm: nil,
                                     isRecording: false, wasAuto: false)
        if case .start = d {} else { XCTFail("expected .start, got \(d)") }
    }

    // MARK: - Auto-end

    func testEndsAfterSustainedRecovery() {
        // Auto-started session; last 6 min all below gate → ends.
        let series = Array(repeating: 65, count: 360)
        let d = LiveAutoStart.decide(buf: buf(series), nowT: 0, restingBpm: resting,
                                     isRecording: true, wasAuto: true)
        XCTAssertEqual(d, .end)
    }

    func testDoesNotEndWhileStillElevated() {
        let series = Array(repeating: 130, count: 360)
        let d = LiveAutoStart.decide(buf: buf(series), nowT: 0, restingBpm: resting,
                                     isRecording: true, wasAuto: true)
        XCTAssertEqual(d, .none)
    }

    func testDoesNotEndBeforeCooldownElapses() {
        // Only 3 min of below-gate data (< endCooldownMin 5) → keep going.
        let series = Array(repeating: 65, count: 180)
        let d = LiveAutoStart.decide(buf: buf(series), nowT: 0, restingBpm: resting,
                                     isRecording: true, wasAuto: true)
        XCTAssertEqual(d, .none)
    }

    func testDoesNotEndIfAnyRecentSampleStillElevated() {
        // 6 min window but one spike above gate 1 min ago → not a clean recovery, keep going.
        var series = Array(repeating: 65, count: 300)
        series += [130]                                  // a late elevated blip within the window
        series += Array(repeating: 65, count: 60)
        let d = LiveAutoStart.decide(buf: buf(series), nowT: 0, restingBpm: resting,
                                     isRecording: true, wasAuto: true)
        XCTAssertEqual(d, .none)
    }

    func testNeverAutoEndsAManualSession() {        // Recording but NOT auto-started → the live monitor must never end it, even fully recovered.
        let series = Array(repeating: 65, count: 600)
        let d = LiveAutoStart.decide(buf: buf(series), nowT: 0, restingBpm: resting,
                                     isRecording: true, wasAuto: false)
        XCTAssertEqual(d, .none)
    }

    /// Regression: mimics a live stream where `now` trails the newest sample by a fraction of a second.
    /// The old auto-end test filtered the buffer to the last `window`, then required
    /// `now - earliest >= window` , after filtering the earliest is inside the window, so this was ~always
    /// just under the threshold on a real ~1 Hz stream and the session would never auto-end.
    func testEndsWhenNowTrailsSamplesByFractionOfASecond() {
        let series = Array(repeating: 65, count: 360)   // 6 min below gate
        let b = buf(series, endT: 0)                     // newest at t=0
        let d = LiveAutoStart.decide(buf: b, nowT: 0.004, restingBpm: resting,
                                     isRecording: true, wasAuto: true)
        XCTAssertEqual(d, .end)
    }

    func testDoesNotEndWithoutFullWindowOfHistory() {
        // Only ~2 min of below-gate history exists (stream just started) → not yet a full cool-down.
        let series = Array(repeating: 65, count: 120)
        let d = LiveAutoStart.decide(buf: buf(series, endT: 0), nowT: 0.004, restingBpm: resting,
                                     isRecording: true, wasAuto: true)
        XCTAssertEqual(d, .none)
    }

    func testEmptyBufferIsNone() {
        XCTAssertEqual(LiveAutoStart.decide(buf: [], nowT: 0, restingBpm: resting,
                                            isRecording: false, wasAuto: false), .none)
    }
}
