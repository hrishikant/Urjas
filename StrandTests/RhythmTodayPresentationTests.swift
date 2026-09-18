import XCTest
import StrandDesign
@testable import Strand

final class RhythmTodayPresentationTests: XCTestCase {
    private typealias Score = RhythmTodayScorePresentation

    func testScoresKeepSleepRecoveryStrainOrderAndStableIdentifiers() {
        XCTAssertEqual(Score.Kind.allCases, [.sleep, .recovery, .strain])
        XCTAssertEqual(Score.Kind.allCases.map(\.accessibilityID), [
            "rhythm.score.sleep", "rhythm.score.recovery", "rhythm.score.strain",
        ])
    }

    func testVisibleFacesHaveOnlyValuesWithoutScaleSuffixes() {
        XCTAssertEqual(Score(kind: .sleep, storedValue: 87.6).valueLabel, "88")
        XCTAssertEqual(Score(kind: .recovery, storedValue: 82.2).valueLabel, "82")
        for kind in Score.Kind.allCases {
            for value in [0.0, 32.4, 67.0, 100.0] {
                let label = Score(kind: kind, storedValue: value).valueLabel
                XCTAssertFalse(label.contains("%"))
                XCTAssertFalse(label.contains("/"))
            }
        }
    }

    func testStrainUsesTheNativeWhoopFormatterWithoutChangingItsStoredValue() {
        for stored in [0.0, 0.1, 24.5, 48.1, 69.6, 99.9, 100.0] {
            let score = Score(kind: .strain, storedValue: stored)
            XCTAssertEqual(score.storedValue, stored)
            XCTAssertEqual(score.valueLabel, UnitFormatter.effortDisplay(stored, scale: .whoop))
            XCTAssertEqual(score.fraction!, UnitFormatter.effortValue(stored, scale: .whoop) / 21,
                           accuracy: 0.000_001)
        }
        XCTAssertEqual(Score(kind: .strain, storedValue: 100).valueLabel, "21.0")
    }

    func testSleepAndRecoveryStayOnTheOriginalHundredPointScale() {
        for kind in [Score.Kind.sleep, .recovery] {
            let score = Score(kind: kind, storedValue: 82.3)
            XCTAssertEqual(score.storedValue, 82.3)
            XCTAssertEqual(score.fraction!, 0.823, accuracy: 0.000_001)
            XCTAssertEqual(score.accessibilityValue, "82 out of 100")
        }
    }

    func testUnavailableNeverBecomesZeroOrAFullRing() {
        for kind in Score.Kind.allCases {
            for missing in [nil, Double.nan, Double.infinity, -Double.infinity, -1, 101] as [Double?] {
                let score = Score(kind: kind, storedValue: missing)
                XCTAssertEqual(score.valueLabel, "—")
                XCTAssertNil(score.fraction)
                XCTAssertEqual(score.accessibilityValue, "Unavailable")
            }
            let zero = Score(kind: kind, storedValue: 0)
            XCTAssertNotEqual(zero.valueLabel, "—")
            XCTAssertEqual(zero.fraction, 0)
        }
    }

    func testCalibrationAndNoDataKeepTheirEmptyFacesAndDistinctExplanations() {
        let calibration = LiquidTodayView.ChargeDisplay.calibrating(nights: 2)
        let noData = LiquidTodayView.ChargeDisplay.noData
        XCTAssertEqual(Score(kind: .recovery, storedValue: calibration.pct).valueLabel, "—")
        XCTAssertEqual(Score(kind: .recovery, storedValue: noData.pct).valueLabel, "—")
        XCTAssertEqual(Score.recoveryHint(calibration), "Calibrating")
        XCTAssertEqual(Score.recoveryHint(noData), "Unavailable")
        XCTAssertNotNil(calibration.calibrationDetail)
    }

    func testCarriedRecoveryKeepsItsActualValueAndDatedCaption() {
        for caption in ["Last night · 16 Sep", "Latest sleep · 1 Aug"] {
            let carried = LiquidTodayView.ChargeDisplay.carried(pct: 61.2, caption: caption)
            XCTAssertEqual(Score(kind: .recovery, storedValue: carried.pct).valueLabel, "61")
            XCTAssertEqual(Score.recoveryHint(carried), caption)
        }
    }

    func testScoresKeepTheirNativeDestinations() {
        XCTAssertEqual(Score.Kind.sleep.destination, .sleep)
        XCTAssertEqual(Score.Kind.recovery.destination, .metric("recovery"))
        XCTAssertEqual(Score.Kind.strain.destination, .metric("strain"))
    }

    func testRingWidthsFitSmallPhonesWithALargerRecoveryCentre() {
        let screenWidths: [CGFloat] = [320, 375, 390, 430, 768]
        for screenWidth in screenWidths {
            let available = screenWidth - 4 * NoopMetrics.cardPadding
            let spacing = NoopMetrics.space2
            let widths = RhythmTodayScoreLayout.columnWidths(availableWidth: available, spacing: spacing)
            XCTAssertEqual(widths.count, 3)
            XCTAssertEqual(widths[0], widths[2], accuracy: 0.001)
            XCTAssertEqual(widths[1] / widths[0], 1.24, accuracy: 0.001)
            XCTAssertEqual(widths.reduce(0, +) + spacing * 2, available, accuracy: 0.001)
            XCTAssertTrue(widths.allSatisfy { $0.isFinite && $0 > 0 })
        }
    }
}
