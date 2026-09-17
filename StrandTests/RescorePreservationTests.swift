import XCTest
import WhoopStore
@testable import Strand

final class RescorePreservationTests: XCTestCase {
    private func daily(day: String = "2026-09-17", hrv: Double? = nil,
                       recovery: Double? = nil, sleep: Double? = 420) -> DailyMetric {
        DailyMetric(day: day, totalSleepMin: sleep, efficiency: 0.9,
                    deepMin: 80, remMin: 90, lightMin: 250, disturbances: 2,
                    restingHr: 58, avgHrv: hrv, recovery: recovery, strain: 12, exerciseCount: 2,
                    spo2Pct: 97, skinTempDevC: 0.3, respRateBpm: 15, steps: 4000,
                    activeKcalEst: 400, spo2Red: 100, spo2Ir: 200)
    }

    func testMissingRRPreservesSnapshotAndAllFreshWorkoutAndSleepFields() {
        let fresh = daily()
        let result = RescorePreservation.retainingMissingRR(
            fresh, previous: daily(hrv: 48, recovery: 72),
            sameOwner: true, hasSleepRR: false, hasSleepEdits: false)
        XCTAssertEqual(result, daily(hrv: 48, recovery: 72))
    }

    func testCurrentMeasurementAlwaysWins() {
        let fresh = daily(hrv: 55, recovery: 80)
        XCTAssertEqual(RescorePreservation.retainingMissingRR(
            fresh, previous: daily(hrv: 48, recovery: 72),
            sameOwner: true, hasSleepRR: false, hasSleepEdits: false), fresh)
    }

    func testRejectedRRDoesNotReviveAnOldScore() {
        let fresh = daily()
        XCTAssertEqual(RescorePreservation.retainingMissingRR(
            fresh, previous: daily(hrv: 48, recovery: 72),
            sameOwner: true, hasSleepRR: true, hasSleepEdits: false), fresh)
    }

    func testSleepEditsAndProviderChangesDoNotCarryOldScores() {
        let fresh = daily()
        for (sameOwner, edited) in [(false, false), (true, true)] {
            XCTAssertEqual(RescorePreservation.retainingMissingRR(
                fresh, previous: daily(hrv: 48, recovery: 72),
                sameOwner: sameOwner, hasSleepRR: false, hasSleepEdits: edited), fresh)
        }
    }

    func testMissingSleepOrNoPriorMeasurementStaysMissing() {
        let durations: [Double?] = [nil, 0]
        for sleep in durations {
            let fresh = daily(sleep: sleep)
            XCTAssertEqual(RescorePreservation.retainingMissingRR(
                fresh, previous: daily(hrv: 48, recovery: 72),
                sameOwner: true, hasSleepRR: false, hasSleepEdits: false), fresh)
        }
        for previous in [nil, daily(), daily(day: "2026-09-16", hrv: 48, recovery: 72)] {
            let fresh = daily()
            XCTAssertEqual(RescorePreservation.retainingMissingRR(
                fresh, previous: previous, sameOwner: true,
                hasSleepRR: false, hasSleepEdits: false), fresh)
        }
    }

    func testPreservedScoreAndProvenancePersistTogether() async throws {
        let store = try await WhoopStore.inMemory()
        let old = daily(hrv: 48, recovery: 72)
        let provenance = ScoreInputProvenanceRow(day: old.day, key: "recovery", sourceId: "strap")
        try await store.persistComputedScores(dailyMetrics: [old], metricPoints: [],
                                               provenance: [provenance], deviceId: "my-whoop-noop",
                                               from: old.day, to: old.day)
        let prior = try await store.dailyMetrics(deviceId: "my-whoop-noop", from: old.day, to: old.day).first
        let owner = try await store.scoreInputSource(deviceId: "my-whoop-noop", day: old.day, key: "recovery")
        let result = RescorePreservation.retainingMissingRR(
            daily(), previous: prior, sameOwner: owner == "strap",
            hasSleepRR: false, hasSleepEdits: false)
        try await store.persistComputedScores(dailyMetrics: [result], metricPoints: [],
                                               provenance: [provenance], deviceId: "my-whoop-noop",
                                               from: old.day, to: old.day)
        let saved = try await store.dailyMetrics(deviceId: "my-whoop-noop", from: old.day, to: old.day).first
        let savedOwner = try await store.scoreInputSource(deviceId: "my-whoop-noop", day: old.day, key: "recovery")
        XCTAssertEqual(saved, old)
        XCTAssertEqual(savedOwner, "strap")
    }
}
