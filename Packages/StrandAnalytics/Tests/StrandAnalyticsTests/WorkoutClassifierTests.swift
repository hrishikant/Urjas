import XCTest
import WhoopProtocol
@testable import StrandAnalytics

final class WorkoutClassifierTests: XCTestCase {

    private let rest = 55
    private let maxHR: Double = 190

    // Build a 1 Hz HR series (bpm per second) starting at ts=0.
    private func series(_ bpm: [Int]) -> [HRSample] {
        bpm.enumerated().map { HRSample(ts: $0.offset, bpm: $0.element) }
    }

    func testTooShortReturnsNil() {
        XCTAssertNil(WorkoutClassifier.classify(hr: series(Array(repeating: 120, count: 5)),
                                                restingBpm: rest, maxBpm: maxHR))
    }

    func testSteadyHighIsEndurance() {
        // 20 min holding ~150 bpm, tiny jitter → steady, high duty cycle, low CV.
        let bpm = (0..<1200).map { 150 + ($0 % 3) - 1 }        // 149..151
        let r = WorkoutClassifier.classify(hr: series(bpm), restingBpm: rest, maxBpm: maxHR)
        XCTAssertEqual(r?.family, .endurance)
        XCTAssertEqual(r?.suggestedSports.first, "Running")
    }

    func testLowIntensityIsMobility() {
        // 20 min at ~95 bpm (below the gate of rest+30=85? -> 95>85). Use ~80 to sit low %HRR & below gate.
        let bpm = Array(repeating: 78, count: 1200)            // %HRR ≈ (78-55)/135 ≈ 0.17, below gate 85
        let r = WorkoutClassifier.classify(hr: series(bpm), restingBpm: rest, maxBpm: maxHR)
        XCTAssertEqual(r?.family, .mobility)
        XCTAssertEqual(r?.suggestedSports.first, "Yoga")
    }

    func testSpikyLowDutyIsStrength() {
        // Sets: 30s hard (150) then 60s rest (70), repeated → high CV, low duty cycle.
        var bpm: [Int] = []
        for _ in 0..<12 {
            bpm += Array(repeating: 150, count: 30)
            bpm += Array(repeating: 70, count: 60)
        }
        let r = WorkoutClassifier.classify(hr: series(bpm), restingBpm: rest, maxBpm: maxHR)
        XCTAssertEqual(r?.family, .strength)
        XCTAssertEqual(r?.suggestedSports.first, "Strength")
    }

    func testFrequentSurgesSustainedIsIntervals() {
        // Court-sport sawtooth: 20s hard (165) / 15s jog (110), mostly above the gate, frequent surges.
        var bpm: [Int] = []
        for _ in 0..<25 {
            bpm += Array(repeating: 165, count: 20)
            bpm += Array(repeating: 110, count: 15)
        }
        let r = WorkoutClassifier.classify(hr: series(bpm), restingBpm: rest, maxBpm: maxHR)
        XCTAssertEqual(r?.family, .intervals)
        XCTAssertTrue(r!.suggestedSports.contains("Badminton"))
    }

    func testFeaturesAreSane() {
        let bpm = Array(repeating: 150, count: 600)
        let f = WorkoutClassifier.classify(hr: series(bpm), restingBpm: rest, maxBpm: maxHR)!.features
        XCTAssertEqual(f.meanBpm, 150, accuracy: 0.5)
        XCTAssertEqual(f.durationMin, 599.0 / 60.0, accuracy: 0.1)
        XCTAssertEqual(f.dutyCycle, 1.0, accuracy: 0.001)          // all above gate
        XCTAssertGreaterThan(f.meanPctHRR, 0.6)
    }

    func testConfidenceInRange() {
        let bpm = (0..<1200).map { 150 + ($0 % 3) - 1 }
        let c = WorkoutClassifier.classify(hr: series(bpm), restingBpm: rest, maxBpm: maxHR)!.confidence
        XCTAssertGreaterThanOrEqual(c, 0.0)
        XCTAssertLessThanOrEqual(c, 1.0)
    }
}
