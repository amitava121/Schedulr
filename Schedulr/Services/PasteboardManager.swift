import Foundation
#if canImport(UIKit)
import UIKit
import Combine
#endif

/// Monitors the system pasteboard for quick-add text patterns (dates, times, schedule intent).
@Observable
final class PasteboardManager {
    static let shared = PasteboardManager()

    private static let scheduleDetectionRegexes: [NSRegularExpression] = {
        let patterns = [
            "\\d{1,2}:\\d{2}",
            "\\d{1,2}\\s*(am|pm)",
            "at\\s+\\d",
            "tomorrow",
            "today",
            "tonight",
            "next\\s+(monday|tuesday|wednesday|thursday|friday|saturday|sunday|week|month)",
            "remind",
            "meeting",
            "appointment",
            "call\\s+",
            "schedule"
        ]
        return patterns.compactMap { try? NSRegularExpression(pattern: $0, options: .caseInsensitive) }
    }()

    private static let dateDetector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue)

    var detectedText: String?
    var hasQuickAddContent: Bool { detectedText != nil }

    private var lastChangeCount: Int = 0
    #if canImport(UIKit)
    private var timer: Timer?
    #endif

    private init() {}

    // MARK: - Monitoring

    func startMonitoring() {
        #if canImport(UIKit)
        let pb = UIPasteboard.general
        lastChangeCount = pb.changeCount
        detectedText = pb.hasStrings ? "Pending clipboard content..." : nil
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.checkPasteboard()
        }
        #endif
    }

    func stopMonitoring() {
        #if canImport(UIKit)
        timer?.invalidate()
        timer = nil
        #endif
    }

    func dismissDetection() {
        detectedText = nil
    }

    // MARK: - Quick Add from Pasteboard

    func parseAndCreateSchedule() -> NLPScheduleParser.ParsedSchedule? {
        guard let text = detectedText else { return nil }
        let result = NLPScheduleParser.parse(text)
        detectedText = nil
        return result
    }

    // MARK: - Check

    #if canImport(UIKit)
    private func checkPasteboard() {
        let pb = UIPasteboard.general
        guard pb.changeCount != lastChangeCount else { return }
        lastChangeCount = pb.changeCount

        // iOS 16+: Instead of reading pb.string directly (which triggers the prompt),
        // we just check if it has *any* strings.
        if pb.hasStrings {
            // Because we can't reliably read the string silently, we just flag
            // that *some* text is available. Tapping quick-add will do the actual read.
            detectedText = "Pending clipboard content..."
        } else {
            detectedText = nil
        }
    }
    #endif

    /// Parses the actual clipboard string. This is called *after* user interaction
    /// to avoid incessant background permission prompts on iOS 16+.
    func parseAndCreateScheduleFromActualPasteboard() -> NLPScheduleParser.ParsedSchedule? {
        #if canImport(UIKit)
        let pb = UIPasteboard.general
        guard let text = pb.string, !text.isEmpty else { return nil }
        let result = NLPScheduleParser.parse(text)
        detectedText = nil
        return result
        #else
        return nil
        #endif
    }

    /// Heuristic: does this text contain date/time-like content?
    private func looksLikeScheduleText(_ text: String) -> Bool {
        let lower = text.lowercased()
        let trimmed = lower.trimmingCharacters(in: .whitespacesAndNewlines)

        // Too long or too short
        guard trimmed.count >= 5 && trimmed.count <= 500 else { return false }

        let range = NSRange(trimmed.startIndex..., in: trimmed)

        for regex in Self.scheduleDetectionRegexes {
            if regex.firstMatch(in: trimmed, range: range) != nil {
                return true
            }
        }

        // Check with NSDataDetector
        if Self.dateDetector?.firstMatch(in: trimmed, range: range) != nil {
            return true
        }

        return false
    }
}
