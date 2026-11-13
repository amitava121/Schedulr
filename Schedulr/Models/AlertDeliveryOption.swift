import Foundation
import SchedulrLogic

typealias AlertDeliveryOption = SchedulrLogic.AlertDeliveryOption

extension SchedulrLogic.AlertDeliveryOption: @retroactive CaseIterable, @retroactive Identifiable {
    public static var allCases: [Self] { [.push, .alarm] }
    public var id: String { rawValue }

    var displayName: String {
        switch self {
        case .push:
            return "Push"
        case .alarm:
            return "Alarm"
        }
    }
}
