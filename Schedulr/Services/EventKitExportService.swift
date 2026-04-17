import Foundation
import EventKit
import OSLog
#if canImport(UIKit)
import UIKit
#endif

/// Handles exporting schedules to system Calendar (EventKit) and .ics files.
enum EventKitExportService {
    nonisolated private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.bittu.Schedulr",
        category: "EventKitExportService"
    )
    private static let eventStore = EKEventStore()

    // MARK: - EventKit Export

    static func exportToCalendar(schedule: Schedule) async -> Bool {
        let granted: Bool
        if #available(iOS 17.0, *) {
            granted = (try? await eventStore.requestFullAccessToEvents()) ?? false
        } else {
            granted = await withCheckedContinuation { continuation in
                eventStore.requestAccess(to: .event) { granted, _ in
                    continuation.resume(returning: granted)
                }
            }
        }

        guard granted else { return false }

        let event = EKEvent(eventStore: eventStore)
        event.title = schedule.title
        event.notes = schedule.notes
        event.startDate = schedule.scheduledDate
        event.endDate = Calendar.current.date(byAdding: .hour, value: 1, to: schedule.scheduledDate) ?? schedule.scheduledDate
        event.timeZone = schedule.scheduleTimeZone
        event.calendar = eventStore.defaultCalendarForNewEvents

        if let urlString = schedule.urlString, let url = URL(string: urlString) {
            event.url = url
        }

        // Add recurrence rule
        if let rule = makeRecurrenceRule(for: schedule) {
            event.addRecurrenceRule(rule)
        }

        // Add alarms for each reminder
        for minutes in schedule.allReminderMinutes {
            let alarm = EKAlarm(relativeOffset: -TimeInterval(minutes * 60))
            event.addAlarm(alarm)
        }

        do {
            try eventStore.save(event, span: .thisEvent)
            return true
        } catch {
            logger.error("Failed to save event to calendar: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    // MARK: - ICS Export

    static func generateICS(for schedule: Schedule) -> String {
        var ics = "BEGIN:VCALENDAR\r\n"
        ics += "VERSION:2.0\r\n"
        ics += "PRODID:-//Schedulr//Schedule Export//EN\r\n"
        if let tzid = schedule.scheduleTimeZone?.identifier {
            ics += "X-WR-TIMEZONE:\(escapeICSString(tzid))\r\n"
        }
        ics += "BEGIN:VEVENT\r\n"
        ics += "UID:\(schedule.id.uuidString)@schedulr\r\n"
        ics += "DTSTAMP:\(icsDateString(Date()))\r\n"
        ics += icsDateFieldLine(
            fieldName: "DTSTART",
            date: schedule.scheduledDate,
            timeZone: schedule.scheduleTimeZone
        )

        let endDate = Calendar.current.date(byAdding: .hour, value: 1, to: schedule.scheduledDate) ?? schedule.scheduledDate
        ics += icsDateFieldLine(
            fieldName: "DTEND",
            date: endDate,
            timeZone: schedule.scheduleTimeZone
        )

        ics += "SUMMARY:\(escapeICSString(schedule.title))\r\n"

        if let notes = schedule.notes, !notes.isEmpty {
            ics += "DESCRIPTION:\(escapeICSString(notes))\r\n"
        }

        if let urlString = schedule.urlString {
            ics += "URL:\(urlString)\r\n"
        }

        // Priority (iCal: 1=high, 5=medium, 9=low)
        let icalPriority: Int
        switch schedule.priority {
        case .high: icalPriority = 1
        case .medium: icalPriority = 5
        case .low: icalPriority = 9
        case .none: icalPriority = 0
        }
        if icalPriority > 0 {
            ics += "PRIORITY:\(icalPriority)\r\n"
        }

        // Recurrence
        if let rrule = makeICSRecurrenceRule(for: schedule) {
            ics += "RRULE:\(rrule)\r\n"
        }

        // Alarms
        for minutes in schedule.allReminderMinutes {
            ics += "BEGIN:VALARM\r\n"
            ics += "TRIGGER:-PT\(minutes)M\r\n"
            ics += "ACTION:DISPLAY\r\n"
            ics += "DESCRIPTION:Reminder\r\n"
            ics += "END:VALARM\r\n"
        }

        // Tags as categories
        if !schedule.tags.isEmpty {
            ics += "CATEGORIES:\(schedule.tags.joined(separator: ","))\r\n"
        }

        ics += "END:VEVENT\r\n"
        ics += "END:VCALENDAR\r\n"

        return ics
    }

    static func saveICSFile(for schedule: Schedule) -> URL? {
        let ics = generateICS(for: schedule)
        let fileName = schedule.title.replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "/", with: "-") + ".ics"
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)

        do {
            guard let icsData = ics.data(using: .utf8) else { return nil }
            try icsData.write(to: tempURL, options: [.atomic, .completeFileProtection])
            return tempURL
        } catch {
            logger.error("Failed to write ICS file: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    // MARK: - Share

    #if canImport(UIKit)
    static func shareSchedule(_ schedule: Schedule, from viewController: UIViewController?) {
        var items: [Any] = []

        // Text summary
        let summary = buildShareText(for: schedule)
        items.append(summary)

        // ICS file
        if let icsURL = saveICSFile(for: schedule) {
            items.append(icsURL)
        }

        let activityVC = UIActivityViewController(activityItems: items, applicationActivities: nil)
        viewController?.present(activityVC, animated: true)
    }
    #endif

    static func buildShareText(for schedule: Schedule) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        switch AppSettings.shared.timeFormatPreference {
        case .system:
            formatter.timeStyle = .short
        case .twelveHour:
            formatter.dateFormat = "EEEE, MMMM d, yyyy h:mm a"
        case .twentyFourHour:
            formatter.dateFormat = "EEEE, MMMM d, yyyy HH:mm"
        }

        var text = "\(schedule.title)\n"
        text += "\(formatter.string(from: schedule.scheduledDate))\n"

        if let notes = schedule.notes, !notes.isEmpty {
            text += "\n\(notes)\n"
        }

        if schedule.repeatPattern != .never {
            text += "Repeats: \(schedule.repeatPattern.displayName)\n"
        }

        if !schedule.tags.isEmpty {
            text += "Tags: \(schedule.tags.joined(separator: ", "))\n"
        }

        return text
    }

    // MARK: - Helpers

    private static func icsDateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: date)
    }

    private static func icsLocalDateString(_ date: Date, in timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd'T'HHmmss"
        formatter.timeZone = timeZone
        return formatter.string(from: date)
    }

    private static func icsDateFieldLine(fieldName: String, date: Date, timeZone: TimeZone?) -> String {
        if let timeZone {
            let tzid = escapeICSString(timeZone.identifier)
            let localDate = icsLocalDateString(date, in: timeZone)
            return "\(fieldName);TZID=\(tzid):\(localDate)\r\n"
        }
        return "\(fieldName):\(icsDateString(date))\r\n"
    }

    private static func escapeICSString(_ string: String) -> String {
        string
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: ";", with: "\\;")
            .replacingOccurrences(of: ",", with: "\\,")
            .replacingOccurrences(of: "\n", with: "\\n")
    }

    private static func makeRecurrenceRule(for schedule: Schedule) -> EKRecurrenceRule? {
        switch schedule.repeatPattern {
        case .never: return nil
        case .daily:
            return EKRecurrenceRule(
                recurrenceWith: .daily,
                interval: 1,
                end: recurrenceEnd(for: schedule)
            )
        case .weekdays:
            let weekdayNumbers = [EKRecurrenceDayOfWeek(.monday),
                                   EKRecurrenceDayOfWeek(.tuesday),
                                   EKRecurrenceDayOfWeek(.wednesday),
                                   EKRecurrenceDayOfWeek(.thursday),
                                   EKRecurrenceDayOfWeek(.friday)]
            return EKRecurrenceRule(
                recurrenceWith: .weekly,
                interval: 1,
                daysOfTheWeek: weekdayNumbers,
                daysOfTheMonth: nil,
                monthsOfTheYear: nil,
                weeksOfTheYear: nil,
                daysOfTheYear: nil,
                setPositions: nil,
                end: recurrenceEnd(for: schedule)
            )
        case .weekly:
            return EKRecurrenceRule(
                recurrenceWith: .weekly,
                interval: 1,
                end: recurrenceEnd(for: schedule)
            )
        case .biweekly:
            return EKRecurrenceRule(
                recurrenceWith: .weekly,
                interval: 2,
                end: recurrenceEnd(for: schedule)
            )
        case .monthly:
            return EKRecurrenceRule(
                recurrenceWith: .monthly,
                interval: 1,
                end: recurrenceEnd(for: schedule)
            )
        case .yearly:
            return EKRecurrenceRule(
                recurrenceWith: .yearly,
                interval: 1,
                end: recurrenceEnd(for: schedule)
            )
        case .everyNDays:
            return EKRecurrenceRule(
                recurrenceWith: .daily,
                interval: max(1, schedule.repeatInterval),
                end: recurrenceEnd(for: schedule)
            )
        case .everyNWeeks:
            return EKRecurrenceRule(
                recurrenceWith: .weekly,
                interval: max(1, schedule.repeatInterval),
                end: recurrenceEnd(for: schedule)
            )
        case .everyNMonths:
            return EKRecurrenceRule(
                recurrenceWith: .monthly,
                interval: max(1, schedule.repeatInterval),
                end: recurrenceEnd(for: schedule)
            )
        case .customWeekdays:
            let ekDays = schedule.repeatWeekdays.compactMap { weekdayToEK($0) }.map { EKRecurrenceDayOfWeek($0) }
            guard !ekDays.isEmpty else { return nil }
            return EKRecurrenceRule(
                recurrenceWith: .weekly,
                interval: 1,
                daysOfTheWeek: ekDays,
                daysOfTheMonth: nil,
                monthsOfTheYear: nil,
                weeksOfTheYear: nil,
                daysOfTheYear: nil,
                setPositions: nil,
                end: recurrenceEnd(for: schedule)
            )
        }
    }

    private static func recurrenceEnd(for schedule: Schedule) -> EKRecurrenceEnd? {
        switch schedule.repeatEndOption {
        case .never: return nil
        case .onDate:
            if let date = schedule.repeatEndDate {
                return EKRecurrenceEnd(end: date)
            }
            return nil
        case .afterCount:
            return schedule.repeatEndCount > 0
                ? EKRecurrenceEnd(occurrenceCount: schedule.repeatEndCount)
                : nil
        }
    }

    private static func weekdayToEK(_ weekday: Int) -> EKWeekday? {
        switch weekday {
        case 1: return .sunday
        case 2: return .monday
        case 3: return .tuesday
        case 4: return .wednesday
        case 5: return .thursday
        case 6: return .friday
        case 7: return .saturday
        default: return nil
        }
    }

    private static func makeICSRecurrenceRule(for schedule: Schedule) -> String? {
        switch schedule.repeatPattern {
        case .never: return nil
        case .daily: return "FREQ=DAILY;INTERVAL=1"
        case .weekdays: return "FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR"
        case .weekly: return "FREQ=WEEKLY;INTERVAL=1"
        case .biweekly: return "FREQ=WEEKLY;INTERVAL=2"
        case .monthly: return "FREQ=MONTHLY;INTERVAL=1"
        case .yearly: return "FREQ=YEARLY;INTERVAL=1"
        case .everyNDays: return "FREQ=DAILY;INTERVAL=\(max(1, schedule.repeatInterval))"
        case .everyNWeeks: return "FREQ=WEEKLY;INTERVAL=\(max(1, schedule.repeatInterval))"
        case .everyNMonths: return "FREQ=MONTHLY;INTERVAL=\(max(1, schedule.repeatInterval))"
        case .customWeekdays:
            let dayMap = [1: "SU", 2: "MO", 3: "TU", 4: "WE", 5: "TH", 6: "FR", 7: "SA"]
            let days = schedule.repeatWeekdays.compactMap { dayMap[$0] }.joined(separator: ",")
            return "FREQ=WEEKLY;BYDAY=\(days)"
        }
    }
}
