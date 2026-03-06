import Foundation

/// Detects scheduling conflicts (overlapping events).
enum ConflictDetectionService {
    struct Conflict: Identifiable {
        let id = UUID()
        let schedule1: Schedule
        let schedule2: Schedule
        let overlapDate: Date
    }

    /// Check if a proposed schedule time conflicts with existing schedules.
    /// Uses a 30-minute default window around each event.
    static func findConflicts(
        for proposedDate: Date,
        excluding scheduleID: UUID? = nil,
        in schedules: [Schedule],
        windowMinutes: Int = 30
    ) -> [Schedule] {
        guard AppSettings.shared.conflictDetectionEnabled else { return [] }

        let calendar = Calendar.current
        let windowStart = calendar.date(byAdding: .minute, value: -windowMinutes, to: proposedDate) ?? proposedDate
        let windowEnd = calendar.date(byAdding: .minute, value: windowMinutes, to: proposedDate) ?? proposedDate

        return schedules.filter { schedule in
            guard schedule.id != scheduleID,
                  !schedule.isSoftDeleted,
                  !schedule.isCompleted
            else { return false }

            let scheduleDate = schedule.scheduledDate

            // For non-repeating, direct time comparison
            if schedule.repeatPattern == .never {
                return scheduleDate >= windowStart && scheduleDate <= windowEnd
            }

            // For repeating events, check if any occurrence falls in the window
            let proposedDay = proposedDate.startOfDay
            return occursOnDay(schedule, day: proposedDay, calendar: calendar) &&
                   timeOverlaps(schedule.scheduledDate, with: proposedDate, windowMinutes: windowMinutes, calendar: calendar)
        }
    }

    /// Find all conflicts within a given date range across all schedules.
    static func findAllConflicts(
        in schedules: [Schedule],
        from startDate: Date,
        to endDate: Date,
        windowMinutes: Int = 30
    ) -> [Conflict] {
        guard AppSettings.shared.conflictDetectionEnabled else { return [] }

        var conflicts: [Conflict] = []
        let activeSchedules = schedules.filter { !$0.isSoftDeleted && !$0.isCompleted }

        for i in 0..<activeSchedules.count {
            for j in (i+1)..<activeSchedules.count {
                let s1 = activeSchedules[i]
                let s2 = activeSchedules[j]

                if let overlapDate = findOverlapDate(between: s1, and: s2, windowMinutes: windowMinutes) {
                    if overlapDate >= startDate && overlapDate <= endDate {
                        conflicts.append(Conflict(schedule1: s1, schedule2: s2, overlapDate: overlapDate))
                    }
                }
            }
        }

        return conflicts
    }

    // MARK: - Private

    private static func timeOverlaps(
        _ existingDate: Date,
        with proposedDate: Date,
        windowMinutes: Int,
        calendar: Calendar
    ) -> Bool {
        let existingMinutes = calendar.component(.hour, from: existingDate) * 60 + calendar.component(.minute, from: existingDate)
        let proposedMinutes = calendar.component(.hour, from: proposedDate) * 60 + calendar.component(.minute, from: proposedDate)
        return abs(existingMinutes - proposedMinutes) < windowMinutes
    }

    private static func occursOnDay(_ schedule: Schedule, day: Date, calendar: Calendar) -> Bool {
        var scheduleCalendar = calendar
        if let tz = schedule.scheduleTimeZone {
            scheduleCalendar.timeZone = tz
        }

        let startDay = scheduleCalendar.startOfDay(for: schedule.scheduledDate)
        let targetDay = scheduleCalendar.startOfDay(for: day)
        guard targetDay >= startDay else { return false }

        let excluded = Set(schedule.excludedOccurrenceDates.map { scheduleCalendar.startOfDay(for: $0) })
        guard !excluded.contains(targetDay) else { return false }

        if schedule.repeatEndOption == .onDate,
           let rawEndDate = schedule.repeatEndDate,
           targetDay > scheduleCalendar.startOfDay(for: rawEndDate) {
            return false
        }

        if schedule.repeatEndOption == .afterCount, schedule.repeatEndCount > 0 {
            let count = countOccurrences(of: schedule, before: targetDay, calendar: scheduleCalendar)
            if count >= schedule.repeatEndCount {
                return false
            }
        }

        return matchesRepeatPattern(
            schedule,
            startDay: startDay,
            day: targetDay,
            calendar: scheduleCalendar
        )
    }

