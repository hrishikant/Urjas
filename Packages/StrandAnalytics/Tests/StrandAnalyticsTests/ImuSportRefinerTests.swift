import XCTest
@testable import StrandAnalytics
import WhoopProtocol

/// Synthetic-IMU tests for the within-family `ImuSportRefiner`. Each case injects a 100 Hz 6-axis
/// signature designed to mimic one sport's WRIST dynamics — swing frequency, rotational (gyro) energy,
/// and impact (jerk) — runs it through the real `ImuFeatureExtractor` (no shortcut), and asserts the
/// refiner recovers the intended concrete sport WITHIN the coarse family the 1 Hz classifier already
/// established. Per the repo's derived-signal rule these are shape-recovery proofs, not a calibration
/// against real labels (that's on-device follow-up).
final class ImuSportRefinerTests: XCTestCase {

    /// Build `n` samples at 100 Hz. Accel rides a gravity baseline with either a sinusoidal swing
    /// (`accelHz`) or sharp periodic SPIKES (`spikeAmp`, for explosive wrist snaps); gyro magnitude is a
    /// steady rotational-energy level. Motion is on single axes — the extractor takes magnitudes, so this
    /// exercises accel-energy / jerk / gyro-energy / cadence exactly as a real capture would.
    private func imu(n: Int = 500, accelAmp: Double = 0, accelHz: Double = 1,
                     gyro: Double, spikeAmp: Double = 0, spikePeriod: Int = 30) -> [RawImuSample] {
        (0..<n).map { i in
            var m = 1.0
            if spikeAmp > 0 { if i % spikePeriod < 2 { m += spikeAmp } }
            else { m += accelAmp * sin(2 * Double.pi * accelHz * Double(i) / 100.0) }
            return RawImuSample(ax: m, ay: 0, az: 0, gx: gyro, gy: 0, gz: 0)
        }
    }

    private func refine(_ coarse: CoarseWorkoutClass, _ samples: [RawImuSample]) -> ImuSportRefiner.Refinement? {
        let f = ImuFeatureExtractor.extract(samples, sampleRateHz: 100)
        return ImuSportRefiner.refine(coarse: coarse, imu: f)
    }

    // MARK: - COURT family

    func testTennis_wholeArmSwing_highAccel() {
        // Big groundstroke swings at 0.6 Hz → high accel translation, moderate gyro, no gait cadence.
        let r = refine(.court, imu(accelAmp: 0.5, accelHz: 0.6, gyro: 80))
        XCTAssertEqual(r?.sport, "Tennis", "reason: \(r?.reason ?? "nil")")
    }

    func testBadminton_wristSnap_highGyroHighJerk() {
        // Explosive wrist flicks: sharp accel spikes (high jerk) + high rotational energy, low sustained
        // whole-arm translation.
        let r = refine(.court, imu(gyro: 180, spikeAmp: 0.8, spikePeriod: 30))
        XCTAssertEqual(r?.sport, "Badminton", "reason: \(r?.reason ?? "nil")")
    }

    func testSquash_rhythmicSwings_cadencePeak() {
        // Continuous rhythmic swinging at 2 Hz (in the gait band) — modest accel, modest gyro, no
        // explosive jerk → falls through to the swing-cadence branch.
        let r = refine(.court, imu(accelAmp: 0.25, accelHz: 2.0, gyro: 90))
        XCTAssertEqual(r?.sport, "Squash", "reason: \(r?.reason ?? "nil")")
    }

    func testCourt_tooStill_keepsFamilyDefault() {
        // Barely moving (accel below the refine floor) → nil, so the caller keeps the family default.
        XCTAssertNil(refine(.court, imu(accelAmp: 0.02, accelHz: 0.6, gyro: 20)))
    }

    // MARK: - RHYTHMIC CARDIO family

    func testSwim_wristRoll_highGyroNoGaitCadence() {
        // Stroke rate 0.7 Hz (below the gait band → no cadence peak) with strong per-stroke wrist ROLL.
        let r = refine(.rhythmicCardio, imu(accelAmp: 0.3, accelHz: 0.7, gyro: 150))
        XCTAssertEqual(r?.sport, "Pool swim", "reason: \(r?.reason ?? "nil")")
    }

    func testRowing_pull_lowGyroNoCadence() {
        // Whole-arm pull at 0.45 Hz (below band) with LITTLE wrist rotation → low gyro.
        let r = refine(.rhythmicCardio, imu(accelAmp: 0.35, accelHz: 0.45, gyro: 50))
        XCTAssertEqual(r?.sport, "Rowing", "reason: \(r?.reason ?? "nil")")
    }

    func testElliptical_handleCadence_inGaitBand() {
        // Hands ride the handles at 2 Hz (in band) → a rhythmic cadence peak wins the elliptical branch.
        let r = refine(.rhythmicCardio, imu(accelAmp: 0.25, accelHz: 2.0, gyro: 90))
        XCTAssertEqual(r?.sport, "Elliptical", "reason: \(r?.reason ?? "nil")")
    }

    // MARK: - Family gating: identical IMU refines differently per coarse family

    func testSameCadenceIMU_squashUnderCourt_ellipticalUnderRhythmic() {
        // The 2 Hz rhythmic signature is the same; only the coarse family (from HR shape) differs — and
        // that's exactly what routes it to Squash vs Elliptical. Proves IMU refines WITHIN the family.
        let samples = imu(accelAmp: 0.25, accelHz: 2.0, gyro: 90)
        XCTAssertEqual(refine(.court, samples)?.sport, "Squash")
        XCTAssertEqual(refine(.rhythmicCardio, samples)?.sport, "Elliptical")
    }

    // MARK: - Non-refinable families keep the 1 Hz default

    func testRunWalkCycleStrengthSki_returnNil() {
        let s = imu(accelAmp: 0.3, accelHz: 2.5, gyro: 100)
        for c in [CoarseWorkoutClass.run, .walk, .cycle, .strength, .ski, .other] {
            XCTAssertNil(refine(c, s), "\(c.rawValue) should keep family default")
        }
    }

    // MARK: - Refined sport is always inside the family's shortlist

    func testRefinedSportAlwaysWithinFamilyShortlist() {
        let cases: [(CoarseWorkoutClass, [RawImuSample])] = [
            (.court, imu(accelAmp: 0.5, accelHz: 0.6, gyro: 80)),
            (.court, imu(gyro: 180, spikeAmp: 0.8)),
            (.court, imu(accelAmp: 0.25, accelHz: 2.0, gyro: 90)),
            (.rhythmicCardio, imu(accelAmp: 0.3, accelHz: 0.7, gyro: 150)),
            (.rhythmicCardio, imu(accelAmp: 0.35, accelHz: 0.45, gyro: 50)),
            (.rhythmicCardio, imu(accelAmp: 0.25, accelHz: 2.0, gyro: 90)),
        ]
        for (coarse, samples) in cases {
            if let r = refine(coarse, samples) {
                XCTAssertTrue(coarse.suggestedSports.contains(r.sport),
                              "\(r.sport) not in \(coarse.rawValue) shortlist \(coarse.suggestedSports)")
            }
        }
    }
}
