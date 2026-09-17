import XCTest
import WhoopProtocol
@testable import StrandAnalytics

final class SleepHROnlyIntegrationTests: XCTestCase {
    private func night(sleepBpm: Int = 55) -> [HRSample] {
        (0..<12 * 3600).map {
            HRSample(ts: $0, bpm: (3600..<8 * 3600).contains($0) ? sleepBpm + ($0 % 3) : sleepBpm + 25)
        }
    }

    func testDifferentSleepingLevelsAreRecoveredWithoutGravity() throws {
        for bpm in [48, 58, 68] {
            let sessions = SleepStager.hrOnlySessions(hr: night(sleepBpm: bpm), rr: [], resp: [])
            let session = try XCTUnwrap(sessions.max { $0.end - $0.start < $1.end - $1.start })
            XCTAssertTrue(session.hrOnly)
            XCTAssertEqual(session.start, 3600)
            XCTAssertEqual(session.end, 8 * 3600 - 1)
            XCTAssertEqual(session.restingHR, bpm + 1)
            XCTAssertNil(session.avgHRV)
            XCTAssertFalse(session.stages.isEmpty)
        }
    }

    func testHRVRequiresActualRRAndTaggedStagesRemainDecodable() throws {
        let rr = (3600..<8 * 3600).map { RRInterval(ts: $0, rrMs: $0 % 2 == 0 ? 980 : 1020) }
        let session = try XCTUnwrap(SleepStager.hrOnlySessions(hr: night(), rr: rr, resp: []).first)
        XCTAssertNotNil(session.avgHRV)
        let json = try XCTUnwrap(AnalyticsEngine.encodeStages(session.stages, hrOnly: session.hrOnly))
        XCTAssertTrue(json.contains("\"hrOnly\":true"))
        XCTAssertEqual(try JSONDecoder().decode([StageSegment].self, from: Data(json.utf8)), session.stages)
    }

    func testAnalyticsFallbackRetainsTheCustomWorkoutPipeline() throws {
        let hr = night().map { sample in
            HRSample(ts: sample.ts, bpm: (10 * 3600..<11 * 3600).contains(sample.ts) ? 150 : sample.bpm)
        }
        let legacy = AnalyticsEngine.analyzeDay(day: "1970-01-01", hr: hr,
                                                profile: UserProfile(age: 30))
        XCTAssertTrue(legacy.sleepSessions.isEmpty)
        let result = AnalyticsEngine.analyzeDay(day: "1970-01-01", hr: hr,
                                                profile: UserProfile(age: 30), useHROnlySleep: true)
        XCTAssertFalse(result.sleepSessions.isEmpty)
        XCTAssertTrue(result.sleepSessions.allSatisfy(\.hrOnly))
        XCTAssertTrue(try XCTUnwrap(result.cachedSleep.first?.stagesJSON).contains("\"hrOnly\":true"))
        XCTAssertNotNil(result.daily.restingHr)
        XCTAssertNil(result.daily.avgHrv)
        XCTAssertNil(result.daily.recovery)
        XCTAssertEqual(result.workouts.count, 1)
        XCTAssertEqual(result.workouts.first?.start, 10 * 3600)
        XCTAssertEqual(result.workouts.first?.end, 11 * 3600 - 1)
    }

    func testPartialFlatDownloadAndOffWristDoNotBecomeSleep() {
        for bpm in [55, 140] {
            let flat = (0..<2 * 3600).map { HRSample(ts: $0, bpm: bpm) }
            XCTAssertTrue(SleepStager.hrOnlySessions(hr: flat, rr: [], resp: []).isEmpty)
        }
        XCTAssertTrue(SleepStager.hrOnlySessions(hr: night(), rr: [], resp: [],
                                                wristOff: [(0, 12 * 3600)]).isEmpty)
    }

    func testMissingHRGapIsNotFilledAsAnUnbrokenNight() {
        let hr = night().filter { !(3 * 3600..<4 * 3600).contains($0.ts) }
        let sessions = SleepStager.hrOnlySessions(hr: hr, rr: [], resp: [])
        XCTAssertGreaterThanOrEqual(sessions.count, 2)
        XCTAssertFalse(sessions.contains { $0.start < 3 * 3600 && $0.end > 4 * 3600 })
    }

    func testFragmentRescueDoesNotChangeAlreadyViableDenseNights() {
        XCTAssertTrue(SleepStager.isFragmentedToNothing([1800, 2400], minSleepS: 3600))
        XCTAssertFalse(SleepStager.isFragmentedToNothing([1800, 5400], minSleepS: 3600))
        XCTAssertFalse(SleepStager.isFragmentedToNothing([1800], minSleepS: 3600))
    }

    func testMotionLabelledGapNeedsLowHRAndLimitedDuration() {
        let periods = [
            SleepStager.Period(stage: "sleep", start: 0, end: 3000),
            SleepStager.Period(stage: "active", start: 3000, end: 4800),
            SleepStager.Period(stage: "sleep", start: 4800, end: 7800)
        ]
        for bpm in [55, 120] {
            let gapHR = (3001...4800).map { HRSample(ts: $0, bpm: bpm) }
            let bridged = SleepStager.bridgeSparseSleep(periods, sparse: true, hr: gapHR, baseline: 70)
            XCTAssertEqual(bridged.count, bpm == 55 ? 1 : 3)
            let unchanged = SleepStager.bridgeSparseSleep(periods, sparse: false, hr: gapHR, baseline: 70)
            XCTAssertEqual(unchanged.map(\.start), periods.map(\.start))
            XCTAssertEqual(unchanged.map(\.end), periods.map(\.end))
            XCTAssertEqual(unchanged.map(\.stage), periods.map(\.stage))
        }
        let longGap = [
            SleepStager.Period(stage: "sleep", start: 0, end: 3000),
            SleepStager.Period(stage: "active", start: 3000, end: 6660),
            SleepStager.Period(stage: "sleep", start: 6660, end: 9660)
        ]
        let lowHR = (3001...6660).map { HRSample(ts: $0, bpm: 55) }
        XCTAssertEqual(SleepStager.bridgeSparseSleep(longGap, sparse: true, hr: lowHR, baseline: 70).count, 3)
        XCTAssertEqual(SleepStager.bridgeSparseSleep(periods, sparse: true, hr: [], baseline: 70).count, 3)
    }
}
