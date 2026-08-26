import WidgetKit
import SwiftUI
import ActivityKit
import StrandDesign

/// Live Activity for an active live-HR / workout session — shown on the Lock Screen and in the Dynamic
/// Island. During a workout it mirrors WHOOP's workout card: a self-counting elapsed timer, the sport,
/// live HR, a Zone 1–5 rail with the current zone lit, and DISTANCE + SPEED for GPS sports. With no
/// workout it falls back to the plain live-HR presentation. The Lock-Screen banner itself lives in
/// `LiveActivityBanner.swift` (shared) so the app can also render it to an image for previews.
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
