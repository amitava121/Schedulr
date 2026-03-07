import Foundation
import JavaScriptCore

/// Local offline date parsing bridge backed by embedded Chrono.js.
enum ChronoJSParser {
    struct ParsedDate {
        let date: Date
        let hasTime: Bool
    }

    private static let parserFunctionName = "schedulrChronoParse"

    static func parse(_ text: String, referenceDate: Date = Date()) -> ParsedDate? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        guard let context = JSContext() else { return nil }
        context.exceptionHandler = { _, _ in }

        context.evaluateScript(ChronoJSScript.source)
        context.evaluateScript(wrapperScript)

        guard let parser = context.objectForKeyedSubscript(parserFunctionName) else {
            return nil
        }

        let referenceISO = isoFormatter.string(from: referenceDate)
        guard let result = parser.call(withArguments: [trimmed, referenceISO]),
              let json = result.toString(),
              let data = json.data(using: .utf8)
        else {
            return nil
        }

        guard let decoded = try? JSONDecoder().decode(ChronoOutput.self, from: data),
              let dateText = decoded.iso,
              let date = parseISO(dateText)
        else {
            return nil
        }

        return ParsedDate(date: date, hasTime: decoded.hasTime ?? false)
    }

    private struct ChronoOutput: Decodable {
        let iso: String?
        let hasTime: Bool?
    }

    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static func parseISO(_ text: String) -> Date? {
        if let precise = isoFormatter.date(from: text) {
            return precise
        }

        let fallback = ISO8601DateFormatter()
        fallback.formatOptions = [.withInternetDateTime]
        return fallback.date(from: text)
    }

    private static let wrapperScript = #"""
    function schedulrChronoParse(input, referenceISO) {
      try {
        if (typeof chrono === 'undefined') {
          return JSON.stringify({ iso: null, hasTime: false });
        }

        const referenceDate = referenceISO ? new Date(referenceISO) : new Date();
        const results = chrono.parse(input, referenceDate, { forwardDate: true });
        if (!results || results.length === 0) {
          return JSON.stringify({ iso: null, hasTime: false });
        }

        const first = results[0];
        const start = first.start;
        if (!start) {
          return JSON.stringify({ iso: null, hasTime: false });
        }

        const date = start.date();
        const hasTime = !!(start.isCertain && (start.isCertain('hour') || start.isCertain('minute')));
        return JSON.stringify({ iso: date.toISOString(), hasTime: hasTime });
      } catch (e) {
        return JSON.stringify({ iso: null, hasTime: false });
      }
    }
    """#
}
