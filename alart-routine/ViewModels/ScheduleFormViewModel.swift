import Foundation
import SwiftUI

@Observable
final class ScheduleFormViewModel {
    enum EarlyReminderChoice: Hashable, Identifiable {
        case none
        case preset(Int)
        case custom

        var id: String {
            switch self {
            case .none: return "none"
            case .preset(let minutes): return "preset-\(minutes)"
            case .custom: return "custom"
            }
        }
    }

    enum SnoozeChoice: Hashable, Identifiable {
        case preset(Int)
        case custom

        var id: String {
            switch self {
            case .preset(let minutes): return "preset-\(minutes)"
            case .custom: return "custom"
            }
        }
    }

    var title: String = ""
    var notes: String = ""
    var urlString: String = ""
    var scheduledDate: Date = Date()
    var hasDate: Bool = true
    var hasTime: Bool = true
    var isUrgent: Bool = false
    var repeatPattern: RepeatPattern = .never
    var repeatWeekdays: [Int] = Array(1...7)
    var repeatEndOption: RepeatEndOption = .never
    var repeatEndDate: Date = Calendar.current.startOfDay(for: Date())
    var alertDeliveryOption: AlertDeliveryOption = .push
    var alarmSoundOption: AlarmSoundOption = .defaultRingtone
    var alarmSnoozeEnabled: Bool = true
    var alarmSnoozeChoice: SnoozeChoice = .preset(10)
    var customAlarmSnoozeTime: Date = ScheduleFormViewModel.timeForReminderMinutes(10)
    var earlyReminderChoice: EarlyReminderChoice = .none
    var customEarlyReminderTime: Date = ScheduleFormViewModel.timeForReminderMinutes(90)
    var listName: String = "Reminders"
    var tags: [String] = []
    var newTag: String = ""
    var isFlagged: Bool = false
    var priority: SchedulePriority = .none

    var isEditing: Bool = false
    private var editingScheduleID: UUID?

