import XCTest
@testable import StrandAnalytics
import WhoopProtocol

final class OvernightBreathingTests: XCTestCase {

    // Build a night of 1 Hz SpO₂ samples with a flat baseline ratio and injected desaturation "notches"
    // (transient UPWARD ratio excursions = oxygen proxy falling). `ir` is fixed; `red` encodes the ratio.
    private func night(hours: Double,
                       baselineRatio: Double = 0.50,
                       notchStarts: [Int] = [],
                       notchDurSec: Int = 20,
                       notchRise: Double = 0.06,
                       startTs: Int = 1_000_000) -> [SpO2Sample] {
        let ir = 100_000
        let n = Int(hours * 3600)
        var out: [SpO2Sample] = []
        out.reserveCapacity(n)
        for i in 0..<n {
            var ratio = baselineRatio
            for s in notchStarts where i >= s && i < s + notchDurSec {
                ratio = baselineRatio * (1.0 + notchRise)
            }
            let red = Int((ratio * Double(ir)).rounded())
            out.append(SpO2Sample(ts: startTs + i, red: red, ir: ir))
        }
        return out
    }

    // MARK: - Bands

    func testSteadinessBands() {
        XCTAssertEqual(OvernightBreathing.steadiness(forDipsPerHour: 0), .steady)
        XCTAssertEqual(OvernightBreathing.steadiness(forDipsPerHour: 7.9), .steady)
        XCTAssertEqual(OvernightBreathing.steadiness(forDipsPerHour: 8), .someVariability)
        XCTAssertEqual(OvernightBreathing.steadiness(forDipsPerHour: 19.9), .someVariability)
        XCTAssertEqual(OvernightBreathing.steadiness(forDipsPerHour: 20), .frequentDips)
        XCTAssertEqual(OvernightBreathing.steadiness(forDipsPerHour: 40), .frequentDips)
    }

    // MARK: - Gates

    func testEmptyInput() {
        let r = OvernightBreathing.analyze(samples: [])
        XCTAssertNil(r.relativeDipsPerHour)
        XCTAssertEqual(r.nInput, 0)
    }

    func testCoverageGateRefusesShortNight() {
        // 1 hour < minCoverageMinutes (120) → refused.
        let r = OvernightBreathing.analyze(samples: night(hours: 1))
        XCTAssertNil(r.relativeDipsPerHour)
        XCTAssertLessThan(r.coverageMinutes, Double(OvernightBreathing.minCoverageMinutes))
    }

    func testInvalidSamplesFilteredThenCoverageGate() {
        // All non-positive → filtered out → empty.
        let bad = (0..<300).map { SpO2Sample(ts: 1000 + $0, red: 0, ir: 0) }
        let r = OvernightBreathing.analyze(samples: bad)
        XCTAssertNil(r.relativeDipsPerHour)
    }

    // MARK: - Detection

    func testFlatNightHasNoDipsAndIsSteady() {
        let r = OvernightBreathing.analyze(samples: night(hours: 3))
        XCTAssertNotNil(r.relativeDipsPerHour)
        XCTAssertEqual(r.dipCount, 0)
        XCTAssertEqual(r.steadiness, .steady)
        XCTAssertGreaterThanOrEqual(r.coverageMinutes, 120)
    }

    func testCountsInjectedNotches() {
        // 6 notches over ~3 h, spaced 1800 s apart (well beyond maxEventSec/mergeGap) → 6 discrete dips.
        let starts = [600, 2400, 4200, 6000, 7800, 9600]
        let r = OvernightBreathing.analyze(samples: night(hours: 3, notchStarts: starts))
        XCTAssertEqual(r.dipCount, 6, "each injected desaturation notch should count once")
        XCTAssertNotNil(r.relativeDipsPerHour)
        XCTAssertEqual(r.steadiness, .steady) // 6 / 3h = 2/h < 8
    }

    func testFrequentNotchesGiveFrequentDipsBand() {
        // 75 notches over 3 h, every 144 s → 25/h → frequentDips.
        let starts = stride(from: 300, to: 300 + 75 * 144, by: 144).map { $0 }
        let r = OvernightBreathing.analyze(samples: night(hours: 3.1, notchStarts: starts))
        XCTAssertEqual(r.dipCount, 75)
        XCTAssertEqual(r.steadiness, .frequentDips)
        XCTAssertGreaterThan(r.relativeDipsPerHour!, OvernightBreathing.someVariabilityMax)
    }

    func testTooShortNotchIsRejected() {
        // 4 s notch < minEventSec(8) → not counted.
        let r = OvernightBreathing.analyze(samples: night(hours: 3, notchStarts: [1000], notchDurSec: 4))
        XCTAssertEqual(r.dipCount, 0)
    }

    func testTooLongExcursionIsRejected() {
        // 300 s excursion > maxEventSec(120) → a baseline shift, not a dip → not counted.
        let r = OvernightBreathing.analyze(samples: night(hours: 3, notchStarts: [2000], notchDurSec: 300))
        XCTAssertEqual(r.dipCount, 0)
    }

    // MARK: - Median helper

    func testMedian() {
        XCTAssertEqual(OvernightBreathing.median([3, 1, 2]), 2, accuracy: 1e-9)
        XCTAssertEqual(OvernightBreathing.median([4, 1, 3, 2]), 2.5, accuracy: 1e-9)
        XCTAssertEqual(OvernightBreathing.median([]), 0, accuracy: 1e-9)
    }
}
