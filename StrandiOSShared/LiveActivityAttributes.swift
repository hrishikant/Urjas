#if os(iOS)
import Foundation
import ActivityKit

/// Live Activity attributes for an active live-HR / workout session. Shared between the app (which
/// starts/updates the activity) and the widget extension (which renders it on the Lock Screen and in
/// the Dynamic Island).
public struct NOOPActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        public var bpm: Int?
        public var recovery: Int?
        public var bonded: Bool
        // Effort / strain on NOOP's 0–100 axis (#446) — one more stat in the Dynamic Island expanded
        // region. OPTIONAL with a nil default so an activity started by an older build still decodes.
        public var effort: Int?
        // Active-workout context (#): the sport being recorded and the current HR zone (1–5), so the
        // Lock Screen / Dynamic Island reads as a workout while a session is live. Both nil when no
        // workout is recording (the activity then falls back to the plain live-HR presentation).
        public var sport: String?
        public var zone: Int?
        // WHOOP-style workout context (#): when a distance sport is recording, the live GPS distance (in
        // METRES) and current speed (in m/s) so the Lock Screen can show DISTANCE + SPEED like WHOOP's
        // workout Live Activity. Both nil for non-distance sports / no GPS. `startedAt` drives the live
        // elapsed timer (`Text(timerInterval:)`) so the banner counts up on its own between pushes.
        public var distanceM: Double?
        public var speedMps: Double?
        public var startedAt: Date?

        public init(bpm: Int?, recovery: Int?, bonded: Bool, effort: Int? = nil,
                    sport: String? = nil, zone: Int? = nil,
                    distanceM: Double? = nil, speedMps: Double? = nil, startedAt: Date? = nil) {
            self.bpm = bpm
            self.recovery = recovery
            self.bonded = bonded
            self.effort = effort
            self.sport = sport
            self.zone = zone
            self.distanceM = distanceM
            self.speedMps = speedMps
            self.startedAt = startedAt
        }
    }

    /// Static title shown for the session.
    public var title: String

    public init(title: String = "Live HR") {
        self.title = title
    }
}
#endif
