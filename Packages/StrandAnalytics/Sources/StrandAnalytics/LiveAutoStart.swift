import Foundation

/// Pure decision core for LIVE workout auto-start / auto-end.
///
/// The after-the-fact `AutoWorkoutDetector` only ever *suggested* a past bout. Users expect a worn
/// strap to *start recording by itself* when they begin a workout (any sport) and to stop when they
/// finish , parity with a watch's auto-detect. `AppModel` owns the live HR stream and the mutable
/// session; this enum owns the stateless "should I start / end right now?" call so it can be unit
/// tested against synthetic HR series without a strap or the app running.
///
/// The gate is the SAME elevated threshold the detector uses: `restingHR + elevatedMarginBPM`. A
/// candidate must hold the gate for `sustainMin` (shorter than the detector's 12 min so the live
/// start is responsive, long enough to reject a flight of stairs), tolerating brief dips up to
/// `maxDipS`. An auto-started session ends once HR holds BELOW the gate for `endCooldownMin`.
public enum LiveAutoStart {

    // MARK: - Constants

    /// Elevated gate margin over resting HR , kept identical to the after-the-fact detector so a live
    /// start and a retro-suggestion agree on what "working" means.
    public static let elevatedMarginBPM = AutoWorkoutDetector.elevatedMarginBPM
    /// Resting-HR fallback when the caller has no nightly RHR yet , shared with the detector.
    public static let defaultRestingHR = AutoWorkoutDetector.defaultRestingHR
    /// A candidate must hold the elevated gate this long before a live session auto-starts.
    public static let sustainMin: Double = 3.0
    /// A dip below the gate no longer than this does NOT break the elevated run.
    public static let maxDipS: Double = 90
    /// An auto-started session auto-ends once HR holds below the gate continuously for this long.
    public static let endCooldownMin: Double = 5.0
    /// Suppression window after an auto-end before a new auto-start can arm (owned by the caller).
    public static let rearmMin: Double = 5.0

    // MARK: - Inputs / output

    /// One smoothed HR reading on the wall clock (seconds). `buf` passed to `decide` MUST be ascending.
    public struct Sample: Equatable, Sendable {
        public let t: Double
        public let bpm: Int
        public init(t: Double, bpm: Int) { self.t = t; self.bpm = bpm }
    }

    public enum Decision: Equatable, Sendable {
        case none
        /// Start a live session seeded from this onset time (seconds).
        case start(onsetT: Double)
        /// End the currently auto-started session.
        case end
    }

    // MARK: - Decision

    /// The current auto-start / auto-end decision.
    /// - buf: smoothed HR samples, ascending by `t`, ideally the last ~20 min.
    /// - nowT: current wall-clock time (seconds).
    /// - restingBpm: most recent nightly resting HR, or nil to use `defaultRestingHR`.
    /// - isRecording: whether a session is already running.
    /// - wasAuto: whether that running session was itself auto-started (only those auto-END).
    public static func decide(buf: [Sample], nowT: Double, restingBpm: Int?,
                              isRecording: Bool, wasAuto: Bool) -> Decision {
        let gate = (restingBpm ?? defaultRestingHR) + elevatedMarginBPM

        if isRecording {
            // Only a session WE auto-started may auto-end , never a manual one the user is running.
            guard wasAuto else { return .none }
            let window = endCooldownMin * 60
            let cutoff = nowT - window
            // Require ≥`window` of history (a sample at/older than the cutoff proves the stream spans the
            // whole cool-down) AND every sample within the window below the gate. NOTE: we must NOT test
            // `nowT - earliest.t >= window` on the *filtered* set , after filtering to `t >= cutoff` the
            // earliest is by definition within the window, so on a live ~1 Hz stream that test is ~always
            // just under `window` and the session would never end. The coverage sample gates it instead.
            guard buf.contains(where: { $0.t <= cutoff }) else { return .none }
            let recent = buf.filter { $0.t >= cutoff }
            guard !recent.isEmpty, recent.allSatisfy({ $0.bpm < gate }) else { return .none }
            return .end
        }

        guard let onset = onset(buf: buf, gate: gate),
              nowT - onset >= sustainMin * 60 else { return .none }
        return .start(onsetT: onset)
    }

    /// The earliest time from which HR has held `gate` continuously up to the newest sample, tolerating
    /// dips no longer than `maxDipS`. Nil when the most recent sample is below the gate (not working) or
    /// the buffer is empty.
    static func onset(buf: [Sample], gate: Int) -> Double? {
        guard let last = buf.last, last.bpm >= gate else { return nil }
        var onset = last.t
        for s in buf.reversed() {
            if s.bpm >= gate {
                onset = s.t                     // extend the elevated run further back
            } else if onset - s.t > maxDipS {
                break                           // dip too long , the chain is broken
            }
        }
        return onset
    }
}
