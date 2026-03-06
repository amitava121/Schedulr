import Foundation

enum RepeatPattern: String, Codable, CaseIterable, Identifiable {
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

    var id: String { rawValue }

    var displayName: String { rawValue }

    /// Whether this pattern uses the `repeatInterval` field on Schedule.
    var usesCustomInterval: Bool {
        switch self {
        case .everyNDays, .everyNWeeks, .everyNMonths: return true
        default: return false
        }
    }

    /// Whether this pattern lets the user pick specific weekdays.
    var usesWeekdaySelection: Bool {
        switch self {
        case .daily, .customWeekdays: return true
        default: return false
        }
    }

    var calendarComponent: Calendar.Component? {
        switch self {
        case .never: return nil
        case .daily, .weekdays, .customWeekdays: return .day
        case .weekly, .biweekly: return .weekOfYear
        case .monthly: return .month
        case .yearly: return .year
        case .everyNDays: return .day
        case .everyNWeeks: return .weekOfYear
        case .everyNMonths: return .month
        }
    }
}

enum RepeatEndOption: String, Codable, CaseIterable, Identifiable {
    case never = "Never"
    case onDate = "On Date"
    case afterCount = "After Count"

    var id: String { rawValue }

    var displayName: String { rawValue }
}
