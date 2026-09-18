import XCTest
@testable import Strand

final class MobileFeatureCatalogTests: XCTestCase {
    func testOriginalMoreDestinationsArePreservedExactlyOnce() {
        let original = MobileFeature.originalGroups.flatMap(\.features)
        XCTAssertEqual(original.count, 26)
        XCTAssertEqual(Set(original).count, 26)
        XCTAssertEqual(MobileFeature.originalGroups.map(\.id), ["Insights", "Body", "Data", "App"])
        XCTAssertTrue(original.contains(.alarms))
        XCTAssertTrue(original.contains(.shortcutsExport))
        XCTAssertTrue(original.contains(.coach))
    }

    func testEveryFeatureHasOneGroupAndNonemptyMetadata() {
        let grouped = (MobileFeature.originalGroups + MobileFeature.additionalGroups).flatMap(\.features)
        XCTAssertEqual(grouped.count, MobileFeature.allCases.count)
        XCTAssertEqual(Set(grouped), Set(MobileFeature.allCases))
        for feature in MobileFeature.allCases {
            XCTAssertFalse(feature.title.isEmpty)
            XCTAssertFalse(feature.subtitle.isEmpty)
            XCTAssertFalse(feature.symbol.isEmpty)
            XCTAssertEqual(MobileFeature(rawValue: feature.id), feature)
        }
    }

    func testSearchFindsDeeperToolsWithoutDependingOnExpandedGroups() {
        XCTAssertTrue(MobileFeature.matching("  HYDRATION  ").contains(.hydration))
        XCTAssertTrue(MobileFeature.matching("sport suggestions").contains(.sportPrediction))
        XCTAssertTrue(MobileFeature.matching("history detection").contains(.workoutAutomation))
        XCTAssertTrue(MobileFeature.matching("your cards").contains(.customizeCards))
        XCTAssertTrue(MobileFeature.matching("nonexistent-feature-xyz").isEmpty)
        XCTAssertEqual(MobileFeature.matching("").count, MobileFeature.allCases.count)
    }
}
