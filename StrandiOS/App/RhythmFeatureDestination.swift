#if os(iOS)
import SwiftUI
import StrandDesign

extension View {
    func mobileFeatureDestinations() -> some View {
        navigationDestination(for: MobileFeature.self) { feature in
            RhythmFeatureDestination(feature: feature)
        }
    }
}

struct RhythmFeatureDestination: View {
    @Environment(\.dismiss) private var dismiss
    let feature: MobileFeature

    var body: some View {
        destination
            .background(StrandPalette.surfaceBase.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.visible, for: .navigationBar)
            .toolbarBackground(StrandPalette.surfaceBase, for: .navigationBar)
            .accessibilityIdentifier("rhythm.destination.\(feature.rawValue)")
    }

    @ViewBuilder private var destination: some View {
        switch feature {
        case .trends: TrendsView()
        case .insightsHub: InsightsHubView()
        case .intelligence: IntelligenceView()
        case .coach: CoachView()
        case .insights, .journal: InsightsView()
        case .explore: MetricExplorerView()
        case .compare: CompareView()
        case .live: LiveView()
        case .workouts: WorkoutsView()
        case .manualWorkout: WorkoutsView(initialAction: .add)
        case .sleepEdit: SleepView(initialAction: .edit)
        case .nap: SleepView(initialAction: .nap)
        case .health: HealthView()
        case .labBook: LabBookView()
        case .stress: StressView()
        case .breathe: BreathingView()
        case .intervals: IntervalTimerView()
        case .rhythm: RhythmHost()
        case .fusedRecord: FusedRecordHost()
        case .appleHealth: AppleHealthView()
        case .miBand: XiaomiBandView()
        case .dataSources: DataSourcesView()
        case .backupSync: BackupSyncView()
        case .shortcutsExport: ShortcutExportSettingsView()
        case .alarms: SmartAlarmView()
        case .automations: AutomationsView()
        case .testCentre: TestCentreView()
        case .siriShortcuts: SiriShortcutsSettingsView()
        case .settings: SettingsView()
        case .devices: DevicesView()
        case .hydration: HydrationView()
        case .caffeine:
            ScreenScaffold(title: "Caffeine", subtitle: "A little context for your next cup.") { CaffeineLogCard() }
        case .hrvSnapshot: HRVSnapshotView()
        case .bodyClock, .cycleAwareness, .fitnessAge, .vitality:
            RhythmHealthFeatureView(feature: feature)
        case .coupled: CoupledView()
        case .sleepDebt: RhythmSleepToolsView()
        case .liveSession: RhythmLiveSessionLauncher()
        case .workoutAutomation: RhythmWorkoutAutomationView()
        case .sportPrediction: RhythmSportPredictionView()
        case .liveActivity: RhythmLiveActivitySettingsView()
        case .customizeToday: RhythmCustomizationLauncher(initialDestination: .today)
        case .customizeMetrics: RhythmCustomizationLauncher(initialDestination: .keyMetrics)
        case .customizeCards: RhythmCustomizationLauncher(initialDestination: .yourCards)
        case .featureMap: RhythmFeatureMapView()
        case .updates: UpdatesInboxView(onClose: { dismiss() })
        case .weeklyDigest: WeeklyDigestView()
        }
    }
}

