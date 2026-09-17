import XCTest
@testable import Strand

final class IntelligenceRescoreGateTests: XCTestCase {
    func testAutomaticTriggersSkipOnlyUnchangedCompleteInputs() {
        for (force, optIn) in [(false, false), (true, true)] {
            XCTAssertTrue(IntelligenceEngine.shouldSkipRescore(
                force: force, skipIfUnchanged: optIn, fingerprint: "same", previous: "same"))
            XCTAssertFalse(IntelligenceEngine.shouldSkipRescore(
                force: force, skipIfUnchanged: optIn, fingerprint: "new", previous: "old"))
        }
    }

    func testEditsAndRecalibrationAlwaysRun() {
        XCTAssertFalse(IntelligenceEngine.shouldSkipRescore(
            force: true, skipIfUnchanged: false, fingerprint: "same", previous: "same"))
    }

    func testNoWatermarkCannotSuppressInitialAnalysis() {
        XCTAssertFalse(IntelligenceEngine.shouldSkipRescore(
            force: false, skipIfUnchanged: true, fingerprint: "new", previous: nil))
        XCTAssertFalse(IntelligenceEngine.shouldSkipRescore(
            force: false, skipIfUnchanged: true, fingerprint: "", previous: ""))
    }
}