    var isValid: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && isCustomEarlyReminderValid
            && isCustomSnoozeValid
            && !isScheduleDateInPast
    }

    var isScheduleDateInPast: Bool {
        normalizedSelectedDate < Self.minimumSchedulableDate()
    }

    var isURLValid: Bool {
        if urlString.isEmpty { return true }
        return URL(string: urlString) != nil
    }

    var earlyReminderMinutes: Int? {
        switch earlyReminderChoice {
        case .none:
            return nil
        case .preset(let minutes):
            return minutes
        case .custom:
            return customEarlyReminderMinutes
        }
    }

    var isCustomEarlyReminderValid: Bool {
        earlyReminderChoice != .custom || customEarlyReminderMinutes != nil
    }

    var isCustomSnoozeValid: Bool {
        !alarmSnoozeEnabled || alarmSnoozeChoice != .custom || customAlarmSnoozeMinutes != nil
    }

    var resolvedAlarmSnoozeMinutes: Int {
        switch alarmSnoozeChoice {
        case .preset(let minutes):
            return minutes
        case .custom:
            return customAlarmSnoozeMinutes ?? 10
        }
    }

    var repeatEndDateRange: ClosedRange<Date> {
        let minDate = Calendar.current.startOfDay(for: normalizedSelectedDate)
        return minDate...Date.distantFuture
    }

    private var normalizedSelectedDate: Date {
        Self.normalizedScheduleDate(scheduledDate)
    }

    private var customEarlyReminderMinutes: Int? {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.hour, .minute], from: customEarlyReminderTime)
        let minutes = (components.hour ?? 0) * 60 + (components.minute ?? 0)
        guard (1...1439).contains(minutes) else { return nil }
        return minutes
    }

    private var customAlarmSnoozeMinutes: Int? {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.hour, .minute], from: customAlarmSnoozeTime)
        let minutes = (components.hour ?? 0) * 60 + (components.minute ?? 0)
        guard (1...1439).contains(minutes) else { return nil }
        return minutes
    }

    private static let presetEarlyReminderMinutes: [Int] = [5, 10, 15, 30, 60]
    private static let presetSnoozeMinutes: [Int] = [5, 10, 15]

    static let earlyReminderChoices: [EarlyReminderChoice] =
        [.none] + presetEarlyReminderMinutes.map { .preset($0) } + [.custom]

    static let snoozeChoices: [SnoozeChoice] =
        presetSnoozeMinutes.map { .preset($0) } + [.custom]

    func earlyReminderDisplayName(_ minutes: Int?) -> String {
        guard let minutes else { return "None" }
        if minutes < 60 { return "\(minutes) minutes before" }

        let hours = minutes / 60
        let remainingMinutes = minutes % 60

        if remainingMinutes == 0 {
            return "\(hours) hour\(hours == 1 ? "" : "s") before"
        }

        return "\(hours)h \(remainingMinutes)m before"
    }

    func earlyReminderDisplayName(for choice: EarlyReminderChoice) -> String {
        switch choice {
        case .none:
            return "None"
        case .preset(let minutes):
            return earlyReminderDisplayName(minutes)
        case .custom:
            return "Custom"
        }
    }

    func snoozeDisplayName(for choice: SnoozeChoice) -> String {
        switch choice {
        case .preset(let minutes):
            return "\(minutes) min"
        case .custom:
            return "Custom Time"
        }
    }

    func isRepeatWeekdaySelected(_ weekday: Int) -> Bool {
        repeatWeekdays.contains(weekday)
    }

    func toggleRepeatWeekday(_ weekday: Int) {
        guard (1...7).contains(weekday) else { return }

        if let index = repeatWeekdays.firstIndex(of: weekday) {
            guard repeatWeekdays.count > 1 else { return }
            repeatWeekdays.remove(at: index)
        } else {
            repeatWeekdays.append(weekday)
            repeatWeekdays.sort()
        }

        repeatWeekdays = sanitizedRepeatWeekdays(repeatWeekdays)
    }

    func configure(with schedule: Schedule) {
        isEditing = true
        editingScheduleID = schedule.id
        title = schedule.title
        notes = schedule.notes ?? ""
        urlString = schedule.urlString ?? ""
        scheduledDate = Self.normalizedScheduleDate(schedule.scheduledDate)
        hasDate = true
        hasTime = true
        isUrgent = schedule.isUrgent
        repeatPattern = schedule.repeatPattern
        repeatWeekdays = sanitizedRepeatWeekdays(schedule.repeatWeekdays)
        repeatEndOption = schedule.repeatEndOption
        let minRepeatEndDate = Calendar.current.startOfDay(for: normalizedSelectedDate)
        if let savedEndDate = schedule.repeatEndDate {
            repeatEndDate = max(Calendar.current.startOfDay(for: savedEndDate), minRepeatEndDate)
        } else {
            repeatEndDate = minRepeatEndDate
        }
        sanitizeRepeatEndConfiguration()
        alertDeliveryOption = schedule.alertDeliveryOption
        let soundOption = schedule.alarmSoundOption
        if AlarmSoundOption.selectableCases.contains(soundOption) {
            alarmSoundOption = soundOption
        } else {
            alarmSoundOption = .defaultRingtone
        }
        alarmSnoozeEnabled = schedule.alarmSnoozeEnabled
        let snoozeMinutes = min(max(schedule.alarmSnoozeMinutes, 1), 1439)
        if Self.presetSnoozeMinutes.contains(snoozeMinutes) {
            alarmSnoozeChoice = .preset(snoozeMinutes)
            customAlarmSnoozeTime = Self.timeForReminderMinutes(10)
        } else {
            alarmSnoozeChoice = .custom
            customAlarmSnoozeTime = Self.timeForReminderMinutes(snoozeMinutes)
        }
        if let minutes = schedule.earlyReminderMinutes, minutes > 0 {
            if Self.presetEarlyReminderMinutes.contains(minutes) {
                earlyReminderChoice = .preset(minutes)
                customEarlyReminderTime = Self.timeForReminderMinutes(90)
            } else {
                earlyReminderChoice = .custom
                customEarlyReminderTime = Self.timeForReminderMinutes(minutes)
            }
        } else {
            earlyReminderChoice = .none
            customEarlyReminderTime = Self.timeForReminderMinutes(90)
        }
        listName = schedule.listName
        tags = schedule.tags
        isFlagged = schedule.isFlagged
        priority = schedule.priority
    }

    func applyTo(_ schedule: Schedule) {
        sanitizeRepeatEndConfiguration()
        schedule.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        schedule.notes = notes.isEmpty ? nil : notes
        schedule.urlString = urlString.isEmpty ? nil : urlString
        schedule.scheduledDate = normalizedSelectedDate
        // Editing a previously completed schedule should reactivate it.
        schedule.isCompleted = false
        schedule.alertDeliveryOption = alertDeliveryOption
        schedule.isUrgent = alertDeliveryOption == .alarm
        schedule.alarmSoundOption = alarmSoundOption
        schedule.alarmSnoozeEnabled = alarmSnoozeEnabled
        schedule.alarmSnoozeMinutes = min(max(resolvedAlarmSnoozeMinutes, 1), 1439)
        schedule.repeatPattern = repeatPattern
        schedule.repeatWeekdays = sanitizedRepeatWeekdays(repeatWeekdays)
        schedule.repeatEndOption = resolvedRepeatEndOption
        schedule.repeatEndDate = resolvedRepeatEndDate
        schedule.earlyReminderMinutes = earlyReminderMinutes
        schedule.listName = listName
        schedule.tags = tags
        schedule.isFlagged = isFlagged
        schedule.priority = priority
    }

    func buildSchedule() -> Schedule {
        sanitizeRepeatEndConfiguration()
        return Schedule(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            notes: notes.isEmpty ? nil : notes,
            urlString: urlString.isEmpty ? nil : urlString,
            scheduledDate: normalizedSelectedDate,
            isUrgent: alertDeliveryOption == .alarm,
            repeatPattern: repeatPattern,
            repeatWeekdays: sanitizedRepeatWeekdays(repeatWeekdays),
            repeatEndOption: resolvedRepeatEndOption,
            repeatEndDate: resolvedRepeatEndDate,
            alertDeliveryOption: alertDeliveryOption,
            alarmSoundOption: alarmSoundOption,
            alarmSnoozeEnabled: alarmSnoozeEnabled,
            alarmSnoozeMinutes: min(max(resolvedAlarmSnoozeMinutes, 1), 1439),
            earlyReminderMinutes: earlyReminderMinutes,
            listName: listName,
            tags: tags,
            isFlagged: isFlagged,
            priority: priority
        )
    }

    func addTag() {
        let tag = newTag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !tag.isEmpty, !tags.contains(tag) else { return }
        tags.append(tag)
        newTag = ""
    }

    func removeTag(_ tag: String) {
        tags.removeAll { $0 == tag }
    }

    func reset() {
        title = ""
        notes = ""
        urlString = ""
        scheduledDate = Self.normalizedScheduleDate(Date())
        hasDate = true
        hasTime = true
        isUrgent = false
        repeatPattern = .never
        repeatWeekdays = Array(1...7)
        repeatEndOption = .never
        repeatEndDate = Calendar.current.startOfDay(for: normalizedSelectedDate)
        alertDeliveryOption = .push
        alarmSoundOption = .defaultRingtone
        alarmSnoozeEnabled = true
        alarmSnoozeChoice = .preset(10)
        customAlarmSnoozeTime = Self.timeForReminderMinutes(10)
        earlyReminderChoice = .none
        customEarlyReminderTime = Self.timeForReminderMinutes(90)
        listName = "Reminders"
        tags = []
        newTag = ""
        isFlagged = false
        priority = .none
        isEditing = false
        editingScheduleID = nil
    }

    func sanitizeRepeatEndConfiguration() {
        let minimumEndDate = Calendar.current.startOfDay(for: normalizedSelectedDate)
        if repeatEndDate < minimumEndDate {
            repeatEndDate = minimumEndDate
        }

        if repeatPattern == .never {
            repeatEndOption = .never
        }
    }

    private func sanitizedRepeatWeekdays(_ weekdays: [Int]) -> [Int] {
        let valid = Set(weekdays.filter { (1...7).contains($0) })
        return valid.isEmpty ? Array(1...7) : valid.sorted()
    }

    private var resolvedRepeatEndOption: RepeatEndOption {
        repeatPattern == .never ? .never : repeatEndOption
    }

    private var resolvedRepeatEndDate: Date? {
        guard repeatPattern != .never, repeatEndOption == .onDate else { return nil }
        return Calendar.current.startOfDay(for: repeatEndDate)
    }

    private static func timeForReminderMinutes(_ minutes: Int) -> Date {
        let clamped = min(max(minutes, 1), 1439)
        let hour = clamped / 60
        let minute = clamped % 60
        return Calendar.current.date(
            bySettingHour: hour,
            minute: minute,
            second: 0,
            of: Date()
        ) ?? Date()
    }

    private static func normalizedScheduleDate(_ date: Date) -> Date {
        let calendar = Calendar.current
        var components = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: date
        )
        components.second = 0
        return calendar.date(from: components) ?? date
    }

    private static func minimumSchedulableDate() -> Date {
        normalizedScheduleDate(Date())
    }
}
