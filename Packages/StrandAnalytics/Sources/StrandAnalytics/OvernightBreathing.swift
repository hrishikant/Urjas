import Foundation
import WhoopProtocol

// OvernightBreathing.swift — a RELATIVE overnight blood-oxygen steadiness screen (Ūrjas).
//
// PURELY ADDITIVE. Introduces NO change to any Charge / Effort / Rest / sleep score; it is a brand-new,
// opt-in nightly readout the Ūrjas Sleep screen surfaces.
//
// WHAT THIS IS — AND IS NOT. Clinical sleep-apnea screening uses the Oxygen Desaturation Index (ODI): the
// number of times per hour the blood-oxygen saturation (SpO₂) drops by ≥ 3–4 PERCENTAGE POINTS and recovers
// (Berry et al., AASM 2020). Computing a true ODI needs a CALIBRATED SpO₂ percentage. The strap only streams
// the RAW red / infrared photodiode counts (`SpO2Sample.red`, `.ir`, unit "raw_adc"); it deliberately does
// NOT expose a calibrated % (see Repository #166). So this engine CANNOT and DOES NOT compute a clinical ODI
// or diagnose apnea. It computes a RELATIVE, unitless proxy: how often the red/IR ratio — which moves
// INVERSELY with oxygen saturation — dipped and recovered overnight, expressed as a nightly steadiness band.
// It is a wellness trend, not a medical test. The UI says exactly this and points anyone with symptoms
// (loud snoring, witnessed gasping, daytime sleepiness) to a doctor.
//
// THE SIGNAL. Beer-Lambert pulse oximetry: SpO₂ falls as the ratio R = red/IR rises. So a desaturation shows
// up as a transient UPWARD excursion of R above its local baseline, followed by a return (the characteristic
// desaturation → resaturation "notch"). We:
//   1. Clean: drop samples with non-positive red/IR (sensor off / bad read).
//   2. Baseline: a centered rolling MEDIAN of R over ±`baselineHalfWindowSec` (robust to the slow perfusion
//      drift that a mean would chase), so only transient dips — not posture/perfusion trends — count.
//   3. Excursion: e[i] = (R[i] − baseline[i]) / baseline[i]. Positive e ⇒ oxygen proxy fell.
//   4. Event: a contiguous run with e ≥ `dipThreshold`, lasting between `minEventSec` and `maxEventSec`
//      (apneic/hypopneic desaturations are seconds-to-a-minute, not hours), runs closer than `mergeGapSec`
//      merged. Each qualifying run = one relative dip.
//   5. Index: relativeDipsPerHour = dips / sleepHours, gated on `minCoverageMinutes` of usable signal.
//
// DELIBERATELY NON-CLINICAL BANDS. We do NOT reuse the clinical AHI cut-points (5 / 15 / 30), which would
// imply a diagnosis we cannot make on uncalibrated ADC. The bands are neutral, plain-language steadiness
// descriptions. Approximate; a screening trend only.

public enum OvernightBreathing {

    // MARK: - Tunables (pinned by test).

    /// Half-width (seconds) of the centered rolling-median baseline window. ±90 s ⇒ a 3-min baseline.
    public static let baselineHalfWindowSec: Int = 90
    /// Relative rise in R = red/IR above baseline that marks a desaturation-like dip. 0.03 = a 3% ratio rise.
    public static let dipThreshold: Double = 0.03
    /// Minimum sustained duration (s) for a run to count as a dip (rejects single-sample spikes).
    public static let minEventSec: Int = 8
    /// Maximum duration (s) for a dip (a longer excursion is a baseline shift / posture change, not a notch).
    public static let maxEventSec: Int = 120
    /// Runs separated by less than this (s) are merged into one dip (bridges brief re-crossings).
    public static let mergeGapSec: Int = 5
    /// Minimum usable signal coverage (minutes) before an index is trustworthy. Below this → nil.
    public static let minCoverageMinutes: Int = 120

    // MARK: - Bands

    /// Plain-language nightly steadiness band. Deliberately NOT clinical severity.
    public enum Steadiness: String, Equatable, Sendable, CaseIterable {
        /// Few relative dips — the oxygen proxy held steady.
        case steady
        /// Some relative dips overnight.
        case someVariability
        /// Frequent relative dips — worth watching / mentioning to a clinician if paired with symptoms.
        case frequentDips

        public var friendlyName: String {
            switch self {
            case .steady: return "Steady"
            case .someVariability: return "Some Variability"
            case .frequentDips: return "Frequent Dips"
            }
        }

        public var caption: String {
            switch self {
            case .steady:
                return "Your blood-oxygen proxy held steady through the night."
            case .someVariability:
                return "Your blood-oxygen proxy dipped and recovered a handful of times."
            case .frequentDips:
                return "Your blood-oxygen proxy dipped and recovered often. This is a relative trend, not a diagnosis — if you also snore loudly, gasp in your sleep, or feel unrested, consider talking to a doctor."
            }
        }
    }

    // Neutral band edges in relative-dips-per-hour (NOT clinical AHI cut-points).
    static let steadyMax: Double = 8
    static let someVariabilityMax: Double = 20

    /// Map a relative-dips-per-hour value to a steadiness band.
    public static func steadiness(forDipsPerHour dph: Double) -> Steadiness {
        if dph < steadyMax { return .steady }
        if dph < someVariabilityMax { return .someVariability }
        return .frequentDips
    }

    // MARK: - Result

