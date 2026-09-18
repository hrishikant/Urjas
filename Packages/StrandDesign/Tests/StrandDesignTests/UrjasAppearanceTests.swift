import XCTest
import SwiftUI
@testable import StrandDesign

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

final class UrjasAppearanceTests: XCTestCase {
    func testRhythmChromeMetrics() {
        XCTAssertEqual(NoopMetrics.rhythmSideInset, 20)
        XCTAssertEqual(NoopMetrics.rhythmTapTarget, 44)
        XCTAssertEqual(NoopMetrics.rhythmLogoSize, 28)
        XCTAssertEqual(NoopMetrics.rhythmAvatarSize, 32)
        XCTAssertEqual(NoopMetrics.rhythmTabHeight, 52)
        XCTAssertEqual(NoopMetrics.rhythmIconSize, 20)
    }

    func testPreferenceContractAndPlatformDefault() throws {
        XCTAssertEqual(UrjasAppearance.rhythmKey, "urjas.rhythmDesignEnabled")
        let suiteName = "StrandDesignTests.UrjasAppearance.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set("dark", forKey: AppearanceMode.storageKey)
        defaults.set("classic", forKey: ChartStyle.storageKey)
        defaults.set(true, forKey: SceneBackgroundPrefs.enabledKey)
        defaults.set(45, forKey: CardAppearancePrefs.opacityKey)
        defaults.set(true, forKey: SkyBehindCardsPrefs.enabledKey)
        let baseline = defaults.dictionaryRepresentation() as NSDictionary

        #if os(iOS)
        XCTAssertTrue(UrjasAppearance.isRhythm(in: defaults))
        #else
        XCTAssertFalse(UrjasAppearance.isRhythm(in: defaults))
        #endif
        XCTAssertNil(defaults.object(forKey: UrjasAppearance.rhythmKey))
        XCTAssertEqual(defaults.dictionaryRepresentation() as NSDictionary, baseline)

        defaults.set(false, forKey: UrjasAppearance.rhythmKey)
        XCTAssertFalse(UrjasAppearance.isRhythm(in: defaults))
        defaults.set(true, forKey: UrjasAppearance.rhythmKey)
        #if os(iOS)
        XCTAssertTrue(UrjasAppearance.isRhythm(in: defaults))
        #else
        XCTAssertFalse(UrjasAppearance.isRhythm(in: defaults))
        #endif
        defaults.removeObject(forKey: UrjasAppearance.rhythmKey)
        XCTAssertEqual(defaults.dictionaryRepresentation() as NSDictionary, baseline)
    }

    func testPaletteAndTypographyRespondToRepeatedOptOut() {
        withRestoredAppearance {
            for enabled in [false, true, false, true] {
                UserDefaults.standard.set(enabled, forKey: UrjasAppearance.rhythmKey)
                #if os(iOS)
                XCTAssertEqual(UrjasAppearance.isRhythm, enabled)
                #else
                XCTAssertFalse(UrjasAppearance.isRhythm)
                #endif
                XCTAssertEqual(StrandPalette.textPrimary, StrandPalette.textPrimary)

                if UrjasAppearance.isRhythm {
                    assertColor(StrandPalette.surfaceBase, light: "#F6F7F2", dark: "#141C18")
                    assertColor(StrandPalette.surfaceRaised, light: "#FFFFFF", dark: "#1D2822")
                    assertColor(StrandPalette.surfaceOverlay, light: "#FFFFFF", dark: "#1D2822")
                    assertColor(StrandPalette.surfaceInset, light: "#F0F2EB", dark: "#253128")
                    assertColor(StrandPalette.hairline, light: "#E1E6DC", dark: "#344237")
                    assertColor(StrandPalette.textPrimary, light: "#24372C", dark: "#EDF1E8")
                    assertColor(StrandPalette.textSecondary, light: "#667268", dark: "#B1BDB0")
                    assertColor(StrandPalette.textTertiary, light: "#879087", dark: "#88998B")
                    assertColor(StrandPalette.rhythmRecovery, light: "#2A694E", dark: "#B8D991")
                    assertColor(StrandPalette.rhythmSleep, light: "#7B63A5", dark: "#C6B6E8")
                    assertColor(StrandPalette.rhythmStrain, light: "#B46231", dark: "#E6B082")
                    assertColor(StrandPalette.rhythmHero, light: "#EDF2E4", dark: "#293B2C")
                    assertColor(StrandPalette.rhythmButtonFill, light: "#24573F", dark: "#CCEAA5")
                    assertColor(StrandPalette.rhythmButtonText, light: "#FFFFFF", dark: "#203422")
                    XCTAssertEqual(StrandFont.body, .system(.body, design: .default, weight: .regular))
                    XCTAssertEqual(StrandFont.title1, .system(.title, design: .default, weight: .semibold))
                    XCTAssertEqual(NoopMetrics.cardPadding, 20)
                    XCTAssertEqual(NoopMetrics.sectionGap, 24)
                } else {
                    assertColor(StrandPalette.surfaceBase, light: "#F2F2F7", dark: "#121518")
                    assertColor(StrandPalette.surfaceRaised, light: "#FFFFFF", dark: "#25292C")
                    assertColor(StrandPalette.surfaceOverlay, light: "#FFFFFF", dark: "#1C1F26")
                    assertColor(StrandPalette.surfaceInset, light: "#E9E9EE", dark: "#1F2229")
                    assertColor(StrandPalette.hairline, light: "#D8D0BD", dark: "#21304A")
                    assertColor(StrandPalette.textPrimary, light: "#1A2230", dark: "#F4F6F8")
                    assertColor(StrandPalette.textSecondary, light: "#4C5564", dark: "#C8CFD8")
                    assertColor(StrandPalette.textTertiary, light: "#7C8696", dark: "#8A94A4")
                    assertColor(StrandPalette.accent, light: "#234F9E", dark: "#60A0E0")
                    XCTAssertEqual(StrandFont.body,
                                   .custom("Helvetica Neue", size: 15, relativeTo: .body).weight(.regular))
                    XCTAssertEqual(NoopMetrics.cardPadding, 16)
                    XCTAssertEqual(NoopMetrics.sectionGap, 22)
                }
                assertColor(StrandPalette.onDarkPrimary, light: "#F4F6F8", dark: "#F4F6F8")
                assertColor(StrandPalette.onDarkSecondary, light: "#C8CFD8", dark: "#C8CFD8")
                assertColor(StrandPalette.onDarkTertiary, light: "#8A94A4", dark: "#8A94A4")
            }
        }
    }

