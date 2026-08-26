import XCTest
import WhoopProtocol
@testable import StrandAnalytics

/// Diagnostic harness: mimic realistic TENNIS vs BADMINTON sessions (HR shape + phone motion + GPS +
/// cadence) and print what the live pipeline (WorkoutClassifier -> SportRanker) actually predicts. This
/// is not a pass/fail spec of desired behaviour so much as a truth probe of the CURRENT engine, so we can
/// see exactly where court-sport detection stands and where the false positives come from.
final class CourtSportDiagnosticsTests: XCTestCase {

    // MARK: - Synthetic HR generators

    /// Build an HR window (1 Hz) from a mean/spikiness/surge profile.
    private func hr(minutes: Int, base: Int, rest: Int,
                    surgeAmp: Int, surgePeriodSec: Int, jitter: Int) -> [HRSample] {
        var out: [HRSample] = []
        var seed: UInt64 = 0x9E3779B97F4A7C15
        func rnd() -> Double { // cheap deterministic LCG in 0..<1
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Double(seed >> 33) / Double(1 << 31)
        }
        let n = minutes * 60
        for i in 0..<n {
            // Surge shape: a raised-cosine burst every surgePeriodSec seconds.
            let phase = Double(i % surgePeriodSec) / Double(surgePeriodSec)
            let surge = surgeAmp > 0 ? Int(Double(surgeAmp) * max(0, cos(2 * .pi * phase))) : 0
            let noise = Int((rnd() - 0.5) * 2 * Double(jitter))
            let ramp = i < 90 ? Int(Double(base - rest) * Double(i) / 90.0) : (base - rest)
            let bpm = rest + ramp + surge + noise
            out.append(HRSample(ts: 1_700_000_000 + i, bpm: max(rest, bpm)))
        }
        return out
    }

    private func report(_ label: String, hr: [HRSample], signals: SportSignals,
                        rest: Int = 55, maxHR: Double = 190) {
        let res = WorkoutClassifier.classify(hr: hr, restingBpm: rest, maxBpm: maxHR)
        let sig = SportSignals(family: res?.family, motion: signals.motion,
                               motionConfidence: signals.motionConfidence,
                               speedMps: signals.speedMps, cadenceSpm: signals.cadenceSpm)
        let top = SportRanker.topPick(sig)
        let rank = Array(SportRanker.rank(sig).prefix(6))
        print("""

        ┏━━ \(label)
        ┃ HR family     : \(res.map { "\($0.family.rawValue) (conf \(String(format: "%.2f", $0.confidence)))" } ?? "nil")
        ┃ HR features   : mean=\(Int(res?.features.meanBpm ?? 0)) cv=\(String(format: "%.3f", res?.features.cv ?? 0)) surges/min=\(String(format: "%.2f", res?.features.surgesPerMin ?? 0)) duty=\(String(format: "%.2f", res?.features.dutyCycle ?? 0))
        ┃ Phone motion  : \(signals.motion.rawValue) (conf \(signals.motionConfidence)) speed=\(signals.speedMps.map { String(format: "%.1f m/s", $0) } ?? "nil") cadence=\(signals.cadenceSpm.map { String(format: "%.0f spm", $0) } ?? "nil")
        ┃ CONFIDENT PICK: \(top ?? "— none (labelled \"Workout\") —")
        ┃ Picker order  : \(rank.joined(separator: " › "))
        ┗━━
        """)
    }

    // MARK: - Court sports

    func testTennis() {
        // Tennis: rallies then pauses between points. Spiky (interval) HR, surges every ~25s. Phone in
        // pocket picks up court movement as intermittent WALKING with a few steps and low ground speed.
        let stream = hr(minutes: 30, base: 138, rest: 55, surgeAmp: 26, surgePeriodSec: 25, jitter: 10)
        report("TENNIS (mimicked)", hr: stream,
               signals: SportSignals(motion: .walking, motionConfidence: 1,
                                     speedMps: 0.6, cadenceSpm: 40))
    }

    func testBadminton() {
        // Badminton: very fast rallies, higher intensity, quicker surges (~20s), spikier.
        let stream = hr(minutes: 30, base: 145, rest: 55, surgeAmp: 28, surgePeriodSec: 20, jitter: 8)
        report("BADMINTON (mimicked)", hr: stream,
               signals: SportSignals(motion: .stationary, motionConfidence: 1,
                                     speedMps: 0.3, cadenceSpm: 20))
    }

    // MARK: - False-positive probes (the user's actual complaint)

    func testStandUpAndGrabWater() {
        // Brief HR bump from standing up: short, low, no real motion. Should NOT look like a workout.
        let stream = hr(minutes: 3, base: 95, rest: 60, surgeAmp: 8, surgePeriodSec: 60, jitter: 4)
        report("FALSE +: stand up / grab water", hr: stream,
               signals: SportSignals(motion: .stationary, motionConfidence: 2,
                                     speedMps: nil, cadenceSpm: nil))
    }

    func testWalkingToKitchen() {
        // 40 s stroll. Real but trivial. Motion=walking briefly.
        let stream = hr(minutes: 2, base: 92, rest: 62, surgeAmp: 5, surgePeriodSec: 40, jitter: 3)
        report("FALSE +: short walk to kitchen", hr: stream,
               signals: SportSignals(motion: .walking, motionConfidence: 2,
                                     speedMps: 1.1, cadenceSpm: 95))
    }

    // MARK: - Ground truth the engine SHOULD get right

    func testActualRun() {
        let stream = hr(minutes: 25, base: 155, rest: 55, surgeAmp: 6, surgePeriodSec: 120, jitter: 4)
        report("RUN (should be confident)", hr: stream,
               signals: SportSignals(motion: .running, motionConfidence: 2,
                                     speedMps: 3.1, cadenceSpm: 170))
    }
}
