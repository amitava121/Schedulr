import Foundation

// MARK: - Bangla Date Cache
private final class BanglaDateCache {
    static let shared = BanglaDateCache()
    private var cache: [Date: Int] = [:]
    private let maxSize = 100
    private let lock = NSLock()
    
    func get(_ date: Date) -> Int? {
        lock.lock()
        defer { lock.unlock() }
        return cache[date]
    }
    
    func set(_ date: Date, value: Int) {
        lock.lock()
        defer { lock.unlock() }
        // Simple LRU: if at capacity, remove oldest entries
        if cache.count >= maxSize && cache[date] == nil {
            let keysToRemove = cache.keys.prefix(cache.count - maxSize + 1)
            for key in keysToRemove {
                cache.removeValue(forKey: key)
            }
        }
        cache[date] = value
    }
}

extension Date {
    var startOfDay: Date {
        Calendar.current.startOfDay(for: self)
    }

    var endOfDay: Date {
        Calendar.current.date(bySettingHour: 23, minute: 59, second: 59, of: self) ?? self
    }

    var startOfWeek: Date {
        var calendar = Calendar.current
        calendar.firstWeekday = AppSettings.shared.firstDayOfWeek
        let dayStart = calendar.startOfDay(for: self)
        let weekday = calendar.component(.weekday, from: dayStart)
        let daysToSubtract = (weekday - calendar.firstWeekday + 7) % 7
        return calendar.date(byAdding: .day, value: -daysToSubtract, to: dayStart) ?? dayStart
    }

    var weekDates: [Date] {
        let start = startOfWeek
        var calendar = Calendar.current
        calendar.firstWeekday = AppSettings.shared.firstDayOfWeek
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    var shortDayName: String {
        DateFormatters.shortDayName.string(from: self)
    }

    var dayNumber: String {
        DateFormatters.dayNumber.string(from: self)
    }

    var isToday: Bool {
        Calendar.current.isDateInToday(self)
    }

    var monthYearString: String {
        DateFormatters.monthYear.string(from: self)
    }

    var fullDayString: String {
        DateFormatters.fullDay.string(from: self)
    }

    func isSameDay(as other: Date) -> Bool {
        Calendar.current.isDate(self, inSameDayAs: other)
    }

    func mergingTime(from sourceDate: Date) -> Date {
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day], from: self)
        let time = calendar.dateComponents([.hour, .minute, .second], from: sourceDate)
        components.hour = time.hour
        components.minute = time.minute
        components.second = time.second ?? 0
        return calendar.date(from: components) ?? sourceDate
    }

    var banglaDate: Int {
        let cacheKey = self.startOfDay
        // Check cache first
        if let cached = BanglaDateCache.shared.get(cacheKey) {
            return cached
        }
        
        // Compute and cache the result
        let calendar = Calendar.current
        let dayOfYear = calendar.ordinality(of: .day, in: .year, for: self) ?? 1
        let daysInYear = calendar.range(of: .day, in: .year, for: self)?.count ?? 365
        let bengaliDayInYear = ((dayOfYear - 1 + 79) % daysInYear) + 1
        let result = ((bengaliDayInYear - 1) % 30) + 1
        
        BanglaDateCache.shared.set(cacheKey, value: result)
        return result
    }

    var isBanglaMonthStart: Bool {
        banglaDate <= 2
    }
}

private enum DateFormatters {
    static let shortDayName: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.setLocalizedDateFormatFromTemplate("EEE")
        return formatter
    }()

    static let dayNumber: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.setLocalizedDateFormatFromTemplate("d")
        return formatter
    }()

    static let monthYear: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.setLocalizedDateFormatFromTemplate("MMMM yyyy")
        return formatter
    }()

    static let fullDay: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.setLocalizedDateFormatFromTemplate("EEEE, MMMM d")
        return formatter
    }()
}
