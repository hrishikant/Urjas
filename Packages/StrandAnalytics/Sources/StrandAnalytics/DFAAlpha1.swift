import Foundation
import WhoopProtocol

// DFAAlpha1.swift — short-scale Detrended Fluctuation Analysis (DFA-α1) of an R-R series,
// and its mapping to personal aerobic / anaerobic training-intensity zones.
//
// PURELY ADDITIVE. This file introduces NO change to any Charge / Effort / Rest / sleep output; it is a
// brand-new, opt-in estimator the Ūrjas UI surfaces on the Effort/Strain screen. The existing HRV engines
// (HRVAnalyzer time-domain, HRVFreqDomain Lomb-Scargle) are untouched; this reuses HRVAnalyzer.cleanRR only.
//
// WHAT DFA-α1 IS. Detrended Fluctuation Analysis (Peng et al. 1994, 1995) measures the fractal
// self-similarity / long-range correlation of a time series. Applied to the tachogram (the sequence of
// successive R-R intervals) over SHORT scales — box sizes of 4 to 16 beats — the resulting scaling exponent
// is written α1. At rest the beat-to-beat dynamics are highly correlated and α1 ≈ 1.0 (pink / 1-f noise).
// As exercise intensity rises the correlations break down toward uncorrelated white-noise behaviour and α1
// falls toward 0.5, and can drop below it at very high intensity.
//
// WHY IT IS USEFUL FOR TRAINING ZONES. Unlike heart rate, which needs a lab-measured max/threshold to
// anchor % zones, and unlike lactate, which needs a finger-prick, DFA-α1 tracks the *organisational state*
// of the autonomic system directly and is measured entirely from the beat-to-beat R-R series the strap
// already streams. Two well-replicated thresholds have emerged (Gronwald & Hoos 2020; Rogers, Giles,
// Draper, Hoos & Gronwald 2021; Rogers et al. 2021 "A New Detection Method…"):
//   • α1 ≈ 0.75  ≈ the FIRST ventilatory / aerobic threshold (VT1 / LT1 / "aerobic threshold").
//   • α1 ≈ 0.50  ≈ the SECOND ventilatory / anaerobic threshold (VT2 / LT2 / "anaerobic threshold").
// So a *rising-intensity* effort crosses α1=0.75 as it leaves the easy aerobic domain and crosses α1=0.50
// as it enters the severe/anaerobic domain. This lets an athlete pace by autonomic state ("keep α1 above
// 0.75 for a true easy day") without any lab test.
//
// IMPORTANT CAVEATS (surfaced honestly in the UI, never hidden):
//   • DFA-α1 is EXQUISITELY sensitive to artifacts. A single missed/extra beat corrupts short-scale
//     correlations and biases α1. We clean with the same range + Malik ectopic filter as HRVAnalyzer and
//     additionally REFUSE a result when too many beats were dropped (see maxArtifactFraction). Published
//     protocols recommend < 5% artifacts; we gate at a slightly more permissive, explicitly-stated bound.
//   • It needs a reasonably stationary window. We use a rolling window of ~120 clean beats (≈ the 2-minute
//     windows used in the literature) and require a minimum of `minBeats` beats.
//   • Thresholds are population averages; individual VT1/VT2 α1 values vary. This is a guide, not a lab test.
//
// APPROXIMATE, non-clinical. No units (α1 is a dimensionless scaling exponent).

public enum DFAAlpha1 {

    // MARK: - Tunables (pinned by test, mirrored in any Kotlin twin).

    /// Smallest DFA box size, in beats. The "α1" short-scale band is 4…16 beats (Peng 1995; Gronwald 2020).
    public static let minBox: Int = 4
    /// Largest DFA box size, in beats.
    public static let maxBox: Int = 16
    /// Minimum clean beats required for a trustworthy α1. Below this the window is too short for a stable
    /// log-log fit over boxes up to 16 beats. ~2 minutes of beats is the published target; 60 is a floor.
    public static let minBeats: Int = 60
    /// Rolling-window target length in clean beats (~2 min at 60 bpm). Callers may pass shorter/longer.
    public static let windowBeats: Int = 120
    /// Maximum fraction of input beats the cleaning pipeline may drop before α1 is refused as too noisy.
    /// DFA-α1 is artifact-sensitive; published work targets < 5%. We gate a touch looser and say so.
    public static let maxArtifactFraction: Double = 0.05

    /// α1 value marking the first (aerobic / VT1) threshold. Rogers et al. 2021.
    public static let aerobicThreshold: Double = 0.75
    /// α1 value marking the second (anaerobic / VT2) threshold. Gronwald & Hoos 2020.
    public static let anaerobicThreshold: Double = 0.50

