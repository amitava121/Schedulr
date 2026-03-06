import Foundation
import UserNotifications

@MainActor
final class DailyDigestService {
    static let shared = DailyDigestService()

    private static let digestRequestIdentifier = "daily-digest-summary"

    private init() {}

    func updateSchedule(using schedules: [Schedule], occurrenceMatcher: @escaping (Schedule, Date, Calendar) -> Bool) {
        Task {
            let center = UNUserNotificationCenter.current()
            center.removePendingNotificationRequests(withIdentifiers: [Self.digestRequestIdentifier])

            guard AppSettings.shared.dailyDigestEnabled else { return }

            let settings = await center.notificationSettings()
            guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional || settings.authorizationStatus == .ephemeral else {
                return
            }

            let content = buildDigestContent(
                schedules: schedules,
                occurrenceMatcher: occurrenceMatcher
            )

            var dateComponents = DateComponents()
            dateComponents.hour = AppSettings.shared.dailyDigestHour
            dateComponents.minute = AppSettings.shared.dailyDigestMinute

            let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
            let request = UNNotificationRequest(
                identifier: Self.digestRequestIdentifier,
                content: content,
                trigger: trigger
            )

            do {
                try await center.add(request)
            } catch {
                print("Daily digest scheduling failed: \(error)")
            }
        }
    }

    func cancelDigest() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [Self.digestRequestIdentifier])
    }

    private func buildDigestContent(
        schedules: [Schedule],
        occurrenceMatcher: @escaping (Schedule, Date, Calendar) -> Bool
    ) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        let calendar = Calendar.current
        let today = Date().startOfDay
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? today

        let activeSchedules = schedules.filter { !$0.isSoftDeleted }
        let overdueCount = activeSchedules.filter { !$0.isCompleted && $0.repeatPattern == .never && $0.scheduledDate < Date() }.count
        let tomorrowCount = activeSchedules.filter { occurrenceMatcher($0, tomorrow, calendar) }.count

        content.title = "Schedulr Daily Digest"
        if overdueCount > 0 {
            content.body = "\(tomorrowCount) upcoming tomorrow • \(overdueCount) overdue"
        } else {
            content.body = "\(tomorrowCount) upcoming for tomorrow"
        }

        content.sound = .default
        if AppSettings.shared.notificationBadgeEnabled {
            content.badge = NSNumber(value: overdueCount)
        }
        if #available(iOS 15.0, *) {
            content.interruptionLevel = .passive
            content.relevanceScore = 0.35
        }

        return content
    }
}
