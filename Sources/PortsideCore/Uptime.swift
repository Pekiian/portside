import Foundation

/// "45s", "12m", "2h 14m", "3d 4h" — compact, stable width via monospaced font.
public func formatUptime(since start: Date, now: Date = Date()) -> String {
    let s = max(0, Int(now.timeIntervalSince(start)))
    if s < 60 { return "\(s)s" }
    let m = s / 60
    if m < 60 { return "\(m)m" }
    let h = m / 60
    if h < 24 { return "\(h)h \(m % 60)m" }
    let d = h / 24
    return "\(d)d \(h % 24)h"
}
