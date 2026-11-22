import XCTest
@testable import PoiseCore

final class ScheduleTests: XCTestCase {
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        return c
    }

    private func date(_ year: Int = 2026, _ month: Int = 11, _ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    func testStartsFreshIntervalDuringWorkingHours() {
        XCTAssertEqual(ReminderSchedule().nextReminder(after: date(2026, 11, 9, 9, 42), intervalMinutes: 30, calendar: calendar), date(2026, 11, 9, 10, 12))
    }

    func testBeforeWorkStartsAtOpeningTime() {
        XCTAssertEqual(ReminderSchedule().nextReminder(after: date(2026, 11, 9, 8, 50), intervalMinutes: 30, calendar: calendar), date(2026, 11, 9, 9))
    }

    func testEndOfDayIsExclusiveAndSkipsWeekend() {
        XCTAssertEqual(ReminderSchedule().nextReminder(after: date(2026, 11, 13, 16, 30), intervalMinutes: 30, calendar: calendar), date(2026, 11, 16, 9))
    }

    func testOnlySelectedWeekdayWrapsToFollowingWeek() {
        let schedule = ReminderSchedule(weekdays: [2])
        XCTAssertEqual(schedule.nextAllowedDate(onOrAfter: date(2026, 11, 9, 18), calendar: calendar), date(2026, 11, 16, 9))
    }

    func testSnoozeDoesNotCrossOutsideWorkingHours() {
        XCTAssertEqual(ReminderSchedule().nextAllowedDate(onOrAfter: date(2026, 11, 9, 17, 2), calendar: calendar), date(2026, 11, 10, 9))
    }

    func testAllDayScheduleIncludesLateEveningButNotNextUnselectedDay() {
        let schedule = ReminderSchedule(weekdays: [2], startMinute: 0, endMinute: 1440)
        XCTAssertTrue(schedule.contains(date(2026, 11, 9, 23, 59), calendar: calendar))
        XCTAssertFalse(schedule.contains(date(2026, 11, 10, 0), calendar: calendar))
    }

    func testDisabledRemindersHaveNoDueDate() {
        var preferences = Preferences()
        preferences.remindersEnabled = false
        XCTAssertNil(preferences.nextReminder(after: date(2026, 11, 9, 10), calendar: calendar))
    }

    func testPauseEndsThenStartsFreshInterval() {
        var preferences = Preferences()
        preferences.pausedUntil = date(2026, 11, 9, 10, 30)
        XCTAssertEqual(preferences.nextReminder(after: date(2026, 11, 9, 10), calendar: calendar), date(2026, 11, 9, 11))
    }

    func testInvalidScheduleNeverProducesDueDate() {
        for schedule in [ReminderSchedule(weekdays: []), ReminderSchedule(startMinute: 1100, endMinute: 900), ReminderSchedule(weekdays: [8])] {
            XCTAssertNil(schedule.nextAllowedDate(onOrAfter: date(2026, 11, 9, 10), calendar: calendar))
        }
    }

    func testSpringDaylightSavingMaintainsLocalOpeningTime() {
        let schedule = ReminderSchedule(weekdays: [1], startMinute: 540, endMinute: 1020)
        XCTAssertEqual(schedule.nextAllowedDate(onOrAfter: date(2027, 3, 13, 18), calendar: calendar), date(2027, 3, 14, 9))
    }

    func testNonexistentSpringHourMovesForward() {
        let schedule = ReminderSchedule(weekdays: [1], startMinute: 150, endMinute: 240)
        XCTAssertEqual(schedule.nextAllowedDate(onOrAfter: date(2027, 3, 14, 0), calendar: calendar), date(2027, 3, 14, 3))
    }

    func testFallDaylightSavingMaintainsLocalOpeningTime() {
        let schedule = ReminderSchedule(weekdays: [1])
        XCTAssertEqual(schedule.nextAllowedDate(onOrAfter: date(2026, 10, 31, 18), calendar: calendar), date(2026, 11, 1, 9))
    }

    func testPreferencesSurviveEncodingIncludingPause() throws {
        var preferences = Preferences()
        preferences.pausedUntil = date(2026, 11, 9, 11)
        preferences.schedule.weekdays = [1, 7]
        let encoded = try JSONEncoder().encode(preferences)
        XCTAssertEqual(try JSONDecoder().decode(Preferences.self, from: encoded), preferences)
    }
}
