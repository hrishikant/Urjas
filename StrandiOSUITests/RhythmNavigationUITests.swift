import XCTest

final class RhythmNavigationUITests: XCTestCase {
    private let app = XCUIApplication()
    private let tabs = ["today", "activity", "sleep", "health", "more"]
    private let features = [
        "trends", "insightsHub", "intelligence", "coach", "insights", "explore", "compare",
        "live", "workouts", "health", "labBook", "stress", "breathe", "intervals", "rhythm",
        "fusedRecord", "appleHealth", "miBand", "dataSources", "backupSync", "shortcutsExport",
        "alarms", "automations", "testCentre", "siriShortcuts", "settings",
        "devices", "hydration", "caffeine", "journal", "bodyClock", "cycleAwareness", "hrvSnapshot",
        "fitnessAge", "vitality", "coupled", "liveSession", "workoutAutomation", "sportPrediction",
        "liveActivity", "sleepDebt", "customizeToday", "customizeMetrics", "customizeCards",
        "featureMap", "updates", "weeklyDigest"
    ]

    override func setUpWithError() throws {
        continueAfterFailure = false
        addUIInterruptionMonitor(withDescription: "Simulator permissions") { alert in
            for title in ["Allow", "Allow While Using App", "OK"] where alert.buttons[title].exists {
                alert.buttons[title].tap()
                return true
            }
            return false
        }
    }

    private func launch(theme: String = "light", sky: Bool = true, legacy: Bool = false, largeText: Bool = false) {
        app.launchArguments = [
            "--demo-seed", "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
            "-theme.appearance", theme, "-noop.showDayCycleBackground", sky ? "YES" : "NO",
            "-urjas.rhythmDesignEnabled", legacy ? "NO" : "YES"
        ]
        if largeText {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityM"]
        }
        app.launch()
        XCTAssertTrue(app.buttons[legacy ? "Home" : "rhythm.tab.today"].waitForExistence(timeout: 60))
    }