    private static func matchesRepeatPattern(
        _ schedule: Schedule,
        startDay: Date,
        day: Date,
        calendar: Calendar
    ) -> Bool {

        switch schedule.repeatPattern {
        case .never:
            return calendar.isDate(day, inSameDayAs: startDay)
        case .daily:
            let weekdays = Set(schedule.repeatWeekdays.filter { (1...7).contains($0) })
            let dayWeekday = calendar.component(.weekday, from: day)
            return weekdays.isEmpty || weekdays.contains(dayWeekday)
        case .weekdays:
            let dayWeekday = calendar.component(.weekday, from: day)
            return (2...6).contains(dayWeekday)
        case .weekly:
            return calendar.component(.weekday, from: day) == calendar.component(.weekday, from: startDay)
        case .biweekly:
            let weeks = calendar.dateComponents([.weekOfYear], from: startDay, to: day).weekOfYear ?? 0
            return weeks % 2 == 0 && calendar.component(.weekday, from: day) == calendar.component(.weekday, from: startDay)
        case .monthly:
            return calendar.component(.day, from: day) == calendar.component(.day, from: startDay)
        case .yearly:
            return calendar.component(.day, from: day) == calendar.component(.day, from: startDay) &&
                   calendar.component(.month, from: day) == calendar.component(.month, from: startDay)
        case .everyNDays:
            let interval = max(1, schedule.repeatInterval)
            let days = calendar.dateComponents([.day], from: startDay, to: day).day ?? 0
            return days % interval == 0
        case .everyNWeeks:
            let interval = max(1, schedule.repeatInterval)
            let weeks = calendar.dateComponents([.weekOfYear], from: startDay, to: day).weekOfYear ?? 0
            return weeks % interval == 0 && calendar.component(.weekday, from: day) == calendar.component(.weekday, from: startDay)
        case .everyNMonths:
            let interval = max(1, schedule.repeatInterval)
            let months = calendar.dateComponents([.month], from: startDay, to: day).month ?? 0
            return months % interval == 0 && calendar.component(.day, from: day) == calendar.component(.day, from: startDay)
        case .customWeekdays:
            let weekdays = Set(schedule.repeatWeekdays.filter { (1...7).contains($0) })
            let dayWeekday = calendar.component(.weekday, from: day)
            return weekdays.contains(dayWeekday)
        }
    }

    private static func countOccurrences(of schedule: Schedule, before targetDay: Date, calendar: Calendar) -> Int {
        let startDay = calendar.startOfDay(for: schedule.scheduledDate)
        let excludedDays = Set(schedule.excludedOccurrenceDates.map { calendar.startOfDay(for: $0) })
        var current = startDay
        var count = 0
        var iterations = 0
        let maxIterations = max(200, schedule.repeatEndCount + 100)

        while current < targetDay && iterations < maxIterations {
            let isOccurrence = matchesRepeatPattern(
                schedule,
                startDay: startDay,
                day: current,
                calendar: calendar
            )

            if isOccurrence && !excludedDays.contains(current) {
                count += 1
            }

            if schedule.repeatEndOption == .afterCount,
               schedule.repeatEndCount > 0,
               count >= schedule.repeatEndCount {
                break
            }

            iterations += 1

            switch schedule.repeatPattern {
            case .never:
                return count
            case .daily, .weekdays, .customWeekdays:
                current = calendar.date(byAdding: .day, value: 1, to: current) ?? current
            case .weekly:
                current = calendar.date(byAdding: .weekOfYear, value: 1, to: current) ?? current
            case .biweekly:
                current = calendar.date(byAdding: .weekOfYear, value: 2, to: current) ?? current
            case .monthly:
                current = calendar.date(byAdding: .month, value: 1, to: current) ?? current
            case .yearly:
                current = calendar.date(byAdding: .year, value: 1, to: current) ?? current
            case .everyNDays:
                current = calendar.date(byAdding: .day, value: max(1, schedule.repeatInterval), to: current) ?? current
            case .everyNWeeks:
                current = calendar.date(byAdding: .weekOfYear, value: max(1, schedule.repeatInterval), to: current) ?? current
            case .everyNMonths:
                current = calendar.date(byAdding: .month, value: max(1, schedule.repeatInterval), to: current) ?? current
            }
        }

        return count
    }

    private static func findOverlapDate(
        between s1: Schedule,
        and s2: Schedule,
        windowMinutes: Int
    ) -> Date? {
        let calendar = Calendar.current

        // Simple case: both non-repeating
        if s1.repeatPattern == .never && s2.repeatPattern == .never {
            if timeOverlaps(s1.scheduledDate, with: s2.scheduledDate, windowMinutes: windowMinutes, calendar: calendar) &&
               calendar.isDate(s1.scheduledDate, inSameDayAs: s2.scheduledDate) {
                return s1.scheduledDate
            }
            return nil
        }

        // Check next 60 days for overlap
        let today = Date().startOfDay
        for dayOffset in 0..<60 {
            guard let day = calendar.date(byAdding: .day, value: dayOffset, to: today) else { continue }
            if occursOnDay(s1, day: day, calendar: calendar) &&
               occursOnDay(s2, day: day, calendar: calendar) &&
               timeOverlaps(s1.scheduledDate, with: s2.scheduledDate, windowMinutes: windowMinutes, calendar: calendar) {
                return day
            }
        }
        return nil
    }
}
