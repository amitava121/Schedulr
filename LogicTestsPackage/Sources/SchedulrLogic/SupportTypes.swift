import Foundation

public enum SchedulePriority: Int, Codable, CaseIterable, Identifiable {
    case none = 0
    case low = 1
    case medium = 2
    case high = 3

    public var id: Int { rawValue }
}

public enum RepeatPattern: String, Codable, CaseIterable, Identifiable {
    case never = "Never"
    case daily = "Daily"
    case weekdays = "Weekdays"
    case weekly = "Weekly"
    case biweekly = "Biweekly"
    case monthly = "Monthly"
    case yearly = "Yearly"
    case everyNDays = "Every N Days"
    case everyNWeeks = "Every N Weeks"
    case everyNMonths = "Every N Months"
    case customWeekdays = "Custom Weekdays"

    public var id: String { rawValue }
}

public enum RepeatEndOption: String, Codable {
    case never = "Never"
    case onDate = "On Date"
    case afterCount = "After Count"
}

public enum AlertDeliveryOption: String, Codable {
    case push
    case alarm
}

public enum AlarmSoundOption: String, Codable {
    case `default`
}

public struct Schedule: Codable, Equatable {
    public var id: UUID
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?
    public var isSoftDeleted: Bool
    public var lastModifiedDeviceID: String
    public var syncVersion: Int
    public var lastSyncedVersion: Int
    public var conflictResolutionTag: String?
    public var title: String
    public var notes: String?
    public var urlString: String?
    public var scheduledDate: Date
    public var isUrgent: Bool
    public var repeatPattern: RepeatPattern
    public var repeatWeekdays: [Int]
    public var excludedOccurrenceDates: [Date]
    public var repeatEndOption: RepeatEndOption
    public var repeatEndDate: Date?
    public var alertDeliveryOption: AlertDeliveryOption
    public var alarmSoundOption: AlarmSoundOption
    public var alarmSnoozeEnabled: Bool
    public var alarmSnoozeMinutes: Int
    public var earlyReminderMinutes: Int?
    public var listName: String
    public var tags: [String]
    public var isFlagged: Bool
    public var isCompleted: Bool
    public var priority: SchedulePriority
    public var repeatInterval: Int
    public var repeatEndCount: Int
    public var additionalReminderMinutes: [Int]
    public var timeZoneIdentifier: String?

    public init(
        id: UUID,
        createdAt: Date,
        updatedAt: Date,
        deletedAt: Date? = nil,
        isSoftDeleted: Bool = false,
        lastModifiedDeviceID: String,
        syncVersion: Int,
        lastSyncedVersion: Int,
        conflictResolutionTag: String? = nil,
        title: String,
        notes: String? = nil,
        urlString: String? = nil,
        scheduledDate: Date,
        isUrgent: Bool = false,
        repeatPattern: RepeatPattern = .never,
        repeatWeekdays: [Int] = [],
        excludedOccurrenceDates: [Date] = [],
        repeatEndOption: RepeatEndOption = .never,
        repeatEndDate: Date? = nil,
        alertDeliveryOption: AlertDeliveryOption = .push,
        alarmSoundOption: AlarmSoundOption = .default,
        alarmSnoozeEnabled: Bool = false,
        alarmSnoozeMinutes: Int = 10,
        earlyReminderMinutes: Int? = nil,
        listName: String = "Reminders",
        tags: [String] = [],
        isFlagged: Bool = false,
        isCompleted: Bool = false,
        priority: SchedulePriority = .none,
        repeatInterval: Int = 1,
        repeatEndCount: Int = 0,
        additionalReminderMinutes: [Int] = [],
        timeZoneIdentifier: String? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.isSoftDeleted = isSoftDeleted
        self.lastModifiedDeviceID = lastModifiedDeviceID
        self.syncVersion = syncVersion
        self.lastSyncedVersion = lastSyncedVersion
        self.conflictResolutionTag = conflictResolutionTag
        self.title = title
        self.notes = notes
        self.urlString = urlString
        self.scheduledDate = scheduledDate
        self.isUrgent = isUrgent
        self.repeatPattern = repeatPattern
        self.repeatWeekdays = repeatWeekdays
        self.excludedOccurrenceDates = excludedOccurrenceDates
        self.repeatEndOption = repeatEndOption
        self.repeatEndDate = repeatEndDate
        self.alertDeliveryOption = alertDeliveryOption
        self.alarmSoundOption = alarmSoundOption
        self.alarmSnoozeEnabled = alarmSnoozeEnabled
        self.alarmSnoozeMinutes = alarmSnoozeMinutes
        self.earlyReminderMinutes = earlyReminderMinutes
        self.listName = listName
        self.tags = tags
        self.isFlagged = isFlagged
        self.isCompleted = isCompleted
        self.priority = priority
        self.repeatInterval = repeatInterval
        self.repeatEndCount = repeatEndCount
        self.additionalReminderMinutes = additionalReminderMinutes
        self.timeZoneIdentifier = timeZoneIdentifier
    }
}

