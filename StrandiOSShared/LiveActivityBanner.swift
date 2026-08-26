#if os(iOS)
import SwiftUI
import StrandDesign

/// The WHOOP-style Lock-Screen / banner presentation for the workout Live Activity. Lives in the shared
/// sources so it compiles into BOTH the widget extension (which renders the real Live Activity) and the
/// app (which can render it to an image for previews / verification via `ImageRenderer`). Shows a
/// self-counting elapsed timer, live HR, a Zone 1–5 rail with the current zone lit, and DISTANCE + SPEED
/// for GPS sports; falls back to a plain live-HR card when no workout is recording.
struct LockScreenView: View {
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
struct ZoneRail: View {
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
func statColumn(label: String, value: String) -> some View {
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
#endif
