import Foundation

/// Stable presentation routes. These never change stored metric or workout identifiers.
enum MobileFeature: String, CaseIterable, Identifiable {
    case trends, insightsHub, intelligence, coach, insights, explore, compare
    case live, workouts, health, labBook, stress, breathe, intervals, rhythm
    case fusedRecord, appleHealth, miBand, dataSources, backupSync, shortcutsExport
    case alarms, automations, testCentre, siriShortcuts, settings
    case devices, hydration, caffeine, journal, bodyClock, cycleAwareness, hrvSnapshot
    case fitnessAge, vitality, coupled, liveSession, workoutAutomation, sportPrediction, liveActivity
    case sleepDebt, customizeToday, customizeMetrics, customizeCards, featureMap, updates, weeklyDigest
    case manualWorkout, sleepEdit, nap

    var id: String { rawValue }

    var title: String {
        switch self {
        case .trends: return String(localized: "Trends")
        case .insightsHub: return String(localized: "What Moves You")
        case .intelligence: return String(localized: "Intelligence")
        case .coach: return String(localized: "Coach")
        case .insights: return String(localized: "Insights")
        case .explore: return String(localized: "Explore")
        case .compare: return String(localized: "Compare")
        case .live: return String(localized: "Live")
        case .workouts: return String(localized: "Workouts")
        case .health: return String(localized: "Health")
        case .labBook: return String(localized: "Lab Book")
        case .stress: return String(localized: "Stress")
        case .breathe: return String(localized: "Breathe")
        case .intervals: return String(localized: "Intervals")
        case .rhythm: return String(localized: "Rhythm")
        case .fusedRecord: return String(localized: "Your Data, Fused")
        case .appleHealth: return String(localized: "Apple Health")
        case .miBand: return String(localized: "Mi Band")
        case .dataSources: return String(localized: "Data Sources")
        case .backupSync: return String(localized: "Backup & Sync")
        case .shortcutsExport: return String(localized: "Shortcuts Export")
        case .alarms: return String(localized: "Alarms")
        case .automations: return String(localized: "Automations")
        case .testCentre: return String(localized: "Test Centre")
        case .siriShortcuts: return String(localized: "Siri & Shortcuts")
        case .settings: return String(localized: "Settings")
        case .devices: return String(localized: "Devices")
        case .hydration: return String(localized: "Hydration")
        case .caffeine: return String(localized: "Caffeine")
        case .journal: return String(localized: "Journal")
        case .bodyClock: return String(localized: "Body Clock")
        case .cycleAwareness: return String(localized: "Cycle Awareness")
        case .hrvSnapshot: return String(localized: "HRV Snapshot")
        case .fitnessAge: return String(localized: "Fitness Age")
        case .vitality: return String(localized: "Vitality")
        case .coupled: return String(localized: "Coupled")
        case .liveSession: return String(localized: "Live Sessions")
        case .workoutAutomation: return String(localized: "Workout Automation")
        case .sportPrediction: return String(localized: "Sport Prediction")
        case .liveActivity: return String(localized: "Live Activity")
        case .sleepDebt: return String(localized: "Sleep Debt")
        case .customizeToday: return String(localized: "Customise Today")
        case .customizeMetrics: return String(localized: "Choose Key Metrics")
        case .customizeCards: return String(localized: "Choose Your Cards")
        case .featureMap: return String(localized: "Feature Map")
        case .updates: return String(localized: "Updates")
        case .weeklyDigest: return String(localized: "Weekly Digest")
        case .manualWorkout: return String(localized: "Add a Workout")
        case .sleepEdit: return String(localized: "Edit Sleep")
        case .nap: return String(localized: "Add a Nap")
        }
    }

