import Foundation

/// Pure decision core for LIVE workout auto-start / auto-end.
///
/// The after-the-fact `AutoWorkoutDetector` only ever *suggested* a past bout. Users expect a worn
/// strap to *start recording by itself* when they begin a workout (any sport) and to stop when they
/// finish , parity with a watch's auto-detect. `AppModel` owns the live HR stream and the mutable
/// session; this enum owns the stateless "should I start / end right now?" call so it can be unit
/// tested against synthetic HR series without a strap or the app running.
///
/// The gate is the SAME elevated threshold the detector uses: `restingHR + elevatedMarginBPM`. To
/// auto-start, HR must be elevated RIGHT NOW and have stayed *mostly* above the gate for the whole
/// `sustainMin` window (`minStartDutyCycle`), with that window densely covered by real samples
/// (`coverageGapS`) so a stale/sparse buffer can't fake a bout. This deliberately rejects the everyday
/// transients (standing up, carrying something, a stressful moment) that a plain "no dip longer than X"
/// rule used to chain into a fake sustained effort.
///
/// An auto-started session auto-ends once HR holds BELOW the gate for `endCooldownMin` (a lone stray
/// spike no longer resets it — see `endMaxElevatedFrac`), OR once the wearer has been continuously still
/// for `motionEndStationaryMin` while HR sits only just above the gate (the motion-assisted end, for
/// sports whose HR stays parked high after the effort stops). The caller additionally ends a session that
/// outlives `maxSessionMin` or whose strap has been off/disconnected for `strapOffEndS`, so a session
/// can never silently run for days.
public enum LiveAutoStart {

    // MARK: - Constants

