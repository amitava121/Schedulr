import Foundation

enum AlertDeliveryOption: String, Codable, CaseIterable, Identifiable {
    case push
    case alarm

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .push:
            return "Push"
        case .alarm:
            return "Alarm"
        }
    }
}
