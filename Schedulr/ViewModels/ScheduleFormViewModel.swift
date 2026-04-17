import Foundation
import SwiftUI
import SchedulrLogic

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

    var title: String = ""
    var notes: String = ""
    var urlString: String = ""
    var scheduledDate: Date = Date()
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
    var repeatInterval: Int = 1
    var repeatEndCount: Int = 10
    var additionalReminderMinutes: [Int] = []
    var timeZoneIdentifier: String? = nil
    var nlpInput: String = ""
    var showNLPMode: Bool = false
    var nlpStatusMessage: String?
    var conflictWarnings: [Schedule] = []

    var isEditing: Bool = false
    private var editingScheduleID: UUID?

    var isValid: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && isCustomEarlyReminderValid
            && isCustomSnoozeValid
            && scheduleDateValidationMessage == nil
    }

    var isScheduleDateInPast: Bool {
        normalizedSelectedDate < Self.minimumSchedulableDate()
    }

    var scheduleDateValidationMessage: String? {
        guard isScheduleDateInPast else { return nil }
        return "Past date/time is not allowed. Please choose a future time."
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
        return SnoozeLogic.snoozeDisplayName(for: choice)
    }

    func isRepeatWeekdaySelected(_ weekday: Int) -> Bool {
        WeekdaySelectionLogic.isSelected(weekday, in: repeatWeekdays)
    }

    func toggleRepeatWeekday(_ weekday: Int) {
        repeatWeekdays = WeekdaySelectionLogic.toggle(weekday, in: repeatWeekdays)
    }

    func configure(with schedule: Schedule) {
        isEditing = true
        editingScheduleID = schedule.id
        title = schedule.title
        notes = schedule.notes ?? ""
        urlString = schedule.urlString ?? ""
        scheduledDate = Self.normalizedScheduleDate(schedule.scheduledDate)
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
        repeatInterval = schedule.repeatInterval
        repeatEndCount = schedule.repeatEndCount > 0 ? schedule.repeatEndCount : 10
        additionalReminderMinutes = schedule.additionalReminderMinutes
        timeZoneIdentifier = schedule.timeZoneIdentifier
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
        schedule.repeatInterval = repeatInterval
        schedule.repeatEndCount = repeatEndOption == .afterCount ? repeatEndCount : 0
        schedule.additionalReminderMinutes = additionalReminderMinutes
        schedule.timeZoneIdentifier = timeZoneIdentifier
    }

    func buildSchedule() -> Schedule {
        sanitizeRepeatEndConfiguration()
        let schedule = Schedule(
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
        schedule.repeatInterval = repeatInterval
        schedule.repeatEndCount = repeatEndOption == .afterCount ? repeatEndCount : 0
        schedule.additionalReminderMinutes = additionalReminderMinutes
        schedule.timeZoneIdentifier = timeZoneIdentifier
        return schedule
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
        let settings = AppSettings.shared

        title = ""
        notes = ""
        urlString = ""
        scheduledDate = Self.normalizedScheduleDate(Date())
        isUrgent = false
        repeatPattern = settings.defaultRepeatPattern
        repeatWeekdays = Array(1...7)
        repeatEndOption = .never
        repeatEndDate = Calendar.current.startOfDay(for: normalizedSelectedDate)
        alertDeliveryOption = settings.defaultAlertStyle
        alarmSoundOption = .defaultRingtone
        alarmSnoozeEnabled = true
        let snoozeDuration = settings.defaultSnoozeDuration
        if Self.presetSnoozeMinutes.contains(snoozeDuration) {
            alarmSnoozeChoice = .preset(snoozeDuration)
            customAlarmSnoozeTime = Self.timeForReminderMinutes(snoozeDuration)
        } else {
            alarmSnoozeChoice = .custom
            customAlarmSnoozeTime = Self.timeForReminderMinutes(snoozeDuration)
        }
        let earlyReminder = settings.defaultEarlyReminderMinutes
        if earlyReminder <= 0 {
            earlyReminderChoice = .none
            customEarlyReminderTime = Self.timeForReminderMinutes(90)
        } else if Self.presetEarlyReminderMinutes.contains(earlyReminder) {
            earlyReminderChoice = .preset(earlyReminder)
            customEarlyReminderTime = Self.timeForReminderMinutes(90)
        } else {
            earlyReminderChoice = .custom
            customEarlyReminderTime = Self.timeForReminderMinutes(earlyReminder)
        }
        listName = settings.defaultCalendar
        tags = []
        newTag = ""
        isFlagged = false
        priority = settings.defaultPriority
        repeatInterval = 1
        repeatEndCount = 10
        additionalReminderMinutes = []
        timeZoneIdentifier = settings.defaultTimeZoneOverride
        nlpInput = ""
        showNLPMode = false
        conflictWarnings = []
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
        WeekdaySelectionLogic.sanitize(weekdays)
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

    // MARK: - NLP Support

    func applyNLPResult() async {
        guard !nlpInput.isEmpty else { return }
        let input = nlpInput
        let parseResult = await NLPScheduleRouter.shared.parse(input)
        let result = parseResult.parsed
        title = result.title
        if let date = result.date {
            scheduledDate = Self.normalizedScheduleDate(date)
        }
        if result.priority != .none {
            priority = result.priority
        }
        if result.repeatPattern != .never {
            repeatPattern = result.repeatPattern
        }
        if let deliveryOption = result.deliveryOption {
            alertDeliveryOption = deliveryOption
        }
        if let earlyReminderMinutes = result.earlyReminderMinutes {
            if Self.presetEarlyReminderMinutes.contains(earlyReminderMinutes) {
                earlyReminderChoice = .preset(earlyReminderMinutes)
            } else {
                earlyReminderChoice = .custom
                customEarlyReminderTime = Self.timeForReminderMinutes(earlyReminderMinutes)
            }
        }
        tags.append(contentsOf: result.tags.filter { !tags.contains($0) })
        nlpStatusMessage = parseResult.internetUnavailable ? "Turn on internet connection for better result." : nil
        nlpInput = ""
        showNLPMode = false
    }

    // MARK: - Smart Suggestions

    func applySmartSuggestions(existingSchedules: [Schedule], availableCalendars: [String]) {
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedTitle.isEmpty else { return }

        let suggestions = SmartSuggestionsService.fullSuggestions(
            for: normalizedTitle,
            existingSchedules: existingSchedules,
            preferredDate: normalizedSelectedDate
        )

        if let firstSuggestedTime = suggestions.suggestedTimes.first {
            let suggestedDate = Self.normalizedScheduleDate(firstSuggestedTime)
            if suggestedDate >= Self.minimumSchedulableDate() {
                scheduledDate = suggestedDate
            }
        }

        if suggestions.suggestedPriority != .none {
            priority = suggestions.suggestedPriority
        }

        if repeatPattern == .never && suggestions.suggestedRepeatPattern != .never {
            repeatPattern = suggestions.suggestedRepeatPattern
        }

        if let suggestedCalendar = suggestions.suggestedCalendar,
           availableCalendars.contains(suggestedCalendar)
        {
            listName = suggestedCalendar
        }

        let uniqueSuggestedTags = suggestions.suggestedTags.filter { !tags.contains($0) }
        tags.append(contentsOf: uniqueSuggestedTags)
    }

    // MARK: - Conflict Detection

    func checkConflicts(against schedules: [Schedule], excluding: Schedule? = nil) {
        guard AppSettings.shared.conflictDetectionEnabled else {
            conflictWarnings = []
            return
        }

        conflictWarnings = ConflictDetectionService.findConflicts(
            for: normalizedSelectedDate,
            excluding: excluding?.id,
            in: schedules
        )
    }

    @discardableResult
    func autoResolveConflicts(against schedules: [Schedule], excluding: Schedule? = nil) -> Bool {
        checkConflicts(against: schedules, excluding: excluding)
        guard !conflictWarnings.isEmpty else { return true }

        let originalDate = scheduledDate
        let stepMinutes = 15
        let maxAttempts = 32

        for attempt in 1...maxAttempts {
            guard let candidate = Calendar.current.date(byAdding: .minute, value: stepMinutes * attempt, to: originalDate) else {
                continue
            }

            let normalizedCandidate = Self.normalizedScheduleDate(candidate)
            if normalizedCandidate < Self.minimumSchedulableDate() { continue }

            let conflicts = ConflictDetectionService.findConflicts(
                for: normalizedCandidate,
                excluding: excluding?.id,
                in: schedules
            )
            if conflicts.isEmpty {
                scheduledDate = normalizedCandidate
                conflictWarnings = []
                return true
            }
        }

        checkConflicts(against: schedules, excluding: excluding)
        return false
    }

    // MARK: - Additional Reminders

    func addAdditionalReminder(_ minutes: Int) {
        guard !additionalReminderMinutes.contains(minutes) else { return }
        additionalReminderMinutes.append(minutes)
        additionalReminderMinutes.sort()
    }

    func removeAdditionalReminder(_ minutes: Int) {
        additionalReminderMinutes.removeAll { $0 == minutes }
    }

    func reminderDisplayText(_ minutes: Int) -> String {
        if minutes < 60 { return "\(minutes) min before" }
        let hours = minutes / 60
        let mins = minutes % 60
        if mins == 0 { return "\(hours)h before" }
        return "\(hours)h \(mins)m before"
    }
}
