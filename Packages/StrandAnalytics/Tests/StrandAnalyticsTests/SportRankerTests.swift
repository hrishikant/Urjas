import XCTest
@testable import StrandAnalytics

final class SportRankerTests: XCTestCase {

    // MARK: topPick — confident, movement-backed calls

    func testRunningFromMotionAndCadence() {
        let s = SportSignals(family: .endurance, motion: .running, motionConfidence: 2,
                             speedMps: 3.2, cadenceSpm: 168)
        XCTAssertEqual(SportRanker.topPick(s), "Running")
        XCTAssertEqual(SportRanker.rank(s).first, "Running")
    }

    func testWalkingFromMotionAndSlowSpeed() {
        let s = SportSignals(family: .mobility, motion: .walking, motionConfidence: 2,
                             speedMps: 1.4, cadenceSpm: 110)
        XCTAssertEqual(SportRanker.topPick(s), "Walking")
    }

    func testCyclingFromMotionAndHighSpeedNoSteps() {
        let s = SportSignals(family: .endurance, motion: .cycling, motionConfidence: 2,
                             speedMps: 7.5, cadenceSpm: nil)
        XCTAssertEqual(SportRanker.topPick(s), "Cycling")
    }

    /// Speed + absence of footfalls should call cycling even when the phone's motion class is unknown.
    func testCyclingFromSpeedWithoutMotionClass() {
        let s = SportSignals(family: .endurance, motion: .unknown, motionConfidence: 0,
                             speedMps: 8.0, cadenceSpm: nil)
        XCTAssertEqual(SportRanker.topPick(s), "Cycling")
    }

    // MARK: topPick — honest nil when nothing is movement-backed

    func testStationaryStrengthIsNotConfident() {
        // Gym session: stationary + strength HR shape. We must NOT confidently name it — the user picks.
        let s = SportSignals(family: .strength, motion: .stationary, motionConfidence: 2,
                             speedMps: nil, cadenceSpm: nil)
        XCTAssertNil(SportRanker.topPick(s), "stationary/strength should stay a guess, not a confident pick")
    }

    func testNoSignalsYieldsNoConfidentPick() {
        let s = SportSignals(family: nil, motion: .unknown, motionConfidence: 0)
        XCTAssertNil(SportRanker.topPick(s))
    }

    func testLowConfidenceMotionIsMuted() {
        // Motion says running but confidence is low and nothing corroborates → no confident pick.
        let s = SportSignals(family: .mobility, motion: .running, motionConfidence: 0)
        XCTAssertNil(SportRanker.topPick(s))
    }

    // MARK: rank — full, de-duplicated, likely-first list

    func testRankIsFullAndDeduplicated() {
        let s = SportSignals(family: .intervals, motion: .running, motionConfidence: 2, speedMps: 3.0)
        let ranked = SportRanker.rank(s)
        XCTAssertEqual(Set(ranked).count, ranked.count, "no duplicates")
        // Every catalogue sport is reachable.
        for name in SportRanker.catalog { XCTAssertTrue(ranked.contains(name), "missing \(name)") }
    }

    func testFamilyLeadsWhenNoMovementSignal() {
        // No motion/speed/cadence → the HR family shortlist should lead the ranking.
        let s = SportSignals(family: .intervals, motion: .unknown, motionConfidence: 0)
        let ranked = SportRanker.rank(s)
        XCTAssertEqual(ranked.first, WorkoutFamily.intervals.suggestedSports.first)
    }

    /// Moving at pace with no footfalls must rank Cycling above Running.
    func testWheelsRankAboveFeetWhenNoSteps() {
        let s = SportSignals(family: .endurance, motion: .unknown, motionConfidence: 0,
                             speedMps: 7.0, cadenceSpm: nil)
        let ranked = SportRanker.rank(s)
        let ci = ranked.firstIndex(of: "Cycling")!
        let ri = ranked.firstIndex(of: "Running")!
        XCTAssertLessThan(ci, ri)
    }

    func testCatalogMatchesWorkoutCatalogCount() {
        // Guardrail: SportRanker.catalog must stay in lockstep with the app's WorkoutCatalog list.
        XCTAssertEqual(SportRanker.catalog.count, 39)
        XCTAssertEqual(SportRanker.catalog.last, "Other")
    }
}
