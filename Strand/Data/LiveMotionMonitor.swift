import Foundation
import Combine
import StrandAnalytics
#if os(iOS)
import CoreMotion
#endif

/// Live phone-motion signals for an in-progress workout — the movement half of sport prediction (#).
///
/// HR alone can't name a sport, so while a session is recording we sample two free on-device signals:
///   • CoreMotion `CMMotionActivityManager` → the coarse motion class (walking / running / cycling /
///     stationary / automotive) with a low/medium/high confidence.
///   • CoreMotion `CMPedometer` live cadence → steps/minute, which separates on-foot (run/walk) from
///     wheels/water and grades run-vs-walk.
/// `SportRanker` fuses these with GPS speed and the HR family into a best-first sport shortlist.
///
/// iOS only (`CoreMotion` motion-activity/pedometer are unavailable on macOS); the macOS build gets a
/// permanently-`.unknown` monitor that votes for nothing. Everything is honest-nil: a denied permission
/// or an unsupported device simply leaves the signal absent so it can't fabricate a guess.
@MainActor
final class LiveMotionMonitor: ObservableObject {
    /// Latest phone motion class. `.unknown` until the first update / when unavailable.
    @Published private(set) var motion: MotionKind = .unknown
    /// CoreMotion confidence for `motion`: 0 low, 1 medium, 2 high.
    @Published private(set) var motionConfidence: Int = 0
    /// Live step cadence in steps/minute, or nil when steps aren't being counted.
    @Published private(set) var cadenceSpm: Double?

    #if os(iOS)
    private let activityManager = CMMotionActivityManager()
    private let pedometer = CMPedometer()
    private var running = false
    #endif

    /// Begin sampling motion + cadence. Safe to call repeatedly (no-op while already running). Triggers
    /// the Motion & Fitness permission prompt on first use (see `NSMotionUsageDescription`).
    func start() {
        #if os(iOS)
        guard !running else { return }
        running = true
        if CMMotionActivityManager.isActivityAvailable() {
            activityManager.startActivityUpdates(to: .main) { [weak self] activity in
                guard let self, let a = activity else { return }
                self.apply(a)
            }
        }
        if CMPedometer.isCadenceAvailable() {
            pedometer.startUpdates(from: Date()) { [weak self] data, _ in
                guard let self else { return }
                // `currentCadence` is steps/second; nil between footfalls (e.g. cycling) → no cadence vote.
                let spm = data?.currentCadence.map { $0.doubleValue * 60.0 }
                Task { @MainActor in self.cadenceSpm = (spm ?? 0) > 0 ? spm : nil }
            }
        }
        #endif
    }

    /// Stop sampling and reset to the neutral no-signal state so a later session starts clean.
    func stop() {
        #if os(iOS)
        guard running else { return }
        running = false
        activityManager.stopActivityUpdates()
        pedometer.stopUpdates()
        #endif
        motion = .unknown
        motionConfidence = 0
        cadenceSpm = nil
    }

    /// Snapshot the current signals (motion + cadence) for `SportRanker`. Speed/family are added by the
    /// caller from the GPS recorder and the HR classifier.
    func signals(family: WorkoutFamily?, speedMps: Double?) -> SportSignals {
        SportSignals(family: family, motion: motion, motionConfidence: motionConfidence,
                     speedMps: speedMps, cadenceSpm: cadenceSpm)
    }

    #if os(iOS)
    private func apply(_ a: CMMotionActivity) {
        // CMMotionActivity is a set of independent booleans; pick the single most specific movement class.
        // Order matters: cycling/running/walking are meaningful movement; stationary/automotive are the
        // "not exercising on foot/wheels" fallbacks; otherwise unknown.
        let kind: MotionKind
        if a.cycling { kind = .cycling }
        else if a.running { kind = .running }
        else if a.walking { kind = .walking }
        else if a.automotive { kind = .automotive }
        else if a.stationary { kind = .stationary }
        else { kind = .unknown }

        let conf: Int
        switch a.confidence {
        case .high: conf = 2
        case .medium: conf = 1
        default: conf = 0
        }
        motion = kind
        motionConfidence = conf
    }
    #endif
}
