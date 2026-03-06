import Foundation
#if canImport(NaturalLanguage)
import NaturalLanguage
#endif

/// On-device smart suggestions for schedule creation and management.
/// Uses heuristics, pattern recognition, and NaturalLanguage framework.
enum SmartSuggestionsService {

    // MARK: - Time Suggestions

    /// Suggests optimal times for a new schedule based on existing patterns.
    static func suggestTimes(
        for title: String,
        existingSchedules: [Schedule],
        preferredDate: Date = Date()
    ) -> [Date] {
        var suggestions: [Date] = []
        let calendar = Calendar.current

        // 1. Find similar schedules and suggest same time
        let similarSchedules = findSimilarSchedules(title: title, in: existingSchedules)
        let commonTimes = extractCommonTimes(from: similarSchedules)
        for time in commonTimes.prefix(2) {
            if let suggested = calendar.date(
                bySettingHour: time.hour,
                minute: time.minute,
                second: 0,
                of: preferredDate
            ) {
                suggestions.append(suggested)
            }
        }

        // 2. Keyword-based suggestions
        let keywordTimes = suggestTimeFromKeywords(in: title, on: preferredDate)
        suggestions.append(contentsOf: keywordTimes)

        // 3. Find free slots (gap-based)
        let freeSlots = findFreeSlots(on: preferredDate, existingSchedules: existingSchedules)
        suggestions.append(contentsOf: freeSlots.prefix(2))

        // Deduplicate and sort
        let unique = Array(Set(suggestions.map { calendar.dateComponents([.year, .month, .day, .hour, .minute], from: $0) }))
            .compactMap { calendar.date(from: $0) }
            .sorted()

        return Array(unique.prefix(5))
    }

    // MARK: - Priority Suggestions

    /// Suggests priority based on title keywords and patterns.
    static func suggestPriority(for title: String, existingSchedules: [Schedule]) -> SchedulePriority {
        let lower = title.lowercased()

        // Keyword-based
        let urgentKeywords = ["urgent", "asap", "emergency", "critical", "deadline", "important", "final"]
        let mediumKeywords = ["meeting", "appointment", "call", "review", "follow up", "check"]
        let lowKeywords = ["maybe", "optional", "sometime", "whenever", "idea", "thought"]

        if urgentKeywords.contains(where: { lower.contains($0) }) { return .high }
        if lowKeywords.contains(where: { lower.contains($0) }) { return .low }
        if mediumKeywords.contains(where: { lower.contains($0) }) { return .medium }

        // Pattern-based: what priority do similar past schedules have?
        let similar = findSimilarSchedules(title: title, in: existingSchedules)
        if !similar.isEmpty {
            let priorityCounts = Dictionary(grouping: similar, by: \.priority)
                .mapValues(\.count)
                .sorted { $0.value > $1.value }
            if let top = priorityCounts.first {
                return top.key
            }
        }

        return .none
    }

    // MARK: - Tag Suggestions

    /// Suggests tags based on title content and existing tag patterns.
    static func suggestTags(for title: String, existingSchedules: [Schedule]) -> [String] {
        var suggestions: [String] = []
        let lower = title.lowercased()

        // Keyword → tag mapping
        let tagKeywords: [String: [String]] = [
            "work": ["meeting", "office", "project", "deadline", "presentation", "report", "client"],
            "health": ["doctor", "gym", "workout", "run", "medicine", "appointment", "dentist", "therapy"],
            "personal": ["birthday", "anniversary", "family", "friend", "dinner", "lunch", "party"],
            "finance": ["pay", "bill", "tax", "invoice", "budget", "bank", "transfer"],
            "travel": ["flight", "hotel", "trip", "travel", "airport", "booking", "visa"],
            "study": ["study", "class", "lecture", "exam", "homework", "assignment", "course", "learn"],
            "shopping": ["buy", "shop", "order", "groceries", "pickup"]
        ]

        for (tag, keywords) in tagKeywords {
            if keywords.contains(where: { lower.contains($0) }) {
                suggestions.append(tag)
            }
        }

        // Pattern-based: what tags do similar schedules use?
        let similar = findSimilarSchedules(title: title, in: existingSchedules)
        let existingTags = similar.flatMap(\.tags)
        let tagCounts = Dictionary(grouping: existingTags, by: { $0 })
            .mapValues(\.count)
            .sorted { $0.value > $1.value }

        for (tag, _) in tagCounts.prefix(3) {
            if !suggestions.contains(tag) {
                suggestions.append(tag)
            }
        }

        return Array(suggestions.prefix(5))
    }

    // MARK: - Calendar Suggestions

