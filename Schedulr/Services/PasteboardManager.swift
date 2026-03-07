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
    private var consumedChangeCount: Int?
    #if canImport(UIKit)
    private var timer: Timer?
    #endif

    private init() {}

    // MARK: - Monitoring

    func startMonitoring() {
        #if canImport(UIKit)
        let pb = UIPasteboard.general
        lastChangeCount = pb.changeCount
        detectedText = shouldOfferQuickAdd(for: pb) ? "Pending clipboard content..." : nil
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

    /// Marks the current clipboard state as consumed so quick-add stays hidden
    /// until the user copies new content.
    func markCurrentClipboardAsConsumed() {
        #if canImport(UIKit)
        let pb = UIPasteboard.general
        consumedChangeCount = pb.changeCount
        detectedText = nil
        #endif
    }

    // MARK: - Quick Add from Pasteboard

    func parseAndCreateSchedule() async -> NLPScheduleRouter.ParseResult? {
        guard let text = detectedText else { return nil }
        let result = await NLPScheduleRouter.shared.parse(text)
        detectedText = nil
        return result
    }

    // MARK: - Check

    #if canImport(UIKit)
    private func checkPasteboard() {
        let pb = UIPasteboard.general
        guard pb.changeCount != lastChangeCount else { return }
        lastChangeCount = pb.changeCount

        if shouldOfferQuickAdd(for: pb) {
            detectedText = "Pending clipboard content..."
        } else {
            detectedText = nil
        }
    }

    private func shouldOfferQuickAdd(for pasteboard: UIPasteboard) -> Bool {
        guard pasteboard.hasStrings else { return false }
        guard let consumedChangeCount else { return true }
        return pasteboard.changeCount != consumedChangeCount
    }
    #endif

    /// Parses the actual clipboard string. This is called *after* user interaction
    /// to avoid incessant background permission prompts on iOS 16+.
    func parseAndCreateScheduleFromActualPasteboard() async -> NLPScheduleRouter.ParseResult? {
        #if canImport(UIKit)
        let pb = UIPasteboard.general
        guard let text = pb.string, !text.isEmpty else { return nil }
        let result = await NLPScheduleRouter.shared.parse(text)
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
