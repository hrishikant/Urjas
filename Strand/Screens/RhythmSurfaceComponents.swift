import SwiftUI
import StrandDesign
import WhoopStore

struct RhythmSurfaceEntryGate {
    private(set) var consumed = false

    mutating func consume<Action>(_ action: Action?, ready: Bool = true) -> Action? {
        guard ready, !consumed, let action else { return nil }
        consumed = true
        return action
    }
}

/// Display-only totals for the already-filtered journal. Missing measurements stay missing.
struct RhythmActivitySummary {
    let sessions: Int
    let activeDays: Int
    let durationSeconds: Double?
    let calories: Double?
    let distanceMeters: Double?
    let averageStrain: Double?
    let detectedSessions: Int

    init(rows: [WorkoutRow], calendar: Calendar = .current) {
        func sum(_ values: [Double]) -> Double? {
            let valid = values.filter { $0.isFinite && $0 >= 0 }
            return valid.isEmpty ? nil : valid.reduce(0, +)
        }
        sessions = rows.count
        activeDays = Set(rows.map {
            calendar.startOfDay(for: Date(timeIntervalSince1970: TimeInterval($0.startTs)))
        }).count
        durationSeconds = sum(rows.compactMap(\.durationS))
        calories = sum(rows.compactMap(\.energyKcal))
        distanceMeters = sum(rows.compactMap(\.distanceM))
        let strains = rows.compactMap(\.strain).filter { $0.isFinite && $0 >= 0 }
        averageStrain = strains.isEmpty ? nil : strains.reduce(0, +) / Double(strains.count)
        detectedSessions = rows.filter { WorkoutSource.classify($0.source) == .detected }.count
    }
}

@MainActor enum RhythmVitalRoute {
    static func metric(key: String, source: DailyMetricSource?) -> MetricDescriptor? {
        let canonicalKey: String
        switch key {
        case "resp": canonicalKey = "resp_rate"
        case "skin": canonicalKey = "skin_temp"
        case "spo2raw": return nil
        default: canonicalKey = key
        }
        guard let base = MetricCatalog.metric(key: canonicalKey, source: "my-whoop") else { return nil }
        guard source == .appleHealth else { return base }
        guard let appleKey = Repository.appleCompatibleKey(forWhoopKey: canonicalKey) else { return nil }
        return MetricDescriptor(key: appleKey, title: base.title, category: base.category,
                                unit: base.unit, source: "apple-health", icon: base.icon,
                                decimals: base.decimals, higherIsBetter: base.higherIsBetter,
                                description: base.description)
    }
}

enum RhythmSleepStagePresentation: Equatable {
    case unavailable, totals, timeline

    static func resolve(asleepMinutes: Double, recordedIntervalCount: Int, hrOnly: Bool = false) -> Self {
        guard !hrOnly, asleepMinutes.isFinite, asleepMinutes > 0 else { return .unavailable }
        return recordedIntervalCount >= 2 ? .timeline : .totals
    }

    static func containsHROnlyStages(_ json: String?) -> Bool {
        guard let data = json?.data(using: .utf8),
              let stages = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]]
        else { return false }
        return stages.contains { ($0["hrOnly"] as? Bool) == true }
    }
}

struct RhythmSurfaceStat: View {
    let title: String
    let value: String
    var caption: String? = nil
    var tint: Color = StrandPalette.textPrimary

    var body: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.space2) {
            Text(title)
                .font(StrandFont.caption)
                .foregroundStyle(StrandPalette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(value)
                .font(StrandFont.number(NoopMetrics.space8))
                .foregroundStyle(tint)
                .lineLimit(1).minimumScaleFactor(0.7)
            if let caption {
                Text(caption)
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

#if os(iOS)
/// First-hop value links participate in the tab's NavigationPath and reselect-to-pop behavior.
struct RhythmSurfaceFeatureGrid: View {
    let features: [MobileFeature]
    var compact = false
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: NoopMetrics.gap),
                                 count: typeSize.isAccessibilitySize ? 1 : 2),
                  alignment: .leading, spacing: NoopMetrics.gap) {
            ForEach(features) { feature in
                NavigationLink(value: feature) {
                    NoopCard {
                        VStack(alignment: .leading, spacing: NoopMetrics.space2) {
                            Image(systemName: feature.symbol)
                                .font(StrandFont.headline)
                                .foregroundStyle(StrandPalette.rhythmRecovery)
                                .accessibilityHidden(true)
                            Text(feature.title)
                                .font(StrandFont.headline)
                                .foregroundStyle(StrandPalette.textPrimary)
                            if !compact {
                                Text(feature.subtitle)
                                    .font(StrandFont.caption)
                                    .foregroundStyle(StrandPalette.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .frame(maxWidth: .infinity, minHeight: NoopMetrics.controlHeight, alignment: .topLeading)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(feature.title)
                .accessibilityHint(feature.subtitle)
                .accessibilityIdentifier("rhythm.feature.\(feature.rawValue)")
            }
        }
    }
}
#endif
