import Foundation
import WhoopProtocol

/// Coarse "shape" family of a workout, inferred from the heart-rate stream alone.
///
/// HR encodes cardiovascular *load*, not the movement pattern, so bpm cannot name a specific sport
/// (badminton, a spin class and a tempo run can all sit at ~140 bpm). What HR *can* separate fairly
/// robustly is a small set of intensity/variability "shapes" , which is what this enum captures. The
/// exact sport is left to the user (pre-filled with the most likely option from the family shortlist).
public enum WorkoutFamily: String, Sendable, CaseIterable, Codable {
    /// Steady-state cardio: HR rises then holds with slow drift, low variability.
    case endurance
    /// Intermittent court / team / HIIT: repeated surges and partial recoveries, high variability.
    case intervals
    /// Resistance training: short spikes per set with drops during rest, low duty cycle.
    case strength
    /// Low-intensity / mobility: modest elevation, low variability.
    case mobility

    /// Human-readable label.
    public var title: String {
        switch self {
        case .endurance: return "Endurance"
        case .intervals: return "Intervals"
        case .strength:  return "Strength"
        case .mobility:  return "Mobility"
        }
    }

    /// Best-first shortlist of likely sports (names match `WorkoutCatalog`), offered for the user to pick.
    public var suggestedSports: [String] {
        switch self {
        case .endurance: return ["Running", "Cycling", "Rowing", "Walking", "Elliptical"]
        case .intervals: return ["HIIT", "Badminton", "Tennis", "Soccer", "Basketball", "Boxing"]
        case .strength:  return ["Strength", "Weightlifting", "Bodybuilding"]
        case .mobility:  return ["Yoga", "Stretching", "Pilates", "Walking"]
        }
    }
}

/// HR-only workout "shape" classifier. Deliberately rule-based (no trained model, no motion sensor):
/// it buckets an HR window into a `WorkoutFamily` from a handful of interpretable features and offers a
/// sport shortlist. It NEVER claims a specific sport , that stays a user choice.
public enum WorkoutClassifier {

    /// Interpretable features extracted from the HR window (exposed for display / debugging / tests).
    public struct Features: Equatable, Sendable {
        public let meanBpm: Double
        public let sdBpm: Double
        /// Coefficient of variation (sd / mean) , the "spikiness" of the trace.
        public let cv: Double
        /// Mean %HRR = (mean − rest) / (max − rest), clamped to 0…1.
        public let meanPctHRR: Double
        /// bpm/min over the first ~2 min (how fast HR ramped at onset).
        public let onsetSlope: Double
        /// Up-crossings of the elevated gate per minute (how "intermittent" the effort is).
        public let surgesPerMin: Double
        /// Fraction of samples at/above the elevated gate (0…1).
        public let dutyCycle: Double
        public let durationMin: Double
    }

    public struct Result: Equatable, Sendable {
        public let family: WorkoutFamily
        /// Rough 0…1 confidence in the family call.
        public let confidence: Double
        public let suggestedSports: [String]
        public let features: Features
    }

    /// Elevated gate margin over resting HR , shared with the detectors so "working" means the same thing.
    static let elevatedMarginBPM = AutoWorkoutDetector.elevatedMarginBPM
    static let defaultRestingHR = AutoWorkoutDetector.defaultRestingHR
    static let defaultMaxHR: Double = 190

    /// Classify an HR window. Returns nil when there are too few samples (< 30 s of data) to be meaningful.
    public static func classify(hr: [HRSample], restingBpm: Int?, maxBpm: Double?) -> Result? {
        let s = hr.sorted { $0.ts < $1.ts }
        guard s.count >= 2 else { return nil }
        let durationSec = Double(s.last!.ts - s.first!.ts)
        guard durationSec >= 30, s.count >= 10 else { return nil }

        let rest = Double(restingBpm ?? defaultRestingHR)
        let maxHR = max(rest + 1, maxBpm ?? defaultMaxHR)
        let gate = Double((restingBpm ?? defaultRestingHR) + elevatedMarginBPM)
        let bpms = s.map { Double($0.bpm) }
        let n = Double(bpms.count)

        let mean = bpms.reduce(0, +) / n
        let variance = bpms.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / n
        let sd = variance.squareRoot()
        let cv = mean > 0 ? sd / mean : 0
        let meanPctHRR = min(1, max(0, (mean - rest) / (maxHR - rest)))
        let dutyCycle = Double(bpms.filter { $0 >= gate }.count) / n

        // Onset slope: bpm rise over the first ~2 minutes (or the whole window if shorter).
        let onsetEnd = s.first!.ts + 120
        let onsetSamples = s.filter { $0.ts <= onsetEnd }
        let onsetSlope: Double = {
            guard let a = onsetSamples.first, let b = onsetSamples.last, b.ts > a.ts else { return 0 }
            return (Double(b.bpm) - Double(a.bpm)) / (Double(b.ts - a.ts) / 60.0)
        }()

        // Surges: up-crossings of the gate (a below→at/above transition), normalised per minute.
        var crossings = 0
        for i in 1..<bpms.count where bpms[i - 1] < gate && bpms[i] >= gate { crossings += 1 }
        let durationMin = durationSec / 60.0
        let surgesPerMin = durationMin > 0 ? Double(crossings) / durationMin : 0

        let features = Features(
            meanBpm: mean, sdBpm: sd, cv: cv, meanPctHRR: meanPctHRR, onsetSlope: onsetSlope,
            surgesPerMin: surgesPerMin, dutyCycle: dutyCycle, durationMin: durationMin)

        let (family, confidence) = decideFamily(features)
        return Result(family: family, confidence: confidence,
                      suggestedSports: family.suggestedSports, features: features)
    }

    /// Rule-based family decision from the features, with a rough confidence.
    static func decideFamily(_ f: Features) -> (WorkoutFamily, Double) {
        // MOBILITY: low intensity AND steady , modest %HRR, rarely above the gate, low variability.
        // (Strength has a similarly low *mean* because of long rests, but it is spiky , high CV , so the
        // CV guard keeps strength out of this bucket.)
        if f.meanPctHRR < 0.35 && f.dutyCycle < 0.4 && f.cv < 0.10 {
            let conf = 0.5 + min(0.4, (0.35 - f.meanPctHRR) * 1.2)
            return (.mobility, conf)
        }
        // STRENGTH: spiky (high CV) with a LOW duty cycle , lots of rest between elevated sets.
        if f.cv >= 0.12 && f.dutyCycle < 0.5 {
            let conf = 0.5 + min(0.4, (f.cv - 0.12) * 2.0)
            return (.strength, conf)
        }
        // INTERVALS: intermittent but sustained , frequent surges and/or high variability at high duty.
        if f.surgesPerMin >= 0.35 || (f.cv >= 0.10 && f.dutyCycle >= 0.5) {
            let conf = 0.5 + min(0.4, f.surgesPerMin * 0.3 + (f.cv - 0.08) * 1.5)
            return (.intervals, max(0.5, conf))
        }
        // ENDURANCE (default): steady, high duty cycle, low variability.
        let conf = 0.5 + min(0.4, f.dutyCycle * 0.3 + max(0, 0.10 - f.cv) * 2.0)
        return (.endurance, conf)
    }
}