    /// Suggests which calendar to use based on title and patterns.
    static func suggestCalendar(for title: String, existingSchedules: [Schedule]) -> String? {
        let similar = findSimilarSchedules(title: title, in: existingSchedules)
        let calendarCounts = Dictionary(grouping: similar, by: \.listName)
            .mapValues(\.count)
            .sorted { $0.value > $1.value }

        return calendarCounts.first?.key
    }

    // MARK: - Repeat Pattern Suggestions

    /// Suggests repeat pattern based on title keywords.
    static func suggestRepeatPattern(for title: String) -> RepeatPattern {
        let lower = title.lowercased()

        if lower.contains("every day") || lower.contains("daily") { return .daily }
        if lower.contains("every week") || lower.contains("weekly") { return .weekly }
        if lower.contains("every month") || lower.contains("monthly") { return .monthly }
        if lower.contains("every year") || lower.contains("yearly") || lower.contains("annual") { return .yearly }
        if lower.contains("weekday") || lower.contains("mon-fri") || lower.contains("workday") { return .weekdays }
        if lower.contains("biweekly") || lower.contains("every other week") || lower.contains("fortnightly") { return .biweekly }

        return .never
    }

    // MARK: - Complete Suggestion Bundle

    struct SuggestionBundle {
        let suggestedTimes: [Date]
        let suggestedPriority: SchedulePriority
        let suggestedTags: [String]
        let suggestedCalendar: String?
        let suggestedRepeatPattern: RepeatPattern
    }

    static func fullSuggestions(
        for title: String,
        existingSchedules: [Schedule],
        preferredDate: Date = Date()
    ) -> SuggestionBundle {
        SuggestionBundle(
            suggestedTimes: suggestTimes(for: title, existingSchedules: existingSchedules, preferredDate: preferredDate),
            suggestedPriority: suggestPriority(for: title, existingSchedules: existingSchedules),
            suggestedTags: suggestTags(for: title, existingSchedules: existingSchedules),
            suggestedCalendar: suggestCalendar(for: title, existingSchedules: existingSchedules),
            suggestedRepeatPattern: suggestRepeatPattern(for: title)
        )
    }

    // MARK: - Private Helpers

    private static func findSimilarSchedules(title: String, in schedules: [Schedule]) -> [Schedule] {
        let words = title.lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { $0.count > 2 } // Skip very short words

        guard !words.isEmpty else { return [] }

        return schedules.filter { schedule in
            let scheduleTitle = schedule.title.lowercased()
            let matchCount = words.filter { scheduleTitle.contains($0) }.count
            return matchCount >= max(1, words.count / 2)
        }
    }

    private struct TimeOfDay: Hashable {
        let hour: Int
        let minute: Int
    }

    private static func extractCommonTimes(from schedules: [Schedule]) -> [TimeOfDay] {
        let calendar = Calendar.current
        let times = schedules.map { schedule -> TimeOfDay in
            let components = calendar.dateComponents([.hour, .minute], from: schedule.scheduledDate)
            return TimeOfDay(hour: components.hour ?? 9, minute: components.minute ?? 0)
        }

        return Dictionary(grouping: times, by: { $0 })
            .mapValues(\.count)
            .sorted { $0.value > $1.value }
            .map(\.key)
    }

    private static func suggestTimeFromKeywords(in title: String, on date: Date) -> [Date] {
        let lower = title.lowercased()
        let calendar = Calendar.current
        var suggestions: [Date] = []

        let timeMappings: [(keywords: [String], hour: Int, minute: Int)] = [
            (["breakfast", "morning"], 8, 0),
            (["lunch"], 12, 30),
            (["afternoon"], 14, 0),
            (["evening", "dinner"], 18, 30),
            (["night", "bedtime"], 22, 0),
            (["standup", "stand-up", "scrum"], 9, 30),
            (["meeting"], 10, 0),
        ]

        for mapping in timeMappings {
            if mapping.keywords.contains(where: { lower.contains($0) }) {
                if let date = calendar.date(bySettingHour: mapping.hour, minute: mapping.minute, second: 0, of: date) {
                    suggestions.append(date)
                }
            }
        }

        return suggestions
    }

    private static func findFreeSlots(on date: Date, existingSchedules: [Schedule]) -> [Date] {
        let calendar = Calendar.current
        let startHour = 8
        let endHour = 20

        // Get schedules for this day
        let dayStart = calendar.startOfDay(for: date)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return [] }

        let daySchedules = existingSchedules.filter { s in
            s.scheduledDate >= dayStart && s.scheduledDate < dayEnd
        }.sorted { $0.scheduledDate < $1.scheduledDate }

        let occupiedHours = Set(daySchedules.map { calendar.component(.hour, from: $0.scheduledDate) })

        var freeSlots: [Date] = []
        for hour in startHour..<endHour {
            if !occupiedHours.contains(hour) {
                if let slot = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: date) {
                    freeSlots.append(slot)
                }
            }
        }

        return freeSlots
    }
}
