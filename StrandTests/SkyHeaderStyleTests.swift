import XCTest
import SwiftUI
import StrandDesign
@testable import Strand

final class SkyHeaderStyleTests: XCTestCase {
    func testHiddenSkyUsesThemeAwareCanvasInk() {
        let style = SkyHeaderStyle(hasSky: false)
        XCTAssertEqual(style.primary, StrandPalette.textPrimary)
        XCTAssertEqual(style.secondary, StrandPalette.textSecondary)
        XCTAssertEqual(style.controlFill, StrandPalette.textPrimary.opacity(0.08))
    }

    func testVisibleSkyKeepsOnDarkInk() {
        let style = SkyHeaderStyle(hasSky: true)
        XCTAssertEqual(style.primary, StrandPalette.onDarkPrimary)
        XCTAssertEqual(style.secondary, StrandPalette.onDarkSecondary)
        XCTAssertEqual(style.controlFill, Color.white.opacity(0.16))
    }
}
