import SwiftUI
import SchedulrLogic

typealias SchedulePriority = SchedulrLogic.SchedulePriority

extension SchedulrLogic.SchedulePriority {

    var displayName: String {
        switch self {
        case .none: return "None"
        case .low: return "Low"
        case .medium: return "Medium"
        case .high: return "High"
        }
    }

    var tintColor: Color {
        AppTheme.priorityColor(self)
    }

    var iconName: String {
        switch self {
        case .none: return "minus"
        case .low: return "exclamationmark"
        case .medium: return "exclamationmark.2"
        case .high: return "exclamationmark.3"
        }
    }
}
