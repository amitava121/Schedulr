#if os(iOS)
import AlarmKit
import Foundation
import OSLog
import SwiftUI

/// Empty payload for AlarmKit-rendered alerts. The system renders the alert and
/// its countdown Live Activity, so nothing needs sharing with the widget target.
struct SchedulrAlarmMetadata: AlarmMetadata {}

/// Schedules system-level alarms via AlarmKit (iOS 26+). These break through
/// Silent mode and Focus and surface on the Lock Screen, Dynamic Island,
/// StandBy and paired Apple Watch — unlike local notifications, which are
/// capped at 64 pending requests and can't break Focus.
///
/// Local notifications remain the backbone for reminders and repeat handling;
/// AlarmKit is layered on top only for `alertDeliveryOption == .alarm`.
@MainActor
final class AlarmKitManager {
    static let shared = AlarmKitManager()

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.bittu.Schedulr",
        category: "AlarmKit"
    )

    private init() {}

    /// Reconciles the system alarm for a schedule: creates/updates it when the
    /// schedule should ring, removes it when it shouldn't. `nextFireDate` comes
    /// from NotificationManager's recurrence logic — pass nil to cancel.
    func updateAlarm(for schedule: Schedule, nextFireDate: Date?) async {
        let manager = AlarmManager.shared
        let id = schedule.id

        guard let fireDate = nextFireDate, fireDate > Date() else {
            cancelAlarm(for: id)
            return
        }

        if let existing = manager.alarms.first(where: { $0.id == id }) {
            // Never cancel an alarm that is currently ringing.
            if existing.state == .alerting { return }
            // Same fire minute already registered → nothing to do.
            if case .fixed(let existingDate) = existing.schedule,
               Int(existingDate.timeIntervalSince1970) / 60 == Int(fireDate.timeIntervalSince1970) / 60 {
                return
            }
            try? manager.cancel(id: id)
        }

        let snoozeEnabled = schedule.alarmSnoozeEnabled
        let alert = AlarmPresentation.Alert(
            title: LocalizedStringResource(stringLiteral: schedule.title),
            stopButton: .stopButton,
            secondaryButton: snoozeEnabled ? .snoozeButton : nil,
            secondaryButtonBehavior: snoozeEnabled ? .countdown : nil
        )
        let attributes = AlarmAttributes(
            presentation: AlarmPresentation(alert: alert),
            metadata: SchedulrAlarmMetadata(),
            tintColor: .orange
        )
        let countdown: Alarm.CountdownDuration? = snoozeEnabled
            ? Alarm.CountdownDuration(
                preAlert: nil,
                postAlert: TimeInterval(max(1, schedule.alarmSnoozeMinutes) * 60)
            )
            : nil
        let configuration = AlarmManager.AlarmConfiguration(
            countdownDuration: countdown,
            schedule: .fixed(fireDate),
            attributes: attributes,
            sound: .default
        )

        do {
            _ = try await manager.schedule(id: id, configuration: configuration)
        } catch {
            Self.logger.error(
                "AlarmKit schedule failed for \(id.uuidString, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    /// Cancels the registered system alarm unless it is currently ringing —
    /// killing a ringing alarm would silence it without the user stopping it.
    func cancelAlarm(for id: UUID) {
        let manager = AlarmManager.shared
        if let existing = manager.alarms.first(where: { $0.id == id }),
           existing.state == .alerting {
            return
        }
        try? manager.cancel(id: id)
    }
}
#endif
