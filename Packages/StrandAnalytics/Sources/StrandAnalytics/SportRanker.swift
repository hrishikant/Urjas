import Foundation

/// The phone's coarse motion class, mirroring CoreMotion's `CMMotionActivity` flags. This is the single
/// most reliable *movement-pattern* signal we can get for free on iPhone — HR encodes load, not motion,
/// so pairing this with HR is what lets us name walking / running / cycling instead of guessing from bpm.
public enum MotionKind: String, Sendable, Codable, CaseIterable {
    case stationary
    case walking
    case running
    case cycling
    case automotive
    case unknown
}

/// Everything we know about the movement pattern of a live session, fused by `SportRanker` into a
/// best-first sport shortlist. All fields are optional / honest-nil: a signal that isn't available
/// (no GPS lock, motion permission denied, strap without a step counter) simply doesn't vote.
public struct SportSignals: Sendable, Equatable {
    /// HR-shape family (from `WorkoutClassifier`), the fallback when motion can't discriminate.
    public var family: WorkoutFamily?
    /// Phone motion class (CoreMotion). `.unknown` when unavailable.
    public var motion: MotionKind
    /// CoreMotion confidence 0…2 (low/medium/high). Below `minMotionConfidence` the motion vote is muted.
    public var motionConfidence: Int
    /// Current ground speed in metres/second (GPS), or nil when no location fix / not a distance sport.
    public var speedMps: Double?
    /// Live step cadence in steps/minute (pedometer), or nil when not counting steps.
    public var cadenceSpm: Double?

    public init(family: WorkoutFamily? = nil,
                motion: MotionKind = .unknown,
                motionConfidence: Int = 0,
                speedMps: Double? = nil,
                cadenceSpm: Double? = nil) {
        self.family = family
        self.motion = motion
        self.motionConfidence = motionConfidence
        self.speedMps = speedMps
        self.cadenceSpm = cadenceSpm
    }
}

/// Fuses movement signals into a best-first sport shortlist for the picker (and an optional confident
/// top pick). Deliberately rule-based and interpretable — no trained model. The design principle is
/// honesty: motion + speed + cadence can pin down foot/wheel sports well, so those get a confident
/// pick; everything else (gym, court, water) falls back to the HR family shortlist and stays a *guess*
/// the user confirms with one tap, never a confident wrong label.
public enum SportRanker {

    /// CoreMotion confidence (0 low, 1 medium, 2 high). We only trust the motion class at medium+.
    static let minMotionConfidence = 1

    /// Speed thresholds (m/s). ~2.2 m/s ≈ 8 km/h (brisk walk / slow jog boundary); ~5.6 m/s ≈ 20 km/h
    /// (clearly wheels, not running).
    static let walkRunSplitMps = 2.2
    static let runCycleSplitMps = 5.6
    /// Cadence thresholds (steps/min). Running foot-strike is fast (>~150); walking is ~90–135.
    static let runCadenceSpm = 145.0
    static let walkCadenceSpm = 70.0
    /// Minimum ground speed (m/s) that counts as real walking gait rather than court shuffling / pacing.
    /// ~0.9 m/s ≈ 3.2 km/h. Below this we do NOT vote "Walking" from speed alone, so a tennis/badminton
    /// player shuffling on court (low speed, few footfalls) isn't confidently mislabelled as walking.
    static let walkFloorMps = 0.9

    /// A confident single pick, or nil when no movement signal is strong enough to name a sport (the
    /// caller then labels the session neutrally, e.g. "Workout", and shows `rank(_:)` in the picker).
    public static func topPick(_ s: SportSignals) -> String? {
        let scores = score(s)
        guard let best = scores.max(by: { $0.value < $1.value }) else { return nil }
        // Require a clear, movement-backed winner. Family-only guesses never earn a confident pick.
        return best.value >= 3.0 ? best.key : nil
    }

    /// Best-first sport shortlist for the picker. Always returns a full, de-duplicated list: the
    /// movement-scored candidates first (highest first), then the HR-family shortlist, then the rest of
    /// the catalogue order, so the user can still reach any sport but the likely ones are one tap away.
    public static func rank(_ s: SportSignals) -> [String] {
        let scores = score(s)
        let scored = scores.filter { $0.value > 0 }
            .sorted { a, b in a.value != b.value ? a.value > b.value : catalogOrder(a.key) < catalogOrder(b.key) }
            .map { $0.key }

        var out: [String] = []
        var seen = Set<String>()
        func add(_ names: [String]) {
            for n in names where !seen.contains(n) { out.append(n); seen.insert(n) }
        }
        add(scored)
        add(s.family?.suggestedSports ?? [])
        add(catalog)
        return out
    }

    // MARK: - Scoring

