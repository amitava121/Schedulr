import AppIntents
import SwiftData
import Foundation

// MARK: - Add Schedule Intent

struct AddScheduleIntent: AppIntent {
    static var title: LocalizedStringResource = "Add Schedule"
    static var description = IntentDescription("Create a new schedule in Schedulr")

    @Parameter(title: "Title")
    var scheduleTitle: String

    @Parameter(title: "Date", kind: .date)
    var scheduledDate: Date?

    @Parameter(title: "Notes")
    var notes: String?

    @Parameter(title: "Priority")
    var priority: SchedulePriorityEntity?

    static var parameterSummary: some ParameterSummary {
        Summary("Add \(\.$scheduleTitle) at \(\.$scheduledDate)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let date = scheduledDate ?? Date()
        let priorityValue = priority?.value ?? .none

        // Post notification to create schedule on main thread
        await MainActor.run {
            NotificationCenter.default.post(
                name: .siriAddScheduleRequest,
                object: nil,
                userInfo: [
                    "title": scheduleTitle,
                    "date": date,
                    "notes": notes as Any,
                    "priority": priorityValue.rawValue
                ]
            )
        }

        return .result(dialog: "Added '\(scheduleTitle)' to your schedule.")
    }
}

// MARK: - View Upcoming Schedules Intent

struct ViewUpcomingSchedulesIntent: AppIntent {
    static var title: LocalizedStringResource = "View Upcoming Schedules"
    static var description = IntentDescription("See your upcoming schedules")

    @Parameter(title: "Count", default: 5)
    var count: Int

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let schedules = await fetchUpcomingSchedules(count: count)
        if schedules.isEmpty {
            return .result(dialog: "No upcoming schedules.")
        }

        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short

        let summary = schedules.map { "\($0.title) at \(formatter.string(from: $0.date))" }
            .joined(separator: "\n")

        return .result(dialog: "Upcoming schedules:\n\(summary)")
    }

    private func fetchUpcomingSchedules(count: Int) async -> [(title: String, date: Date)] {
        // Read from widget snapshot in app group
        let appGroupID = "group.com.bittu.Schedulr"
        let snapshotKey = "widget.scheduleSnapshot.v1"
        guard let defaults = UserDefaults(suiteName: appGroupID),
              let data = defaults.data(forKey: snapshotKey)
        else { return [] }

        struct WidgetSnapshot: Codable {
            var updatedAt: Date
            var upcoming: [WidgetItem]
        }
        struct WidgetItem: Codable {
            var title: String
            var scheduledDate: Date
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let snapshot = try? decoder.decode(WidgetSnapshot.self, from: data) else { return [] }

        return snapshot.upcoming.prefix(count).map { (title: $0.title, date: $0.scheduledDate) }
    }
}

// MARK: - Complete Schedule Intent

struct CompleteScheduleIntent: AppIntent {
    static var title: LocalizedStringResource = "Complete Schedule"
    static var description = IntentDescription("Mark a schedule as completed")

    @Parameter(title: "Schedule Title")
    var scheduleTitle: String

    func perform() async throws -> some IntentResult & ProvidesDialog {
        await MainActor.run {
            NotificationCenter.default.post(
                name: .siriCompleteScheduleRequest,
                object: nil,
                userInfo: ["title": scheduleTitle]
            )
        }

        return .result(dialog: "Marked '\(scheduleTitle)' as completed.")
    }
}

// MARK: - App Shortcuts Provider

struct SchedulrShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AddScheduleIntent(),
            phrases: [
                "Add a schedule in \(.applicationName)",
                "Create a reminder in \(.applicationName)",
                "Add a new schedule to \(.applicationName)"
            ],
            shortTitle: "Add Schedule",
            systemImageName: "calendar.badge.plus"
        )

        AppShortcut(
            intent: ViewUpcomingSchedulesIntent(),
            phrases: [
                "Show upcoming schedules in \(.applicationName)",
                "What's next in \(.applicationName)"
            ],
            shortTitle: "View Upcoming",
            systemImageName: "calendar"
        )

        AppShortcut(
            intent: CompleteScheduleIntent(),
            phrases: [
                "Complete schedule in \(.applicationName)",
                "Mark a schedule as done in \(.applicationName)"
            ],
            shortTitle: "Complete Schedule",
            systemImageName: "checkmark.circle"
        )
    }
}

// MARK: - Priority Entity

struct SchedulePriorityEntity: AppEntity {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Priority")
    static var defaultQuery = SchedulePriorityQuery()

    var id: String
    var value: SchedulePriority

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(value.displayName)")
    }
}

struct SchedulePriorityQuery: EntityQuery {
    @MainActor
    func entities(for identifiers: [String]) async throws -> [SchedulePriorityEntity] {
        EntityExtraction.extract(
            identifiers: identifiers,
            allEntities: SchedulePriority.allCases,
            idProvider: { $0.displayName }
        )
        .map { SchedulePriorityEntity(id: $0.displayName, value: $0) }
    }

    @MainActor
    func suggestedEntities() async throws -> [SchedulePriorityEntity] {
        SchedulePriority.allCases.map { SchedulePriorityEntity(id: $0.displayName, value: $0) }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let siriAddScheduleRequest = Notification.Name("siriAddScheduleRequest")
    static let siriCompleteScheduleRequest = Notification.Name("siriCompleteScheduleRequest")
}
