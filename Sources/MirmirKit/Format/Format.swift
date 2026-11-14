import Foundation

/// Display formatting shared by every screen. Keeps units consistent with the
/// TUI: GB with one decimal, tok/s with one decimal under 1,000.
public enum Format {
    public static func gigabytes(_ bytes: UInt64) -> String {
        String(format: "%.1f", Double(bytes) / 1_000_000_000)
    }

    public static func bytes(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(clamping: bytes), countStyle: .decimal)
    }

    public static func rate(_ value: Double?) -> String {
        guard let value else { return "—" }
        return value >= 1000 ? grouped(Int(value.rounded())) : String(format: "%.1f", value)
    }

    public static func grouped(_ value: Int) -> String {
        value.formatted(.number.grouping(.automatic))
    }

    public static func grouped(_ value: UInt64) -> String {
        grouped(Int(clamping: value))
    }

    public static func seconds(fromMilliseconds value: Double?) -> String {
        guard let value else { return "—" }
        return String(format: "%.2f", value / 1000)
    }

    public static func percent(_ ratio: Double?) -> String {
        guard let ratio else { return "—" }
        return String(format: "%.0f", ratio * 100)
    }

    public static func duration(_ interval: TimeInterval) -> String {
        let minutes = Int(interval / 60)
        if minutes < 1 { return "\(Int(interval)) s" }
        if minutes < 60 { return "\(minutes) min" }
        let hours = minutes / 60
        if hours < 48 { return "\(hours) h \(minutes % 60) min" }
        return "\(hours / 24) days"
    }

    public static func relative(_ date: Date, now: Date = Date()) -> String {
        #if canImport(Darwin)
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: now)
        #else
        // swift-corelibs-foundation has no RelativeDateTimeFormatter; this
        // keeps MirmirKit building and testable on Linux.
        let interval = now.timeIntervalSince(date)
        return interval >= 0 ? "\(duration(interval)) ago" : "in \(duration(-interval))"
        #endif
    }
}
