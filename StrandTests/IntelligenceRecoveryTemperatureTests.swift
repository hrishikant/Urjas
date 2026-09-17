import XCTest
import StrandAnalytics
import WhoopStore
@testable import Strand

@MainActor
final class IntelligenceRecoveryTemperatureTests: XCTestCase {
    private func baseline(_ mean: Double, spread: Double,
                          status: BaselineStatus = .trusted) -> BaselineState {
        BaselineState(baseline: mean, spread: spread,
                      nValid: status == .calibrating ? 3 : 14,
                      nightsSinceUpdate: status == .stale ? 15 : 0, status: status)
    }

    private func daily(skin: Double? = nil, recovery: Double? = 99) -> DailyMetric {
        DailyMetric(day: "2026-09-17", totalSleepMin: 420, efficiency: 0.85,
                    deepMin: 80, remMin: 90, lightMin: 250, disturbances: 2,
                    restingHr: 58, avgHrv: 48, recovery: recovery, strain: 61, exerciseCount: 2,
                    spo2Pct: 97, skinTempDevC: skin, respRateBpm: 15, steps: 42,
                    activeKcalEst: 1840, spo2Red: 100, spo2Ir: 200)
    }

    private func expected(_ input: DailyMetric, hrv: BaselineState, skin: Double?) -> Double? {
        RecoveryScorer.recovery(
            hrv: 48, rhr: 58, resp: 15, hrvBaseline: hrv, rhrBaseline: nil,
            respBaseline: nil,
            sleepPerf: AnalyticsEngine.Rest.composite(daily: input).map { $0 / 100 } ?? input.efficiency,
            skinTempDev: skin)
    }

    func testDeviationIsAttachedBeforeScoringWithoutChangingOtherMetrics() {
        let hrv = baseline(50, spread: 6)
        let baselines = AnalyticsEngine.ProfileBaselines(hrv: hrv, skinTemp: baseline(34.5, spread: 0.4))
        for (nightly, deviation) in [(34.804, 0.3), (34.196, -0.3)] {
            let result = IntelligenceEngine.recomputeRecoveryDaily(
                daily(), nightlySkinTempC: nightly, baselines: baselines)
            let score = expected(daily(), hrv: hrv, skin: deviation)
            XCTAssertNotEqual(score, expected(daily(), hrv: hrv, skin: nil))
            XCTAssertEqual(result, daily(skin: deviation, recovery: score))
        }
    }

    func testMissingOrUnusableTemperatureClearsStaleDeviation() {
        let hrv = baseline(50, spread: 6)
        let cases: [(Double?, BaselineState?)] = [
            (nil, baseline(34.5, spread: 0.4)), (34.8, nil),
            (34.8, baseline(34.5, spread: 0.4, status: .calibrating)),
            (34.8, baseline(34.5, spread: 0.4, status: .stale))
        ]
        for (nightly, skinBaseline) in cases {
            let result = IntelligenceEngine.recomputeRecoveryDaily(
                daily(skin: 9), nightlySkinTempC: nightly,
                baselines: .init(hrv: hrv, skinTemp: skinBaseline))
            XCTAssertEqual(result, daily(recovery: expected(daily(), hrv: hrv, skin: nil)))
        }
    }

    func testTemperatureCannotBypassRecoveryCalibration() {
        let hrvBaselines: [BaselineState?] = [nil, baseline(50, spread: 6, status: .calibrating)]
        for hrv in hrvBaselines {
            let result = IntelligenceEngine.recomputeRecoveryDaily(
                daily(), nightlySkinTempC: 34.8,
                baselines: .init(hrv: hrv, skinTemp: baseline(34.5, spread: 0.4)))
            XCTAssertNil(result.recovery)
            XCTAssertEqual(result.skinTempDevC, 0.3)
        }
    }
}
