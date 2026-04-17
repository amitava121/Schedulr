import Foundation

public struct WeekdaySelectionLogic {
    public static func isSelected(_ weekday: Int, in weekdays: [Int]) -> Bool {
        weekdays.contains(weekday)
    }

    public static func toggle(_ weekday: Int, in weekdays: [Int]) -> [Int] {
        guard (1...7).contains(weekday) else { return weekdays }

        var result = weekdays
        if let index = result.firstIndex(of: weekday) {
            guard result.count > 1 else { return result }
            result.remove(at: index)
        } else {
            result.append(weekday)
            result.sort()
        }

        return sanitize(result)
    }

    public static func sanitize(_ weekdays: [Int]) -> [Int] {
        let valid = Set(weekdays.filter { (1...7).contains($0) })
        return valid.isEmpty ? Array(1...7) : valid.sorted()
    }
}
