import Foundation

public struct JSONSerializationUtils {
    public static let iso8601WithFractionalSecondsFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    public static func jsonCompatibleValue(from value: Any, customTransform: ((Any) -> Any?)? = nil) -> Any? {
        if let custom = customTransform?(value) {
            return custom
        }

        switch value {
        case let date as Date:
            return iso8601WithFractionalSecondsFormatter.string(from: date)
        case let string as String:
            return string
        case let bool as Bool:
            return bool
        case let int as Int:
            return int
        case let double as Double:
            return double.isFinite ? double : nil
        case let number as NSNumber:
            return number
        case let array as [Any]:
            return array.map { element -> Any in
                if element is NSNull { return NSNull() }
                return jsonCompatibleValue(from: element, customTransform: customTransform) ?? NSNull()
            }
        case let dictionary as [String: Any]:
            var normalized: [String: Any] = [:]
            for (key, nestedValue) in dictionary {
                if nestedValue is NSNull {
                    normalized[key] = NSNull()
                } else if let mapped = jsonCompatibleValue(from: nestedValue, customTransform: customTransform) {
                    normalized[key] = mapped
                }
            }
            return normalized
        case is NSNull:
            return NSNull()
        default:
            return nil
        }
    }
}
