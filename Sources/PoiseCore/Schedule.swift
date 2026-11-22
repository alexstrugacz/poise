import Foundation

public struct ReminderSchedule: Codable, Equatable {
    /// Calendar weekday numbers: Sunday = 1, Monday = 2, … Saturday = 7.
    public var weekdays: Set<Int>
    public var startMinute: Int
    public var endMinute: Int

    public init(weekdays: Set<Int> = [2, 3, 4, 5, 6], startMinute: Int = 540, endMinute: Int = 1020) {
        self.weekdays = weekdays
        self.startMinute = startMinute
        self.endMinute = endMinute
    }

    public var isValid: Bool {
        !weekdays.isEmpty && weekdays.isSubset(of: Set(1...7))
            && (0..<1440).contains(startMinute) && (1...1440).contains(endMinute)
            && startMinute < endMinute
    }

    private func window(on day: Date, calendar: Calendar) -> DateInterval? {
        guard isValid, weekdays.contains(calendar.component(.weekday, from: day)),
              let start = calendar.date(bySettingHour: startMinute / 60, minute: startMinute % 60,
                                        second: 0, of: day, matchingPolicy: .nextTime),
              let end = endMinute == 1440
                ? calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: day))
                : calendar.date(bySettingHour: endMinute / 60, minute: endMinute % 60,
                                second: 0, of: day, matchingPolicy: .nextTime),
              start < end else { return nil }
        return DateInterval(start: start, end: end)
    }

    public func contains(_ date: Date, calendar: Calendar = .current) -> Bool {
        guard let window = window(on: date, calendar: calendar) else { return false }
        return date >= window.start && date < window.end
    }

    public func nextAllowedDate(onOrAfter date: Date, calendar: Calendar = .current) -> Date? {
        guard isValid else { return nil }
        let day = calendar.startOfDay(for: date)
        // Include next week's same weekday when today's window has already ended.
        for offset in 0...7 {
            guard let candidateDay = calendar.date(byAdding: .day, value: offset, to: day),
                  let window = window(on: candidateDay, calendar: calendar) else { continue }
            let candidate = max(date, window.start)
            if candidate < window.end { return candidate }
        }
        return nil
    }

    public func nextReminder(after date: Date, intervalMinutes: Int, calendar: Calendar = .current) -> Date? {
        guard intervalMinutes > 0 else { return nil }
        let candidate = contains(date, calendar: calendar)
            ? date.addingTimeInterval(TimeInterval(intervalMinutes * 60)) : date
        return nextAllowedDate(onOrAfter: candidate, calendar: calendar)
    }
}

public struct Preferences: Codable, Equatable {
    public var remindersEnabled = true
    public var intervalMinutes = 30
    public var soundEnabled = false
    public var showCountdown = false
    public var pausedUntil: Date?
    public var schedule = ReminderSchedule()

    public init() {}

    public var isValid: Bool {
        [15, 30, 45, 60].contains(intervalMinutes) && schedule.isValid
    }

    public func nextReminder(after now: Date, calendar: Calendar = .current) -> Date? {
        guard remindersEnabled, isValid else { return nil }
        // A pause stops the timer; a fresh interval begins when it ends.
        let anchor = max(now, pausedUntil ?? now)
        return schedule.nextReminder(after: anchor, intervalMinutes: intervalMinutes, calendar: calendar)
    }
}
