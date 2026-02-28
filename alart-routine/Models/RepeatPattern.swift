import Foundation

enum RepeatPattern: String, Codable, CaseIterable, Identifiable {
    case never = "Never"
    case daily = "Daily"
    case weekly = "Weekly"
    case monthly = "Monthly"
    case yearly = "Yearly"

    var id: String { rawValue }

    var displayName: String { rawValue }

    var calendarComponent: Calendar.Component? {
        switch self {
        case .never: return nil
        case .daily: return .day
        case .weekly: return .weekOfYear
        case .monthly: return .month
        case .yearly: return .year
        }
    }
}

enum RepeatEndOption: String, Codable, CaseIterable, Identifiable {
    case never = "Never"
    case onDate = "On Date"

    var id: String { rawValue }

    var displayName: String { rawValue }
}