    // MARK: - Zones

    /// Personal training-intensity zone inferred from the current α1, in plain language for the UI.
    public enum Zone: String, Equatable, Sendable, CaseIterable {
        /// α1 ≥ 0.75 — correlated dynamics; comfortably below the aerobic threshold. "Easy".
        case easy
        /// 0.50 ≤ α1 < 0.75 — between the aerobic and anaerobic thresholds. "Moderate / Tempo".
        case moderate
        /// α1 < 0.50 — uncorrelated/anti-correlated dynamics; at or above the anaerobic threshold. "Hard".
        case hard

        /// Layman-friendly label shown to the user.
        public var friendlyName: String {
            switch self {
            case .easy: return "Easy"
            case .moderate: return "Moderate"
            case .hard: return "Hard"
            }
        }

        /// One-line coaching cue.
        public var guidance: String {
            switch self {
            case .easy:
                return "Below your aerobic threshold — sustainable for hours. Ideal for recovery and base miles."
            case .moderate:
                return "Between your aerobic and anaerobic thresholds — tempo effort you can hold for a while."
            case .hard:
                return "At or above your anaerobic threshold — high strain, sustainable only in short bursts."
            }
        }
    }

    /// Result of an α1 computation over one window.
    public struct Alpha1Result: Equatable, Sendable {
        /// The short-scale scaling exponent α1, or nil when the window was too short/noisy.
        public let alpha1: Double?
        /// The inferred training zone, or nil when α1 is nil.
        public let zone: Zone?
        /// Count of R-R intervals supplied (before cleaning).
        public let nInput: Int
        /// Count of clean intervals after range + ectopic filtering.
        public let nClean: Int
        /// Fraction of input beats dropped by cleaning (0…1); nil when nInput == 0.
        public let artifactFraction: Double?

        public init(alpha1: Double?, zone: Zone?, nInput: Int, nClean: Int, artifactFraction: Double?) {
            self.alpha1 = alpha1
            self.zone = zone
            self.nInput = nInput
            self.nClean = nClean
            self.artifactFraction = artifactFraction
        }

        static func empty(nInput: Int, nClean: Int, artifactFraction: Double?) -> Alpha1Result {
            Alpha1Result(alpha1: nil, zone: nil, nInput: nInput, nClean: nClean,
                         artifactFraction: artifactFraction)
        }
    }

    // MARK: - Public API

    /// Map a raw α1 value to a training zone using the aerobic (0.75) and anaerobic (0.50) thresholds.
    public static func zone(forAlpha1 a: Double) -> Zone {
        if a >= aerobicThreshold { return .easy }
        if a >= anaerobicThreshold { return .moderate }
        return .hard
    }

    /// Compute DFA-α1 and its training zone from a series of R-R intervals (ms).
    ///
    /// Pipeline: HRVAnalyzer.cleanRR (range + Malik ectopic) → artifact-fraction gate → short-scale DFA over
    /// boxes `minBox…maxBox` → log-log least-squares slope = α1 → zone mapping. Returns an empty result
    /// (alpha1 == nil) when there are too few clean beats or the artifact fraction exceeds the gate.
    public static func analyze(rrMs: [Double]) -> Alpha1Result {
        let nInput = rrMs.count
        guard nInput > 0 else {
            return .empty(nInput: 0, nClean: 0, artifactFraction: nil)
        }
        let clean = HRVAnalyzer.cleanRR(rrMs)
        let nClean = clean.count
        let dropped = nInput - nClean
        let artifactFraction = Double(dropped) / Double(nInput)

        guard nClean >= minBeats else {
            return .empty(nInput: nInput, nClean: nClean, artifactFraction: artifactFraction)
        }
        guard artifactFraction <= maxArtifactFraction else {
            return .empty(nInput: nInput, nClean: nClean, artifactFraction: artifactFraction)
        }
        guard let a = alpha1(cleanRR: clean) else {
            return .empty(nInput: nInput, nClean: nClean, artifactFraction: artifactFraction)
        }
        return Alpha1Result(alpha1: a, zone: zone(forAlpha1: a),
                            nInput: nInput, nClean: nClean, artifactFraction: artifactFraction)
    }

    // MARK: - Core DFA (operates on an already-clean NN series)