    private func capture(_ name: String) {
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    private func openFeature(_ key: String, opensEditor: Bool = false) {
        app.buttons["rhythm.tab.more"].tap()
        let search = app.textFields["rhythm.more.search"]
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        if app.buttons["Clear feature search"].exists { app.buttons["Clear feature search"].tap() }
        search.tap()
        search.typeText(key)
        let link = app.buttons["rhythm.feature.\(key)"]
        XCTAssertTrue(link.waitForExistence(timeout: 10), key)
        link.tap()
        if !opensEditor {
            XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "rhythm.destination.\(key)")
                .firstMatch.waitForExistence(timeout: 15), "Unreachable feature: \(key)")
        }
    }

    func test01FiveTabsInBothThemesWithLegacySkyEnabled() {
        for theme in ["light", "dark"] {
            launch(theme: theme)
            for tab in tabs {
                let button = app.buttons["rhythm.tab.\(tab)"]
                button.tap()
                XCTAssertTrue(button.isSelected, tab)
                XCTAssertTrue(app.buttons["rhythm.profile"].exists)
                XCTAssertTrue(app.buttons["rhythm.sync"].exists)
                for identifier in ["rhythm.theme", "rhythm.quick", "rhythm.profile", "rhythm.sync"] {
                    XCTAssertGreaterThanOrEqual(app.buttons[identifier].frame.height, 44, identifier)
                    XCTAssertGreaterThanOrEqual(app.buttons[identifier].frame.width, 44, identifier)
                }
                XCTAssertLessThanOrEqual(button.frame.maxX, app.frame.maxX + 1)
                capture("rhythm-\(theme)-\(tab)")
            }
            app.terminate()
        }
    }

    func test02EveryFeatureCanOpenAndReturnByReselectingMore() {
        launch()
        for feature in features {
            XCTContext.runActivity(named: feature) { _ in
                openFeature(feature)
                app.buttons["rhythm.tab.more"].tap()
                XCTAssertTrue(app.textFields["rhythm.more.search"].waitForExistence(timeout: 10),
                              "Reselect failed after \(feature)")
            }
        }
    }

    func test03ScoreRingsHaveNativeBackNavigation() {
        launch()
        for key in ["sleep", "recovery", "strain"] {
            let ring = app.buttons["rhythm.score.\(key)"]
            XCTAssertTrue(ring.waitForExistence(timeout: 15), key)
            ring.tap()
            let back = app.navigationBars.buttons.firstMatch
            XCTAssertTrue(back.waitForExistence(timeout: 10), "Missing Back for \(key)")
            back.tap()
            XCTAssertTrue(ring.waitForExistence(timeout: 10))
        }
        capture("rhythm-three-rings")
    }

    func test04SearchWorksAcrossCollapsedGroupsAndNoResults() {
        launch()
        openFeature("backupSync")
        app.buttons["rhythm.tab.more"].tap()
        let search = app.textFields["rhythm.more.search"]
        app.buttons["Clear feature search"].tap()
        search.tap()
        search.typeText("no-such-feature-xyz")
        XCTAssertTrue(app.staticTexts["No matching features"].waitForExistence(timeout: 10))
        app.buttons["Clear feature search"].tap()
        XCTAssertTrue(app.buttons["rhythm.more.group.Insights"].waitForExistence(timeout: 10))
    }

    func test05CustomizationUsesExistingCancellableEditor() {
        launch()
        openFeature("customizeToday")
        app.buttons["rhythm.customize.edit"].tap()
        XCTAssertTrue(app.buttons["Save"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Cancel"].exists)
        capture("rhythm-customization")
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["rhythm.customize.edit"].waitForExistence(timeout: 10))
    }

    func test06CoachProviderNamesAndCustomURLRemainAvailable() {
        launch()
        openFeature("coach")
        XCTAssertTrue(app.staticTexts["Connect a provider"].waitForExistence(timeout: 10))
        let provider = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Provider")).firstMatch
        provider.tap()
        XCTAssertTrue(app.buttons["Google Gemini"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Custom (OpenAI-compatible)"].exists)
        app.buttons["Custom (OpenAI-compatible)"].tap()
        XCTAssertTrue(app.textFields["Server URL"].waitForExistence(timeout: 10))
        capture("rhythm-coach-settings")
    }

    func test07LegacyInterfaceRemainsAvailable() {
        launch(theme: "dark", sky: false, legacy: true)
        XCTAssertFalse(app.buttons["rhythm.tab.today"].exists)
        for title in ["Health", "Sleep", "More"] {
            XCTAssertTrue(app.buttons[title].exists)
            app.buttons[title].tap()
        }
        app.buttons["Home"].tap()
        capture("rhythm-legacy-opt-out")
    }

    func test08DirectEditorsOpenWithoutSavingOnCancel() {
        launch()
        for key in ["manualWorkout", "sleepEdit", "nap"] {
            openFeature(key, opensEditor: true)
            let cancel = app.buttons["Cancel"].firstMatch
            XCTAssertTrue(cancel.waitForExistence(timeout: 15), key)
            capture("rhythm-editor-\(key)")
            cancel.tap()
            XCTAssertFalse(app.buttons["Cancel"].firstMatch.waitForExistence(timeout: 2),
                           "Entry action reopened after cancellation: \(key)")
        }
    }

    func test09ManualWorkoutPersistsAcrossRelaunch() {
        launch()
        openFeature("manualWorkout", opensEditor: true)
        let sport = app.textFields["Sport"]
        XCTAssertTrue(sport.waitForExistence(timeout: 10))
        sport.tap()
        sport.typeText("Rhythm QA")
        app.buttons["Add workout"].tap()
        XCTAssertTrue(sport.waitForNonExistence(timeout: 20))
        app.terminate()
        launch()
        app.buttons["rhythm.tab.activity"].tap()
        let search = app.textFields["rhythm.activity.search"]
        for _ in 0..<8 where !search.isHittable { app.swipeUp() }
        XCTAssertTrue(search.isHittable)
        search.tap()
        search.typeText("Rhythm QA")
        app.swipeUp()
        XCTAssertTrue(app.staticTexts["Rhythm QA"].firstMatch.waitForExistence(timeout: 15))
        capture("rhythm-manual-workout-persisted")
    }

    func test10QuickStartFullSportPickerAndEndConfirmation() {
        launch()
        app.buttons["rhythm.quick"].tap()
        app.buttons["rhythm.quick.start"].tap()
        let search = app.textFields["Search sport"].firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        search.tap()
        search.typeText("Badminton")
        app.buttons["Pick Badminton"].tap()
        app.buttons["Start Badminton"].tap()
        let end = app.buttons["End workout"].firstMatch
        XCTAssertTrue(end.waitForExistence(timeout: 15))
        capture("rhythm-live-badminton")
        end.tap()
        XCTAssertTrue(app.alerts["End this workout?"].waitForExistence(timeout: 10))
        app.alerts.buttons["Cancel"].tap()
        XCTAssertTrue(end.exists)
        end.tap()
        app.alerts.buttons["End workout"].tap()
        XCTAssertTrue(end.waitForNonExistence(timeout: 15))
    }

    func test11CustomizationSaveAndRelaunchPersistence() {
        launch()
        openFeature("customizeMetrics")
        app.buttons["rhythm.customize.edit"].tap()
        let detailed = app.switches["Detailed tiles"]
        XCTAssertTrue(detailed.waitForExistence(timeout: 10))
        let original = detailed.value as? String
        capture("rhythm-customization-before-toggle")
        detailed.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        let changedValue = NSPredicate(format: "value != %@", original ?? "")
        _ = expectation(for: changedValue, evaluatedWith: detailed)
        waitForExpectations(timeout: 5)
        let changed = detailed.value as? String
        XCTAssertNotEqual(original, changed)
        app.buttons["Save"].tap()
        app.terminate()
        launch()
        openFeature("customizeMetrics")
        app.buttons["rhythm.customize.edit"].tap()
        XCTAssertTrue(detailed.waitForExistence(timeout: 10))
        XCTAssertEqual(detailed.value as? String, changed)
        detailed.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        app.buttons["Save"].tap()
    }

    func test12DataSourcesReselectAndFeatureGrid() {
        launch()
        for feature in ["dataSources", "backupSync", "hrvSnapshot", "fitnessAge", "featureMap"] {
            openFeature(feature)
            capture("rhythm-route-\(feature)")
            app.buttons["rhythm.tab.more"].tap()
            capture("rhythm-return-\(feature)")
            XCTAssertTrue(app.textFields["rhythm.more.search"].waitForExistence(timeout: 10), feature)
        }
    }

    func test13LargeTextKeepsRingsAndPrimaryControlsWithinScreen() {
        launch(largeText: true)
        let sleep = app.buttons["rhythm.score.sleep"]
        let recovery = app.buttons["rhythm.score.recovery"]
        let strain = app.buttons["rhythm.score.strain"]
        XCTAssertTrue(sleep.waitForExistence(timeout: 15))
        XCTAssertLessThan(sleep.frame.midX, recovery.frame.midX)
        XCTAssertLessThan(recovery.frame.midX, strain.frame.midX)
        XCTAssertGreaterThan(recovery.frame.width, sleep.frame.width)
        XCTAssertGreaterThanOrEqual(sleep.frame.minX, 0)
        XCTAssertLessThanOrEqual(strain.frame.maxX, app.frame.maxX + 1)
        for tab in tabs {
            app.buttons["rhythm.tab.\(tab)"].tap()
            for key in ["rhythm.theme", "rhythm.quick", "rhythm.profile", "rhythm.sync"] {
                let button = app.buttons[key]
                XCTAssertGreaterThanOrEqual(button.frame.width, 44, key)
                XCTAssertGreaterThanOrEqual(button.frame.minX, 0, key)
                XCTAssertLessThanOrEqual(button.frame.maxX, app.frame.maxX + 1, key)
            }
            capture("rhythm-large-text-\(tab)")
        }
    }

    func test14LiveActivityKeepsRawValuesAndDecodesOlderPayloads() throws {
        let oldPayload = Data(#"{"bpm":123,"recovery":65,"bonded":true,"effort":80}"#.utf8)
        let oldState = try JSONDecoder().decode(NOOPActivityAttributes.ContentState.self, from: oldPayload)
        XCTAssertEqual(oldState.effort, 80)
        XCTAssertNil(oldState.effortDisplay)
        let state = NOOPActivityAttributes.ContentState(bpm: 123, recovery: 65, bonded: true,
                                                       effort: 80, effortDisplay: "16.8")
        let restored = try JSONDecoder().decode(NOOPActivityAttributes.ContentState.self,
                                                from: JSONEncoder().encode(state))
        XCTAssertEqual(restored, state)
        XCTAssertEqual(restored.effort, 80)
        XCTAssertEqual(restored.effortDisplay, "16.8")
    }
}
