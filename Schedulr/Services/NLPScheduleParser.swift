import Foundation
#if canImport(NaturalLanguage)
import NaturalLanguage
#endif

/// Parses natural language input like "Remind me to call mom tomorrow at 3pm"
/// into structured schedule data.
struct NLPScheduleParser {
    struct ParsedSchedule {
        var title: String = ""
        var date: Date?
        var hasTime: Bool = false
        var priority: SchedulePriority = .none
        var tags: [String] = []
        var repeatPattern: RepeatPattern = .never
        var deliveryOption: AlertDeliveryOption?
        var earlyReminderMinutes: Int?
    }

    private struct LinguisticSignal {
        var nouns: [String] = []
        var verbs: [String] = []
        var keywords: [String] = []
    }

    private static let timeIndicatorRegexes: [NSRegularExpression] = {
        [
            #"\d{1,2}:\d{2}"#,
            #"\d{1,2}\.\d{2}"#,
            #"\d{1,2},\d{2}"#,
            #"\d{1,2}\s*(am|pm)"#,
            #"at\s+\d"#,
            #"noon"#,
            #"midnight"#,
            #"morning"#,
            #"afternoon"#,
            #"evening"#,
            #"night"#
        ].compactMap { try? NSRegularExpression(pattern: $0, options: .caseInsensitive) }
    }()

    private static let inDurationRegex = try? NSRegularExpression(
        pattern: #"in\s+(\d+)\s+(hour|minute|min|day|week)"#,
        options: .caseInsensitive
    )

    private static let explicitTimeRegex = try? NSRegularExpression(
        pattern: #"\b(?:at\s+)?(\d{1,2})(?:[:\.,](\d{2}))?\s*(am|pm)?\b|\b(noon|midnight)\b"#,
        options: .caseInsensitive
    )

    private static let earlyReminderRegex = try? NSRegularExpression(
        pattern: #"\b(?:with\s+)?(\d{1,3})\s*(minute|minutes|min|mins)\s*(?:early|eairly)\s*reminder\b|\b(?:with\s+)?(\d{1,3})\s*(minute|minutes|min|mins)\s*(?:early|eairly)\b"#,
        options: .caseInsensitive
    )

    private static let tagRegex = try? NSRegularExpression(pattern: #"#(\w+)"#)

    private static let titleCleanupRegexes: [NSRegularExpression] = {
        [
            #"\s*(?:at|@)\s+\d{1,2}(?::\d{2})?\s*(?:am|pm)?"#,
            #"\s*(?:at|@)\s+\d{1,2}(?:[:\.,]\d{2})?\s*(?:am|pm)?"#,
            #"\s*\b\d{1,2}(?:[:\.,]\d{2})\b"#,
            #"\s*\.\d{2}\b"#,
            #"\s*\b(?:tomorrow|today|tonight|next\s+week|next\s+month)\b"#,
            #"\s*\b(?:daily|weekly|monthly|yearly|every\s+day|every\s+week)\b"#,
            #"\s*(?:urgent|important|critical)"#,
            #"\s*(?:high|medium|low) priority"#,
            #"\s*(?:with\s+)?alarm\b"#,
            #"\s*(?:with\s+)?\d{1,3}\s*(?:minute|minutes|min|mins)\s*(?:early|eairly)\s*reminder\b"#,
            #"\s*(?:with\s+)?\d{1,3}\s*(?:minute|minutes|min|mins)\s*(?:early|eairly)\b"#,
            #"\s*#\w+"#,
            #"\s*!+"#
        ].compactMap { try? NSRegularExpression(pattern: $0, options: .caseInsensitive) }
    }()

    static func parse(_ input: String) -> ParsedSchedule {
        var result = ParsedSchedule()
        let lowered = input.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !lowered.isEmpty else { return result }
        let linguistic = extractLinguisticSignal(from: input)

        // Extract date/time using NSDataDetector
        let dateResult = extractDateTime(from: input)
        var resolvedDate = dateResult.date
        let explicitTime = extractExplicitTime(from: lowered)
        var hasTime = dateResult.hasTime || explicitTime != nil

        // Chrono.js local fallback parsing for richer natural-language date support.
        if resolvedDate == nil,
           let chrono = ChronoJSParser.parse(input)
        {
            resolvedDate = chrono.date
            hasTime = hasTime || chrono.hasTime
        }

        // Try relative date words if detector didn't find a date
        if resolvedDate == nil {
            resolvedDate = parseRelativeDate(from: lowered)
            if resolvedDate != nil {
                hasTime = hasTime || parseHasExplicitTime(from: lowered)
            }
        }

        if resolvedDate == nil, explicitTime != nil {
            resolvedDate = Date()
        }

        if let baseDate = resolvedDate,
           let explicitTime,
           !dateResult.hasTime
        {
            resolvedDate = merge(baseDate: baseDate, time: explicitTime)
        }

        if !hasTime,
           let normalizedBase = resolvedDate
        {
            resolvedDate = Calendar.current.startOfDay(for: normalizedBase)
        }

        result.date = resolvedDate
        result.hasTime = hasTime

        // Extract priority
        result.priority = extractPriority(from: lowered, linguistic: linguistic)

        // Extract repeat pattern
        result.repeatPattern = extractRepeatPattern(from: lowered)

        // Extract delivery option
        result.deliveryOption = extractDeliveryOption(from: lowered)

        // Extract early reminder
        result.earlyReminderMinutes = extractEarlyReminderMinutes(from: lowered)

        // Extract tags (#tag syntax)
        result.tags = extractTags(from: input, linguistic: linguistic)

        // Build title — remove detected metadata from the input
        result.title = buildTitle(from: input, dateRange: dateResult.range, linguistic: linguistic)

        return result
    }

    // MARK: - Date/Time Extraction

    private struct DateTimeResult {
        var date: Date?
        var hasTime: Bool = false
        var range: Range<String.Index>?
    }

    private static func extractDateTime(from text: String) -> DateTimeResult {
        var result = DateTimeResult()

        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) else {
            return result
        }

        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = detector.matches(in: text, options: [], range: nsRange)

        for match in matches {
            guard let date = match.date,
                  let range = Range(match.range, in: text)
            else { continue }

            result.date = date
            result.range = range

            // Check if the match includes time component
            result.hasTime = match.duration == 0 && hasTimeIndicator(in: String(text[range]))
            break
        }

        return result
    }

