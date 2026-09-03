import XCTest
@testable import StrandAnalytics

final class TodayInsightsTests: XCTestCase {

    // MARK: - Headline (feature 1)

    func testHeadlineCallForEveryLevel() {
        XCTAssertEqual(TodayHeadline.call(for: .primed), .push)
        XCTAssertEqual(TodayHeadline.call(for: .balanced), .maintain)
        XCTAssertEqual(TodayHeadline.call(for: .strained), .easy)
        XCTAssertEqual(TodayHeadline.call(for: .rundown), .rest)
        XCTAssertNil(TodayHeadline.call(for: .insufficient))
    }

    // MARK: - Baseline comparison (feature 2)

    func testBaselineDeltaAboveAverage() {
        let d = BaselineCompare.delta(current: 80, history: [70, 60, 65, 75])
        XCTAssertNotNil(d)
        XCTAssertEqual(d!.baseline, 67.5, accuracy: 0.001)
        XCTAssertEqual(d!.diff, 12.5, accuracy: 0.001)
        XCTAssertEqual(d!.sampleCount, 4)
        XCTAssertEqual(BaselineCompare.classify(d!), .above)
    }

    func testBaselineDeltaBelowAverage() {
        let d = BaselineCompare.delta(current: 50, history: [70, 60, 65])!
        XCTAssertEqual(d.diff, -15, accuracy: 0.001)
        XCTAssertEqual(BaselineCompare.classify(d), .below)
    }

    func testBaselineInLineWithinTolerance() {
        let d = BaselineCompare.delta(current: 66, history: [67, 65, 66])!  // mean 66
        XCTAssertEqual(BaselineCompare.classify(d, tolerance: 2), .inLine)
    }

    func testBaselineNilWhenNoCurrent() {
        XCTAssertNil(BaselineCompare.delta(current: nil, history: [1, 2, 3]))
    }

    func testBaselineNilWhenTooFewSamples() {
        XCTAssertNil(BaselineCompare.delta(current: 80, history: [70, 60], minSamples: 3))
    }

    func testBaselineIgnstNonFiniteHistory() {
        let d = BaselineCompare.delta(current: 80, history: [70, .nan, 60, .infinity, 65])
        XCTAssertEqual(d?.sampleCount, 3)
        XCTAssertEqual(d?.baseline ?? -1, 65, accuracy: 0.001)
    }

    // MARK: - Affirmation + streak (feature 5)

    func testAffirmationToneBands() {
        XCTAssertEqual(Affirmation.tone(charge: 90), .peak)
        XCTAssertEqual(Affirmation.tone(charge: 85), .peak)
        XCTAssertEqual(Affirmation.tone(charge: 75), .strong)
        XCTAssertEqual(Affirmation.tone(charge: 55), .steady)
        XCTAssertEqual(Affirmation.tone(charge: 30), .low)
        XCTAssertEqual(Affirmation.tone(charge: nil), .none)
    }

    func testShowStreakThreshold() {
        XCTAssertFalse(Affirmation.showStreak(2))
        XCTAssertTrue(Affirmation.showStreak(3))
        XCTAssertTrue(Affirmation.showStreak(10))
    }

    // MARK: - Calibration (feature 6)

    func testCalibrationProgressCounts() {
        XCTAssertEqual(CalibrationStatus.progress(daysWithData: 0), CalibrationStatus.Progress(day: 1, target: 14))
        XCTAssertEqual(CalibrationStatus.progress(daysWithData: 2), CalibrationStatus.Progress(day: 3, target: 14))
        XCTAssertEqual(CalibrationStatus.progress(daysWithData: 13), CalibrationStatus.Progress(day: 14, target: 14))
    }

    func testCalibrationHiddenOnceComplete() {
        XCTAssertNil(CalibrationStatus.progress(daysWithData: 14))
        XCTAssertNil(CalibrationStatus.progress(daysWithData: 30))
    }

    func testCalibrationCustomTarget() {
        XCTAssertEqual(CalibrationStatus.progress(daysWithData: 1, target: 7), CalibrationStatus.Progress(day: 2, target: 7))
        XCTAssertNil(CalibrationStatus.progress(daysWithData: 5, target: 0))
    }
}
