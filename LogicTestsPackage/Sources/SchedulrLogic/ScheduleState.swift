import Foundation

public protocol ScheduleState: AnyObject {
    var id: UUID { get set }
    var title: String { get set }
    var notes: String? { get set }
    var scheduledDate: Date { get set }
    var alertDeliveryOption: AlertDeliveryOption { get set }
    var priority: SchedulePriority { get set }
    var isCompleted: Bool { get set }
    var repeatPattern: RepeatPattern { get set }
    var tags: [String] { get set }
    var listName: String { get set }
    var urlString: String? { get set }
    var earlyReminderMinutes: Int? { get set }
    var repeatInterval: Int { get set }
    var repeatEndCount: Int { get set }
    var additionalReminderMinutes: [Int] { get set }
    var timeZoneIdentifier: String? { get set }
}

/// A lightweight, value-type snapshot of a Schedule for undo/redo.
public struct ScheduleSnapshot: Codable {
    public let id: UUID
    public let title: String
    public let notes: String?
    public let scheduledDate: Date
    public let alertOption: String // raw value
    public let priority: Int      // raw value
    public let isCompleted: Bool
    public let repeatPattern: String
    public let tags: [String]
    public let calendar: String
    public let urlString: String?
    public let reminderMinutesBefore: Int?
    public let repeatInterval: Int
    public let repeatEndCount: Int
    public let additionalReminderMinutes: [Int]
    public let timeZoneIdentifier: String?

    public init(from schedule: any ScheduleState) {
        self.id = schedule.id
        self.title = schedule.title
        self.notes = schedule.notes
        self.scheduledDate = schedule.scheduledDate
        self.alertOption = schedule.alertDeliveryOption.rawValue
        self.priority = schedule.priority.rawValue
        self.isCompleted = schedule.isCompleted
        self.repeatPattern = schedule.repeatPattern.rawValue
        self.tags = schedule.tags
        self.calendar = schedule.listName
        self.urlString = schedule.urlString
        self.reminderMinutesBefore = schedule.earlyReminderMinutes
        self.repeatInterval = schedule.repeatInterval
        self.repeatEndCount = schedule.repeatEndCount
        self.additionalReminderMinutes = schedule.additionalReminderMinutes
        self.timeZoneIdentifier = schedule.timeZoneIdentifier
    }

    public func apply(to schedule: any ScheduleState) {
        schedule.title = title
        schedule.notes = notes
        schedule.scheduledDate = scheduledDate
        schedule.alertDeliveryOption = AlertDeliveryOption(rawValue: alertOption) ?? .push
        schedule.priority = SchedulePriority(rawValue: priority) ?? .none
        schedule.isCompleted = isCompleted
        schedule.repeatPattern = RepeatPattern(rawValue: repeatPattern) ?? .never
        schedule.tags = tags
        schedule.listName = calendar
        schedule.urlString = urlString
        schedule.earlyReminderMinutes = reminderMinutesBefore
        schedule.repeatInterval = repeatInterval
        schedule.repeatEndCount = repeatEndCount
        schedule.additionalReminderMinutes = additionalReminderMinutes
        schedule.timeZoneIdentifier = timeZoneIdentifier
    }
}
