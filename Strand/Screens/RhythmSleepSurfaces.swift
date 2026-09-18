import SwiftUI
import StrandDesign

struct RhythmSleepToolsView: View {
    var body: some View {
        SleepView(focusesSleepDebt: true)
    }
}

/// Reuses the existing bedtime intention; it never edits detected sleep or the alarm schedule.
struct RhythmBedtimeIntentionCard: View {
    @AppStorage(CaffeineLogCard.bedtimeMinutesKey) private var bedtimeMinutes = 23 * 60

    var body: some View {
        NoopCard(tint: StrandPalette.rhythmHero) {
            VStack(alignment: .leading, spacing: NoopMetrics.space4) {
                Text("Make space for tonight")
                    .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                Text("A softer landing.")
                    .font(StrandFont.title2).foregroundStyle(StrandPalette.textPrimary)
                DatePicker("Bedtime intention", selection: bedtime, displayedComponents: .hourAndMinute)
                    .font(StrandFont.headline)
                    .tint(StrandPalette.rhythmRecovery)
                    .accessibilityIdentifier("rhythm.sleep.bedtime")
                Text("A plan, not a sleep measurement. This is also the bedtime used by your caffeine timing guide. Wake alarms and wind-down reminders have their own controls.")
                    .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                #if os(iOS)
                NavigationLink(value: MobileFeature.alarms) {
                    Label("Adjust alarms & wind-down", systemImage: "alarm")
                        .font(StrandFont.headline)
                        .frame(minHeight: NoopMetrics.controlHeight)
                }
                .accessibilityIdentifier("rhythm.sleep.alarms")
                #endif
            }
        }
    }

    private var bedtime: Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(bySettingHour: min(max(bedtimeMinutes / 60, 0), 23),
                                      minute: min(max(bedtimeMinutes % 60, 0), 59), second: 0, of: Date()) ?? Date()
            },
            set: { value in
                let components = Calendar.current.dateComponents([.hour, .minute], from: value)
                bedtimeMinutes = min(max((components.hour ?? 23) * 60 + (components.minute ?? 0), 0), 1439)
            }
        )
    }
}
