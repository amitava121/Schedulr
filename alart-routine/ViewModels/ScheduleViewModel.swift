import Foundation
import SwiftData
import SwiftUI
#if canImport(WidgetKit)
import WidgetKit
#endif

enum ZoomLevel {
    case week
    case day
}

/// Stable identity for a day row — avoids creating new arrays / tuples each render.
struct DayItem: Identifiable {
    let id: Date          // startOfDay is unique per row
    let index: Int
    let date: Date
    let schedules: [Schedule]
}

@Observable
final class ScheduleViewModel {
    private static let recurringCompletionStorageKey = "scheduleRecurringCompletion.v1"
    private static let widgetAppGroupID = "group.com.bittu.alart-routine"
    private static let widgetSnapshotKey = "widget.scheduleSnapshot.v1"
    private static let widgetCompletionRequestsKey = "widget.completeRequests.v1"

    private struct WidgetScheduleSnapshot: Codable {
        var updatedAt: Date
        var upcoming: [WidgetScheduleItem]
        var past: [WidgetScheduleItem]
    }

    private struct WidgetScheduleItem: Codable {
        var id: String
        var title: String
        var scheduledDate: Date
        var notes: String?
        var urlString: String?
        var repeatPatternName: String
        var deliveryName: String
        var priorityName: String
        var earlyReminderMinutes: Int?
        var isCompleted: Bool
    }

    private struct WidgetCompletionRequest: Codable {
        var scheduleID: String
        var occurrenceDate: Date
    }

    var schedules: [Schedule] = []
    var zoomLevel: ZoomLevel = .week
    var selectedDayIndex: Int = 0
    var isLoading = false
    var showingAddForm = false
    var editingSchedule: Schedule?
    var pendingNewScheduleDate: Date?

    /// Cached week dates — rebuilt only when `currentWeekStart` changes.
    private(set) var weekDates: [Date] = []
    /// Pre-built rows for the current week with schedules attached.
    private(set) var dayItems: [DayItem] = []

    private var _currentWeekStart: Date = Date().startOfWeek

    var currentWeekStart: Date {
        get { _currentWeekStart }
        set {
            guard newValue != _currentWeekStart else { return }
            _currentWeekStart = newValue
            rebuildWeek()
        }
    }

    private var modelContext: ModelContext?
    private var schedulesByDay: [Date: [Schedule]] = [:]
    private var recurringCompletionBySchedule: [UUID: Set<Date>] = [:]
    private var hasLoadedInitialData = false

    var selectedDate: Date {
        weekDates[safe: selectedDayIndex] ?? Date()
    }

    var weekTitle: String {
        _currentWeekStart.monthYearString
    }

    var dayTitle: String {
        selectedDate.fullDayString
    }

    func setup(modelContext: ModelContext) {
        self.modelContext = modelContext
        guard !hasLoadedInitialData else { return }
        hasLoadedInitialData = true
        loadRecurringCompletionState()
        rebuildWeek()
        fetchSchedules()
        consumeWidgetCompletionRequests()
        observeMarkAsReadNotifications()
    }

    func consumeWidgetCompletionRequests() {
        guard let defaults = UserDefaults(suiteName: Self.widgetAppGroupID),
              let rawData = defaults.data(forKey: Self.widgetCompletionRequestsKey)
        else {
            return
        }

          let decoder = JSONDecoder()
          decoder.dateDecodingStrategy = .iso8601
        guard let requests = try? decoder.decode([WidgetCompletionRequest].self, from: rawData),
              !requests.isEmpty
        else {
            defaults.removeObject(forKey: Self.widgetCompletionRequestsKey)
            return
        }

        defaults.removeObject(forKey: Self.widgetCompletionRequestsKey)

        var changed = false
        for request in requests {
            guard let scheduleID = UUID(uuidString: request.scheduleID),
                  let schedule = schedule(withID: scheduleID)
            else {
                continue
            }

            if schedule.repeatPattern == .never {
                guard !schedule.isCompleted else { continue }
                schedule.isCompleted = true
                NotificationManager.shared.cancelNotification(for: schedule)
                changed = true
            } else {
                let day = request.occurrenceDate.startOfDay
                guard !isScheduleCompleted(schedule, on: day) else { continue }
                setRecurringCompletion(for: schedule, on: day, isCompleted: true)
                changed = true
            }
        }

        guard changed else {
            updateWidgetSnapshot()
            return
        }

        saveContext()
        normalizeSchedules()
    }