private struct RhythmFeatureMapView: View {
    var body: some View {
        ScreenScaffold(title: "Feature Map", subtitle: "Familiar tools, with their own place.") {
            Text("All 26 original More destinations remain available. Your deeper tools and custom recording features are listed below as well.")
                .font(StrandFont.body).foregroundStyle(StrandPalette.textSecondary)
            ForEach(MobileFeature.originalGroups + MobileFeature.additionalGroups) { group in
                VStack(alignment: .leading, spacing: NoopMetrics.space2) {
                    Text(group.title).font(StrandFont.headline).foregroundStyle(StrandPalette.textPrimary)
                    NoopCard(padding: 0) {
                        VStack(spacing: 0) {
                            ForEach(group.features.filter { $0 != .featureMap }) { feature in
                                RhythmFeatureRow(feature: feature)
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct RhythmCustomizationLauncher: View {
    let initialDestination: TodayCustomizationDestination
    @AppStorage(TodayLayoutPrefs.orderKey) private var orderRaw = ""
    @AppStorage(TodayLayoutPrefs.hiddenKey) private var hiddenRaw = ""
    @AppStorage(KeyMetricPrefs.layoutKey) private var metricsRaw = ""
    @AppStorage("today.keyMetricsDetailed") private var detailed = true
    @AppStorage("today.keyMetricsWindowDays") private var windowDays = 14
    @AppStorage(DashboardCardPrefs.selectionKey) private var cardsRaw = ""
    @State private var showEditor = false

    private var feature: MobileFeature {
        switch initialDestination {
        case .today: return .customizeToday
        case .keyMetrics: return .customizeMetrics
        case .yourCards: return .customizeCards
        }
    }

    var body: some View {
        ScreenScaffold(title: LocalizedStringKey(feature.title), subtitle: LocalizedStringKey(feature.subtitle)) {
            NoopCard {
                VStack(alignment: .leading, spacing: NoopMetrics.space4) {
                    Text("Your layout, your choice.")
                        .font(StrandFont.title2).foregroundStyle(StrandPalette.textPrimary)
                    Text("Reorder, hide or restore sections and choose your cards. Changes use your existing Home preferences. Cancel keeps the original layout; Save applies your changes.")
                        .font(StrandFont.body).foregroundStyle(StrandPalette.textSecondary)
                    Button("Edit layout") { showEditor = true }
                        .buttonStyle(.borderedProminent).tint(StrandPalette.rhythmButtonFill)
                        .accessibilityIdentifier("rhythm.customize.edit")
                }
            }
            Text("\(TodayLayoutPrefs.visibleOrder(orderRaw: orderRaw, hiddenRaw: hiddenRaw).count) visible Home sections")
                .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
        }
        .sheet(isPresented: $showEditor) {
            TodayCustomizationSheet(
                initialDestination: initialDestination,
                sectionOrderRaw: $orderRaw, hiddenSectionsRaw: $hiddenRaw,
                keyMetricsRaw: $metricsRaw, keyMetricsDetailed: $detailed,
                keyMetricsWindowDays: $windowDays, dashboardCardsRaw: $cardsRaw
            )
        }
    }
}

private struct RhythmLiveSessionLauncher: View {
    @AppStorage(LiveSessionPrefs.betaKey) private var enabled = true
    @State private var showSession = false

    var body: some View {
        ScreenScaffold(title: "Live Sessions", subtitle: "Your silence-first workout guardian.") {
            NoopCard {
                VStack(alignment: .leading, spacing: NoopMetrics.space4) {
                    Label("Beta", systemImage: "shield").font(StrandFont.caption)
                    Text("A quieter way to stay in your range.")
                        .font(StrandFont.title2).foregroundStyle(StrandPalette.textPrimary)
                    Text("Your existing guardian watches available live heart-rate signals and offers the wrist cues you enabled. When the stream is stale, coaching pauses. Opening this page does not begin a session.")
                        .font(StrandFont.body).foregroundStyle(StrandPalette.textSecondary)
                    Toggle("Live Sessions (beta)", isOn: $enabled).tint(StrandPalette.accent)
                    Button("Start session") { showSession = true }
                        .buttonStyle(.borderedProminent).tint(StrandPalette.rhythmButtonFill)
                        .disabled(!enabled)
                        .accessibilityIdentifier("rhythm.guardian.start")
                }
            }
        }
        .fullScreenCover(isPresented: $showSession) {
            LiveSessionView(onClose: { showSession = false })
        }
    }
}

private struct RhythmWorkoutAutomationView: View {
    @AppStorage(PuffinExperiment.autoDetectWorkoutsKey) private var enabled = false
    @AppStorage(Collector.imuCaptureEnabledKey) private var imuCapture = true

    var body: some View {
        ScreenScaffold(title: "Workout Automation", subtitle: "The planned sessions. The ones you did not start.") {
            NoopCard {
                VStack(alignment: .leading, spacing: NoopMetrics.space4) {
                    Toggle("Auto-detect workouts", isOn: $enabled).tint(StrandPalette.accent)
                        .accessibilityIdentifier("rhythm.workouts.automatic")
                    Text("Uses the same setting as Settings. Sustained exertion can start a live session; cool-down, lost contact and safety limits end automatically started sessions. Manual recordings remain under your control.")
                        .font(StrandFont.body).foregroundStyle(StrandPalette.textSecondary)
                    Divider()
                    Label("Catch up after the app was away", systemImage: "arrow.triangle.2.circlepath")
                        .font(StrandFont.headline)
                    Text("Received history is analysed by the existing detector. Confirmed sports and manual or imported sessions are protected from later recomputation. iOS can suspend the app; this design does not remove those system limits.")
                        .font(StrandFont.body).foregroundStyle(StrandPalette.textSecondary)
                    Divider()
                    Toggle("Keep available raw IMU for sport refinement", isOn: $imuCapture)
                        .tint(StrandPalette.accent)
                        .accessibilityIdentifier("rhythm.workouts.imu")
                    Text("Keeps the supported band's decoded motion buffers for the existing within-family sport refinement. Missing motion never becomes a confident label. No new sensor or firmware command is sent by this switch.")
                        .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                }
            }
            NoopCard(padding: 0) {
                VStack(spacing: 0) {
                    RhythmFeatureRow(feature: .sportPrediction)
                    RhythmFeatureRow(feature: .workouts)
                    RhythmFeatureRow(feature: .testCentre)
                }
            }
        }
    }
}

private struct RhythmSportPredictionView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScreenScaffold(title: "Sport Prediction", subtitle: "A suggestion, never a replacement for your choice.") {
            NoopCard {
                VStack(alignment: .leading, spacing: NoopMetrics.space4) {
                    if let workout = model.activeWorkout {
                        Text(workout.sport).font(StrandFont.title2)
                        Text("\(workout.samples.count) heart-rate samples in this recording")
                            .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                        if workout.samples.count > 1 {
                            Text("Suggestions from the current recording").font(StrandFont.headline)
                            ForEach(Array(model.liveWorkoutSuggestions.prefix(6)), id: \.self) { sport in
                                Button { model.setActiveWorkoutSport(sport) } label: {
                                    HStack {
                                        Text(sport).font(StrandFont.body)
                                        Spacer()
                                        Image(systemName: sport == workout.sport ? "checkmark.circle.fill" : "circle")
                                    }
                                    .frame(minHeight: NoopMetrics.rhythmTapTarget)
                                }
                                .buttonStyle(.plain).foregroundStyle(StrandPalette.accent)
                                .accessibilityLabel("Choose \(sport)")
                            }
                        } else {
                            Text("Waiting for usable recording signals. No confidence percentage is invented.")
                                .font(StrandFont.body).foregroundStyle(StrandPalette.textSecondary)
                        }
                    } else {
                        Text("No active recording.").font(StrandFont.title2)
                        Text("Start a workout to see the available live suggestions, or open a saved session to correct its sport.")
                            .font(StrandFont.body).foregroundStyle(StrandPalette.textSecondary)
                    }
                    Divider()
                    Text("The native ranking combines available heart-rate shape, phone motion, cadence and GPS speed. Synced raw IMU can refine supported history. These are heuristic suggestions, not guaranteed sport recognition.")
                        .font(StrandFont.body).foregroundStyle(StrandPalette.textSecondary)
                }
            }
            NoopCard(padding: 0) {
                VStack(spacing: 0) {
                    RhythmFeatureRow(feature: .live)
                    RhythmFeatureRow(feature: .workouts)
                }
            }
        }
    }
}

private struct RhythmLiveActivitySettingsView: View {
    @EnvironmentObject private var model: AppModel
    @AppStorage(UnitPrefs.liveActivityKey) private var enabled = true

    var body: some View {
        ScreenScaffold(title: "Live Activity", subtitle: "Your workout stays within reach.") {
            NoopCard {
                VStack(alignment: .leading, spacing: NoopMetrics.space4) {
                    Toggle("Show Live Activity", isOn: $enabled).tint(StrandPalette.accent)
                        .accessibilityIdentifier("rhythm.liveActivity.enabled")
                    Text("Uses your existing Lock Screen and Dynamic Island integration. Available fields depend on a real connected band and the recording. iOS decides whether the system surface is shown.")
                        .font(StrandFont.body).foregroundStyle(StrandPalette.textSecondary)
                    if let started = model.liveWorkoutStartedAt, let sport = model.liveWorkoutSport {
                        Divider()
                        Text(sport).font(StrandFont.title2)
                        Text(started, style: .timer).font(StrandFont.number(NoopMetrics.space8))
                        Text("Current recording").font(StrandFont.caption)
                    } else {
                        Text("No workout is recording.").font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                    }
                    Text("When connected, live heart rate may also appear outside a workout. Turning this off hides the system activity without deleting the session.")
                        .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                }
            }
            NoopCard(padding: 0) { RhythmFeatureRow(feature: .live) }
        }
    }
}
#endif
