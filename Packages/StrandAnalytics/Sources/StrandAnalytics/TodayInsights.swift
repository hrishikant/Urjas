import Foundation

// TodayInsights.swift - small, pure decision helpers that power the Today screen's WHOOP/Oura-style
// comprehension aids: a one-line daily headline, a "vs your baseline" comparison per score, a positive
// affirmation tone keyed to today's Charge, and a calibration-progress readout for a new wearer.
//
// Everything here is a pure function of its inputs (no clock, no I/O, no PII, no localization). The view
// owns the localized copy and formatting; these helpers own the numbers and the decisions so they can be
// unit-tested against fixtures. No em-dashes.

// MARK: - Headline (feature 1)

/// The single "what do I do today?" answer, mapped from the readiness verdict. Leaders (WHOOP daily
/// outlook, Oura's one-line message) always lead with one plain-language call before the raw scores.
public enum TodayHeadline {
    public enum Call: String, Sendable, Equatable, CaseIterable {
        case push       // primed - go hard
        case maintain   // balanced - normal training
        case easy       // strained - pull back a little
        case rest       // rundown - recover
    }

    /// The day's call, or nil when there isn't enough history to make one (`.insufficient`).
    public static func call(for level: ReadinessEngine.Level) -> Call? {
        switch level {
        case .primed:       return .push
        case .balanced:     return .maintain
        case .strained:     return .easy
        case .rundown:      return .rest
        case .insufficient: return nil
        }
    }
}

// MARK: - Baseline comparison (feature 2)

/// "vs your baseline" for a single score. Oura tags every metric against the user's own baseline; this is
/// the same idea generalized: compare today's value to the mean of the trailing history the caller passes.
public enum BaselineCompare {
    public enum Trend: String, Sendable, Equatable { case above, below, inLine }

    public struct Delta: Equatable, Sendable {
        public let current: Double
        public let baseline: Double
        /// current - baseline. Positive means above the user's own average.
        public let diff: Double
        public let sampleCount: Int
        public init(current: Double, baseline: Double, diff: Double, sampleCount: Int) {
            self.current = current; self.baseline = baseline; self.diff = diff; self.sampleCount = sampleCount
        }
    }

    /// Compare `current` to the mean of `history` (prior days, today excluded). Returns nil when `current`
    /// is absent or there aren't at least `minSamples` finite history values (no baseline claim on thin data).
    public static func delta(current: Double?, history: [Double], minSamples: Int = 3) -> Delta? {
        guard let current, current.isFinite else { return nil }
        let vals = history.filter { $0.isFinite }
        guard vals.count >= minSamples else { return nil }
        let mean = vals.reduce(0, +) / Double(vals.count)
        return Delta(current: current, baseline: mean, diff: current - mean, sampleCount: vals.count)
    }

    /// Classify a delta with a dead-band `tolerance` so tiny day-to-day noise reads as "in line".
    public static func classify(_ delta: Delta, tolerance: Double = 2) -> Trend {
        if delta.diff > tolerance { return .above }
        if delta.diff < -tolerance { return .below }
        return .inLine
    }
}

// MARK: - Affirmation + streak tone (feature 5)

/// A positive-reinforcement tone keyed to today's Charge, plus the streak framing. WHOOP/Oura lean on
/// encouraging, non-clinical copy ("you're recovering well"); the view maps each tone to localized copy.
public enum Affirmation {
    public enum Tone: String, Sendable, Equatable { case peak, strong, steady, low, none }

    /// Charge is a 0-100 recovery score. Higher bands earn a more celebratory tone; nil Charge → `.none`.
    public static func tone(charge: Double?) -> Tone {
        guard let c = charge, c.isFinite else { return .none }
        switch c {
        case 85...:     return .peak
        case 70..<85:   return .strong
        case 50..<70:   return .steady
        default:        return .low
        }
    }

    /// A streak badge is worth showing once it is a genuine run (>= `minToShow` consecutive days).
    public static func showStreak(_ current: Int, minToShow: Int = 3) -> Bool { current >= minToShow }
}

// MARK: - Calibration progress (feature 6)

/// "Calibrating - day N of T" for a new wearer, so a thin first-fortnight of data reads as expected
/// learning rather than a broken app. Oura/WHOOP both front-load a multi-day calibration message.
public enum CalibrationStatus {
    public struct Progress: Equatable, Sendable {
        /// 1-based day within the calibration window (1...target).
        public let day: Int
        public let target: Int
        public init(day: Int, target: Int) { self.day = day; self.target = target }
    }

    /// Given the number of distinct days that already carry data, return the calibration progress, or nil
    /// once calibration is complete (`daysWithData >= target`) or the target is non-positive.
    public static func progress(daysWithData: Int, target: Int = 14) -> Progress? {
        guard target > 0 else { return nil }
        guard daysWithData < target else { return nil }
        let day = Swift.min(Swift.max(daysWithData + 1, 1), target)
        return Progress(day: day, target: target)
    }
}
