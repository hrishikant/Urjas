import XCTest
@testable import StrandAnalytics
import WhoopProtocol

final class DFAAlpha1Tests: XCTestCase {

    // MARK: - Deterministic pseudo-random source (so tests never flake).

    /// Tiny reproducible LCG (Numerical Recipes constants). Returns a Double in [-1, 1).
    private struct LCG {
        var state: UInt64
        init(seed: UInt64) { state = seed }
        mutating func nextUnit() -> Double {
            state = 6364136223846793005 &* state &+ 1442695040888963407
            let top = Double(state >> 11) / Double(UInt64(1) << 53) // [0,1)
            return top * 2.0 - 1.0
        }
    }

    // MARK: - Zone mapping thresholds

    func testZoneMappingBoundaries() {
        XCTAssertEqual(DFAAlpha1.zone(forAlpha1: 1.10), .easy)
        XCTAssertEqual(DFAAlpha1.zone(forAlpha1: 0.75), .easy)      // inclusive at aerobic threshold
        XCTAssertEqual(DFAAlpha1.zone(forAlpha1: 0.7499), .moderate)
        XCTAssertEqual(DFAAlpha1.zone(forAlpha1: 0.50), .moderate)  // inclusive at anaerobic threshold
        XCTAssertEqual(DFAAlpha1.zone(forAlpha1: 0.4999), .hard)
        XCTAssertEqual(DFAAlpha1.zone(forAlpha1: 0.20), .hard)
    }

    // MARK: - leastSquaresSlope

    func testLeastSquaresSlopeKnown() {
        // y = 2x + 1 → slope 2.
        let x = [0.0, 1, 2, 3, 4]
        let y = x.map { 2 * $0 + 1 }
        XCTAssertEqual(DFAAlpha1.leastSquaresSlope(x: x, y: y)!, 2.0, accuracy: 1e-9)
    }

    func testLeastSquaresSlopeDegenerate() {
        XCTAssertNil(DFAAlpha1.leastSquaresSlope(x: [1, 1, 1], y: [1, 2, 3]))
        XCTAssertNil(DFAAlpha1.leastSquaresSlope(x: [1], y: [1]))
    }

    // MARK: - detrendedSumSq

    func testDetrendedResidualOfLineIsZero() {
        // A perfectly linear profile fits exactly → zero residual.
        let y = (0..<10).map { 3.0 * Double($0) - 4.0 }
        XCTAssertEqual(DFAAlpha1.detrendedSumSq(y, start: 0, length: 10), 0.0, accuracy: 1e-9)
    }

    // MARK: - Gates

    func testEmptyInput() {
        let r = DFAAlpha1.analyze(rrMs: [])
        XCTAssertNil(r.alpha1)
        XCTAssertNil(r.zone)
        XCTAssertEqual(r.nInput, 0)
        XCTAssertNil(r.artifactFraction)
    }

    func testTooFewCleanBeatsRefused() {
        let rr = Array(repeating: 800.0, count: DFAAlpha1.minBeats - 1)
        let r = DFAAlpha1.analyze(rrMs: rr)
        XCTAssertNil(r.alpha1)
        XCTAssertEqual(r.nInput, DFAAlpha1.minBeats - 1)
    }

    func testArtifactGateRefusesNoisyCapture() {
        // Half the beats are physiologically impossible (dropped by range filter) → artifactFraction 0.5
        // > maxArtifactFraction → refused even though > minBeats survive.
        var rr: [Double] = []
        for _ in 0..<80 { rr.append(800); rr.append(50) } // 50 ms is far below rrMin (300) → dropped
        let r = DFAAlpha1.analyze(rrMs: rr)
        XCTAssertNil(r.alpha1, "should refuse when artifact fraction exceeds the gate")
        XCTAssertGreaterThan(r.artifactFraction!, DFAAlpha1.maxArtifactFraction)
    }

    // MARK: - Behavioural: α1 discriminates correlated vs uncorrelated dynamics

    func testWhiteNoiseGivesLowAlpha1AndBrownGivesHigher() {
        var rng = LCG(seed: 0xC0FFEE)

        // Uncorrelated (white) R-R around 800 ms: DFA α1 ≈ 0.5 (finite-size may nudge it a little).
        var white: [Double] = []
        for _ in 0..<400 { white.append(800 + 30 * rng.nextUnit()) }

        // Strongly correlated ("brown"): a bounded random walk → long-range correlated → α1 well above white.
        var brown: [Double] = []
        var v = 800.0
        for _ in 0..<400 {
            v += 8 * rng.nextUnit()
            v = min(1000, max(600, v)) // keep physiological so the range filter doesn't distort the test
            brown.append(v)
        }

        let rw = DFAAlpha1.analyze(rrMs: white)
        let rb = DFAAlpha1.analyze(rrMs: brown)

        XCTAssertNotNil(rw.alpha1)
        XCTAssertNotNil(rb.alpha1)
        // White noise sits below the aerobic threshold's "easy" region and near 0.5.
        XCTAssertLessThan(rw.alpha1!, 0.85)
        XCTAssertGreaterThan(rw.alpha1!, 0.20)
        // Correlated dynamics score meaningfully higher.
        XCTAssertGreaterThan(rb.alpha1!, rw.alpha1! + 0.2)
    }

    func testResultCarriesCleanCountsAndZone() {
        var rng = LCG(seed: 42)
        var brown: [Double] = []
        var v = 850.0
        for _ in 0..<300 {
            v += 6 * rng.nextUnit()
            v = min(1000, max(650, v))
            brown.append(v)
        }
        let r = DFAAlpha1.analyze(rrMs: brown)
        XCTAssertNotNil(r.alpha1)
        XCTAssertNotNil(r.zone)
        XCTAssertEqual(r.nInput, 300)
        XCTAssertGreaterThanOrEqual(r.nClean, DFAAlpha1.minBeats)
        XCTAssertEqual(r.zone, DFAAlpha1.zone(forAlpha1: r.alpha1!))
    }
}