public struct ScheduleDelta: Codable, Equatable {
    public var scheduleID: String
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?
    public var isSoftDeleted: Bool
    public var lastModifiedDeviceID: String
    public var title: String
    public var notes: String?
    public var urlString: String?
    public var scheduledDate: Date
    public var isUrgent: Bool
    public var repeatPatternRaw: String
    public var repeatWeekdays: [Int]
    public var excludedOccurrenceDates: [Date]
    public var repeatEndOptionRaw: String
    public var repeatEndDate: Date?
    public var alertDeliveryRaw: String
    public var alarmSoundRaw: String
    public var alarmSnoozeEnabled: Bool
    public var alarmSnoozeMinutes: Int
    public var earlyReminderMinutes: Int?
    public var additionalReminderMinutes: [Int]
    public var timeZoneIdentifier: String?
    public var listName: String
    public var tags: [String]
    public var isFlagged: Bool
    public var isCompleted: Bool
    public var priorityRaw: Int
    public var repeatInterval: Int
    public var repeatEndCount: Int
    public var syncVersion: Int
    public var conflictResolutionTag: String?
    public var deviceID: String
    public var clientUpdatedAt: Date
    public var serverUpdatedAt: Date?

    public init(
        scheduleID: String,
        createdAt: Date,
        updatedAt: Date,
        deletedAt: Date? = nil,
        isSoftDeleted: Bool = false,
        lastModifiedDeviceID: String,
        title: String,
        notes: String? = nil,
        urlString: String? = nil,
        scheduledDate: Date,
        isUrgent: Bool = false,
        repeatPatternRaw: String = RepeatPattern.never.rawValue,
        repeatWeekdays: [Int] = [],
        excludedOccurrenceDates: [Date] = [],
        repeatEndOptionRaw: String = RepeatEndOption.never.rawValue,
        repeatEndDate: Date? = nil,
        alertDeliveryRaw: String = AlertDeliveryOption.push.rawValue,
        alarmSoundRaw: String = AlarmSoundOption.default.rawValue,
        alarmSnoozeEnabled: Bool = false,
        alarmSnoozeMinutes: Int = 10,
        earlyReminderMinutes: Int? = nil,
        additionalReminderMinutes: [Int] = [],
        timeZoneIdentifier: String? = nil,
        listName: String = "Reminders",
        tags: [String] = [],
        isFlagged: Bool = false,
        isCompleted: Bool = false,
        priorityRaw: Int = SchedulePriority.none.rawValue,
        repeatInterval: Int = 1,
        repeatEndCount: Int = 0,
        syncVersion: Int,
        conflictResolutionTag: String? = nil,
        deviceID: String,
        clientUpdatedAt: Date,
        serverUpdatedAt: Date? = nil
    ) {
        self.scheduleID = scheduleID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.isSoftDeleted = isSoftDeleted
        self.lastModifiedDeviceID = lastModifiedDeviceID
        self.title = title
        self.notes = notes
        self.urlString = urlString
        self.scheduledDate = scheduledDate
        self.isUrgent = isUrgent
        self.repeatPatternRaw = repeatPatternRaw
        self.repeatWeekdays = repeatWeekdays
        self.excludedOccurrenceDates = excludedOccurrenceDates
        self.repeatEndOptionRaw = repeatEndOptionRaw
        self.repeatEndDate = repeatEndDate
        self.alertDeliveryRaw = alertDeliveryRaw
        self.alarmSoundRaw = alarmSoundRaw
        self.alarmSnoozeEnabled = alarmSnoozeEnabled
        self.alarmSnoozeMinutes = alarmSnoozeMinutes
        self.earlyReminderMinutes = earlyReminderMinutes
        self.additionalReminderMinutes = additionalReminderMinutes
        self.timeZoneIdentifier = timeZoneIdentifier
        self.listName = listName
        self.tags = tags
        self.isFlagged = isFlagged
        self.isCompleted = isCompleted
        self.priorityRaw = priorityRaw
        self.repeatInterval = repeatInterval
        self.repeatEndCount = repeatEndCount
        self.syncVersion = syncVersion
        self.conflictResolutionTag = conflictResolutionTag
        self.deviceID = deviceID
        self.clientUpdatedAt = clientUpdatedAt
        self.serverUpdatedAt = serverUpdatedAt
    }
}

extension Date {
    public var startOfDay: Date {
        Calendar.current.startOfDay(for: self)
    }
}
