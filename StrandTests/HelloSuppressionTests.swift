import XCTest
import WhoopProtocol
@testable import Strand

final class HelloSuppressionTests: XCTestCase {
    func testExplicitRetryDoesNotRemovePersistentSuppression() {
        XCTAssertFalse(HelloSuppression.shouldSend(suppressed: true, userInitiated: false))
        XCTAssertTrue(HelloSuppression.shouldSend(suppressed: true, userInitiated: true))
        XCTAssertTrue(HelloSuppression.shouldSend(suppressed: false, userInitiated: false))
        let id = UUID()
        defer { HelloSuppression.clear(id) }
        UserDefaults.standard.set(true, forKey: HelloSuppression.key(id))
        XCTAssertTrue(HelloSuppression.suppressed(id))
        XCTAssertFalse(HelloSuppression.suppressed(UUID()))
        HelloSuppression.clear(id)
        XCTAssertFalse(HelloSuppression.suppressed(id))
    }

    func testOnlyUnansweredUnintentionalWhoop5DisconnectCounts() {
        XCTAssertTrue(HelloSuppression.countsAsUnanswered(
            pending: true, bonded: false, intentional: false, family: .whoop5))
        for family: DeviceFamily in [.whoop4, .whoop5] {
            XCTAssertFalse(HelloSuppression.countsAsUnanswered(
                pending: false, bonded: false, intentional: false, family: family))
            XCTAssertFalse(HelloSuppression.countsAsUnanswered(
                pending: true, bonded: true, intentional: false, family: family))
            XCTAssertFalse(HelloSuppression.countsAsUnanswered(
                pending: true, bonded: false, intentional: true, family: family))
        }
        XCTAssertFalse(HelloSuppression.countsAsUnanswered(
            pending: true, bonded: false, intentional: false, family: .whoop4))
    }

    func testLiveHRWatchdogDoesNotPretendToHaveAnEncryptedBond() {
        XCTAssertTrue(HelloSuppression.keepAliveMayRun(
            connected: true, didBond: false, bonded: true, family: .whoop5))
        XCTAssertFalse(HelloSuppression.keepAliveMayRun(
            connected: true, didBond: false, bonded: true, family: .whoop4))
        XCTAssertFalse(HelloSuppression.keepAliveMayRun(
            connected: false, didBond: true, bonded: true, family: .whoop5))
    }

    func testRRUnitsUseFamilyAndPreserveRawValues() throws {
        for raw in [600, 800, 1024, 1500] {
            let parsed = try XCTUnwrap(StandardHeartRate.parse(
                [0x10, 70, UInt8(raw & 255), UInt8(raw >> 8)]))
            XCTAssertEqual(parsed.hr, 70)
            XCTAssertEqual(parsed.rrRawTicks, [raw])
            XCTAssertEqual(StandardHeartRate.intervals(
                rr: parsed.rr, rawTicks: parsed.rrRawTicks, family: .whoop5), [raw])
            XCTAssertEqual(StandardHeartRate.intervals(
                rr: parsed.rr, rawTicks: parsed.rrRawTicks, family: .whoop4),
                           [Int((Double(raw) * 1000 / 1024).rounded())])
        }
    }
}
