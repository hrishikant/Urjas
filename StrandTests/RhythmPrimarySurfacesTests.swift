import XCTest
import WhoopStore
@testable import Strand

final class RhythmPrimarySurfacesTests: XCTestCase {
    @MainActor func testVitalDetailsKeepTheDisplayedSourceAndCompatibleKey() {
        for (key, expected) in [("spo2", "spo2"), ("resp", "resp_rate"), ("rhr", "resting_hr"), ("hrv", "hrv")] {
            let descriptor = RhythmVitalRoute.metric(key: key, source: .appleHealth)
            XCTAssertEqual(descriptor?.key, expected)
            XCTAssertEqual(descriptor?.source, "apple-health")
        }
        XCTAssertEqual(RhythmVitalRoute.metric(key: "spo2", source: .whoopImport)?.source, "my-whoop")
        XCTAssertEqual(RhythmVitalRoute.metric(key: "resp", source: .noopComputed)?.key, "resp_rate")
        XCTAssertNil(RhythmVitalRoute.metric(key: "spo2raw", source: .noopComputed))
    }

    func testEntryActionIsConsumedOncePerPresentation() {
        var gate = RhythmSurfaceEntryGate()
        XCTAssertEqual(gate.consume(WorkoutsView.EntryAction.start), .start)
        XCTAssertTrue(gate.consumed)
        XCTAssertNil(gate.consume(WorkoutsView.EntryAction.start))
        XCTAssertNil(gate.consume(WorkoutsView.EntryAction.add))
        var nextPresentation = RhythmSurfaceEntryGate()
        XCTAssertEqual(nextPresentation.consume(WorkoutsView.EntryAction.add), .add)
    }

    func testSleepEntryWaitsForRealSessionRead() {
        var gate = RhythmSurfaceEntryGate()
        XCTAssertNil(gate.consume(SleepView.EntryAction.edit, ready: false))
        XCTAssertFalse(gate.consumed)
        XCTAssertEqual(gate.consume(SleepView.EntryAction.edit, ready: true), .edit)
        XCTAssertNil(gate.consume(SleepView.EntryAction.edit))
    }

    func testDefaultEntryDoesNothing() {
        var gate = RhythmSurfaceEntryGate()
        XCTAssertNil(gate.consume(nil as WorkoutsView.EntryAction?))
        XCTAssertFalse(gate.consumed)
    }

    @MainActor func testEntryInitializersRemainBackwardsCompatible() {
        _ = WorkoutsView()
        _ = WorkoutsView(previewRows: [])
        _ = WorkoutsView(previewRows: [], initialAction: .add)
        _ = WorkoutsView(initialAction: .start)
        _ = SleepView()
        _ = SleepView(focusesSleepDebt: true)
        _ = SleepView(initialAction: .edit)
        _ = SleepView(initialAction: .nap)
    }

    private func row(start: Int = 1_800_000_000, source: String = "manual",
                     duration: Double? = nil, calories: Double? = nil,
                     distance: Double? = nil, strain: Double? = nil) -> WorkoutRow {
        WorkoutRow(startTs: start, endTs: start + 3600, sport: "Running", source: source,
                   durationS: duration, energyKcal: calories, avgHr: nil, maxHr: nil,
                   strain: strain, distanceM: distance, zonesJSON: nil, notes: nil)
    }

    func testMissingMeasurementsDoNotBecomeZeros() {
        let summary = RhythmActivitySummary(rows: [row()])
        XCTAssertEqual(summary.sessions, 1)
        XCTAssertNil(summary.durationSeconds)
        XCTAssertNil(summary.calories)
        XCTAssertNil(summary.distanceMeters)
        XCTAssertNil(summary.averageStrain)
    }

    func testSummaryKeepsStoredStrainAndSources() {
        let rows = [
            row(source: "my-whoop-noop", duration: 1200, calories: 50, distance: 1000, strain: 80),
            row(start: 1_800_000_100, source: "whoop", duration: 2400, calories: 150, distance: 3000, strain: 20),
            row(start: 1_800_000_200, source: "apple_health")
        ]
        let summary = RhythmActivitySummary(rows: rows)
        XCTAssertEqual(summary.sessions, 3)
        XCTAssertEqual(summary.detectedSessions, 1)
        XCTAssertEqual(summary.durationSeconds, 3600)
        XCTAssertEqual(summary.calories, 200)
        XCTAssertEqual(summary.distanceMeters, 4000)
        XCTAssertEqual(summary.averageStrain, 50, "Summary stays on stored 0–100; only its label converts to 0–21.")
        XCTAssertEqual(rows[0].strain, 80)
        XCTAssertEqual(rows[0].source, "my-whoop-noop")
    }

    func testActiveDaysFollowLocalCalendar() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 3600)!
        let day = calendar.date(from: DateComponents(year: 2026, month: 9, day: 17))!
        let start = Int(day.timeIntervalSince1970)
        let summary = RhythmActivitySummary(rows: [
            row(start: start + 60), row(start: start + 86340), row(start: start + 86460)
        ], calendar: calendar)
        XCTAssertEqual(summary.activeDays, 2)
    }

    func testEmptyAndInvalidMeasurementsStayHonest() {
        let empty = RhythmActivitySummary(rows: [])
        XCTAssertEqual(empty.sessions, 0)
        XCTAssertEqual(empty.activeDays, 0)
        XCTAssertNil(empty.durationSeconds)
        let invalid = RhythmActivitySummary(rows: [row(duration: .nan, calories: -.infinity,
                                                        distance: -1, strain: .infinity)])
        XCTAssertNil(invalid.durationSeconds)
        XCTAssertNil(invalid.calories)
        XCTAssertNil(invalid.distanceMeters)
        XCTAssertNil(invalid.averageStrain)
        XCTAssertEqual(RhythmActivitySummary(rows: [row(distance: 0)]).distanceMeters, 0)
    }

    func testOnlyRecordedStagesProduceTimeline() {
        XCTAssertEqual(RhythmSleepStagePresentation.resolve(asleepMinutes: 420, recordedIntervalCount: 12), .timeline)
        XCTAssertEqual(RhythmSleepStagePresentation.resolve(asleepMinutes: 420, recordedIntervalCount: 0), .totals,
                       "Imported stage totals must never get a made-up timed sequence.")
        XCTAssertEqual(RhythmSleepStagePresentation.resolve(asleepMinutes: 0, recordedIntervalCount: 12), .unavailable)
        XCTAssertEqual(RhythmSleepStagePresentation.resolve(asleepMinutes: .nan, recordedIntervalCount: 12), .unavailable)
    }

    func testHROnlyPlaceholdersNeverBecomeLightSleepStages() {
        let tagged = #"[{"start":100,"end":200,"stage":"light","hrOnly":true}]"#
        XCTAssertTrue(RhythmSleepStagePresentation.containsHROnlyStages(tagged))
        XCTAssertEqual(RhythmSleepStagePresentation.resolve(asleepMinutes: 420, recordedIntervalCount: 12,
                                                            hrOnly: true), .unavailable)
        XCTAssertFalse(RhythmSleepStagePresentation.containsHROnlyStages(#"{"light":300,"deep":60,"rem":60}"#))
        XCTAssertFalse(RhythmSleepStagePresentation.containsHROnlyStages(#"[{"stage":"light","hrOnly":false}]"#))
        XCTAssertFalse(RhythmSleepStagePresentation.containsHROnlyStages(nil))
        XCTAssertFalse(RhythmSleepStagePresentation.containsHROnlyStages("not json"))
    }
}
