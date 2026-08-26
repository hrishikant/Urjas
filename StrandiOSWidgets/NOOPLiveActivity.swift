import WidgetKit
import SwiftUI
import ActivityKit
import StrandDesign

/// Live Activity for an active live-HR / workout session — shown on the Lock Screen and in the Dynamic
/// Island. During a workout it mirrors WHOOP's workout card: a self-counting elapsed timer, the sport,
/// live HR, a Zone 1–5 rail with the current zone lit, and DISTANCE + SPEED for GPS sports. With no
/// workout it falls back to the plain live-HR presentation.
struct NOOPLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: NOOPActivityAttributes.self) { context in
            LockScreenView(state: context.state, title: context.attributes.title)
                .padding()
                .activityBackgroundTint(StrandPalette.surfaceBase)
                .activitySystemActionForegroundColor(StrandPalette.textPrimary)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label("\(context.state.bpm.map(String.init) ?? "–")", systemImage: "heart.fill")
                        .foregroundStyle(StrandPalette.statusCritical)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    HStack(spacing: 10) {
                        if let z = context.state.zone, z >= 1 {
                            statColumn(label: "Zone", value: "\(z)")
                        } else if let r = context.state.recovery {
                            statColumn(label: "Charge", value: "\(r)%")
                        }
                        if let e = context.state.effort {
                            statColumn(label: "Effort", value: "\(e)")
                        }
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Text(context.state.sport ?? context.attributes.title)
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        if let d = context.state.distanceM {
                            Text(LiveActivityFormat.distance(d))
                                .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        }
                        if let start = context.state.startedAt {
                            Text(timerInterval: start...Date.distantFuture, countsDown: false)
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(StrandPalette.textPrimary)
                                .frame(maxWidth: 54, alignment: .trailing)
                        }
                    }
                }
            } compactLeading: {
                Image(systemName: context.state.sport != nil ? "figure.run" : "heart.fill")
                    .foregroundStyle(StrandPalette.statusCritical)
            } compactTrailing: {
                Text("\(context.state.bpm.map(String.init) ?? "–")")
            } minimal: {
                Image(systemName: "heart.fill").foregroundStyle(StrandPalette.statusCritical)
            }
        }
    }
}

/// The Lock-Screen / banner presentation. WHOOP-style workout layout when a sport is recording.
private struct LockScreenView: View {
    let state: NOOPActivityAttributes.ContentState
    let title: String

    private var isWorkout: Bool { state.sport != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Row 1: sport / title + self-counting elapsed timer (WHOOP's top line).
            HStack(spacing: 8) {
                Image(systemName: isWorkout ? "figure.run" : "waveform.path.ecg")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(StrandPalette.statusCritical)
                Text(state.sport ?? title)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(StrandPalette.textPrimary)
                Spacer(minLength: 0)
                if let start = state.startedAt {
                    Text(timerInterval: start...Date.distantFuture, countsDown: false)
                        .font(.callout.monospacedDigit().weight(.semibold))
                        .foregroundStyle(StrandPalette.textPrimary)
                        .frame(maxWidth: 66, alignment: .trailing)
                }
            }

            // Row 2: big live HR + (for GPS sports) distance & speed, WHOOP's stat row.
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                metric(value: state.bpm.map(String.init) ?? "–", unit: "BPM",
                       color: StrandPalette.statusCritical)
                if let d = state.distanceM {
                    metric(value: LiveActivityFormat.distanceValue(d), unit: LiveActivityFormat.distanceUnit,
                           color: StrandPalette.textPrimary)
                }
                if let s = state.speedMps {
                    metric(value: LiveActivityFormat.speedValue(s), unit: LiveActivityFormat.speedUnit,
                           color: StrandPalette.textPrimary)
                }
                Spacer(minLength: 0)
                if !isWorkout, let r = state.recovery {
                    metric(value: "\(r)%", unit: "CHARGE", color: StrandPalette.textSecondary)
                }
            }

            // Row 3: Zone 1–5 rail with the current zone lit (WHOOP's zone bar).
            if let z = state.zone, z >= 1 {
                ZoneRail(current: z)
            }
        }
    }

    @ViewBuilder
    private func metric(value: String, unit: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(color)
            Text(unit)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(StrandPalette.textTertiary)
        }
        .fixedSize()
    }
}

/// A five-segment Zone rail (WHOOP-style) with the current zone highlighted in its zone colour and the
/// number shown; the rest read as dim capsules so the active zone stands out at a glance on the Lock Screen.
private struct ZoneRail: View {
    let current: Int

    var body: some View {
        HStack(spacing: 4) {
            ForEach(1...5, id: \.self) { z in
                let active = z == current
                ZStack {
                    Capsule()
                        .fill(active ? LiveActivityFormat.zoneColor(z) : StrandPalette.textTertiary.opacity(0.25))
                    Text("\(z)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(active ? Color.black.opacity(0.85) : StrandPalette.textTertiary)
                }
                .frame(height: 16)
            }
        }
    }
}

/// Dynamic Island expanded-region stat column (label over value).
@ViewBuilder
private func statColumn(label: String, value: String) -> some View {
    VStack(alignment: .center, spacing: 1) {
        Text(label).font(.caption2).foregroundStyle(.secondary)
        Text(value).font(.headline)
    }
    .multilineTextAlignment(.center)
    .fixedSize()
}

/// Locale-aware distance / speed formatting + zone colours for the Live Activity. The widget extension
/// can't see the app's `UnitPrefs`, so it reads the system measurement system directly (miles/mph in the
/// US, km/km·h elsewhere — matching what WHOOP shows).
enum LiveActivityFormat {
    private static var metric: Bool { Locale.current.measurementSystem == .metric }

    static func distanceValue(_ meters: Double) -> String {
        metric ? String(format: "%.2f", meters / 1000) : String(format: "%.2f", meters / 1609.344)
    }
    static var distanceUnit: String { metric ? "KM" : "MI" }
    static func distance(_ meters: Double) -> String { "\(distanceValue(meters)) \(distanceUnit.lowercased())" }

    static func speedValue(_ mps: Double) -> String {
        metric ? String(format: "%.1f", mps * 3.6) : String(format: "%.1f", mps * 2.2369363)
    }
    static var speedUnit: String { metric ? "KM/H" : "MPH" }

    /// WHOOP-style zone palette: blue (1) → teal → green → orange → red (5).
    static func zoneColor(_ zone: Int) -> Color {
        switch zone {
        case 1: return Color(red: 0.30, green: 0.62, blue: 0.98)
        case 2: return Color(red: 0.20, green: 0.78, blue: 0.78)
        case 3: return Color(red: 0.36, green: 0.82, blue: 0.44)
        case 4: return Color(red: 0.98, green: 0.66, blue: 0.24)
        default: return Color(red: 0.96, green: 0.32, blue: 0.34)
        }
    }
}
