import XCTest
@testable import StrandAnalytics
import WhoopProtocol

/// End-to-end MIMIC of the after-sync sport-prediction path the app now runs (WorkoutTypeFeatureExtractor
/// -> WorkoutTypeClassifier). Each case synthesizes REALISTIC per-second strap streams for one activity —
/// HR shape (smooth vs bursty), wrist-motion intensity (magnitude + regularity), and the strap's own
/// activity-class ticks (still/walk/run) — then asserts the pipeline lands on the right coarse family and
/// prints a full trace (features + top-3 scores + the concrete label the UI would show) so accuracy is
/// visible, not just pass/fail.
final class MimicSportAccuracyTests: XCTestCase {

    // MARK: - Stream synthesis knobs

    /// Build a full window of the three decoded streams from high-level, physically-motivated knobs.
    /// - hrBase/hrWork: resting-ish vs working BPM. `bursty` alternates work/rest blocks (sets, rallies)
    ///   to raise HR CV; smooth efforts stay near hrWork.
    /// - motionLevel: mean per-second wrist orientation-change magnitude.
    /// - motionSpread: how far each second deviates from motionLevel (drives motion VARIANCE).
    /// - motionBursty: when true, motion alternates near-0 (pause) and high (action) -> high motion CV
    ///   (irregular, court/HIIT); when false, motion stays near motionLevel -> low CV (regular, swim/row).
    /// - tickClass: per-second strap activity class (0 still / 1 walk / 2 run), or nil for none.
    private func makeStreams(
        durationMin: Int,
        hrBase: Int, hrWork: Int, bursty: Bool,
        motionLevel: Double, motionSpread: Double, motionBursty: Bool,
        tick: (_ second: Int) -> Int?
    ) -> (hr: [HRSample], gravity: [GravitySample], steps: [StepSample], start: Int, end: Int) {
        let start = 1_700_000_000
        let n = durationMin * 60
        var hr: [HRSample] = []; hr.reserveCapacity(n)
        var grav: [GravitySample] = []; grav.reserveCapacity(n + 1)
        var steps: [StepSample] = []; steps.reserveCapacity(n)

        // Deterministic pseudo-noise so runs are reproducible (no XCTest flakiness).
        var seed: UInt64 = 0x9E3779B97F4A7C15
        func rand() -> Double { // 0..<1
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Double((seed >> 33) & 0xFFFFFF) / Double(0x1000000)
        }

        var x = 0.0
        // Prime one gravity sample before the window so the first in-window delta is real.
        grav.append(GravitySample(ts: start - 1, x: x, y: 0, z: 0))

        var counter = 0
        for i in 0..<n {
            let ts = start + i
            // ── HR ──
            let workBlock = ((i / 90) % 2 == 0) // 90 s work / 90 s ease blocks when bursty
            let targetHR: Double
            if bursty {
                // Realistic sets/rallies-then-pause swing (~34 bpm), not an extreme 60+ bpm sawtooth —
                // real court/strength HR CV lands ~0.10–0.14, which is what the classifier must handle.
                targetHR = workBlock ? Double(hrWork) : Double(hrWork - 34)
            } else {
                targetHR = Double(hrWork)
            }
            let hrJitter = (rand() - 0.5) * 4.0
            hr.append(HRSample(ts: ts, bpm: max(40, Int((targetHR + hrJitter).rounded()))))

            // ── Motion intensity for this second ──
            var inten: Double
            if motionBursty {
                // action/pause alternation on a ~6 s cycle -> high CV
                let action = (i % 6) < 4
                inten = action ? motionLevel + motionSpread * (rand()) : motionLevel * 0.08 * rand()
            } else {
                inten = max(0, motionLevel + (rand() - 0.5) * 2.0 * motionSpread)
            }
            let sign = (i % 2 == 0) ? 1.0 : -1.0
            x += sign * inten
            grav.append(GravitySample(ts: ts, x: x, y: 0, z: 0))

            // ── Steps / activity class ──
            if let cls = tick(i) {
                if cls != 0 { counter += (cls == 2 ? 3 : 2) }
                steps.append(StepSample(ts: ts, counter: counter, activityClass: cls))
            }
        }
        return (hr, grav, steps, start, start + n - 1)
    }

