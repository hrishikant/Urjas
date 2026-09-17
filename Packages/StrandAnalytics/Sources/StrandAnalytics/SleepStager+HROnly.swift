import Foundation
import WhoopProtocol

extension SleepStager {
    public static let hrOnlyAnchorPercentile = 0.10
    public static let hrOnlyBandMult = 1.05
    public static let hrOnlyEpochS = 60

    /// NOOP v11 HR-only fallback, with the fork's existing off-wrist/daytime/span guards retained.
    /// Stages remain estimates; HRV is computed only from actual R-R measurements.
    public static func hrOnlySessions(hr: [HRSample], rr: [RRInterval], resp: [RespSample],
                                      minMinutes: Int = minSleepMin, tzOffsetSeconds: Int = 0,
                                      wristOff: [(start: Int, end: Int)] = [],
                                      traceSink: ((String) -> Void)? = nil) -> [SleepSession] {
        let sorted = hr.filter { (30...220).contains($0.bpm) }.sorted { $0.ts < $1.ts }
        guard !sorted.isEmpty else { return [] }
        let bpms = sorted.map { Double($0.bpm) }.sorted()
        let anchor = bpms[Int(Double(bpms.count - 1) * hrOnlyAnchorPercentile)]
        // A flat partial download has no sleep/wake contrast; do not call an arbitrary plateau sleep.
        guard bpms[Int(Double(bpms.count - 1) * 0.90)] > anchor * hrOnlyBandMult else {
            traceSink?("sleep hrOnly=true kept=0 reason=insufficient-HR-contrast")
            return []
        }
        let baseline = HRVAnalyzer.median(bpms)
        let rrSorted = rr.sortedByTsStable()
        let periods = mergePeriods(hrOnlySleepRuns(sorted, baseline: anchor))
        var result: [SleepSession] = []
        for period in periods where period.stage == "sleep" {
            let span = period.end - period.start
            guard span >= minMinutes * 60, span <= maxMainSleepSpanS,
                  offWristFraction(period, hr: sorted, wristOff: wristOff) < maxOffWristSleepFraction else { continue }
            let resting = sessionRestingHR(start: period.start, end: period.end, hr: sorted)
            if isDaytimeCenter(period, tzOffsetSeconds: tzOffsetSeconds),
               !passesDaytimeGuard(period, restingHR: resting, baseline: baseline) { continue }
            let stages = SleepStagerV2.stageSession(start: period.start, end: period.end,
                                                    grav: [], hr: sorted, rr: rrSorted, resp: resp)
            guard !stages.isEmpty else { continue }
            result.append(SleepSession(
                start: period.start, end: period.end,
                efficiency: efficiency(start: period.start, end: period.end, stages: stages),
                stages: stages, restingHR: resting,
                avgHRV: sessionAvgHRV(start: period.start, end: period.end, rr: rrSorted),
                hrOnly: true))
        }
        traceSink?("sleep hrOnly=true anchor=\(Int(anchor)) runs=\(periods.count) kept=\(result.count)")
        return result
    }

    static func hrOnlySleepRuns(_ hr: [HRSample], baseline: Double?,
                                epochS: Int = hrOnlyEpochS,
                                maxGapMinutes: Int = maxGapMin) -> [Period] {
        guard let baseline, baseline > 0, epochS > 0, !hr.isEmpty else { return [] }
        var byEpoch: [Int: [Double]] = [:]
        var lastTs: [Int: Int] = [:]
        for sample in hr {
            let key = sample.ts / epochS
            byEpoch[key, default: []].append(Double(sample.bpm))
            lastTs[key] = max(lastTs[key] ?? Int.min, sample.ts)
        }
        let keys = byEpoch.keys.sorted()
        let flags = keys.map { HRVAnalyzer.median(byEpoch[$0]!) <= baseline * hrOnlyBandMult }
        var result: [Period] = []
        var start = 0
        for index in 1...keys.count {
            if index == keys.count || flags[index] != flags[start]
                || (keys[index] - keys[index - 1]) * epochS > maxGapMinutes * 60 {
                result.append(Period(stage: flags[start] ? "sleep" : "active",
                                     start: keys[start] * epochS, end: lastTs[keys[index - 1]]!))
                start = index
            }
        }
        return result
    }
}