    public struct Result: Equatable, Sendable {
        /// Relative desaturation-like dips per hour of usable signal, or nil when coverage was too low.
        public let relativeDipsPerHour: Double?
        /// The steadiness band, or nil when the index is nil.
        public let steadiness: Steadiness?
        /// Count of qualifying dips detected.
        public let dipCount: Int
        /// Minutes of usable (clean) signal the index was computed over.
        public let coverageMinutes: Double
        /// Count of raw samples supplied.
        public let nInput: Int

        public init(relativeDipsPerHour: Double?, steadiness: Steadiness?, dipCount: Int,
                    coverageMinutes: Double, nInput: Int) {
            self.relativeDipsPerHour = relativeDipsPerHour
            self.steadiness = steadiness
            self.dipCount = dipCount
            self.coverageMinutes = coverageMinutes
            self.nInput = nInput
        }

        static func empty(nInput: Int, coverageMinutes: Double = 0) -> Result {
            Result(relativeDipsPerHour: nil, steadiness: nil, dipCount: 0,
                   coverageMinutes: coverageMinutes, nInput: nInput)
        }
    }

    // MARK: - Public API

    /// Compute the relative overnight breathing-steadiness screen from a night's SpO₂ samples.
    /// Returns an empty result (relativeDipsPerHour == nil) when there are too few clean samples or the
    /// usable coverage is below `minCoverageMinutes`.
    public static func analyze(samples: [SpO2Sample]) -> Result {
        let nInput = samples.count
        guard nInput > 0 else { return .empty(nInput: 0) }

        // 1. Clean + sort by time. Keep (ts, ratio) for valid reads only.
        let clean = samples
            .filter { $0.red > 0 && $0.ir > 0 }
            .sorted { $0.ts < $1.ts }
        guard clean.count >= 2 else { return .empty(nInput: nInput) }

        let ts = clean.map { $0.ts }
        let ratio = clean.map { Double($0.red) / Double($0.ir) }

        // Usable coverage = span of clean samples in minutes.
        let coverageMinutes = Double(ts.last! - ts.first!) / 60.0
        guard coverageMinutes >= Double(minCoverageMinutes) else {
            return .empty(nInput: nInput, coverageMinutes: coverageMinutes)
        }

        // 2/3. Centered rolling-median baseline → relative excursion series.
        let excursion = relativeExcursion(ts: ts, ratio: ratio)

        // 4. Count qualifying dip events.
        let dips = countDips(ts: ts, excursion: excursion)

        // 5. Index over the usable hours.
        let hours = coverageMinutes / 60.0
        guard hours > 0 else { return .empty(nInput: nInput, coverageMinutes: coverageMinutes) }
        let dph = Double(dips) / hours

        return Result(relativeDipsPerHour: dph, steadiness: steadiness(forDipsPerHour: dph),
                      dipCount: dips, coverageMinutes: coverageMinutes, nInput: nInput)
    }

    // MARK: - Core (operate on parallel ts / value arrays)

    /// Relative excursion e[i] = (ratio[i] − baseline[i]) / baseline[i], baseline = centered rolling median
    /// of `ratio` over the time window [ts[i]−halfWindow, ts[i]+halfWindow]. Positive ⇒ oxygen proxy fell.
    static func relativeExcursion(ts: [Int], ratio: [Double]) -> [Double] {
        let n = ratio.count
        guard n > 0, ts.count == n else { return [] }
        var out = [Double](repeating: 0, count: n)
        var lo = 0, hi = 0
        for i in 0..<n {
            let lowBound = ts[i] - baselineHalfWindowSec
            let highBound = ts[i] + baselineHalfWindowSec
            while lo < n && ts[lo] < lowBound { lo += 1 }
            if hi < i { hi = i }
            while hi + 1 < n && ts[hi + 1] <= highBound { hi += 1 }
            let base = median(Array(ratio[lo...hi]))
            out[i] = base > 0 ? (ratio[i] - base) / base : 0
        }
        return out
    }

    /// Count desaturation-like dips: contiguous runs with excursion ≥ dipThreshold, runs closer than
    /// `mergeGapSec` merged, keeping only merged runs whose total duration is in [minEventSec, maxEventSec].
    static func countDips(ts: [Int], excursion: [Double]) -> Int {
        let n = excursion.count
        guard n > 0, ts.count == n else { return 0 }

        // Collect raw above-threshold runs as (startTs, endTs).
        var runs: [(start: Int, end: Int)] = []
        var i = 0
        while i < n {
            if excursion[i] >= dipThreshold {
                let start = ts[i]
                var j = i
                while j + 1 < n && excursion[j + 1] >= dipThreshold { j += 1 }
                runs.append((start, ts[j]))
                i = j + 1
            } else {
                i += 1
            }
        }
        guard !runs.isEmpty else { return 0 }

        // Merge runs separated by < mergeGapSec.
        var merged: [(start: Int, end: Int)] = [runs[0]]
        for r in runs.dropFirst() {
            if r.start - merged[merged.count - 1].end < mergeGapSec {
                merged[merged.count - 1].end = max(merged[merged.count - 1].end, r.end)
            } else {
                merged.append(r)
            }
        }

        // Keep only merged runs whose duration is in the physiological dip window.
        var count = 0
        for m in merged {
            let dur = m.end - m.start
            if dur >= minEventSec && dur <= maxEventSec { count += 1 }
        }
        return count
    }

    // MARK: - Helpers

    static func median(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let s = values.sorted()
        let n = s.count
        return n % 2 == 1 ? s[n / 2] : (s[n / 2 - 1] + s[n / 2]) / 2
    }
}