    /// Elevated gate margin over resting HR , kept identical to the after-the-fact detector so a live
    /// start and a retro-suggestion agree on what "working" means.
    public static let elevatedMarginBPM = AutoWorkoutDetector.elevatedMarginBPM
    /// Resting-HR fallback when the caller has no nightly RHR yet , shared with the detector.
    public static let defaultRestingHR = AutoWorkoutDetector.defaultRestingHR
    /// HR must stay mostly above the elevated gate for this long before a live session auto-starts.
    /// Deliberately strict (parity with a conservative watch) so brief everyday exertion never starts one.
    public static let sustainMin: Double = 7.0
    /// A dip below the gate no longer than this does NOT break the elevated run used to seed the onset.
    public static let maxDipS: Double = 30
    /// Fraction of samples in the `sustainMin` window that must be at/above the gate to auto-start. This
    /// is the core false-start guard: intermittent spikes (stand up, reach for a glass) never reach it.
    public static let minStartDutyCycle: Double = 0.85
    /// The longest gap allowed between consecutive samples when judging start/end windows. A larger gap
    /// means the strap wasn't actually streaming across the window, so we can't trust it — don't fire.
    public static let coverageGapS: Double = 45
    /// An auto-started session auto-ends once HR holds below the gate continuously for this long.
    public static let endCooldownMin: Double = 5.0
    /// A single stray spike must not reset the cool-down: up to this fraction of the cool-down window may
    /// still read at/above the gate and the session will STILL end (as long as the newest sample is below).
    public static let endMaxElevatedFrac: Double = 0.10
    /// Suppression window after an auto-end before a new auto-start can arm (owned by the caller).
    public static let rearmMin: Double = 5.0
    /// Hard safety cap: the caller auto-ends an auto-started session that has run this long, no matter
    /// what the HR is doing — a backstop against a session that never cools down.
    public static let maxSessionMin: Double = 240
    /// The caller auto-ends an auto-started session once the strap has been off / disconnected this long
    /// (the live buffer stops feeding when unworn, so the HR cool-down path alone can't catch this case).
    public static let strapOffEndS: Double = 180
    /// Motion-assisted end: how long the wearer must be continuously NON-vigorous (phone motion stationary /
    /// automotive) before we may end on stillness alone. Deliberately longer than the HR cool-down because
    /// this path fires while HR is still above the gate, so it must be sure the effort is genuinely over.
    public static let motionEndStationaryMin: Double = 10.0
    /// The HR grace band above the gate tolerated by the motion-assisted end. Some sports leave HR parked a
    /// little above resting for a long while after the effort stops (e.g. badminton, HIIT); once the wearer
    /// has been still for `motionEndStationaryMin` AND HR is within this band of the gate (i.e. not still
    /// hammering), the session ends even though the HR-only cool-down never dropped it below the gate.
    public static let motionEndGraceBPM = 15

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
    /// - motionStationaryFor: seconds the wearer has been continuously non-vigorous (phone motion
    ///   stationary/automotive), or nil when no trustworthy motion signal is available (permission denied,
    ///   unsupported device, or actively moving). Enables the motion-assisted end for sports that leave HR
    ///   elevated after the effort stops; nil preserves the pure HR-only behaviour.
    public static func decide(buf: [Sample], nowT: Double, restingBpm: Int?,
                              isRecording: Bool, wasAuto: Bool,
                              motionStationaryFor: Double? = nil) -> Decision {
        let gate = (restingBpm ?? defaultRestingHR) + elevatedMarginBPM

        if isRecording {
            // Only a session WE auto-started may auto-end , never a manual one the user is running.
            guard wasAuto else { return .none }
            let window = endCooldownMin * 60
            let cutoff = nowT - window
            // Require ≥`window` of history (a sample at/older than the cutoff proves the stream spans the
            // whole cool-down). NOTE: we must NOT test `nowT - earliest.t >= window` on the *filtered* set.
            guard buf.contains(where: { $0.t <= cutoff }) else { return .none }
            let recent = buf.filter { $0.t >= cutoff }
            guard let last = recent.last else { return .none }
            // HR-only end: the newest reading is below the gate...
            if last.bpm < gate {
                // ...and the cool-down is genuine: at most `endMaxElevatedFrac` of it may still read at/
                // above the gate, so ONE stray high sample (motion/optical noise) can't keep a session
                // alive for hours the way the old "every sample below gate" rule did.
                let elevated = recent.reduce(0) { $0 + ($1.bpm >= gate ? 1 : 0) }
                if Double(elevated) / Double(recent.count) <= endMaxElevatedFrac { return .end }
            }
            // Motion-assisted end: HR may still sit above the gate, but the wearer has been continuously
            // still for `motionEndStationaryMin` and HR is within `motionEndGraceBPM` of the gate (not
            // still working). This catches sports (badminton, HIIT) whose HR stays parked above the gate
            // long after play stops, which the HR-only cool-down above never ends.
            if let stationaryFor = motionStationaryFor,
               stationaryFor >= motionEndStationaryMin * 60,
               last.bpm < gate + motionEndGraceBPM {
                return .end
            }
            return .none
        }

        // START. Must be elevated RIGHT NOW, with a full sustain window of densely-sampled, mostly-
        // elevated history behind it. The duty-cycle + coverage checks are what stop everyday transients
        // (stand up, reach for a glass, a stressful moment) from ever chaining into a fake bout.
        guard let last = buf.last, last.bpm >= gate else { return .none }
        let sustainWindow = sustainMin * 60
        let winStart = nowT - sustainWindow
        // A sample at/older than the window start proves we actually have ≥`sustainMin` of history.
        guard buf.contains(where: { $0.t <= winStart }) else { return .none }
        let win = buf.filter { $0.t >= winStart }
        guard win.count >= 2 else { return .none }
        // The window must be continuously covered (no dropout longer than `coverageGapS`), else we never
        // truly observed the effort and mustn't start off a stale/sparse buffer.
        guard isDenselyCovered(win, from: winStart, to: nowT) else { return .none }
        // Mostly elevated across the whole window , the false-start guard.
        let elevated = win.reduce(0) { $0 + ($1.bpm >= gate ? 1 : 0) }
        guard Double(elevated) / Double(win.count) >= minStartDutyCycle else { return .none }
        return .start(onsetT: onset(buf: buf, gate: gate) ?? winStart)
    }

    /// True when `win` (samples with `t` in `[from, to]`) has no gap longer than `maxGap` anywhere from
    /// `from` through the newest sample to `to` , i.e. the strap streamed continuously across the window.
    static func isDenselyCovered(_ win: [Sample], from: Double, to: Double,
                                 maxGap: Double = coverageGapS) -> Bool {
        var prev = from
        for s in win {
            if s.t - prev > maxGap { return false }
            prev = s.t
        }
        return to - prev <= maxGap
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
