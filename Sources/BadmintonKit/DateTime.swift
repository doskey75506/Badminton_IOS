import Foundation

/// Timezone-naive date-time (mirrors java.time.LocalDateTime).
///
/// Stored/parsed as "yyyy-MM-dd'T'HH:mm:ss"; parsing also accepts the
/// seconds-optional form produced by Kotlin's LocalDateTime.toString()
/// ("yyyy-MM-dd'T'HH:mm") which appears in Android test fixtures.
public struct DateTime: Comparable, Equatable, Sendable {
    public var year: Int
    public var month: Int
    public var day: Int
    public var hour: Int
    public var minute: Int
    public var second: Int

    public init(year: Int, month: Int, day: Int, hour: Int = 0, minute: Int = 0, second: Int = 0) {
        self.year = year
        self.month = month
        self.day = day
        self.hour = hour
        self.minute = minute
        self.second = second
    }

    public static func now() -> DateTime {
        let cal = Calendar.current
        let c = cal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: Date())
        return DateTime(
            year: c.year ?? 1970, month: c.month ?? 1, day: c.day ?? 1,
            hour: c.hour ?? 0, minute: c.minute ?? 0, second: c.second ?? 0
        )
    }

    /// Seconds since an arbitrary epoch (days-from-civil), for differences only.
    public var totalSeconds: Int64 {
        Int64(DateTime.daysFromCivil(year, month, day)) * 86400
            + Int64(hour) * 3600 + Int64(minute) * 60 + Int64(second)
    }

    public static func < (lhs: DateTime, rhs: DateTime) -> Bool {
        lhs.totalSeconds < rhs.totalSeconds
    }

    public func adding(minutes: Int) -> DateTime {
        DateTime.fromTotalSeconds(totalSeconds + Int64(minutes) * 60)
    }

    public func secondsSince(_ other: DateTime) -> Double {
        Double(totalSeconds - other.totalSeconds)
    }

    /// "yyyy-MM-dd'T'HH:mm:ss"
    public var isoString: String {
        String(format: "%04d-%02d-%02dT%02d:%02d:%02d", year, month, day, hour, minute, second)
    }

    /// "HH:mm"
    public var timeString: String {
        String(format: "%02d:%02d", hour, minute)
    }

    public static func parse(_ s: String?) -> DateTime? {
        guard let s else { return nil }
        let parts = s.split(separator: "T", omittingEmptySubsequences: false)
        guard parts.count == 2 else { return nil }
        let dateParts = parts[0].split(separator: "-")
        guard dateParts.count == 3, let y = Int(dateParts[0]), let mo = Int(dateParts[1]), let d = Int(dateParts[2]) else { return nil }
        let timeParts = parts[1].split(separator: ":")
        guard timeParts.count == 2 || timeParts.count == 3,
              let h = Int(timeParts[0]), let mi = Int(timeParts[1]) else { return nil }
        var sec = 0
        if timeParts.count == 3 {
            guard let v = Int(timeParts[2]) else { return nil }
            sec = v
        }
        return DateTime(year: y, month: mo, day: d, hour: h, minute: mi, second: sec)
    }

    static func fromTotalSeconds(_ t: Int64) -> DateTime {
        var days = t / 86400
        var rem = t % 86400
        if rem < 0 { rem += 86400; days -= 1 }
        let (y, mo, d) = DateTime.civilFromDays(Int(days))
        return DateTime(year: y, month: mo, day: d, hour: Int(rem / 3600), minute: Int((rem % 3600) / 60), second: Int(rem % 60))
    }

    /// Howard Hinnant's days_from_civil
    static func daysFromCivil(_ y0: Int, _ m: Int, _ d: Int) -> Int {
        let y = y0 - (m <= 2 ? 1 : 0)
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let doy = (153 * (m + (m > 2 ? -3 : 9)) + 2) / 5 + d - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146097 + doe - 719468
    }

    /// Howard Hinnant's civil_from_days
    static func civilFromDays(_ z0: Int) -> (Int, Int, Int) {
        let z = z0 + 719468
        let era = (z >= 0 ? z : z - 146096) / 146097
        let doe = z - era * 146097
        let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365
        let y = yoe + era * 400
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp = (5 * doy + 2) / 153
        let d = doy - (153 * mp + 2) / 5 + 1
        let m = mp + (mp < 10 ? 3 : -9)
        return (y + (m <= 2 ? 1 : 0), m, d)
    }
}

// MARK: - "yyyy-MM-dd" helpers (mirrors java.time.LocalDate usage in the app)

public enum DateOnly {
    public static func today() -> String {
        format(Date())
    }

    public static func format(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    public static func parse(_ s: String) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: s)
    }

    public static func adding(days: Int, to iso: String) -> String {
        guard let d = parse(iso) else { return iso }
        let cal = Calendar.current
        guard let out = cal.date(byAdding: .day, value: days, to: d) else { return iso }
        return format(out)
    }

    /// Bridge to Date for SwiftUI pickers (start of day, local timezone).
    public static func fromDate(_ date: Date) -> String {
        format(date)
    }
}
