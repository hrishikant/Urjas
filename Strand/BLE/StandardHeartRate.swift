import Foundation
import WhoopProtocol

/// Pure parser for the standard BLE Heart Rate Measurement characteristic (0x2A37).
/// Returns the heart rate (bpm) and any R-R intervals (ms). Pure → unit-testable.
public enum StandardHeartRate {
    public static func parse(_ data: [UInt8]) -> (hr: Int, rr: [Int], rrRawTicks: [Int])? {
        guard !data.isEmpty else { return nil }
        let flags = data[0]
        var idx = 1
        let hr: Int
        if flags & 0x01 != 0 {                       // 16-bit HR
            guard idx + 1 < data.count else { return nil }
            hr = Int(data[idx]) | (Int(data[idx + 1]) << 8); idx += 2
        } else {                                     // 8-bit HR
            guard idx < data.count else { return nil }
            hr = Int(data[idx]); idx += 1
        }
        if flags & 0x08 != 0 { idx += 2 }            // skip Energy Expended (bit 3)
        var rr: [Int] = []
        var rrRawTicks: [Int] = []
        if (flags >> 4) & 0x01 != 0 {                // R-R present (bit 4)
            while idx + 1 < data.count {
                let raw = Int(data[idx]) | (Int(data[idx + 1]) << 8)
                rrRawTicks.append(raw)
                rr.append(Int((Double(raw) / 1024.0 * 1000.0).rounded()))   // 1/1024 s → ms
                idx += 2
            }
        }
        return (hr, rr, rrRawTicks)
    }

    /// WHOOP 5/MG uses milliseconds on 0x2A37; other families retain the Bluetooth 1/1024 s conversion.
    static func intervals(rr: [Int], rawTicks: [Int], family: DeviceFamily) -> [Int] {
        family == .whoop5 ? rawTicks : rr
    }
}
