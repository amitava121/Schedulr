import Foundation

public enum SnoozeChoice: Hashable, Identifiable {
    case preset(Int)
    case custom

    public var id: String {
        switch self {
        case .preset(let minutes): return "preset-\(minutes)"
        case .custom: return "custom"
        }
    }
}

public struct SnoozeLogic {
    public static func snoozeDisplayName(for choice: SnoozeChoice) -> String {
        switch choice {
        case .preset(let minutes):
            return "\(minutes) min"
        case .custom:
            return "Custom Time"
        }
    }
}
