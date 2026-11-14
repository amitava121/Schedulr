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

    private func ensureAuthorization() async -> Bool {
        let manager = AlarmManager.shared
        switch manager.authorizationState {
        case .authorized:
            return true
        case .denied:
            return false
        case .notDetermined:
            do {
                return try await manager.requestAuthorization() == .authorized
            } catch {
                Self.logger.error(
                    "AlarmKit authorization request failed: \(error.localizedDescription, privacy: .public)"
                )
                return false
            }
        @unknown default:
            return false
        }
    }

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

        guard await ensureAuthorization() else {
            Self.logger.error(
                "AlarmKit authorization is unavailable; system alarm not scheduled for \(id.uuidString, privacy: .public)"
            )
            return
        }

        let fingerprint = configFingerprint(for: schedule)
        if let existing = currentAlarm(id: id) {
            // Never touch an alarm that is ringing, counting down to its next
            // ring (snooze), or paused — only replace a still-pending one.
            guard existing.state == .scheduled else { return }
            // The daemon can't report back presentation/sound/snooze config,
            // so the last-applied fingerprint decides whether an edit that
            // kept the same alarm time also needs a re-registration.
            if Self.isSameSchedule(existing.schedule, desired),
               storedFingerprint(for: id) == fingerprint { return }
            Self.logger.debug(
                "AlarmKit replacing \(id.uuidString, privacy: .public): existing=\(String(describing: existing.schedule), privacy: .public) desired=\(String(describing: desired), privacy: .public)"
            )
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
            UserDefaults.standard.set(fingerprint, forKey: Self.fingerprintKey(for: id))
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
        UserDefaults.standard.removeObject(forKey: Self.fingerprintKey(for: id))
        guard let existing = currentAlarm(id: id),
              existing.state == .scheduled else { return }
        try? AlarmManager.shared.cancel(id: id)
    }

    /// Semantic equality: the daemon may hand back weekdays in a different
    /// order than we registered them, and fixed dates only matter to the minute.
    private static func isSameSchedule(_ existing: Alarm.Schedule?, _ desired: Alarm.Schedule) -> Bool {
        switch (existing, desired) {
        case (.fixed(let lhs)?, .fixed(let rhs)):
            return Int(lhs.timeIntervalSince1970) / 60 == Int(rhs.timeIntervalSince1970) / 60
        case (.relative(let lhs)?, .relative(let rhs)):
            guard lhs.time == rhs.time else { return false }
            switch (lhs.repeats, rhs.repeats) {
            case (.never, .never):
                return true
            case (.weekly(let lhsDays), .weekly(let rhsDays)):
                return Set(lhsDays) == Set(rhsDays)
            default:
                return false
            }
        default:
            return false
        }
    }

    /// Everything `isSameSchedule` can't see: the presentation and delivery
    /// options (title, snooze button/duration, sound) that AlarmKit never
    /// reports back. Persisted so a config-only edit still re-registers the
    /// alarm, including across launches.
    private func configFingerprint(for schedule: Schedule) -> String {
        let sound = schedule.alarmSoundOption.bestAvailableBundledSoundFileName ?? "default"
        return "\(schedule.title)|snooze=\(schedule.alarmSnoozeEnabled)|mins=\(schedule.alarmSnoozeMinutes)|sound=\(sound)"
    }

    private static func fingerprintKey(for id: UUID) -> String {
        "alarmkit.fingerprint.\(id.uuidString)"
    }

    private func storedFingerprint(for id: UUID) -> String? {
        UserDefaults.standard.string(forKey: Self.fingerprintKey(for: id))
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