    func markScheduleCompleted(scheduleID: UUID, occurrenceDate: Date? = nil) {
        guard let schedule = schedule(withID: scheduleID) else { return }

        if schedule.repeatPattern == .never {
            guard !schedule.isCompleted else { return }
            schedule.isCompleted = true
            NotificationManager.shared.cancelNotification(for: schedule)
            saveContext()
            normalizeSchedules()
            return
        }

        let day = (occurrenceDate ?? Date()).startOfDay
        guard !isScheduleCompleted(schedule, on: day) else { return }
        setRecurringCompletion(for: schedule, on: day, isCompleted: true)
    }

    /// Ensures a consistent default landing state on cold launch.
    func prepareDefaultWeekLanding() {
        let today = Date()
        currentWeekStart = today.startOfWeek

        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: today)
        let firstWeekday = calendar.firstWeekday
        selectedDayIndex = (weekday - firstWeekday + 7) % 7

        zoomLevel = .week
    }
    
    private func observeMarkAsReadNotifications() {
        NotificationCenter.default.addObserver(
            forName: .didMarkScheduleAsRead,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self,
                  let scheduleIDString = notification.userInfo?["scheduleID"] as? String,
                  let scheduleID = UUID(uuidString: scheduleIDString),
                  let schedule = self.schedule(withID: scheduleID)
            else { return }

            if schedule.repeatPattern == .never {
                schedule.isCompleted = true
                self.saveContext()
                self.normalizeSchedules()
                HapticManager.notification(.success)
                return
            }

            let occurrenceDate = self.occurrenceDate(from: notification.userInfo) ?? Date()
            self.setRecurringCompletion(for: schedule, on: occurrenceDate, isCompleted: true)
            HapticManager.notification(.success)
        }
    }

    func fetchSchedules() {
        guard let modelContext else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let descriptor = FetchDescriptor<Schedule>(
                sortBy: [SortDescriptor(\.scheduledDate)]
            )
            schedules = try modelContext.fetch(descriptor)
            pruneRecurringCompletionState()
            normalizeSchedules()
        } catch {
            print("Fetch error: \(error)")
            schedules = []
            schedulesByDay = [:]
        }
    }

    func schedules(for date: Date) -> [Schedule] {
        let day = date.startOfDay
        if let cached = schedulesByDay[day] {
            return cached
        }

        let calendar = Calendar.current
        let filtered = schedules.filter { schedule in
            occurs(schedule, on: day, calendar: calendar)
        }
        return filtered.sorted { lhs, rhs in
            isScheduledEarlier(lhs, than: rhs, calendar: calendar)
        }
    }

    func schedule(withID id: UUID) -> Schedule? {
        schedules.first { $0.id == id }
    }

    func isScheduleCompleted(_ schedule: Schedule, on occurrenceDate: Date) -> Bool {
        if schedule.repeatPattern == .never {
            return schedule.isCompleted
        }

        let day = occurrenceDate.startOfDay
        return recurringCompletionBySchedule[schedule.id]?.contains(day) ?? false
    }

    func addSchedule(_ schedule: Schedule) {
        guard let modelContext else { return }
        guard !isScheduleDateInPast(schedule.scheduledDate) else {
            HapticManager.notification(.warning)
            return
        }
        modelContext.insert(schedule)
        saveContext()
        schedules.append(schedule)
        normalizeSchedules()
        NotificationManager.shared.scheduleNotification(for: schedule)
        pendingNewScheduleDate = nil
        HapticManager.notification(.success)
    }

    func deleteSchedule(_ schedule: Schedule) {
        guard let modelContext else { return }
        NotificationManager.shared.cancelNotification(for: schedule)
        modelContext.delete(schedule)
        saveContext()
        schedules.removeAll { $0.id == schedule.id }
        if recurringCompletionBySchedule.removeValue(forKey: schedule.id) != nil {
            persistRecurringCompletionState()
        }
        normalizeSchedules()
        HapticManager.notification(.warning)
    }

    func updateSchedule(_ schedule: Schedule) {
        guard !isScheduleDateInPast(schedule.scheduledDate) else {
            HapticManager.notification(.warning)
            return
        }
        saveContext()
        if schedule.repeatPattern == .never && schedule.isCompleted {
            NotificationManager.shared.cancelNotification(for: schedule)
        } else {
            NotificationManager.shared.updateNotification(for: schedule)
        }
        normalizeSchedules()
    }

    func toggleScheduleCompletion(_ schedule: Schedule, on occurrenceDate: Date? = nil) {
        if schedule.repeatPattern != .never {
            let day = (occurrenceDate ?? selectedDate).startOfDay
            let isNowCompleted = !isScheduleCompleted(schedule, on: day)
            setRecurringCompletion(for: schedule, on: day, isCompleted: isNowCompleted)
            if isNowCompleted {
                HapticManager.notification(.success)
            } else {
                HapticManager.selection()
            }
            return
        }

        schedule.isCompleted.toggle()
        saveContext()

        if schedule.isCompleted {
            NotificationManager.shared.cancelNotification(for: schedule)
            HapticManager.notification(.success)
        } else {
            let shouldBeActive = schedule.repeatPattern != .never || schedule.scheduledDate > Date()
            if shouldBeActive {
                NotificationManager.shared.updateNotification(for: schedule)
            }
            HapticManager.selection()
        }

        normalizeSchedules()
    }

    func resyncAllScheduleNotifications() {
        for schedule in schedules {
            if schedule.repeatPattern == .never && schedule.isCompleted {
                NotificationManager.shared.cancelNotification(for: schedule)
                continue
            }
            let shouldBeActive = schedule.repeatPattern != .never || schedule.scheduledDate > Date()
            if shouldBeActive {
                NotificationManager.shared.updateNotification(for: schedule)
            } else {
                NotificationManager.shared.cancelNotification(for: schedule)
            }
        }
    }

    func zoomToDay(index: Int) {
        selectedDayIndex = min(max(index, 0), 6)
        zoomLevel = .day
        HapticManager.impact(.medium)
    }

    func zoomToWeek() {
        zoomLevel = .week
        HapticManager.impact(.light)
    }

    func goToPreviousWeek() {
        if let newStart = Calendar.current.date(byAdding: .weekOfYear, value: -1, to: currentWeekStart) {
            currentWeekStart = newStart
        }
    }

    func goToNextWeek() {
        if let newStart = Calendar.current.date(byAdding: .weekOfYear, value: 1, to: currentWeekStart) {
            currentWeekStart = newStart
        }
    }

    func goToPreviousDay() {
        if selectedDayIndex > 0 {
            selectedDayIndex -= 1
        } else {
            goToPreviousWeek()
            selectedDayIndex = 6
        }
        HapticManager.selection()
    }

    func goToNextDay() {
        if selectedDayIndex < 6 {
            selectedDayIndex += 1
        } else {
            goToNextWeek()
            selectedDayIndex = 0
        }
        HapticManager.selection()
    }

    func goToToday() {
        currentWeekStart = Date().startOfWeek
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: Date())
        let firstWeekday = calendar.firstWeekday
        selectedDayIndex = (weekday - firstWeekday + 7) % 7
    }

    @discardableResult
    func focusOnSchedule(withID id: UUID) -> Bool {
        guard let schedule = schedule(withID: id) else { return false }
        focus(on: schedule.scheduledDate)
        return true
    }

    func focus(on date: Date) {
        currentWeekStart = date.startOfWeek

        if let index = weekDates.firstIndex(where: { Calendar.current.isDate($0, inSameDayAs: date) }) {
            selectedDayIndex = index
        } else {
            selectedDayIndex = 0
        }

        // Stay on whichever zoom level the user is already on (week or day).
        // Do NOT force zoomLevel = .day here so that notification taps
        // land on the week view with the correct day highlighted.
    }

    func startAddingSchedule(on date: Date, dayIndex: Int) {
        selectedDayIndex = min(max(dayIndex, 0), 6)
        pendingNewScheduleDate = dateWithCurrentTime(from: date)
        showingAddForm = true
    }

    func clearPendingNewScheduleDate() {
        pendingNewScheduleDate = nil
    }

    private func setRecurringCompletion(
        for schedule: Schedule,
        on occurrenceDate: Date,
        isCompleted: Bool
    ) {
        let day = occurrenceDate.startOfDay
        var completedDays = recurringCompletionBySchedule[schedule.id] ?? []

        if isCompleted {
            completedDays.insert(day)
        } else {
            completedDays.remove(day)
        }

        if completedDays.isEmpty {
            recurringCompletionBySchedule.removeValue(forKey: schedule.id)
        } else {
            recurringCompletionBySchedule[schedule.id] = completedDays
        }

        persistRecurringCompletionState()
        rebuildDayItems()
        updateWidgetSnapshot()
    }

    private func occurrenceDate(from userInfo: [AnyHashable: Any]?) -> Date? {
        guard let userInfo else { return nil }

        if let value = userInfo["occurrenceTimestamp"] as? TimeInterval {
            return Date(timeIntervalSince1970: value)
        }

        if let value = userInfo["occurrenceTimestamp"] as? NSNumber {
            return Date(timeIntervalSince1970: value.doubleValue)
        }

        if let value = userInfo["occurrenceTimestamp"] as? String,
           let timestamp = TimeInterval(value)
        {
            return Date(timeIntervalSince1970: timestamp)
        }

        return nil
    }

    private func loadRecurringCompletionState() {
        let defaults = UserDefaults.standard
        guard let raw = defaults.dictionary(forKey: Self.recurringCompletionStorageKey) else {
            recurringCompletionBySchedule = [:]
            return
        }

        var parsed: [UUID: Set<Date>] = [:]
        parsed.reserveCapacity(raw.count)

        for (scheduleIDString, value) in raw {
            guard let scheduleID = UUID(uuidString: scheduleIDString) else { continue }

            let timestamps: [TimeInterval]
            if let numbers = value as? [NSNumber] {
                timestamps = numbers.map(\.doubleValue)
            } else if let doubles = value as? [Double] {
                timestamps = doubles
            } else if let strings = value as? [String] {
                timestamps = strings.compactMap(TimeInterval.init)
            } else {
                continue
            }

            let days = Set(timestamps.map { Date(timeIntervalSince1970: $0).startOfDay })
            if !days.isEmpty {
                parsed[scheduleID] = days
            }
        }

        recurringCompletionBySchedule = parsed
    }

    private func persistRecurringCompletionState() {
        var encoded: [String: [TimeInterval]] = [:]
        encoded.reserveCapacity(recurringCompletionBySchedule.count)

        for (scheduleID, days) in recurringCompletionBySchedule {
            let timestamps = days
                .map(\.timeIntervalSince1970)
                .sorted()

            if !timestamps.isEmpty {
                encoded[scheduleID.uuidString] = timestamps
            }
        }

        UserDefaults.standard.set(encoded, forKey: Self.recurringCompletionStorageKey)
    }

    private func pruneRecurringCompletionState() {
        let validIDs = Set(
            schedules
                .filter { $0.repeatPattern != .never }
                .map(\.id)
        )

        let staleIDs = recurringCompletionBySchedule.keys.filter { !validIDs.contains($0) }
        guard !staleIDs.isEmpty else { return }

        for staleID in staleIDs {
            recurringCompletionBySchedule.removeValue(forKey: staleID)
        }
        persistRecurringCompletionState()
    }

    private func saveContext() {
        guard let modelContext else { return }
        do {
            try modelContext.save()
        } catch {
            print("Save error: \(error)")
        }
    }

    private func isScheduleDateInPast(_ date: Date) -> Bool {
        let calendar = Calendar.current
        let now = Date()
        var nowComponents = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: now)
        nowComponents.second = 0
        let minimumAllowedDate = calendar.date(from: nowComponents) ?? now
        return date < minimumAllowedDate
    }

    private func dateWithCurrentTime(from date: Date) -> Date {
        let calendar = Calendar.current
        var dayComponents = calendar.dateComponents([.year, .month, .day], from: date)
        let nowComponents = calendar.dateComponents([.hour, .minute], from: Date())
        dayComponents.hour = nowComponents.hour
        dayComponents.minute = nowComponents.minute
        dayComponents.second = 0
        return calendar.date(from: dayComponents) ?? date
    }

    private func normalizeSchedules() {
        schedules.sort { $0.scheduledDate < $1.scheduledDate }
        rebuildScheduleIndex()
        rebuildDayItems()
        updateWidgetSnapshot()
    }

    private func rebuildWeek() {
        weekDates = _currentWeekStart.weekDates
        rebuildScheduleIndex()
        rebuildDayItems()
    }

    private func rebuildDayItems() {
        dayItems = weekDates.enumerated().map { index, date in
            DayItem(
                id: date.startOfDay,
                index: index,
                date: date,
                schedules: schedulesByDay[date.startOfDay] ?? []
            )
        }
    }

    private func rebuildScheduleIndex() {
        let calendar = Calendar.current
        var grouped: [Date: [Schedule]] = [:]
        grouped.reserveCapacity(weekDates.count)

        for weekDay in weekDates {
            grouped[weekDay.startOfDay] = []
        }

        for schedule in schedules {
            for weekDay in weekDates {
                let day = weekDay.startOfDay
                guard occurs(schedule, on: day, calendar: calendar) else { continue }
                grouped[day, default: []].append(schedule)
            }
        }

        for day in grouped.keys {
            grouped[day]?.sort { lhs, rhs in
                isScheduledEarlier(lhs, than: rhs, calendar: calendar)
            }
        }

        schedulesByDay = grouped
    }

    private func isScheduledEarlier(
        _ lhs: Schedule,
        than rhs: Schedule,
        calendar: Calendar
    ) -> Bool {
        let lhm = calendar.component(.hour, from: lhs.scheduledDate) * 60
            + calendar.component(.minute, from: lhs.scheduledDate)
        let rhm = calendar.component(.hour, from: rhs.scheduledDate) * 60
            + calendar.component(.minute, from: rhs.scheduledDate)

        if lhm == rhm {
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
        return lhm < rhm
    }

    private func occurs(
        _ schedule: Schedule,
        on day: Date,
        calendar: Calendar
    ) -> Bool {
        let startDay = schedule.scheduledDate.startOfDay
        let targetDay = day.startOfDay

        guard targetDay >= startDay else { return false }

        if schedule.repeatEndOption == .onDate,
           let endDate = schedule.repeatEndDate?.startOfDay,
           targetDay > endDate
        {
            return false
        }

        switch schedule.repeatPattern {
        case .never:
            return calendar.isDate(targetDay, inSameDayAs: startDay)

        case .daily:
            let weekdays = normalizedWeekdays(schedule.repeatWeekdays)
            let weekday = calendar.component(.weekday, from: targetDay)
            return weekdays.contains(weekday)

        case .weekly:
            return calendar.component(.weekday, from: targetDay) == calendar.component(.weekday, from: startDay)

        case .monthly:
            return calendar.component(.day, from: targetDay) == calendar.component(.day, from: startDay)

        case .yearly:
            let targetMonth = calendar.component(.month, from: targetDay)
            let targetDayOfMonth = calendar.component(.day, from: targetDay)
            let startMonth = calendar.component(.month, from: startDay)
            let startDayOfMonth = calendar.component(.day, from: startDay)
            return targetMonth == startMonth && targetDayOfMonth == startDayOfMonth
        }
    }

    private func normalizedWeekdays(_ weekdays: [Int]) -> [Int] {
        let valid = Set(weekdays.filter { (1...7).contains($0) })
        return valid.isEmpty ? Array(1...7) : valid.sorted()
    }

    private func updateWidgetSnapshot() {
        guard let defaults = UserDefaults(suiteName: Self.widgetAppGroupID) else { return }

        let now = Date()
        let calendar = Calendar.current
        let today = now.startOfDay

        let todayItems = schedules
            .filter { occurs($0, on: today, calendar: calendar) }
            .map { schedule -> WidgetScheduleItem in
                let occurrenceDate = occurrenceDate(for: schedule, on: today, calendar: calendar)
                let occurrenceCompleted = isScheduleCompleted(schedule, on: occurrenceDate)
                return makeWidgetItem(
                    from: schedule,
                    occurrenceDate: occurrenceDate,
                    isCompleted: occurrenceCompleted
                )
            }
            .sorted { lhs, rhs in
                lhs.scheduledDate < rhs.scheduledDate
            }

        let upcomingItems = todayItems
            .filter { $0.scheduledDate >= now }
            .prefix(6)

        let pastItems = todayItems
            .filter { $0.scheduledDate < now || $0.isCompleted }
            .suffix(6)
            .reversed()

        let snapshot = WidgetScheduleSnapshot(
            updatedAt: now,
            upcoming: Array(upcomingItems),
            past: Array(pastItems)
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let encoded = try? encoder.encode(snapshot) else { return }

        defaults.set(encoded, forKey: Self.widgetSnapshotKey)

#if canImport(WidgetKit)
        WidgetCenter.shared.reloadTimelines(ofKind: "AlarmStatusWidget")
#endif
    }

    private func makeWidgetItem(
        from schedule: Schedule,
        occurrenceDate: Date,
        isCompleted: Bool
    ) -> WidgetScheduleItem {
        WidgetScheduleItem(
            id: schedule.id.uuidString,
            title: schedule.title,
            scheduledDate: occurrenceDate,
            notes: schedule.notes,
            urlString: schedule.urlString,
            repeatPatternName: schedule.repeatPattern.displayName,
            deliveryName: schedule.alertDeliveryOption.displayName,
            priorityName: schedule.priority.displayName,
            earlyReminderMinutes: schedule.earlyReminderMinutes,
            isCompleted: isCompleted
        )
    }

    private func occurrenceDate(for schedule: Schedule, on day: Date, calendar: Calendar) -> Date {
        let dayComponents = calendar.dateComponents([.year, .month, .day], from: day)
        let timeComponents = calendar.dateComponents([.hour, .minute, .second], from: schedule.scheduledDate)
        var merged = DateComponents()
        merged.year = dayComponents.year
        merged.month = dayComponents.month
        merged.day = dayComponents.day
        merged.hour = timeComponents.hour
        merged.minute = timeComponents.minute
        merged.second = timeComponents.second ?? 0
        return calendar.date(from: merged) ?? schedule.scheduledDate
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