    private func run(_ name: String,
                     _ s: (hr: [HRSample], gravity: [GravitySample], steps: [StepSample], start: Int, end: Int),
                     restingHR: Double = 55, maxHR: Double = 190, kcal: Double? = nil) -> WorkoutClassPrediction {
        let feats = WorkoutTypeFeatureExtractor.extract(
            hr: s.hr, gravity: s.gravity, steps: s.steps, start: s.start, end: s.end,
            restingHR: restingHR, maxHR: maxHR, caloriesKcal: kcal)!
        let pred = WorkoutTypeClassifier.classify(feats)
        let top3 = pred.scores.sorted { $0.value > $1.value }.prefix(3)
            .map { "\($0.key.rawValue) \(String(format: "%.2f", $0.value))" }.joined(separator: " › ")
        let label = pred.predictedClass.suggestedSports.first ?? "—"
        print(String(format: """
        ┏━━ %@
        ┃ features  : hrCV=%.3f meanHRR=%.0f%%  motionVar=%.3f motionCV=%.2f  still/walk/run=%.2f/%.2f/%.2f tickCov=%.2f
        ┃ scores    : %@
        ┃ PREDICT   : %@  (conf %.2f) → label "%@"
        ┗━━
        """, name, feats.hrCV, (feats.meanHRRPct ?? -1), feats.motionVariance, feats.motionCV,
        feats.stillFraction, feats.walkFraction, feats.runFraction, feats.tickCoverage,
        top3, pred.predictedClass.rawValue, pred.confidence, label))
        return pred
    }

    // MARK: - The mimics

    func testMimicAccuracyAcrossSports() {
        // SWIMMING (freestyle): phone benched; strap on wrist sweeps continuously & regularly; HR smooth
        // and elevated; strap step-class reads mostly "still" (no foot-strike underwater).
        let swim = run("SWIMMING (freestyle, 30 min)", makeStreams(
            durationMin: 30, hrBase: 55, hrWork: 150, bursty: false,
            motionLevel: 0.9, motionSpread: 0.25, motionBursty: false,
            tick: { _ in 0 }), kcal: 11)
        XCTAssertEqual(swim.predictedClass, .rhythmicCardio, "swim should be rhythmic cardio")

        // ROWING (erg): continuous regular drive/recovery, smooth HR, some arm motion, still ticks.
        let row = run("ROWING (erg, 25 min)", makeStreams(
            durationMin: 25, hrBase: 55, hrWork: 145, bursty: false,
            motionLevel: 0.75, motionSpread: 0.30, motionBursty: false,
            tick: { _ in 0 }), kcal: 10)
        XCTAssertEqual(row.predictedClass, .rhythmicCardio, "rowing should be rhythmic cardio")

        // TENNIS: bursty HR (rallies then pauses), irregular start-stop wrist motion, player moves so
        // strap logs some walk/run ticks.
        let tennis = run("TENNIS (45 min)", makeStreams(
            durationMin: 45, hrBase: 60, hrWork: 158, bursty: true,
            motionLevel: 0.35, motionSpread: 0.55, motionBursty: true,
            tick: { i in (i % 6 < 4) ? ((i % 18 < 3) ? 2 : 1) : 0 }), kcal: 9)
        XCTAssertEqual(tennis.predictedClass, .court, "tennis should be court")

        // BADMINTON: like tennis but lighter, quicker bursts; still court family.
        let badminton = run("BADMINTON (40 min)", makeStreams(
            durationMin: 40, hrBase: 60, hrWork: 150, bursty: true,
            motionLevel: 0.30, motionSpread: 0.50, motionBursty: true,
            tick: { i in (i % 6 < 4) ? ((i % 20 < 2) ? 2 : 1) : 0 }), kcal: 8)
        XCTAssertEqual(badminton.predictedClass, .court, "badminton should be court")

        // GYM / STRENGTH: sets-then-rest bursty HR, LOW wrist-motion magnitude, still-dominant ticks.
        let gym = run("GYM / STRENGTH (40 min)", makeStreams(
            durationMin: 40, hrBase: 65, hrWork: 130, bursty: true,
            motionLevel: 0.06, motionSpread: 0.05, motionBursty: true,
            tick: { _ in 0 }), kcal: 6)
        XCTAssertEqual(gym.predictedClass, .strength, "gym should be strength")

        // RUNNING (outdoor): steady high HR, run-class ticks dominate.
        let running = run("RUNNING (outdoor, 30 min)", makeStreams(
            durationMin: 30, hrBase: 60, hrWork: 165, bursty: false,
            motionLevel: 0.22, motionSpread: 0.10, motionBursty: false,
            tick: { _ in 2 }), kcal: 13)
        XCTAssertEqual(running.predictedClass, .run, "running should be run")

        // WALKING: low steady HR, walk-class ticks dominate, low motion.
        let walking = run("WALKING (brisk, 30 min)", makeStreams(
            durationMin: 30, hrBase: 55, hrWork: 95, bursty: false,
            motionLevel: 0.05, motionSpread: 0.02, motionBursty: false,
            tick: { _ in 1 }), kcal: 4)
        XCTAssertEqual(walking.predictedClass, .walk, "walking should be walk")

        // CYCLING (steady): smooth elevated HR, very low wrist motion (hands on bars), still ticks.
        let cycle = run("CYCLING (steady, 40 min)", makeStreams(
            durationMin: 40, hrBase: 58, hrWork: 140, bursty: false,
            motionLevel: 0.03, motionSpread: 0.02, motionBursty: false,
            tick: { _ in 0 }), kcal: 9)
        XCTAssertEqual(cycle.predictedClass, .cycle, "cycling should be cycle")
    }
}
