import Foundation
import SchedulrLogic

typealias RepeatPattern = SchedulrLogic.RepeatPattern
typealias RepeatEndOption = SchedulrLogic.RepeatEndOption

extension SchedulrLogic.RepeatPattern {
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

extension SchedulrLogic.RepeatEndOption: @retroactive CaseIterable, @retroactive Identifiable {
    public static var allCases: [Self] { [.never, .onDate, .afterCount] }
    public var id: String { rawValue }

    var displayName: String { rawValue }
}