    /// Short-scale DFA scaling exponent α1 over boxes `minBox…maxBox`, computed on an ALREADY-CLEAN NN
    /// series (ms). No filtering is applied here. Returns nil when the series is too short to fill at least
    /// two distinct box sizes, or when the log-log fit is degenerate.
    ///
    /// Algorithm (Peng et al. 1994):
    ///   1. Integrate the mean-removed series: y(k) = Σ_{i≤k} (nn[i] − mean).
    ///   2. For each box size n, split y into non-overlapping windows of length n from the FRONT and again
    ///      from the BACK (doubling the window count, standard for short series), least-squares detrend each
    ///      window, and accumulate residual variance. F(n) = sqrt(mean residual variance).
    ///   3. α1 = slope of log F(n) vs log n across n ∈ [minBox, maxBox].
    public static func alpha1(cleanRR nn: [Double]) -> Double? {
        let N = nn.count
        guard N >= minBox * 2 else { return nil }

        // 1. Cumulative sum of mean-removed series (the DFA "profile").
        let mean = nn.reduce(0, +) / Double(N)
        var y = [Double](repeating: 0, count: N)
        var run = 0.0
        for i in 0..<N {
            run += nn[i] - mean
            y[i] = run
        }

        // 2. Fluctuation F(n) for each box size in the α1 band.
        let hiBox = min(maxBox, N / 2)   // need at least two windows of size n from one direction.
        guard hiBox >= minBox else { return nil }

        var logN: [Double] = []
        var logF: [Double] = []
        for n in minBox...hiBox {
            guard let f = fluctuation(profile: y, boxSize: n), f > 0 else { continue }
            logN.append(Foundation.log(Double(n)))
            logF.append(Foundation.log(f))
        }
        guard logN.count >= 2 else { return nil }

        // 3. Least-squares slope of log F vs log n.
        return leastSquaresSlope(x: logN, y: logF)
    }

    // MARK: - Helpers

    /// F(n): root-mean-square residual of least-squares linear detrending over non-overlapping boxes of
    /// size `boxSize`, scanned from both the front and the back of the profile. Returns nil when no
    /// complete box fits.
    static func fluctuation(profile y: [Double], boxSize n: Int) -> Double? {
        let N = y.count
        guard n >= 2, N >= n else { return nil }
        let boxes = N / n
        guard boxes >= 1 else { return nil }

        var sumSqResid = 0.0
        var countPts = 0

        // Forward: boxes [0, boxes*n) aligned to the start.
        for b in 0..<boxes {
            let start = b * n
            sumSqResid += detrendedSumSq(y, start: start, length: n)
            countPts += n
        }
        // Backward: boxes aligned to the end (covers the tail the forward pass may drop, doubles coverage).
        for b in 0..<boxes {
            let start = N - (b + 1) * n
            sumSqResid += detrendedSumSq(y, start: start, length: n)
            countPts += n
        }
        guard countPts > 0 else { return nil }
        return (sumSqResid / Double(countPts)).squareRoot()
    }

    /// Sum of squared residuals of a least-squares straight-line fit to y[start ..< start+length].
    static func detrendedSumSq(_ y: [Double], start: Int, length: Int) -> Double {
        // Local x = 0…length-1. Fit y = a + b*x, return Σ (y - (a + b*x))^2.
        let m = Double(length)
        var sumX = 0.0, sumY = 0.0, sumXX = 0.0, sumXY = 0.0
        for i in 0..<length {
            let x = Double(i)
            let v = y[start + i]
            sumX += x; sumY += v; sumXX += x * x; sumXY += x * v
        }
        let denom = m * sumXX - sumX * sumX
        guard denom != 0 else {
            // Degenerate (length 1): residual is deviation from mean.
            let mean = sumY / m
            var ss = 0.0
            for i in 0..<length { let d = y[start + i] - mean; ss += d * d }
            return ss
        }
        let b = (m * sumXY - sumX * sumY) / denom
        let a = (sumY - b * sumX) / m
        var ss = 0.0
        for i in 0..<length {
            let x = Double(i)
            let resid = y[start + i] - (a + b * x)
            ss += resid * resid
        }
        return ss
    }

    /// Ordinary-least-squares slope of y on x. Returns nil for degenerate (zero-variance x) input.
    static func leastSquaresSlope(x: [Double], y: [Double]) -> Double? {
        let n = x.count
        guard n >= 2, n == y.count else { return nil }
        let m = Double(n)
        var sumX = 0.0, sumY = 0.0, sumXX = 0.0, sumXY = 0.0
        for i in 0..<n {
            sumX += x[i]; sumY += y[i]; sumXX += x[i] * x[i]; sumXY += x[i] * y[i]
        }
        let denom = m * sumXX - sumX * sumX
        guard denom != 0 else { return nil }
        return (m * sumXY - sumX * sumY) / denom
    }
}
