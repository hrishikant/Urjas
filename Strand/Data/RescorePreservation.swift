import WhoopStore

enum RescorePreservation {
    /// Keep a previously measured snapshot only when this pass has no sleep R-R input.
    /// Never fill across days/providers, override a fresh measurement, or undo a sleep edit.
    static func retainingMissingRR(_ fresh: DailyMetric, previous: DailyMetric?,
                                   sameOwner: Bool, hasSleepRR: Bool,
                                   hasSleepEdits: Bool) -> DailyMetric {
        guard !hasSleepRR, !hasSleepEdits, sameOwner, fresh.avgHrv == nil,
              (fresh.totalSleepMin ?? 0) > 0,
              let previous, previous.day == fresh.day, previous.avgHrv != nil else { return fresh }
        return DailyMetric(
            day: fresh.day, totalSleepMin: fresh.totalSleepMin, efficiency: fresh.efficiency,
            deepMin: fresh.deepMin, remMin: fresh.remMin, lightMin: fresh.lightMin,
            disturbances: fresh.disturbances, restingHr: fresh.restingHr,
            avgHrv: previous.avgHrv, recovery: fresh.recovery ?? previous.recovery,
            strain: fresh.strain, exerciseCount: fresh.exerciseCount, spo2Pct: fresh.spo2Pct,
            skinTempDevC: fresh.skinTempDevC, respRateBpm: fresh.respRateBpm ?? previous.respRateBpm,
            steps: fresh.steps, activeKcalEst: fresh.activeKcalEst,
            spo2Red: fresh.spo2Red, spo2Ir: fresh.spo2Ir)
    }
}