    private static func hasTimeIndicator(in text: String) -> Bool {
        let lowered = text.lowercased()
        let range = NSRange(lowered.startIndex..<lowered.endIndex, in: lowered)
        return timeIndicatorRegexes.contains { regex in
            regex.firstMatch(in: lowered, options: [], range: range) != nil
        }
    }

    private static func parseRelativeDate(from text: String) -> Date? {
        let calendar = Calendar.current
        let now = Date()

        if text.contains("today") {
            return now
        }
        if text.contains("tomorrow") {
            return calendar.date(byAdding: .day, value: 1, to: now)
        }
        if text.contains("day after tomorrow") {
            return calendar.date(byAdding: .day, value: 2, to: now)
        }
        if text.contains("next week") {
            return calendar.date(byAdding: .weekOfYear, value: 1, to: now)
        }
        if text.contains("next month") {
            return calendar.date(byAdding: .month, value: 1, to: now)
        }

        // "next Monday", "next Tuesday", etc.
        let weekdays = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]
        for (index, dayName) in weekdays.enumerated() {
            if text.contains("next \(dayName)") {
                let targetWeekday = index + 1 // Calendar.component uses 1=Sun, 7=Sat
                let currentWeekday = calendar.component(.weekday, from: now)
                var daysAhead = targetWeekday - currentWeekday
                if daysAhead <= 0 { daysAhead += 7 }
                return calendar.date(byAdding: .day, value: daysAhead, to: now)
            }
            if text.contains(dayName) {
                let targetWeekday = index + 1
                let currentWeekday = calendar.component(.weekday, from: now)
                var daysAhead = targetWeekday - currentWeekday
                if daysAhead <= 0 { daysAhead += 7 }
                return calendar.date(byAdding: .day, value: daysAhead, to: now)
            }
        }

        // "in X hours/minutes/days"
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        if let match = inDurationRegex?.firstMatch(in: text, options: [], range: nsRange),
           let matchRange = Range(match.range, in: text)
        {
            let matched = String(text[matchRange])
            let parts = matched.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            if parts.count >= 3, let value = Int(parts[1]) {
                let unit = parts[2].lowercased()
                switch unit {
                case "minute", "min", "minutes", "mins":
                    return calendar.date(byAdding: .minute, value: value, to: now)
                case "hour", "hours":
                    return calendar.date(byAdding: .hour, value: value, to: now)
                case "day", "days":
                    return calendar.date(byAdding: .day, value: value, to: now)
                case "week", "weeks":
                    return calendar.date(byAdding: .weekOfYear, value: value, to: now)
                default:
                    break
                }
            }
        }

