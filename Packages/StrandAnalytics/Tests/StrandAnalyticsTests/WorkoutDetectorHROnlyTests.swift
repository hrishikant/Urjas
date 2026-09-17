import XCTest
@testable import StrandAnalytics
import WhoopProtocol

/// HR-only retroactive detection (#retro-detect): a sport played while the app was suspended banks HR
/// history but no phone motion, so the motion-gated `detect(...)` misses it. `detectHROnly` recovers
/// those bouts from HR alone; `mergeHROnly` folds them under the richer motion bouts without double count.
final class WorkoutDetectorHROnlyTests: XCTestCase {

    private let resting = 60.0
    // Gate = resting + hrOnlyMarginBPM (30) = 90 bpm. Use 150 for "working", 65 for "at rest".
    private func working(_ range: Range<Int>, bpm: Int = 150) -> [HRSample] {
        range.map { HRSample(ts: $0, bpm: bpm) }
    }
    private func atRest(_ range: Range<Int>, bpm: Int = 65) -> [HRSample] {
        range.map { HRSample(ts: $0, bpm: bpm) }
    }

    // MARK: - detectHROnly

    func testDetectsSustainedElevatedBout() {
        // 15 min elevated (>= 10 min min), flanked by rest. One bout expected.
        var hr = atRest(0..<300)
        hr += working(300..<1200)          // 900 s elevated
        hr += atRest(1200..<1500)
        let out = WorkoutDetector.detectHROnly(hr: hr, restingHR: resting, maxHR: 190)
        XCTAssertEqual(out.count, 1)
        let b = out[0]
        XCTAssertEqual(b.start, 300)
        XCTAssertEqual(b.end, 1199)
        XCTAssertGreaterThanOrEqual(b.durationS, 600)
        XCTAssertEqual(Int(b.avgHR.rounded()), 150)
        XCTAssertEqual(b.peakHR, 150)
    }

    func testShortElevationIgnored() {
        // 8 min elevated < 10 min min → dropped.
        var hr = atRest(0..<300)
        hr += working(300..<780)           // 480 s < 600
        hr += atRest(780..<1080)
        XCTAssertTrue(WorkoutDetector.detectHROnly(hr: hr, restingHR: resting, maxHR: 190).isEmpty)
    }

    func testBridgesShortDip() {
        // Elevated, a 90 s dip (<= 120 s tolerance), elevated again → ONE continuous bout.
        var hr = working(0..<500)
        hr += atRest(500..<590)            // 90 s dip
        hr += working(590..<1100)
        let out = WorkoutDetector.detectHROnly(hr: hr, restingHR: resting, maxHR: 190)
        XCTAssertEqual(out.count, 1)
        XCTAssertEqual(out[0].start, 0)
        XCTAssertEqual(out[0].end, 1099)
    }

    func testLongDipSplitsBouts() {
        // A 200 s dip (> 120 s tolerance) between two 11 min efforts → the gap breaks them; only the
        // segments that are each >= 10 min survive.
        var hr = working(0..<660)          // 660 s
        hr += atRest(660..<860)            // 200 s dip
        hr += working(860..<1520)          // 660 s
        let out = WorkoutDetector.detectHROnly(hr: hr, restingHR: resting, maxHR: 190)
        XCTAssertEqual(out.count, 2)
        XCTAssertEqual(out[0].start, 0)
        XCTAssertEqual(out[0].end, 659)
        XCTAssertEqual(out[1].start, 860)
        XCTAssertEqual(out[1].end, 1519)
    }

    func testNonElevatedTailDoesNotPadDuration() {
        // Only elevated samples advance the bout's end edge, so a long resting tail can't inflate it.
        var hr = working(0..<900)          // 900 s elevated
        hr += atRest(900..<3600)           // 45 min resting tail
        let out = WorkoutDetector.detectHROnly(hr: hr, restingHR: resting, maxHR: 190)
        XCTAssertEqual(out.count, 1)
        XCTAssertEqual(out[0].end, 899)
        XCTAssertLessThan(out[0].durationS, 1000)
    }

    func testEmptyAndTinyInput() {
        XCTAssertTrue(WorkoutDetector.detectHROnly(hr: [], restingHR: resting, maxHR: 190).isEmpty)
        XCTAssertTrue(WorkoutDetector.detectHROnly(hr: [HRSample(ts: 0, bpm: 150)],
                                                   restingHR: resting, maxHR: 190).isEmpty)
    }

    func testAllRestingProducesNothing() {
        let hr = atRest(0..<3600)
        XCTAssertTrue(WorkoutDetector.detectHROnly(hr: hr, restingHR: resting, maxHR: 190).isEmpty)
    }

    func testFullAnalysisPopulated() {
        let hr = working(0..<1200, bpm: 150)
        let profile = UserProfile(weightKg: 80, heightCm: 180, age: 30, sex: "male")
        let out = WorkoutDetector.detectHROnly(hr: hr, restingHR: resting, maxHR: 190, profile: profile)
        XCTAssertEqual(out.count, 1)
        let b = out[0]
        XCTAssertNotNil(b.caloriesKcal)
        XCTAssertGreaterThan(b.caloriesKcal ?? 0, 0)
        XCTAssertGreaterThan(b.strain ?? 0, 0)
        XCTAssertFalse(b.zoneTimePct.isEmpty)
    }

    // MARK: - mergeHROnly

    private func session(_ start: Int, _ end: Int) -> ExerciseSession {
        ExerciseSession(start: start, end: end, avgHR: 150, peakHR: 160, strain: 5,
                        durationS: Double(end - start), zoneTimePct: [:], avgHRRPct: nil,
                        hrmax: 190, hrmaxSource: "test", caloriesKcal: 100, caloriesKJ: 418)
    }

    func testMergeKeepsNonOverlappingHROnly() {
        let motion = [session(0, 600)]
        let hrOnly = [session(1000, 1600)]
        let merged = WorkoutDetector.mergeHROnly(motion: motion, hrOnly: hrOnly)
        XCTAssertEqual(merged.count, 2)
    }

    func testMergeDropsOverlappingHROnly() {
        let motion = [session(0, 600)]
        let hrOnly = [session(300, 900)]     // overlaps motion → dropped
        let merged = WorkoutDetector.mergeHROnly(motion: motion, hrOnly: hrOnly)
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].start, 0)
    }

    func testMergeEmptyHROnly() {
        let motion = [session(0, 600)]
        XCTAssertEqual(WorkoutDetector.mergeHROnly(motion: motion, hrOnly: []).count, 1)
    }

    func testMergeEmptyMotion() {
        let hrOnly = [session(0, 600), session(1000, 1600)]
        XCTAssertEqual(WorkoutDetector.mergeHROnly(motion: [], hrOnly: hrOnly).count, 2)
    }
}
