import AppIntents
import SwiftUI

// MARK: - Focus Filter Intent

/// Allows the system Focus feature to filter visible schedules by calendar or priority.
@available(iOS 16.0, *)
struct SchedulrFocusFilter: SetFocusFilterIntent {
    static var title: LocalizedStringResource = "Filter Schedulr"
    static var description: IntentDescription? = IntentDescription(
        "Choose which schedules appear during this Focus.",
        categoryName: "Filter"
    )

    @Parameter(title: "Filter by Calendar")
    var calendarName: String?

    @Parameter(title: "Filter by Priority")
    var priorityFilter: FocusPriorityFilter?

    @Parameter(title: "Show Completed Schedules")
    var showCompleted: Bool?

    var displayRepresentation: DisplayRepresentation {
        var subtitle = ""
        if let cal = calendarName { subtitle += "Calendar: \(cal)  " }
        if let pri = priorityFilter { subtitle += "Priority: \(pri.localizedStringResource)" }
        return DisplayRepresentation(
            title: "Schedulr Filter",
            subtitle: subtitle.isEmpty ? "All schedules" : "\(subtitle)"
        )
    }

    func perform() async throws -> some IntentResult {
        // Store focus filter preferences so the app can read them
        let defaults = UserDefaults.standard
        defaults.set(calendarName, forKey: "focusFilterCalendar")
        defaults.set(priorityFilter?.rawValue, forKey: "focusFilterPriority")
        defaults.set(showCompleted ?? true, forKey: "focusFilterShowCompleted")

        NotificationCenter.default.post(name: .focusFilterChanged, object: nil)

        return .result()
    }
}

// MARK: - Focus Priority Filter Enum

@available(iOS 16.0, *)
enum FocusPriorityFilter: String, AppEnum {
    case high
    case medium
    case low
    case all

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Priority"

    static var caseDisplayRepresentations: [FocusPriorityFilter: DisplayRepresentation] = [
        .high: "High",
        .medium: "Medium",
        .low: "Low",
        .all: "All"
    ]
}

// MARK: - Focus Filter State

/// Reads the current Focus filter state from UserDefaults.
struct FocusFilterState {
    static var current: FocusFilterState {
        let defaults = UserDefaults.standard
        let storedShowCompleted = defaults.object(forKey: "focusFilterShowCompleted") as? Bool
        return FocusFilterState(
            calendarName: defaults.string(forKey: "focusFilterCalendar"),
            priorityRawValue: defaults.string(forKey: "focusFilterPriority"),
            showCompleted: storedShowCompleted ?? true
        )
    }

    let calendarName: String?
    let priorityRawValue: String?
    let showCompleted: Bool

    var priorityFilter: SchedulePriority? {
        guard let raw = priorityRawValue, raw != "all" else { return nil }
        switch raw {
        case "high":
            return .high
        case "medium":
            return .medium
        case "low":
            return .low
        default:
            return nil
        }
    }

    func shouldShow(_ schedule: Schedule) -> Bool {
        // Calendar filter
        if let cal = calendarName, !cal.isEmpty {
            if schedule.listName != cal { return false }
        }

        // Priority filter
        if let priority = priorityFilter {
            if schedule.priority != priority { return false }
        }

        // Completed filter
        if !showCompleted && schedule.isCompleted { return false }

        return true
    }
}

// MARK: - Notification

extension Notification.Name {
    nonisolated static let focusFilterChanged = Notification.Name("focusFilterChanged")
}