    var subtitle: String {
        switch self {
        case .trends: return String(localized: "Your numbers, over time.")
        case .insightsHub: return String(localized: "Habits, outcomes and your own experiments.")
        case .intelligence: return String(localized: "Understand and recompute your scores.")
        case .coach: return String(localized: "Your provider, your model, your consent.")
        case .insights: return String(localized: "Your journal and personal patterns.")
        case .explore: return String(localized: "Every metric and its original source.")
        case .compare: return String(localized: "Put your signals side by side.")
        case .live: return String(localized: "Heart rate, signals and recording controls.")
        case .workouts: return String(localized: "Planned sessions and spontaneous games.")
        case .health: return String(localized: "Get to know your own baseline.")
        case .labBook: return String(localized: "A private notebook for your health records.")
        case .stress: return String(localized: "Autonomic load, with room to pause.")
        case .breathe: return String(localized: "Guided breathing and real-time biofeedback.")
        case .intervals: return String(localized: "Work, recover and repeat.")
        case .rhythm: return String(localized: "Experimental beat-to-beat visualisation.")
        case .fusedRecord: return String(localized: "Choose the source you trust per signal.")
        case .appleHealth: return String(localized: "Permissions, imports and write-back.")
        case .miBand: return String(localized: "Bring in your Mi Fitness history.")
        case .dataSources: return String(localized: "Import and manage your original data.")
        case .backupSync: return String(localized: "Local backups and restore controls.")
        case .shortcutsExport: return String(localized: "Your sideload-friendly Apple Health path.")
        case .alarms: return String(localized: "Wake-up plans and wind-down reminders.")
        case .automations: return String(localized: "Wrist alerts, quiet hours and triggers.")
        case .testCentre: return String(localized: "Connection, sensor and analysis diagnostics.")
        case .siriShortcuts: return String(localized: "Hands-free actions and useful recipes.")
        case .settings: return String(localized: "Profile, units, appearance and preferences.")
        case .devices: return String(localized: "Pair, switch and inspect your band.")
        case .hydration: return String(localized: "Log drinks and follow your daily total.")
        case .caffeine: return String(localized: "Log caffeine and understand its timing.")
        case .journal: return String(localized: "How did today feel?")
        case .bodyClock: return String(localized: "Light, sleep and your daily rhythm.")
        case .cycleAwareness: return String(localized: "Optional awareness, with consent.")
        case .hrvSnapshot: return String(localized: "A still, seated reading from your band.")
        case .fitnessAge: return String(localized: "Your weekly fitness comparison.")
        case .vitality: return String(localized: "A wider view of everyday habits.")
        case .coupled: return String(localized: "HRV and resting heart rate in context.")
        case .liveSession: return String(localized: "Your silence-first workout guardian.")
        case .workoutAutomation: return String(localized: "Automatic starts, stops and history detection.")
        case .sportPrediction: return String(localized: "Available signals and editable sport suggestions.")
        case .liveActivity: return String(localized: "Your workout on the Lock Screen and Dynamic Island.")
        case .sleepDebt: return String(localized: "Recent sleep balance, including separate naps.")
        case .customizeToday: return String(localized: "Reorder or hide your nine Home sections.")
        case .customizeMetrics: return String(localized: "Choose your numbers and trend detail.")
        case .customizeCards: return String(localized: "Keep your personal tools close.")
        case .featureMap: return String(localized: "Find every destination in the new layout.")
        case .updates: return String(localized: "Reading updates and your dismissed cards.")
        case .weeklyDigest: return String(localized: "A week of recovery, movement and rest.")
        case .manualWorkout: return String(localized: "Log a session you did not record.")
        case .sleepEdit: return String(localized: "Correct the latest main night's recorded times.")
        case .nap: return String(localized: "Keep a daytime rest separate from your main night.")
        }
    }

    var symbol: String {
        switch self {
        case .trends, .intelligence, .insights, .compare, .weeklyDigest: return "chart.xyaxis.line"
        case .insightsHub, .coach, .automations, .sportPrediction: return "sparkles"
        case .explore, .featureMap: return "magnifyingglass"
        case .live, .rhythm, .hrvSnapshot, .coupled: return "waveform.path.ecg"
        case .workouts, .fitnessAge, .manualWorkout: return "figure.run"
        case .health, .appleHealth, .vitality: return "heart"
        case .labBook: return "books.vertical"
        case .stress, .breathe: return "wind"
        case .intervals: return "timer"
        case .fusedRecord, .dataSources, .miBand: return "square.stack.3d.up"
        case .backupSync: return "externaldrive"
        case .shortcutsExport: return "square.and.arrow.up"
        case .alarms: return "alarm"
        case .testCentre: return "stethoscope"
        case .siriShortcuts: return "mic"
        case .settings, .customizeToday, .customizeMetrics, .customizeCards, .workoutAutomation: return "slider.horizontal.3"
        case .devices, .liveActivity: return "applewatch"
        case .hydration: return "drop"
        case .caffeine: return "cup.and.saucer"
        case .journal: return "square.and.pencil"
        case .bodyClock: return "sun.max"
        case .cycleAwareness, .sleepDebt, .sleepEdit, .nap: return "moon"
        case .liveSession: return "shield"
        case .updates: return "bell"
        }
    }

    static func matching(_ query: String) -> [MobileFeature] {
        let words = query.split(whereSeparator: \.isWhitespace).map(String.init)
        return allCases.filter { feature in
            let content = "\(feature.title) \(feature.subtitle) \(feature.rawValue)"
            return words.allSatisfy { content.localizedStandardContains($0) }
        }.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    static let originalGroups: [MobileFeatureGroup] = [
        .init(id: "Insights", title: String(localized: "Insights"), features: [.trends, .insightsHub, .intelligence, .coach, .insights, .explore, .compare]),
        .init(id: "Body", title: String(localized: "Body"), features: [.live, .workouts, .health, .labBook, .stress, .breathe, .intervals, .rhythm]),
        .init(id: "Data", title: String(localized: "Data"), features: [.fusedRecord, .appleHealth, .miBand, .dataSources, .backupSync, .shortcutsExport]),
        .init(id: "App", title: String(localized: "App"), features: [.alarms, .automations, .testCentre, .siriShortcuts, .settings]),
    ]

    static let additionalGroups: [MobileFeatureGroup] = [
        .init(id: "custom", title: String(localized: "Your custom tools"), features: [.workoutAutomation, .sportPrediction, .liveSession, .liveActivity, .devices]),
        .init(id: "daily", title: String(localized: "Everyday tools"), features: [.manualWorkout, .sleepEdit, .nap, .fitnessAge, .vitality, .hydration, .caffeine, .journal, .bodyClock, .cycleAwareness, .hrvSnapshot, .sleepDebt, .coupled, .weeklyDigest]),
        .init(id: "personal", title: String(localized: "Make it yours"), features: [.customizeToday, .customizeMetrics, .customizeCards, .updates, .featureMap]),
    ]
}

struct MobileFeatureGroup: Identifiable {
    let id: String
    let title: String
    let features: [MobileFeature]
}