    func testChartAndSemanticColorsAreIndependentOfRhythm() {
        withRestoredAppearance {
            for style in ChartStyle.allCases {
                StrandPalette.chartStyle = style
                UserDefaults.standard.set(false, forKey: UrjasAppearance.rhythmKey)
                let legacy = dataColors()
                UserDefaults.standard.set(true, forKey: UrjasAppearance.rhythmKey)
                XCTAssertEqual(StrandPalette.chartStyle, style)
                XCTAssertEqual(dataColors(), legacy)
            }
        }
    }

    func testPrimaryButtonUsesContrastingRhythmPair() throws {
        try withRestoredAppearance {
            UserDefaults.standard.set(true, forKey: UrjasAppearance.rhythmKey)
            let primary = NoopButtonAppearance(.primary)
            let fill = try XCTUnwrap(primary.fill)
            if UrjasAppearance.isRhythm {
                assertColor(fill, light: "#24573F", dark: "#CCEAA5")
                assertColor(primary.label, light: "#FFFFFF", dark: "#203422")
                XCTAssertEqual(NoopButtonMetrics.cornerRadius, 12)
            } else {
                assertColor(fill, light: "#234F9E", dark: "#60A0E0")
                assertColor(primary.label, light: "#FFFFFF", dark: "#FFFFFF")
                XCTAssertEqual(NoopButtonMetrics.cornerRadius, 14)
            }
            XCTAssertGreaterThanOrEqual(NoopButtonMetrics.height, 44)
        }
    }

    private func withRestoredAppearance(_ body: () throws -> Void) rethrows {
        let stored = UserDefaults.standard.object(forKey: UrjasAppearance.rhythmKey)
        let chartStyle = StrandPalette.chartStyle
        defer {
            if let stored {
                UserDefaults.standard.set(stored, forKey: UrjasAppearance.rhythmKey)
            } else {
                UserDefaults.standard.removeObject(forKey: UrjasAppearance.rhythmKey)
            }
            StrandPalette.chartStyle = chartStyle
        }
        try body()
    }

    private func dataColors() -> [Double] {
        let colors = StrandPalette.recoveryStops.map(\.color)
            + StrandPalette.strainStops.map(\.color)
            + StrandPalette.hrZones
            + [StrandPalette.sleepAwake, StrandPalette.sleepLight,
               StrandPalette.sleepDeep, StrandPalette.sleepREM,
               StrandPalette.statusPositive, StrandPalette.statusWarning, StrandPalette.statusCritical]
        return colors.flatMap { color in
            let c = color.rgbaComponents
            return [c.r, c.g, c.b, c.a]
        }
    }

    private func assertColor(_ color: Color, light: String, dark: String,
                             file: StaticString = #filePath, line: UInt = #line) {
        for isDark in [false, true] {
            let expected = Color.sRGBComponents(hex: isDark ? dark : light)
            var actual = color.rgbaComponents
            #if os(iOS)
            UITraitCollection(userInterfaceStyle: isDark ? .dark : .light).performAsCurrent {
                actual = color.rgbaComponents
            }
            #elseif canImport(AppKit)
            NSAppearance(named: isDark ? .darkAqua : .aqua)?.performAsCurrentDrawingAppearance {
                actual = color.rgbaComponents
            }
            #endif
            XCTAssertEqual(actual.r, expected.r, accuracy: 0.005, file: file, line: line)
            XCTAssertEqual(actual.g, expected.g, accuracy: 0.005, file: file, line: line)
            XCTAssertEqual(actual.b, expected.b, accuracy: 0.005, file: file, line: line)
            XCTAssertEqual(actual.a, expected.a, accuracy: 0.005, file: file, line: line)
        }
    }
}
