#if os(iOS)
import ActivityKit
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

    private static let snoozeButton = AlarmButton(
        text: "Snooze",
        textColor: .orange,
        systemImageName: "zzz"
    )

    private init() {}

    /// Reconciles the system alarm for a schedule: creates/updates it when the
    /// schedule should ring, removes it when it shouldn't.
    /// `alarmSchedule` is the AlarmKit-native schedule (`.relative` with
    /// recurrence when the repeat pattern maps, `.fixed` otherwise); nil means
    /// cancel. `nextFireDate` is used only to sanity-check that the alarm is
    /// still pending.
    func updateAlarm(
        for schedule: Schedule,
        alarmSchedule: Alarm.Schedule?,
        nextFireDate: Date?
    ) async {
        let manager = AlarmManager.shared
        let id = schedule.id

        guard let desired = alarmSchedule,
              let fireDate = nextFireDate, fireDate > Date() else {
            cancelAlarm(for: id)
            return
        }

        if let existing = currentAlarm(id: id) {
            // Never touch an alarm that is ringing, counting down to its next
            // ring (snooze), or paused — only replace a still-pending one.
            guard existing.state == .scheduled else { return }
            if existing.schedule == desired { return }
            try? manager.cancel(id: id)
        }

        let snoozeEnabled = schedule.alarmSnoozeEnabled
        let alert = AlarmPresentation.Alert(
            title: LocalizedStringResource(stringLiteral: schedule.title),
            secondaryButton: snoozeEnabled ? Self.snoozeButton : nil,
            secondaryButtonBehavior: snoozeEnabled ? .countdown : nil
        )
        let attributes = AlarmAttributes<SchedulrAlarmMetadata>(
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
        let sound: AlertConfiguration.AlertSound = schedule.alarmSoundOption
            .bestAvailableBundledSoundFileName
            .map { .named($0) } ?? .default
        let configuration = AlarmManager.AlarmConfiguration<SchedulrAlarmMetadata>(
            countdownDuration: countdown,
            schedule: desired,
            attributes: attributes,
            sound: sound
        )

        do {
            _ = try await manager.schedule(id: id, configuration: configuration)
            Self.logger.info(
                "AlarmKit alarm scheduled for \(id.uuidString, privacy: .public) at \(fireDate, privacy: .public)"
            )
        } catch {
            Self.logger.error(
                "AlarmKit schedule failed for \(id.uuidString, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    /// Cancels a still-pending system alarm. Alarms that are ringing, in
    /// snooze countdown, or paused are left alone — cancelling those would
    /// silence an alarm the user is actively expecting. Returns early when
    /// nothing is registered so push-only schedules don't emit
    /// `Alarm does not exist` noise in mobiletimerd.
    func cancelAlarm(for id: UUID) {
        guard let existing = currentAlarm(id: id),
              existing.state == .scheduled else { return }
        try? AlarmManager.shared.cancel(id: id)
    }

    private func currentAlarm(id: UUID) -> Alarm? {
        do {
            return try AlarmManager.shared.alarms.first(where: { $0.id == id })
        } catch {
            Self.logger.error("AlarmKit alarms lookup failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}
#endif
