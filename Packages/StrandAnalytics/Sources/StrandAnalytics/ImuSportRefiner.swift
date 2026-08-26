import Foundation
import WhoopProtocol

// ImuSportRefiner.swift — within-FAMILY concrete-sport refinement from decoded 100 Hz 6-axis IMU (#423).
//
// The 1 Hz `WorkoutTypeClassifier` resolves the coarse FAMILY (court / rhythmic-cardio / …) but, as its
// own header states, cannot separate the sport WITHIN a family (tennis vs badminton, swim vs row) — a
// ~1 Hz wrist-gravity vector is below the Nyquist limit of a racquet snap or a stroke. The 5/MG offload
// buffer's 100 Hz accel+gyro DOES resolve those: `ImuFeatureExtractor` turns a window into cadence,
// accel energy, jerk (impact/explosiveness) and gyro (wrist ROTATION) — the axes that distinguish, e.g.,
// a badminton wrist-flick (gyro/jerk dominant) from a tennis groundstroke (whole-arm accel).
//
// SHIP STATUS: first-pass HEURISTIC with documented, clamped thresholds, validated ONLY against synthetic
// IMU fixtures that each recover a distinct injected signature (see `ImuSportRefinerTests`). Like the
// coarse classifier it feeds, this is ADVISORY: it upgrades a detected bout's auto-LABEL from the family
// default to a within-family best guess, never overrides a user's own pick, and returns nil (keep the
// family default) whenever the IMU signature isn't distinctive enough. Real-world accuracy needs
// on-device validation against labeled sessions — the thresholds here are physically-motivated starting
// points, not calibrated against a user's history (none was available while writing this).

public enum ImuSportRefiner {

    // MARK: - Thresholds (deg/s for gyro, g for accel; first-pass — tune against labeled data)

    /// Gyro energy (mean |gyro|, °/s) above which wrist ROTATION dominates — a racquet snap / swim roll.
    public static let gyroHighDps = 120.0
    /// Gyro energy below which there's little wrist rotation — a rowing pull, a treadmill-steady arm.
    public static let gyroLowDps = 70.0
    /// Jerk RMS (g/sample) above which motion is EXPLOSIVE/impactful — flicks, jumps, foot-strike.
    public static let jerkHighG = 0.18
    /// Accel AC energy (g) above which whole-arm TRANSLATION dominates — a big tennis swing, a strong pull.
    public static let accelHighG = 0.30
    /// Below this accel energy the window is too still to refine confidently → keep the family default.
    public static let accelMinG = 0.06
    /// Fewer than this many samples (≈ <1 s at 100 Hz) is too little to trust → keep the family default.
    public static let minSamples = 100

    /// One refinement result: the concrete sport plus a short rationale (for the workouts trace).
    public struct Refinement: Equatable, Sendable {
        public let sport: String
        public let reason: String
        public init(sport: String, reason: String) { self.sport = sport; self.reason = reason }
    }

    /// Refine a coarse family into a concrete `WorkoutCatalog` sport from IMU features, or nil to keep the
    /// family's default label. The returned sport is ALWAYS within `coarse.suggestedSports`, so the
    /// display + one-tap picker stay consistent with the family.
    public static func refine(coarse: CoarseWorkoutClass, imu: ImuActivityFeatures) -> Refinement? {
        // Not enough signal to say anything more than the 1 Hz family did.
        guard imu.sampleCount >= minSamples, imu.accelEnergyG >= accelMinG else { return nil }

        switch coarse {
        case .court:
            // Badminton: light racquet driven by WRIST — high rotational energy + explosive jerk, without
            // the whole-arm translation of a groundstroke. Tennis: big arm swings → high accel energy.
            // Squash: continuous, rhythmic swinging in a small box → a real swing cadence peak.
            if imu.gyroEnergyDps >= gyroHighDps && imu.jerkRms >= jerkHighG && imu.accelEnergyG < accelHighG {
                return Refinement(sport: "Badminton",
                                  reason: "gyro \(int(imu.gyroEnergyDps))dps + jerk \(f2(imu.jerkRms))g wrist-snap, accel \(f2(imu.accelEnergyG))g")
            }
            if imu.accelEnergyG >= accelHighG {
                return Refinement(sport: "Tennis",
                                  reason: "accel \(f2(imu.accelEnergyG))g whole-arm swing, gyro \(int(imu.gyroEnergyDps))dps")
            }
            if let c = imu.cadenceHz, imu.cadenceStrength >= 0.30 {
                return Refinement(sport: "Squash",
                                  reason: "rhythmic swings \(f2(c))Hz (strength \(f2(imu.cadenceStrength)))")
            }
            return nil

        case .rhythmicCardio:
            // Elliptical: hands ride moving handles at a gait-band cadence (1.2–3.5 Hz) → a rhythmic peak.
            // Swim: strong per-stroke wrist ROLL (high gyro), stroke rate below the gait band → no peak.
            // Rowing: whole-arm PULL with little wrist rotation (low gyro), no gait-band peak.
            if imu.cadenceHz != nil && imu.cadenceStrength >= 0.30 {
                return Refinement(sport: "Elliptical",
                                  reason: "gait-band cadence \(f2(imu.cadenceHz ?? 0))Hz — handle-driven")
            }
            if imu.gyroEnergyDps >= gyroHighDps {
                return Refinement(sport: "Pool swim",
                                  reason: "gyro \(int(imu.gyroEnergyDps))dps wrist-roll per stroke")
            }
            if imu.gyroEnergyDps <= gyroLowDps {
                return Refinement(sport: "Rowing",
                                  reason: "low gyro \(int(imu.gyroEnergyDps))dps — pull, little wrist roll")
            }
            return nil

        // Foot-gait families (run/walk) and the low-motion families (cycle/strength) aren't further
        // separable by wrist IMU alone in a way that changes the SPORT (cadence is metadata, not a
        // different sport); keep the 1 Hz family default.
        case .run, .walk, .strength, .cycle, .ski, .other:
            return nil
        }
    }

    // MARK: - tiny formatters for the rationale string
    private static func f2(_ x: Double) -> String { String(format: "%.2f", x) }
    private static func int(_ x: Double) -> String { String(Int(x.rounded())) }
}