    /// Per-sport score from the fused signals. Higher = more likely. Movement signals (motion class,
    /// speed, cadence) dominate; the HR family adds a smaller nudge so it only decides ties / fills the
    /// tail. Scores of 0 mean "no positive evidence".
    static func score(_ s: SportSignals) -> [String: Double] {
        var sc: [String: Double] = [:]
        func bump(_ name: String, _ v: Double) { sc[name, default: 0] += v }

        let trustMotion = s.motionConfidence >= minMotionConfidence
        let hasSteps = (s.cadenceSpm ?? 0) > 0
        let spd = s.speedMps

        // 1) Phone motion class — the primary vote.
        if trustMotion {
            switch s.motion {
            case .running:
                bump("Running", 4); bump("Treadmill run", 1)
            case .walking:
                // Walking motion alone is easily produced by court shuffling / pacing between points, so
                // it only earns its full weight when corroborated by a real gait signal (a true walking
                // ground speed OR actual footfalls). Uncorroborated, it stays a weak vote so court /
                // interval sports fall to the neutral "Workout" picker instead of a wrong "Walking" label.
                let gait = (spd ?? 0) >= walkFloorMps || (s.cadenceSpm ?? 0) >= walkCadenceSpm
                bump("Walking", gait ? 3.5 : 0.6); bump("Hiking", gait ? 1.5 : 0.3)
                if gait { bump("Treadmill walk", 1) }
            case .cycling:
                bump("Cycling", 4); bump("Indoor cycle", 1)
            case .automotive:
                // In a vehicle → almost never a workout; nudge nothing (let HR family/other decide).
                break
            case .stationary:
                // Stationary but HR is up → gym / mat work — BUT only nudge "Strength" when the HR shape
                // agrees (or is unknown). For an intervals/endurance/mobility family (court, team, HIIT,
                // cardio) a stationary phone must NOT push Strength to the top of the picker.
                if s.family == nil || s.family == .strength { bump("Strength", 1.5) }
            case .unknown:
                break
            }
        }

        // 2) GPS speed — corroborates or, with steps, discriminates walk/run/cycle even if motion is unknown.
        if let v = spd, v > 0.3 {
            if v >= runCycleSplitMps {
                // Too fast to be running on foot → wheels (or downhill snow).
                bump("Cycling", 3)
            } else if v >= walkRunSplitMps {
                // Jog/run pace band.
                bump("Running", 2)
            } else if v >= walkFloorMps {
                // Real walking ground speed → walking/hiking. Below `walkFloorMps` (a court shuffle /
                // drift) we deliberately cast no walking vote.
                bump("Walking", 1.5); bump("Hiking", 0.8)
            }
        }

        // 3) Step cadence — footfalls exist only for on-foot sports; fast cadence favours running.
        if hasSteps, let cad = s.cadenceSpm {
            if cad >= runCadenceSpm {
                bump("Running", 2)
            } else if cad >= walkCadenceSpm {
                bump("Walking", 1.2); bump("Hiking", 0.6)
            }
        } else if spd != nil, (spd ?? 0) >= walkRunSplitMps {
            // Moving at pace with NO footfalls → wheels, not feet. Reinforce cycling, dampen running.
            bump("Cycling", 1.5)
            sc["Running"] = max(0, (sc["Running"] ?? 0) - 1)
            sc["Walking"] = max(0, (sc["Walking"] ?? 0) - 1)
        }

        // 4) HR family — a gentle nudge so it breaks ties and seeds the tail, never overrides movement.
        if let fam = s.family {
            for (i, name) in fam.suggestedSports.enumerated() {
                bump(name, 0.8 - Double(i) * 0.12)
            }
        }

        return sc
    }

    // MARK: - Catalogue order (kept in lockstep with `WorkoutCatalog.all` names)

    /// Canonical sport names in catalogue order — the tail of `rank(_:)` and the tie-break key. Mirrors
    /// `WorkoutCatalog.all`; StrandAnalytics can't import the app target, so the names live here too.
    static let catalog: [String] = [
        "Running", "Walking", "Hiking", "Cycling", "Open-water swim", "Rowing",
        "Treadmill run", "Treadmill walk", "Indoor cycle", "Pool swim", "Row machine",
        "Elliptical", "Strength", "Bodybuilding", "Weightlifting", "HIIT", "Yoga",
        "Pilates", "Boxing", "Basketball", "Soccer", "Baseball", "Badminton", "Tennis",
        "Squash", "Racquetball", "Table tennis", "Volleyball", "Martial arts", "Dancing",
        "Golf", "Climbing", "Stretching", "Skiing", "Snowboarding", "Padel", "Pickleball",
        "Bowling", "Other",
    ]

    private static let catalogIndex: [String: Int] =
        Dictionary(uniqueKeysWithValues: catalog.enumerated().map { ($0.element, $0.offset) })

    static func catalogOrder(_ name: String) -> Int { catalogIndex[name] ?? Int.max }
}