        return nil
    }

    private static func parseHasExplicitTime(from text: String) -> Bool {
        hasTimeIndicator(in: text)
    }

    private static func extractExplicitTime(from text: String) -> DateComponents? {
        guard let explicitTimeRegex else { return nil }
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = explicitTimeRegex.firstMatch(in: text, options: [], range: nsRange) else {
            return nil
        }

        if let noonRange = Range(match.range(at: 4), in: text), !noonRange.isEmpty {
            let keyword = text[noonRange].lowercased()
            if keyword == "noon" {
                return DateComponents(hour: 12, minute: 0)
            }
            if keyword == "midnight" {
                return DateComponents(hour: 0, minute: 0)
            }
        }

        guard let hourRange = Range(match.range(at: 1), in: text),
              let rawHour = Int(text[hourRange])
        else {
            return nil
        }

        let minute: Int
        if let minuteRange = Range(match.range(at: 2), in: text), !minuteRange.isEmpty {
            minute = Int(text[minuteRange]) ?? 0
        } else {
            minute = 0
        }

        var hour = rawHour
        if let meridiemRange = Range(match.range(at: 3), in: text), !meridiemRange.isEmpty {
            let meridiem = text[meridiemRange].lowercased()
            if meridiem == "pm" && hour < 12 {
                hour += 12
            }
            if meridiem == "am" && hour == 12 {
                hour = 0
            }
        }

        guard (0...23).contains(hour), (0...59).contains(minute) else {
            return nil
        }

        return DateComponents(hour: hour, minute: minute)
    }

    private static func merge(baseDate: Date, time: DateComponents) -> Date {
        var calendar = Calendar.current
        calendar.timeZone = .current
        var merged = calendar.dateComponents([.year, .month, .day], from: baseDate)
        merged.hour = time.hour
        merged.minute = time.minute
        merged.second = 0
        return calendar.date(from: merged) ?? baseDate
    }

    // MARK: - Priority Extraction

    private static func extractPriority(from text: String, linguistic: LinguisticSignal) -> SchedulePriority {
        if text.contains("urgent") || text.contains("critical") || text.contains("important") || text.contains("high priority") {
            return .high
        }
        if text.contains("medium priority") {
            return .medium
        }
        if text.contains("low priority") {
            return .low
        }
        // Exclamation marks indicate urgency
        let exclamationCount = text.filter { $0 == "!" }.count
        if exclamationCount >= 3 { return .high }
        if exclamationCount >= 2 { return .medium }
        if exclamationCount >= 1 { return .low }

        // NLTagger-derived keyword signal can still infer intent when explicit
        // "priority" wording is missing.
        let signal = Set(linguistic.keywords)
        if !signal.isDisjoint(with: ["deadline", "asap", "critical", "urgent"]) {
            return .high
        }
        if !signal.isDisjoint(with: ["review", "meeting", "appointment", "call"]) {
            return .medium
        }
        return .none
    }

    // MARK: - Repeat Pattern Extraction

    private static func extractRepeatPattern(from text: String) -> RepeatPattern {
        if text.contains("every day") || text.contains("daily") {
            return .daily
        }
        if text.contains("every week") || text.contains("weekly") {
            return .weekly
        }
        if text.contains("every month") || text.contains("monthly") {
            return .monthly
        }
        if text.contains("every year") || text.contains("yearly") || text.contains("annually") {
            return .yearly
        }
        if text.contains("weekday") || text.contains("mon-fri") || text.contains("monday to friday") {
            return .weekdays
        }
        if text.contains("biweekly") || text.contains("every two weeks") || text.contains("every other week") {
            return .biweekly
        }
        return .never
    }

    // MARK: - Delivery Option Extraction

    private static func extractDeliveryOption(from text: String) -> AlertDeliveryOption? {
        if containsWholeWord("alarm", in: text) || containsWholeWord("alart", in: text) {
            return .alarm
        }
        if containsWholeWord("push", in: text) {
            return .push
        }
        return nil
    }

    private static func containsWholeWord(_ word: String, in text: String) -> Bool {
        let pattern = "\\b\(NSRegularExpression.escapedPattern(for: word))\\b"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return false
        }
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.firstMatch(in: text, options: [], range: nsRange) != nil
    }

    private static func extractEarlyReminderMinutes(from text: String) -> Int? {
        guard let earlyReminderRegex else { return nil }
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = earlyReminderRegex.firstMatch(in: text, options: [], range: nsRange) else {
            return nil
        }

        let captureGroups = [1, 3]
        for group in captureGroups {
            if let range = Range(match.range(at: group), in: text),
               !range.isEmpty,
               let minutes = Int(text[range]),
               (1...1439).contains(minutes)
            {
                return minutes
            }
        }

        return nil
    }

    // MARK: - Tag Extraction

    private static func extractTags(from text: String, linguistic: LinguisticSignal) -> [String] {
        guard let regex = tagRegex else { return [] }
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = regex.matches(in: text, options: [], range: nsRange)
        var explicit = matches.compactMap { match -> String? in
            guard let range = Range(match.range(at: 1), in: text) else { return nil }
            return String(text[range]).lowercased()
        }

        // Add lightweight inferred tags from noun keywords when user did not
        // provide #tags explicitly.
        if explicit.isEmpty {
            explicit = inferTags(from: linguistic)
        }

        return Array(NSOrderedSet(array: explicit)) as? [String] ?? explicit
    }

    // MARK: - Title Builder

    private static func buildTitle(from input: String, dateRange: Range<String.Index>?, linguistic: LinguisticSignal) -> String {
        var title = input

        // Remove detector-matched date/time from the original string before any
        // prefix trimming to keep ranges aligned.
        if let dateRange,
           dateRange.lowerBound >= title.startIndex,
           dateRange.upperBound <= title.endIndex
        {
            title.removeSubrange(dateRange)
        }

        // Remove common prefixes
        let prefixes = ["remind me to ", "remind me ", "schedule ", "add ", "create ", "set ", "new "]
        for prefix in prefixes {
            if title.lowercased().hasPrefix(prefix) {
                title = String(title.dropFirst(prefix.count))
                break
            }
        }

        // Remove time-related phrases
        for regex in titleCleanupRegexes {
            let nsRange = NSRange(title.startIndex..<title.endIndex, in: title)
            title = regex.stringByReplacingMatches(in: title, options: [], range: nsRange, withTemplate: "")
        }

        title = title
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Remove dangling connector words left after metadata stripping.
        title = title.replacingOccurrences(
            of: #"\b(and|to|for|with|at|on|in|by)\b\s*$"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )

        if title.isEmpty || title.split(separator: " ").count <= 1 {
            let semantic = semanticTitle(from: linguistic)
            if !semantic.isEmpty {
                title = semantic
            }
        }

        title = title.trimmingCharacters(in: .whitespacesAndNewlines)

        // Capitalize first letter
        if let first = title.first {
            title = String(first).uppercased() + title.dropFirst()
        }

        return title.isEmpty ? input : title
    }

    private static func inferTags(from linguistic: LinguisticSignal) -> [String] {
        let nouns = Array(linguistic.nouns.prefix(3))
        var inferred: [String] = []

        for noun in nouns {
            switch noun {
            case "meeting", "report", "project", "client", "office":
                inferred.append("work")
            case "doctor", "dentist", "gym", "medicine", "therapy":
                inferred.append("health")
            case "bill", "invoice", "tax", "payment", "bank":
                inferred.append("finance")
            case "family", "birthday", "dinner", "friend":
                inferred.append("personal")
            default:
                break
            }
        }

        return Array(NSOrderedSet(array: inferred)) as? [String] ?? inferred
    }

    private static func semanticTitle(from linguistic: LinguisticSignal) -> String {
        let verb = linguistic.verbs.first?.capitalized ?? ""
        let nouns = linguistic.nouns.prefix(2).map { $0.capitalized }
        let nounPhrase = nouns.joined(separator: " ")

        if !verb.isEmpty && !nounPhrase.isEmpty {
            return "\(verb) \(nounPhrase)"
        }
        if !nounPhrase.isEmpty {
            return nounPhrase
        }
        return ""
    }

    private static func extractLinguisticSignal(from text: String) -> LinguisticSignal {
        #if canImport(NaturalLanguage)
        var signal = LinguisticSignal()
        let lowercased = text.lowercased()

        let tagger = NLTagger(tagSchemes: [.lexicalClass, .lemma])
        tagger.string = lowercased

        let range = lowercased.startIndex..<lowercased.endIndex
        let options: NLTagger.Options = [.omitWhitespace, .omitPunctuation]

        tagger.enumerateTags(in: range, unit: .word, scheme: .lexicalClass, options: options) { tag, tokenRange in
            let token = String(lowercased[tokenRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard token.count > 1 else { return true }

            let lemma = tagger.tag(at: tokenRange.lowerBound, unit: .word, scheme: .lemma).0?.rawValue ?? token
            let normalized = lemma.lowercased()

            if isStopWord(normalized) { return true }

            switch tag {
            case .some(.noun), .some(.personalName), .some(.placeName), .some(.organizationName):
                signal.nouns.append(normalized)
            case .some(.verb):
                signal.verbs.append(normalized)
            case .some(.adjective):
                signal.keywords.append(normalized)
            default:
                signal.keywords.append(normalized)
            }
            return true
        }

        signal.nouns = Array(NSOrderedSet(array: signal.nouns)) as? [String] ?? signal.nouns
        signal.verbs = Array(NSOrderedSet(array: signal.verbs)) as? [String] ?? signal.verbs
        signal.keywords = Array(NSOrderedSet(array: signal.keywords)) as? [String] ?? signal.keywords
        return signal
        #else
        return LinguisticSignal()
        #endif
    }

    private static func isStopWord(_ token: String) -> Bool {
        let stopWords: Set<String> = [
            "a", "an", "the", "to", "for", "with", "at", "on", "in", "by", "of", "and", "or",
            "me", "my", "is", "are", "be", "this", "that", "tomorrow", "today", "tonight",
            "am", "pm", "minute", "minutes", "min", "mins", "priority", "reminder"
        ]
        return stopWords.contains(token)
    }
}
