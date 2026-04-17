import Foundation
import OSLog
import UserNotifications
#if canImport(WidgetKit)
import WidgetKit
#endif
#if os(iOS)
import AudioToolbox
import UIKit
#endif

@Observable
final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()
    nonisolated private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.bittu.Schedulr",
        category: "notifications"
    )
    nonisolated private static let bundledAlarmSoundResource = "alarm_sound"
    nonisolated private static let bundledAlarmSoundExtension = "caf"
    nonisolated private static let bundledAlarmSoundName = UNNotificationSoundName("alarm_sound.caf")
    nonisolated private static let appleDefaultAlarmSystemSoundID: UInt32 = 1005
    // Schedule a single alarm notification sound (no extra follow-up ring requests).
    nonisolated private static let alarmFollowUpOffsetsSeconds: [Int] = []
    // Cleanup support for follow-up notifications created by older app builds.
    nonisolated private static let legacyAlarmFollowUpOffsetsSeconds: [Int] = [20, 40]
    nonisolated private static let maxFiniteRepeatOccurrences = 60
    nonisolated private static let widgetAppGroupID = "group.com.bittu.Schedulr"
    nonisolated private static let widgetSnapshotKey = "widget.scheduleSnapshot.v1"

    private struct WidgetScheduleSnapshot: Codable {
        var updatedAt: Date
        var upcoming: [WidgetScheduleItem]
        var past: [WidgetScheduleItem]
    }

    private struct WidgetScheduleItem: Codable {
        var id: String
        var title: String
        var scheduledDate: Date
        var notes: String?
        var urlString: String?
        var repeatPatternName: String
        var deliveryName: String
        var priorityName: String
        var earlyReminderMinutes: Int?
        var isCompleted: Bool
    }

    var isAuthorized = false
#if os(iOS)
    private var isPreviewPlaying = false
    private var dynamicSystemSoundIDs: [String: SystemSoundID] = [:]
    private var alarmLoopToken: UUID?
    private var alarmAutoStopTask: Task<Void, Never>?
    private var previewPlayTask: Task<Void, Never>?
    private var previewToken: UUID?
    private var previewSystemSoundID: SystemSoundID?
    private(set) var isAlarmPlaying = false
    private(set) var alarmTitle: String = ""
    private(set) var alarmSnoozeMinutes: Int = 0
    private(set) var alarmScheduleID: String?
    private(set) var alarmSoundFileName: String?
#endif

    private override init() {
        super.init()
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        configureNotificationCategories()
        pruneLegacyAlarmFollowUpRequests()
        Task { @MainActor in
            await refreshAuthorizationStatus()
        }
    }

    @MainActor
    func requestAuthorization() async {
        let center = UNUserNotificationCenter.current()
        var basicOptions: UNAuthorizationOptions = [.alert, .sound]
        if AppSettings.shared.notificationBadgeEnabled {
            basicOptions.insert(.badge)
        }

        // Step 1: Request basic permissions (alert, badge, sound)
        // This MUST succeed for any notifications to show on lock screen.
        do {
            _ = try await center.requestAuthorization(options: basicOptions)
        } catch {
            Self.logger.error("Basic notification authorization error: \(error.localizedDescription, privacy: .public)")
        }

        await refreshAuthorizationStatus()

#if os(iOS)
        // Step 2: Separately try to upgrade to critical alerts.
        // Critical alerts require the com.apple.developer.usernotifications.critical-alerts
        // entitlement. Without it this call throws — but basic permissions are already granted.
        do {
            let settings = await center.notificationSettings()
            if settings.criticalAlertSetting != .enabled {
                var options: UNAuthorizationOptions = [.alert, .sound, .criticalAlert]
                if AppSettings.shared.notificationBadgeEnabled {
                    options.insert(.badge)
                }
                _ = try await center.requestAuthorization(options: options)
                await refreshAuthorizationStatus()
            }
        } catch {
            // Expected failure when entitlement is absent — basic notifications still work.
            Self.logger.warning("Critical alert authorization unavailable: \(error.localizedDescription, privacy: .public)")
        }
#endif

    }

    func scheduleNotification(for schedule: Schedule) {
        Task(priority: .userInitiated) {
            let center = UNUserNotificationCenter.current()
            let settings = await center.notificationSettings()
            let authorized = Self.isStatusAuthorized(settings.authorizationStatus)
            let shouldSuppressForFocus = await MainActor.run {
                shouldSuppressDuringFocus()
            }

            await MainActor.run {
                isAuthorized = authorized
            }

            guard settings.authorizationStatus != .denied else { return }

            if shouldSuppressForFocus {
                cancelNotification(for: schedule)
                return
            }

            if authorized || settings.authorizationStatus == .notDetermined {
                // Always schedule local notifications — they are the reliable backbone.
                let requests = mainRequests(for: schedule, settings: settings)
                for request in requests {
                    do {
                        try await center.add(request)
                    } catch {
                        Self.logger.error("Main notification scheduling error: \(error.localizedDescription, privacy: .public)")
                    }
                }

                // Schedule all reminders (primary earlyReminderMinutes + additionalReminderMinutes)
                let allReminders = schedule.allReminderMinutes
                for reminderMinutes in allReminders {
                    let earlyRequests = earlyReminderRequests(
                        for: schedule,
                        minutesBefore: reminderMinutes,
                        settings: settings
                    )
                    for request in earlyRequests {
                        do {
                            try await center.add(request)
                        } catch {
                            Self.logger.error("Early reminder scheduling error (\(reminderMinutes, privacy: .public)m): \(error.localizedDescription, privacy: .public)")
                        }
                    }
                }
            }
        }
    }

    func cancelNotification(for schedule: Schedule) {
        let center = UNUserNotificationCenter.current()
        let schedulePrefix = schedule.id.uuidString
        let fallbackIdentifiers = Set(allIdentifiers(for: schedule.id) + Self.allIdentifiersStatic(for: schedule.id))

        center.getPendingNotificationRequests { requests in
            let scopedIdentifiers = requests
                .map(\ .identifier)
                .filter { $0.hasPrefix(schedulePrefix) }
            let identifiersToRemove = Array(Set(scopedIdentifiers).union(fallbackIdentifiers))
            guard !identifiersToRemove.isEmpty else { return }
            center.removePendingNotificationRequests(withIdentifiers: identifiersToRemove)
        }

        center.getDeliveredNotifications { notifications in
            let scopedIdentifiers = notifications
                .map { $0.request.identifier }
                .filter { $0.hasPrefix(schedulePrefix) }
            let identifiersToRemove = Array(Set(scopedIdentifiers).union(fallbackIdentifiers))
            guard !identifiersToRemove.isEmpty else { return }
            center.removeDeliveredNotifications(withIdentifiers: identifiersToRemove)
        }
    }

    func updateNotification(for schedule: Schedule) {
        cancelNotification(for: schedule)
        scheduleNotification(for: schedule)
    }

    // MARK: - UNUserNotificationCenterDelegate

    // NOTE: These delegate methods must NOT be `nonisolated`.
    // With SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor the class is
    // implicitly @MainActor. Removing `nonisolated` ensures the
    // Swift async bridge hops to the main thread before executing
    // the body, preventing "Call must be made on main thread" crashes
    // when downstream code touches UIKit or SwiftUI observation.

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        if shouldSuppressDuringFocus() {
            return []
        }

        if AppSettings.shared.notificationBadgeEnabled {
            return [.banner, .list, .sound, .badge]
        }
        return [.banner, .list, .sound]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let actionIdentifier = response.actionIdentifier
        let userInfo = response.notification.request.content.userInfo
        let requestIdentifier = response.notification.request.identifier
        let isAlarm = Self.isAlarmFlagSet(in: userInfo)
        let isRepeating = Self.isRepeatingFlagSet(in: userInfo)
        let scheduleID = Self.scheduleID(from: userInfo)
        let isMarkAsReadAction =
            actionIdentifier == NotificationActionID.markAsRead ||
            actionIdentifier == NotificationActionID.markDone ||
            actionIdentifier == NotificationActionID.stop ||
            actionIdentifier == NotificationActionID.markComplete

#if os(iOS)
        if isAlarm {
            Self.clearAlarmBurstNotifications(
                for: requestIdentifier,
                center: center
            )
        }
#endif

        if actionIdentifier == NotificationActionID.snooze {
            Self.scheduleSnoozeNotification(from: response.notification)
            return
        }

        if isMarkAsReadAction {
            Self.markNotificationRead(
                requestIdentifier: requestIdentifier,
                scheduleID: scheduleID,
                isRepeating: isRepeating,
                occurrenceDate: response.notification.date
            )
            return
        }

        guard actionIdentifier == UNNotificationDefaultActionIdentifier else { return }
        guard let scheduleID else { return }

        Self.storePendingTappedScheduleID(scheduleID)
        // Already on MainActor — post directly.
        NotificationCenter.default.post(
            name: .didTapScheduleNotification,
            object: nil,
            userInfo: ["scheduleID": scheduleID.uuidString]
        )
    }

    private func shouldSuppressDuringFocus() -> Bool {
        guard AppSettings.shared.suppressNotificationsDuringFocus else { return false }
        let focusState = FocusFilterState.current

        let hasCalendarFilter = !(focusState.calendarName?.isEmpty ?? true)
        let hasPriorityFilter = !(focusState.priorityRawValue?.isEmpty ?? true)
        let hidesCompleted = !focusState.showCompleted

        return hasCalendarFilter || hasPriorityFilter || hidesCompleted
    }

    // MARK: - Alarm Playback

#if os(iOS)
    /// Play alarm audio on the system alert (ringer) channel.
    @MainActor
    func playAlarmSound(
        title: String = "Alarm",
        snoozeMinutes: Int = 0,
        scheduleID: String? = nil,
        soundFileName: String? = nil
    ) {
        // Avoid restarting if already playing for the same notification
        if isAlarmPlaying { return }

        stopAlarmSound()
        alarmTitle = title
        alarmSnoozeMinutes = snoozeMinutes
        alarmScheduleID = scheduleID

        let trimmedToken = soundFileName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedToken: String? = {
            guard let trimmedToken, !trimmedToken.isEmpty else { return nil }
            if let dotIndex = trimmedToken.lastIndex(of: ".") {
                return String(trimmedToken[..<dotIndex])
            }
            return trimmedToken
        }()
        let resolvedOption = normalizedToken.flatMap { AlarmSoundOption(rawValue: $0) }
        let bundledFileName = resolvedOption?.bundledSoundFileName ?? (resolvedOption == nil ? normalizedToken : nil)
        let fallbackFileName = Self.bundledAlarmSoundResource
        alarmSoundFileName = resolvedOption?.rawValue ?? bundledFileName ?? fallbackFileName

        if #available(iOS 16.1, *),
           let scheduleID,
           let scheduleUUID = UUID(uuidString: scheduleID) {
            LiveActivityManager.shared.startAlarmActivity(
                scheduleID: scheduleUUID,
                title: title,
                scheduledTime: Date(),
                alarmSoundName: alarmSoundFileName ?? Self.bundledAlarmSoundResource
            )
        }

        let preferredSoundID: SystemSoundID = {
            if let resolvedOption {
                if let bundledName = resolvedOption.bestAvailableBundledSoundFileName,
                   let soundID = systemSoundID(forBundledFile: bundledName) {
                    return soundID
                }

                if let systemSoundID = resolvedOption.previewSystemSoundID {
                    return systemSoundID
                }
            }

            if let bundledFileName,
               let soundID = systemSoundID(forBundledFile: bundledFileName) {
                return soundID
            }

            return Self.appleDefaultAlarmSystemSoundID
        }()

        isAlarmPlaying = true
        let token = UUID()
        alarmLoopToken = token
        alarmAutoStopTask?.cancel()
        alarmAutoStopTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(60))
            guard let self, self.alarmLoopToken == token else { return }
            self.stopAlarmSound()
        }
        loopSystemSound(preferredSoundID, token: token)
    }

    @MainActor
    func stopAlarmSound(shouldStopLiveActivity: Bool = true) {
        alarmLoopToken = nil
        alarmAutoStopTask?.cancel()
        alarmAutoStopTask = nil
        isAlarmPlaying = false
        alarmTitle = ""
        alarmSnoozeMinutes = 0
        alarmScheduleID = nil
        alarmSoundFileName = nil

        if shouldStopLiveActivity, #available(iOS 16.1, *) {
            LiveActivityManager.shared.stopAlarmActivity()
        }
    }

    /// Snooze: stop the alarm and schedule a new notification after snoozeMinutes.
    @MainActor
    func snoozeAlarm() {
        let minutes = alarmSnoozeMinutes > 0 ? alarmSnoozeMinutes : 10
        let title = alarmTitle
        let soundFileName = alarmSoundFileName ?? Self.bundledAlarmSoundResource
        let snoozeUntil = Date().addingTimeInterval(TimeInterval(minutes * 60))

        if #available(iOS 16.1, *) {
            LiveActivityManager.shared.updateSnooze(until: snoozeUntil)
        }

        stopAlarmSound(shouldStopLiveActivity: false)

        // Schedule a snooze notification
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = "Snoozed alarm"
        content.userInfo = [
            "isAlarm": true,
            "snoozeMinutes": minutes,
            "alarmSoundFile": soundFileName
        ]
        content.categoryIdentifier = "SCHEDULE_ALERT_SNOOZE"
        if #available(iOS 15.0, *) {
            content.interruptionLevel = .timeSensitive
            content.relevanceScore = 1.0
        }
        content.sound = Self.bundledNotificationSound(fileName: soundFileName)

        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: TimeInterval(minutes * 60),
            repeats: false
        )
        let request = UNNotificationRequest(
            identifier: "snooze-\(UUID().uuidString)",
            content: content,
            trigger: trigger
        )
        let rootIdentifier = request.identifier
        var requests = [request]
        for offset in Self.alarmFollowUpOffsetsSeconds {
            let followUpTrigger = UNTimeIntervalNotificationTrigger(
                timeInterval: TimeInterval(minutes * 60 + offset),
                repeats: false
            )
            let followUpContent = content.mutableCopy() as? UNMutableNotificationContent ?? content
            requests.append(
                UNNotificationRequest(
                    identifier: Self.alarmFollowUpIdentifier(
                        for: rootIdentifier,
                        offsetSeconds: offset
                    ),
                    content: followUpContent,
                    trigger: followUpTrigger
                )
            )
        }
        Self.enqueueRequests(requests, context: "Snooze scheduling")

        HapticManager.notification(.warning)
    }

    /// Loop a specific SystemSoundID for alarm playback (alert tones).
    @MainActor
    private func loopSystemSound(_ soundID: SystemSoundID, token: UUID) {
        guard isAlarmPlaying, alarmLoopToken == token else { return }
        AudioServicesPlayAlertSoundWithCompletion(soundID) { [weak self] in
            Task { @MainActor in
                guard let self, self.isAlarmPlaying, self.alarmLoopToken == token else { return }
                self.loopSystemSound(soundID, token: token)
            }
        }
    }
#endif

    // MARK: - Private

    private func refreshAuthorizationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        let authorized = Self.isStatusAuthorized(settings.authorizationStatus)

        await MainActor.run {
            isAuthorized = authorized
        }
    }

    func applyBadgePreferenceChange() {
#if os(iOS)
        DispatchQueue.main.async {
            if !AppSettings.shared.notificationBadgeEnabled {
                self.setBadgeCount(0)
            }
        }
#endif
    }

    func refreshBadgeCount(
        schedules: [Schedule],
        occurrenceMatchesDay: (Schedule, Date, Calendar) -> Bool,
        isOccurrenceCompleted: (Schedule, Date) -> Bool
    ) {
#if os(iOS)
        guard AppSettings.shared.notificationBadgeEnabled else {
            DispatchQueue.main.async {
                self.setBadgeCount(0)
            }
            return
        }

        let now = Date()
        let calendar = Calendar.current
        let today = now.startOfDay

        let overdueOrDueCount = schedules.reduce(into: 0) { count, schedule in
            guard !schedule.isSoftDeleted else { return }

            if schedule.repeatPattern == .never {
                if !schedule.isCompleted && schedule.scheduledDate <= now {
                    count += 1
                }
                return
            }

            guard occurrenceMatchesDay(schedule, today, calendar) else { return }
            if !isOccurrenceCompleted(schedule, today) {
                count += 1
            }
        }

        DispatchQueue.main.async {
            self.setBadgeCount(overdueOrDueCount)
        }
#endif
    }

#if os(iOS)
    private func setBadgeCount(_ count: Int) {
        if #available(iOS 17.0, *) {
            UNUserNotificationCenter.current().setBadgeCount(count, withCompletionHandler: nil)
        } else {
            UIApplication.shared.applicationIconBadgeNumber = count
        }
    }
#endif

    private func pruneLegacyAlarmFollowUpRequests() {
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { requests in
            let legacyIdentifiers = requests.compactMap { request -> String? in
                let id = request.identifier
                guard Self.isLegacyFollowUpIdentifier(id) else { return nil }
                return id
            }

            guard !legacyIdentifiers.isEmpty else { return }
            center.removePendingNotificationRequests(withIdentifiers: legacyIdentifiers)
        }
    }

    @MainActor
    func previewAlarmSound(_ sound: AlarmSoundOption) {
#if os(iOS)
        previewPlayTask?.cancel()
        stopPreviewSound()

        previewPlayTask = Task { @MainActor [weak self] in
            guard let self else { return }

            // Small debounce prevents overlapping artifacts while quickly changing picker values.
            try? await Task.sleep(for: .milliseconds(80))
            guard !Task.isCancelled else { return }

            let selection = previewSystemSoundSelection(for: sound)
            if selection.disposable {
                previewSystemSoundID = selection.id
            } else {
                previewSystemSoundID = nil
            }

            isPreviewPlaying = true
            let token = UUID()
            previewToken = token

            AudioServicesPlayAlertSoundWithCompletion(selection.id) { [weak self] in
                Task { @MainActor in
                    guard let self, self.previewToken == token else { return }
                    self.stopPreviewSound()
                }
            }
        }
#endif
    }

    @MainActor
    func stopPreviewAlarmSound() {
#if os(iOS)
        previewPlayTask?.cancel()
        previewPlayTask = nil
        stopPreviewSound()
#endif
    }

    private static func isStatusAuthorized(_ status: UNAuthorizationStatus) -> Bool {
        switch status {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied, .notDetermined:
            return false
        @unknown default:
            return false
        }
    }

#if os(iOS)
    @MainActor
    private func stopPreviewSound() {
        previewToken = nil
        if let previewSystemSoundID {
            AudioServicesDisposeSystemSoundID(previewSystemSoundID)
            self.previewSystemSoundID = nil
        }
        isPreviewPlaying = false
    }

    @MainActor
    private func previewSystemSoundSelection(
        for sound: AlarmSoundOption
    ) -> (id: SystemSoundID, disposable: Bool) {
        if let bundledName = sound.bestAvailableBundledSoundFileName,
           let soundID = createPreviewSystemSoundID(forBundledFile: bundledName) {
            return (soundID, true)
        }

        if let systemSoundID = sound.previewSystemSoundID {
            return (systemSoundID, false)
        }

        if let fallbackID = createPreviewSystemSoundID(forBundledFile: Self.bundledAlarmSoundResource) {
            return (fallbackID, true)
        }

        return (Self.appleDefaultAlarmSystemSoundID, false)
    }

    @MainActor
    private func createPreviewSystemSoundID(forBundledFile name: String) -> SystemSoundID? {
        guard let url = Bundle.main.url(
            forResource: name,
            withExtension: Self.bundledAlarmSoundExtension
        ) else {
            return nil
        }

        var soundID: SystemSoundID = 0
        let status = AudioServicesCreateSystemSoundID(url as CFURL, &soundID)
        guard status == kAudioServicesNoError else {
            Self.logger.error("Preview sound creation failed (\(status, privacy: .public)) for \(name, privacy: .public)")
            return nil
        }

        return soundID
    }

    @MainActor
    private func systemSoundID(forBundledFile name: String) -> SystemSoundID? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let cached = dynamicSystemSoundIDs[trimmed] {
            return cached
        }

        guard let url = Bundle.main.url(
            forResource: trimmed,
            withExtension: Self.bundledAlarmSoundExtension
        ) else {
            return nil
        }

        var soundID: SystemSoundID = 0
        let status = AudioServicesCreateSystemSoundID(url as CFURL, &soundID)
        guard status == kAudioServicesNoError else {
            Self.logger.error("System sound creation failed (\(status, privacy: .public)) for \(trimmed, privacy: .public)")
            return nil
        }

        dynamicSystemSoundIDs[trimmed] = soundID
        return soundID
    }
#endif

    private func configureNotificationCategories() {
        // ── Shared actions ──
        // Snooze is intentionally excluded from system notification actions.
        let completeAction = UNNotificationAction(
            identifier: NotificationActionID.markComplete,
            title: "✓ Done",
            options: []
        )
        let readAction = UNNotificationAction(
            identifier: NotificationActionID.markAsRead,
            title: "Dismiss",
            options: []
        )

        let actions = [completeAction, readAction]

        // All alarm & push categories now show only Done + Dismiss.
        let alarmWithSnooze = UNNotificationCategory(
            identifier: NotificationCategoryID.standardWithSnooze,
            actions: actions,
            intentIdentifiers: []
        )
        let alarmFlaggedWithSnooze = UNNotificationCategory(
            identifier: NotificationCategoryID.flaggedWithSnooze,
            actions: actions,
            intentIdentifiers: []
        )
        let alarmNoSnooze = UNNotificationCategory(
            identifier: NotificationCategoryID.standardNoSnooze,
            actions: actions,
            intentIdentifiers: []
        )
        let alarmFlaggedNoSnooze = UNNotificationCategory(
            identifier: NotificationCategoryID.flaggedNoSnooze,
            actions: actions,
            intentIdentifiers: []
        )
        let pushCategory = UNNotificationCategory(
            identifier: NotificationCategoryID.pushReminder,
            actions: actions,
            intentIdentifiers: []
        )

        UNUserNotificationCenter.current().setNotificationCategories([
            alarmWithSnooze,
            alarmFlaggedWithSnooze,
            alarmNoSnooze,
            alarmFlaggedNoSnooze,
            pushCategory
        ])
    }

    private enum ScheduleNotificationKind {
        case scheduled
        case earlyReminder
    }

    private func mainRequests(
        for schedule: Schedule,
        settings: UNNotificationSettings
    ) -> [UNNotificationRequest] {
        if schedule.repeatPattern == .never {
            guard let trigger = oneTimeTrigger(for: schedule.scheduledDate) else {
                return []
            }

            let content = baseContent(
                title: schedule.title,
                body: schedule.notes ?? "Scheduled reminder",
                schedule: schedule,
                settings: settings,
                kind: .scheduled
            )

            let rootIdentifier = mainIdentifier(for: schedule.id)
            var requests = [
                UNNotificationRequest(
                    identifier: rootIdentifier,
                    content: content,
                    trigger: trigger
                )
            ]

            if schedule.alertDeliveryOption == .alarm {
                for offset in Self.alarmFollowUpOffsetsSeconds {
                    guard let followUpTrigger = oneTimeTrigger(
                        for: schedule.scheduledDate.addingTimeInterval(TimeInterval(offset))
                    ) else {
                        continue
                    }
                    let followUpContent = content.mutableCopy() as? UNMutableNotificationContent ?? content
                    requests.append(
                        UNNotificationRequest(
                            identifier: Self.alarmFollowUpIdentifier(
                                for: rootIdentifier,
                                offsetSeconds: offset
                            ),
                            content: followUpContent,
                            trigger: followUpTrigger
                        )
                    )
                }
            }

            return requests
        }

        if let repeatEndBoundary = repeatEndBoundary(for: schedule) {
            return finiteMainRequests(
                for: schedule,
                through: repeatEndBoundary,
                settings: settings
            )
        }

        if schedule.repeatPattern == .daily {
            let calendar = Calendar.current
            let weekdays = normalizedWeekdays(schedule.repeatWeekdays)
            let sourceDay = schedule.scheduledDate.startOfDay
            let timeComponents = calendar.dateComponents([.hour, .minute, .second], from: schedule.scheduledDate)

            return weekdays.flatMap { weekday in
                var dateComponents = timeComponents
                dateComponents.weekday = weekday

                let trigger = UNCalendarNotificationTrigger(
                    dateMatching: dateComponents,
                    repeats: true
                )

                let content = baseContent(
                    title: schedule.title,
                    body: schedule.notes ?? "Scheduled reminder",
                    schedule: schedule,
                    settings: settings,
                    kind: .scheduled
                )

                let rootIdentifier = mainIdentifier(for: schedule.id, weekday: weekday)
                var requests = [
                    UNNotificationRequest(
                        identifier: rootIdentifier,
                        content: content,
                        trigger: trigger
                    )
                ]

                if schedule.alertDeliveryOption == .alarm {
                    for offset in Self.alarmFollowUpOffsetsSeconds {
                        guard let followUpDate = calendar.date(
                            byAdding: .second,
                            value: offset,
                            to: schedule.scheduledDate
                        ) else {
                            continue
                        }
                        let followUpDay = followUpDate.startOfDay
                        let dayOffset = calendar.dateComponents([.day], from: sourceDay, to: followUpDay).day ?? 0
                        var followUpComponents = calendar.dateComponents(
                            [.hour, .minute, .second],
                            from: followUpDate
                        )
                        followUpComponents.weekday = shiftedWeekday(weekday, by: dayOffset)
                        let followUpTrigger = UNCalendarNotificationTrigger(
                            dateMatching: followUpComponents,
                            repeats: true
                        )
                        let followUpContent = content.mutableCopy() as? UNMutableNotificationContent ?? content
                        requests.append(
                            UNNotificationRequest(
                                identifier: Self.alarmFollowUpIdentifier(
                                    for: rootIdentifier,
                                    offsetSeconds: offset
                                ),
                                content: followUpContent,
                                trigger: followUpTrigger
                            )
                        )
                    }
                }

                return requests
            }
        }

        let content = baseContent(
            title: schedule.title,
            body: schedule.notes ?? "Scheduled reminder",
            schedule: schedule,
            settings: settings,
            kind: .scheduled
        )

        let baseDateComponents = dateComponents(
            for: schedule.scheduledDate,
            repeatPattern: schedule.repeatPattern,
            timeZone: schedule.scheduleTimeZone
        )
        let trigger = UNCalendarNotificationTrigger(
            dateMatching: baseDateComponents,
            repeats: schedule.repeatPattern != .never
        )

        let rootIdentifier = mainIdentifier(for: schedule.id)
        var requests = [
            UNNotificationRequest(
                identifier: rootIdentifier,
                content: content,
                trigger: trigger
            )
        ]

        if schedule.alertDeliveryOption == .alarm {
            for offset in Self.alarmFollowUpOffsetsSeconds {
                let followUpDate = schedule.scheduledDate.addingTimeInterval(TimeInterval(offset))
                let followUpComponents = dateComponents(
                    for: followUpDate,
                    repeatPattern: schedule.repeatPattern,
                    timeZone: schedule.scheduleTimeZone
                )
                let followUpTrigger = UNCalendarNotificationTrigger(
                    dateMatching: followUpComponents,
                    repeats: true
                )
                let followUpContent = content.mutableCopy() as? UNMutableNotificationContent ?? content
                requests.append(
                    UNNotificationRequest(
                        identifier: Self.alarmFollowUpIdentifier(
                            for: rootIdentifier,
                            offsetSeconds: offset
                        ),
                        content: followUpContent,
                        trigger: followUpTrigger
                    )
                )
            }
        }

        return requests
    }

    private func earlyReminderRequests(
        for schedule: Schedule,
        minutesBefore: Int,
        settings: UNNotificationSettings
    ) -> [UNNotificationRequest] {
        var tzCalendar = Calendar.current
        if let tz = schedule.scheduleTimeZone {
            tzCalendar.timeZone = tz
        }
        let earlyDate = tzCalendar.date(
            byAdding: .minute,
            value: -minutesBefore,
            to: schedule.scheduledDate
        ) ?? schedule.scheduledDate

        if schedule.repeatPattern == .never {
            guard let trigger = oneTimeTrigger(for: earlyDate) else {
                return []
            }

            let content = baseContent(
                title: "Coming up: \(schedule.title)",
                body: "In \(minutesBefore) minutes",
                schedule: schedule,
                settings: settings,
                kind: .earlyReminder
            )

            return [
                UNNotificationRequest(
                    identifier: earlyIdentifier(for: schedule.id, minutesBefore: minutesBefore),
                    content: content,
                    trigger: trigger
                )
            ]
        }

        if let repeatEndBoundary = repeatEndBoundary(for: schedule) {
            return finiteEarlyReminderRequests(
                for: schedule,
                minutesBefore: minutesBefore,
                through: repeatEndBoundary,
                settings: settings
            )
        }

        if schedule.repeatPattern == .daily {
            var calendar = Calendar.current
            if let tz = schedule.scheduleTimeZone {
                calendar.timeZone = tz
            }
            let weekdays = normalizedWeekdays(schedule.repeatWeekdays)
            let sourceDay = schedule.scheduledDate.startOfDay
            let earlyDay = earlyDate.startOfDay
            let dayOffset = calendar.dateComponents([.day], from: sourceDay, to: earlyDay).day ?? 0
            let timeComponents = calendar.dateComponents([.hour, .minute, .second], from: earlyDate)

            return weekdays.map { weekday in
                var dateComponents = timeComponents
                dateComponents.weekday = shiftedWeekday(weekday, by: dayOffset)

                let trigger = UNCalendarNotificationTrigger(
                    dateMatching: dateComponents,
                    repeats: true
                )

                let content = baseContent(
                    title: "Coming up: \(schedule.title)",
                    body: "In \(minutesBefore) minutes",
                    schedule: schedule,
                    settings: settings,
                    kind: .earlyReminder
                )

                return UNNotificationRequest(
                    identifier: earlyIdentifier(for: schedule.id, weekday: weekday, minutesBefore: minutesBefore),
                    content: content,
                    trigger: trigger
                )
            }
        }

        let content = baseContent(
            title: "Coming up: \(schedule.title)",
            body: "In \(minutesBefore) minutes",
            schedule: schedule,
            settings: settings,
            kind: .earlyReminder
        )

        let dateComponents = dateComponents(
            for: earlyDate,
            repeatPattern: schedule.repeatPattern,
            timeZone: schedule.scheduleTimeZone
        )
        let trigger = UNCalendarNotificationTrigger(
            dateMatching: dateComponents,
            repeats: schedule.repeatPattern != .never
        )

        return [
            UNNotificationRequest(
                identifier: earlyIdentifier(for: schedule.id, minutesBefore: minutesBefore),
                content: content,
                trigger: trigger
            )
        ]
    }

    private func finiteMainRequests(
        for schedule: Schedule,
        through endDate: Date,
        settings: UNNotificationSettings
    ) -> [UNNotificationRequest] {
        let occurrences = recurringOccurrences(for: schedule, through: endDate)
        guard !occurrences.isEmpty else { return [] }

        let content = baseContent(
            title: schedule.title,
            body: schedule.notes ?? "Scheduled reminder",
            schedule: schedule,
            settings: settings,
            kind: .scheduled
        )

        return occurrences.enumerated().flatMap { index, occurrence in
            guard let trigger = oneTimeTrigger(for: occurrence) else {
                return [UNNotificationRequest]()
            }

            let rootIdentifier = mainIdentifier(for: schedule.id, occurrenceIndex: index)
            var requests: [UNNotificationRequest] = [
                UNNotificationRequest(
                    identifier: rootIdentifier,
                    content: content,
                    trigger: trigger
                )
            ]

            if schedule.alertDeliveryOption == .alarm {
                for offset in Self.alarmFollowUpOffsetsSeconds {
                    guard let followUpTrigger = oneTimeTrigger(
                        for: occurrence.addingTimeInterval(TimeInterval(offset))
                    ) else {
                        continue
                    }
                    let followUpContent = content.mutableCopy() as? UNMutableNotificationContent ?? content
                    requests.append(
                        UNNotificationRequest(
                            identifier: Self.alarmFollowUpIdentifier(
                                for: rootIdentifier,
                                offsetSeconds: offset
                            ),
                            content: followUpContent,
                            trigger: followUpTrigger
                        )
                    )
                }
            }

            return requests
        }
    }

    private func finiteEarlyReminderRequests(
        for schedule: Schedule,
        minutesBefore: Int,
        through endDate: Date,
        settings: UNNotificationSettings
    ) -> [UNNotificationRequest] {
        let occurrences = recurringOccurrences(for: schedule, through: endDate)
        guard !occurrences.isEmpty else { return [] }

        let content = baseContent(
            title: "Coming up: \(schedule.title)",
            body: "In \(minutesBefore) minutes",
            schedule: schedule,
            settings: settings,
            kind: .earlyReminder
        )

        return occurrences.enumerated().compactMap { index, occurrence in
            var tzCalendar = Calendar.current
            if let tz = schedule.scheduleTimeZone {
                tzCalendar.timeZone = tz
            }
            guard let earlyDate = tzCalendar.date(
                byAdding: .minute,
                value: -minutesBefore,
                to: occurrence
            ) else {
                return nil
            }
            guard let trigger = oneTimeTrigger(for: earlyDate) else { return nil }

            return UNNotificationRequest(
                identifier: earlyIdentifier(for: schedule.id, occurrenceIndex: index, minutesBefore: minutesBefore),
                content: content,
                trigger: trigger
            )
        }
    }

    private func repeatEndBoundary(for schedule: Schedule) -> Date? {
        guard schedule.repeatPattern != .never else { return nil }
        switch schedule.repeatEndOption {
        case .onDate:
            guard let repeatEndDate = schedule.repeatEndDate else { return nil }
            let boundary = repeatEndDate.endOfDay
            return max(boundary, schedule.scheduledDate)

        case .afterCount:
            let requestedCount = max(1, schedule.repeatEndCount)
            let occurrences = recurringOccurrences(
                for: schedule,
                maxOccurrences: requestedCount
            )
            return occurrences.last

        case .never:
            return nil
        }
    }

    private func recurringOccurrences(
        for schedule: Schedule,
        maxOccurrences: Int
    ) -> [Date] {
        guard maxOccurrences > 0 else { return [] }

        let boundedCount = min(maxOccurrences, Self.maxFiniteRepeatOccurrences)
        let horizon = Calendar.current.date(byAdding: .year, value: 200, to: schedule.scheduledDate)
            ?? Date.distantFuture

        let allOccurrences = recurringOccurrences(for: schedule, through: horizon)
        if allOccurrences.count <= boundedCount {
            return allOccurrences
        }
        return Array(allOccurrences.prefix(boundedCount))
    }

    private func recurringOccurrences(for schedule: Schedule, through endDate: Date) -> [Date] {
        guard schedule.repeatPattern != .never else { return [] }
        guard schedule.scheduledDate <= endDate else { return [] }

        let calendar = Calendar.current
        let limit = Self.maxFiniteRepeatOccurrences
        var occurrences: [Date] = []
        occurrences.reserveCapacity(limit)

        switch schedule.repeatPattern {
        case .daily:
            let weekdays = normalizedWeekdays(schedule.repeatWeekdays)
            let hour = calendar.component(.hour, from: schedule.scheduledDate)
            let minute = calendar.component(.minute, from: schedule.scheduledDate)
            let second = calendar.component(.second, from: schedule.scheduledDate)
            var day = schedule.scheduledDate.startOfDay

            while day <= endDate, occurrences.count < limit {
                let weekday = calendar.component(.weekday, from: day)
                if weekdays.contains(weekday),
                   let occurrence = calendar.date(
                    bySettingHour: hour,
                    minute: minute,
                    second: second,
                    of: day
                   ),
                   occurrence >= schedule.scheduledDate,
                   occurrence <= endDate {
                    occurrences.append(occurrence)
                }

                guard let nextDay = calendar.date(byAdding: .day, value: 1, to: day) else {
                    break
                }
                day = nextDay
            }

        case .weekly, .monthly, .yearly, .biweekly, .everyNWeeks, .everyNMonths:
            let matchComponents = dateComponents(
                for: schedule.scheduledDate,
                repeatPattern: schedule.repeatPattern
            )
            var cursor = schedule.scheduledDate.addingTimeInterval(-1)

            while occurrences.count < limit {
                guard let nextDate = calendar.nextDate(
                    after: cursor,
                    matching: matchComponents,
                    matchingPolicy: .nextTimePreservingSmallerComponents,
                    repeatedTimePolicy: .first,
                    direction: .forward
                ) else {
                    break
                }

                if nextDate > endDate {
                    break
                }

                if nextDate >= schedule.scheduledDate {
                    // For interval-based patterns, verify the interval
                    var include = true
                    if schedule.repeatPattern == .biweekly {
                        let weeks = calendar.dateComponents([.weekOfYear], from: schedule.scheduledDate, to: nextDate).weekOfYear ?? 0
                        include = weeks % 2 == 0
                    } else if schedule.repeatPattern == .everyNWeeks {
                        let weeks = calendar.dateComponents([.weekOfYear], from: schedule.scheduledDate, to: nextDate).weekOfYear ?? 0
                        include = weeks % max(1, schedule.repeatInterval) == 0
                    } else if schedule.repeatPattern == .everyNMonths {
                        let months = calendar.dateComponents([.month], from: schedule.scheduledDate, to: nextDate).month ?? 0
                        include = months % max(1, schedule.repeatInterval) == 0
                    }
                    if include {
                        occurrences.append(nextDate)
                    }
                }

                cursor = nextDate.addingTimeInterval(1)
            }

        case .weekdays:
            let hour = calendar.component(.hour, from: schedule.scheduledDate)
            let minute = calendar.component(.minute, from: schedule.scheduledDate)
            let second = calendar.component(.second, from: schedule.scheduledDate)
            var day = schedule.scheduledDate.startOfDay

            while day <= endDate, occurrences.count < limit {
                let weekday = calendar.component(.weekday, from: day)
                if (2...6).contains(weekday),
                   let occurrence = calendar.date(
                    bySettingHour: hour,
                    minute: minute,
                    second: second,
                    of: day
                   ),
                   occurrence >= schedule.scheduledDate,
                   occurrence <= endDate {
                    occurrences.append(occurrence)
                }
                guard let nextDay = calendar.date(byAdding: .day, value: 1, to: day) else { break }
                day = nextDay
            }

        case .everyNDays:
            let interval = max(1, schedule.repeatInterval)
            var cursor = schedule.scheduledDate
            while cursor <= endDate, occurrences.count < limit {
                occurrences.append(cursor)
                guard let next = calendar.date(byAdding: .day, value: interval, to: cursor) else { break }
                cursor = next
            }

        case .customWeekdays:
            let allowedWeekdays = Set(schedule.repeatWeekdays)
            let hour = calendar.component(.hour, from: schedule.scheduledDate)
            let minute = calendar.component(.minute, from: schedule.scheduledDate)
            let second = calendar.component(.second, from: schedule.scheduledDate)
            var day = schedule.scheduledDate.startOfDay

            while day <= endDate, occurrences.count < limit {
                let weekday = calendar.component(.weekday, from: day)
                if allowedWeekdays.contains(weekday),
                   let occurrence = calendar.date(
                    bySettingHour: hour,
                    minute: minute,
                    second: second,
                    of: day
                   ),
                   occurrence >= schedule.scheduledDate,
                   occurrence <= endDate {
                    occurrences.append(occurrence)
                }
                guard let nextDay = calendar.date(byAdding: .day, value: 1, to: day) else { break }
                day = nextDay
            }

        case .never:
            break
        }

        return occurrences
    }

    private func baseContent(
        title: String,
        body: String,
        schedule: Schedule,
        settings: UNNotificationSettings,
        kind: ScheduleNotificationKind
    ) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = notificationSound(for: schedule, settings: settings, kind: kind)
        if AppSettings.shared.notificationBadgeEnabled {
            content.badge = NSNumber(value: 1)
        }

        var userInfo: [String: Any] = [
            "scheduleID": schedule.id.uuidString,
            "isRepeating": schedule.repeatPattern != .never
        ]
        if kind == .scheduled, schedule.alertDeliveryOption == .alarm {
            userInfo["isAlarm"] = true
            userInfo["alarmSoundFile"] = schedule.alarmSoundOption.rawValue
            if schedule.alarmSnoozeEnabled {
                userInfo["snoozeMinutes"] = min(max(schedule.alarmSnoozeMinutes, 1), 1439)
            }
        }
        content.userInfo = userInfo
        content.categoryIdentifier = notificationCategoryIdentifier(for: schedule, kind: kind)

        if #available(iOS 15.0, macOS 12.0, *) {
            switch kind {
            case .earlyReminder:
                // Early reminder should be push-only, never alarm/ringtone.
                content.interruptionLevel = .active
                content.relevanceScore = schedule.priority == .high ? 0.9 : 0.75
            case .scheduled:
                switch schedule.alertDeliveryOption {
                case .push:
                    // High priority breaks through Focus modes via Time Sensitive.
                    if schedule.priority == .high {
                        content.interruptionLevel = .timeSensitive
                    } else {
                        content.interruptionLevel = .active
                    }
                    content.relevanceScore = schedule.priority == .high ? 1.0 : 0.9
                case .alarm:
                    if settings.criticalAlertSetting == .enabled {
                        content.interruptionLevel = .critical
                    } else {
                        content.interruptionLevel = .timeSensitive
                    }
                    content.relevanceScore = 1.0
                }
            }
        }

        return content
    }

    private func notificationCategoryIdentifier(
        for schedule: Schedule,
        kind: ScheduleNotificationKind
    ) -> String {
        guard kind == .scheduled else {
            // Early reminder should always behave as push category.
            return NotificationCategoryID.pushReminder
        }

        return categoryIdentifier(for: schedule)
    }

    /// The sound iOS plays when delivering the notification (lock screen / background).
    /// Foreground delivery also uses system notification sound presentation.
    private func notificationSound(
        for schedule: Schedule,
        settings: UNNotificationSettings,
        kind: ScheduleNotificationKind
    ) -> UNNotificationSound? {
        // Early reminder should never use the selected alarm ringtone.
        guard kind == .scheduled else { return .default }

        let option = schedule.alertDeliveryOption

        // Push: standard system chime
        guard option == .alarm else { return .default }

        let soundOption = schedule.alarmSoundOption

#if os(iOS)
        if settings.criticalAlertSetting == .enabled, soundOption.usesCriticalAlert {
            return .defaultCritical
        }
#endif

        return Self.bundledNotificationSound(fileName: soundOption.rawValue)
    }

    private func dateComponents(
        for date: Date,
        repeatPattern: RepeatPattern,
        timeZone: TimeZone? = nil
    ) -> DateComponents {
        var calendar = Calendar.current
        if let tz = timeZone {
            calendar.timeZone = tz
        }
        switch repeatPattern {
        case .never:
            var components = calendar.dateComponents(
                [.year, .month, .day, .hour, .minute, .second],
                from: date
            )
            components.timeZone = timeZone ?? .autoupdatingCurrent
            return components
        case .daily, .everyNDays, .weekdays, .customWeekdays:
            return calendar.dateComponents([.hour, .minute, .second], from: date)
        case .weekly, .biweekly, .everyNWeeks:
            return calendar.dateComponents([.weekday, .hour, .minute, .second], from: date)
        case .monthly, .everyNMonths:
            return calendar.dateComponents([.day, .hour, .minute, .second], from: date)
        case .yearly:
            return calendar.dateComponents([.month, .day, .hour, .minute, .second], from: date)
        }
    }

    private func oneTimeTrigger(for date: Date) -> UNNotificationTrigger? {
        let interval = date.timeIntervalSinceNow
        let allowedPastGrace: TimeInterval = 60

        guard interval >= -allowedPastGrace else { return nil }

        // Use interval-based one-time triggers for tighter delivery timing.
        let fireInterval = max(1, interval)
        return UNTimeIntervalNotificationTrigger(
            timeInterval: fireInterval,
            repeats: false
        )
    }

    private func normalizedWeekdays(_ weekdays: [Int]) -> [Int] {
        let valid = Set(weekdays.filter { (1...7).contains($0) })
        return valid.isEmpty ? Array(1...7) : valid.sorted()
    }

    private func shiftedWeekday(_ weekday: Int, by dayOffset: Int) -> Int {
        let normalized = ((weekday - 1 + dayOffset) % 7 + 7) % 7
        return normalized + 1
    }

    private nonisolated static func scheduleSnoozeNotification(from notification: UNNotification) {
        let content = notification.request.content.mutableCopy() as? UNMutableNotificationContent
            ?? UNMutableNotificationContent()

        let snoozeMinutes = snoozeMinutes(from: content.userInfo)
        let alarmSoundFile = stringValue(forKey: "alarmSoundFile", in: content.userInfo)
        content.sound = bundledNotificationSound(fileName: alarmSoundFile)
        if #available(iOS 15.0, macOS 12.0, *) {
            content.interruptionLevel = .timeSensitive
            content.relevanceScore = 1.0
        }
        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: TimeInterval(snoozeMinutes * 60),
            repeats: false
        )
        let rootIdentifier = "\(notification.request.identifier)-snooze-\(UUID().uuidString)"
        var requests = [
            UNNotificationRequest(
                identifier: rootIdentifier,
                content: content,
                trigger: trigger
            )
        ]

        for offset in alarmFollowUpOffsetsSeconds {
            let followUpTrigger = UNTimeIntervalNotificationTrigger(
                timeInterval: TimeInterval(snoozeMinutes * 60 + offset),
                repeats: false
            )
            let followUpContent = content.mutableCopy() as? UNMutableNotificationContent ?? content
            requests.append(
                UNNotificationRequest(
                    identifier: alarmFollowUpIdentifier(
                        for: rootIdentifier,
                        offsetSeconds: offset
                    ),
                    content: followUpContent,
                    trigger: followUpTrigger
                )
            )
        }

        enqueueRequests(requests, context: "Snooze scheduling")
    }

    private func categoryIdentifier(for schedule: Schedule) -> String {
        // Push notifications: only "Mark as Read"
        guard schedule.alertDeliveryOption == .alarm else {
            return NotificationCategoryID.pushReminder
        }

        // Alarm notifications: "Snooze + Mark as Read" only when snooze is enabled.
        let includesSnooze = schedule.alarmSnoozeEnabled

        switch (schedule.isFlagged, includesSnooze) {
        case (true, true):
            return NotificationCategoryID.flaggedWithSnooze
        case (true, false):
            return NotificationCategoryID.flaggedNoSnooze
        case (false, true):
            return NotificationCategoryID.standardWithSnooze
        case (false, false):
            return NotificationCategoryID.standardNoSnooze
        }
    }

    private nonisolated static func snoozeMinutes(from userInfo: [AnyHashable: Any]) -> Int {
        if let minutes = userInfo["snoozeMinutes"] as? Int {
            return min(max(minutes, 1), 1439)
        }

        if let minutesNumber = userInfo["snoozeMinutes"] as? NSNumber {
            return min(max(minutesNumber.intValue, 1), 1439)
        }

        if let minutesString = userInfo["snoozeMinutes"] as? String,
           let minutes = Int(minutesString)
        {
            return min(max(minutes, 1), 1439)
        }

        return 10
    }

    func consumePendingTappedScheduleID() -> UUID? {
        let defaults = UserDefaults.standard

        // Ignore pending IDs from a previous process (e.g. app crash + relaunch).
        if defaults.string(forKey: Self.pendingTappedScheduleSessionKey) != Self.currentProcessSessionID {
            defaults.removeObject(forKey: Self.pendingTappedScheduleIDKey)
            defaults.removeObject(forKey: Self.pendingTappedScheduleTimestampKey)
            defaults.removeObject(forKey: Self.pendingTappedScheduleSessionKey)
            return nil
        }

        // Discard stale IDs so normal app launches don't unexpectedly jump to day view.
        if let timestamp = defaults.object(forKey: Self.pendingTappedScheduleTimestampKey) as? TimeInterval {
            let age = Date().timeIntervalSince1970 - timestamp
            if age > Self.pendingTappedScheduleMaxAgeSeconds {
                defaults.removeObject(forKey: Self.pendingTappedScheduleIDKey)
                defaults.removeObject(forKey: Self.pendingTappedScheduleTimestampKey)
                defaults.removeObject(forKey: Self.pendingTappedScheduleSessionKey)
                return nil
            }
        }

        guard
            let rawValue = defaults.string(forKey: Self.pendingTappedScheduleIDKey),
            let scheduleID = UUID(uuidString: rawValue)
        else {
            return nil
        }

        defaults.removeObject(forKey: Self.pendingTappedScheduleIDKey)
        defaults.removeObject(forKey: Self.pendingTappedScheduleTimestampKey)
        defaults.removeObject(forKey: Self.pendingTappedScheduleSessionKey)
        return scheduleID
    }

    func acknowledgePendingTappedScheduleID(_ scheduleID: UUID) {
        let defaults = UserDefaults.standard
        guard defaults.string(forKey: Self.pendingTappedScheduleSessionKey) == Self.currentProcessSessionID else {
            return
        }
        guard defaults.string(forKey: Self.pendingTappedScheduleIDKey) == scheduleID.uuidString else {
            return
        }
        defaults.removeObject(forKey: Self.pendingTappedScheduleIDKey)
        defaults.removeObject(forKey: Self.pendingTappedScheduleTimestampKey)
        defaults.removeObject(forKey: Self.pendingTappedScheduleSessionKey)
    }

    private nonisolated static func scheduleID(from userInfo: [AnyHashable: Any]) -> UUID? {
        if let id = userInfo["scheduleID"] as? UUID {
            return id
        }

        if let id = userInfo["scheduleID"] as? NSUUID {
            return id as UUID
        }

        if let id = userInfo["scheduleID"] as? NSString {
            return UUID(uuidString: id as String)
        }

        if let idString = userInfo["scheduleID"] as? String {
            return UUID(uuidString: idString)
        }

        return nil
    }

    private nonisolated static func storePendingTappedScheduleID(_ id: UUID) {
        UserDefaults.standard.set(id.uuidString, forKey: pendingTappedScheduleIDKey)
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: pendingTappedScheduleTimestampKey)
        UserDefaults.standard.set(currentProcessSessionID, forKey: pendingTappedScheduleSessionKey)
    }

    private nonisolated static func clearPendingTappedScheduleID() {
        UserDefaults.standard.removeObject(forKey: pendingTappedScheduleIDKey)
        UserDefaults.standard.removeObject(forKey: pendingTappedScheduleTimestampKey)
        UserDefaults.standard.removeObject(forKey: pendingTappedScheduleSessionKey)
    }

    private nonisolated static func isAlarmFlagSet(in userInfo: [AnyHashable: Any]) -> Bool {
        if let value = userInfo["isAlarm"] as? Bool {
            return value
        }

        if let value = userInfo["isAlarm"] as? NSNumber {
            return value.boolValue
        }

        if let value = userInfo["isAlarm"] as? NSString {
            return isTruthyString(value as String)
        }

        if let value = userInfo["isAlarm"] as? String {
            return isTruthyString(value)
        }

        return false
    }

    private nonisolated static func isRepeatingFlagSet(in userInfo: [AnyHashable: Any]) -> Bool {
        if let value = userInfo["isRepeating"] as? Bool {
            return value
        }

        if let value = userInfo["isRepeating"] as? NSNumber {
            return value.boolValue
        }

        if let value = userInfo["isRepeating"] as? NSString {
            return isTruthyString(value as String)
        }

        if let value = userInfo["isRepeating"] as? String {
            return isTruthyString(value)
        }

        return false
    }

    private nonisolated static func stringValue(
        forKey key: String,
        in userInfo: [AnyHashable: Any]
    ) -> String? {
        if let value = userInfo[key] as? String {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }

        if let value = userInfo[key] as? NSString {
            let stringValue = value as String
            let trimmed = stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }

        return nil
    }

    private nonisolated static func isTruthyString(_ value: String) -> Bool {
        switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "1", "true", "yes", "y":
            return true
        default:
            return false
        }
    }

    private static func markNotificationRead(
        requestIdentifier: String,
        scheduleID: UUID?,
        isRepeating: Bool,
        occurrenceDate: Date?
    ) {
        let center = UNUserNotificationCenter.current()
        center.removeDeliveredNotifications(withIdentifiers: [requestIdentifier])
        clearAlarmBurstNotifications(for: requestIdentifier, center: center)

        if let scheduleID {
            if !isRepeating {
                let identifiers = allIdentifiersStatic(for: scheduleID)
                center.removePendingNotificationRequests(withIdentifiers: identifiers)
            }

            markWidgetSnapshotCompleted(
                scheduleID: scheduleID,
                occurrenceDate: occurrenceDate,
                isRepeating: isRepeating
            )

            Task { @MainActor in
                var payload: [String: Any] = ["scheduleID": scheduleID.uuidString]
                if let occurrenceDate {
                    payload["occurrenceTimestamp"] = occurrenceDate.timeIntervalSince1970
                }

                NotificationCenter.default.post(
                    name: .didMarkScheduleAsRead,
                    object: nil,
                    userInfo: payload
                )
            }
        } else {
            reloadWidgetTimelines()
        }
    }

    private static func markWidgetSnapshotCompleted(
        scheduleID: UUID,
        occurrenceDate: Date?,
        isRepeating: Bool
    ) {
        defer { reloadWidgetTimelines() }

        guard let defaults = UserDefaults(suiteName: widgetAppGroupID),
              let rawData = defaults.data(forKey: widgetSnapshotKey)
        else {
            return
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard var snapshot = try? decoder.decode(WidgetScheduleSnapshot.self, from: rawData) else {
            return
        }

        let scheduleIDValue = scheduleID.uuidString
        let doesMatchOccurrence: (Date) -> Bool = { itemDate in
            guard isRepeating, let occurrenceDate else { return true }
            let secondsDelta = abs(itemDate.timeIntervalSince(occurrenceDate))
            if secondsDelta <= 90 {
                return true
            }
            return Calendar.autoupdatingCurrent.isDate(
                itemDate,
                equalTo: occurrenceDate,
                toGranularity: .minute
            )
        }

        var didMutate = false

        for index in snapshot.upcoming.indices {
            guard snapshot.upcoming[index].id == scheduleIDValue else { continue }
            guard doesMatchOccurrence(snapshot.upcoming[index].scheduledDate) else { continue }
            if !snapshot.upcoming[index].isCompleted {
                snapshot.upcoming[index].isCompleted = true
                didMutate = true
            }
        }

        for index in snapshot.past.indices {
            guard snapshot.past[index].id == scheduleIDValue else { continue }
            guard doesMatchOccurrence(snapshot.past[index].scheduledDate) else { continue }
            if !snapshot.past[index].isCompleted {
                snapshot.past[index].isCompleted = true
                didMutate = true
            }
        }

        guard didMutate else { return }

        snapshot.updatedAt = Date()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let encoded = try? encoder.encode(snapshot) else { return }
        defaults.set(encoded, forKey: widgetSnapshotKey)
    }

    private static func reloadWidgetTimelines() {
#if canImport(WidgetKit)
        Task { @MainActor in
            WidgetCenter.shared.reloadTimelines(ofKind: "AlarmStatusWidget")
        }
#endif
    }
    
    /// Static version to generate all notification identifiers for a schedule ID
    private nonisolated static func allIdentifiersStatic(for scheduleID: UUID) -> [String] {
        let rootMainIdentifiers = mainRootIdentifiersStatic(for: scheduleID)
        var identifiers = rootMainIdentifiers
        identifiers.append("\(scheduleID.uuidString)-early")
        for rootIdentifier in rootMainIdentifiers {
            identifiers.append(contentsOf: alarmFollowUpIdentifiers(for: rootIdentifier))
        }

        let commonMinutes = [0, 5, 10, 15, 30, 45, 60, 90, 120, 180, 240, 360, 720, 1440]

        for weekday in 1...7 {
            for mins in commonMinutes {
                let suffix = mins > 0 ? "-\(mins)m" : ""
                identifiers.append("\(scheduleID.uuidString)-early-weekday-\(weekday)\(suffix)")
            }
        }

        for occurrenceIndex in 0..<maxFiniteRepeatOccurrences {
            for mins in commonMinutes {
                let suffix = mins > 0 ? "-\(mins)m" : ""
                identifiers.append("\(scheduleID.uuidString)-early-occ-\(occurrenceIndex)\(suffix)")
            }
        }

        for mins in commonMinutes where mins > 0 {
            identifiers.append("\(scheduleID.uuidString)-early-\(mins)m")
        }

        return identifiers
    }

    private nonisolated static func mainRootIdentifiersStatic(for scheduleID: UUID) -> [String] {
        var identifiers = ["\(scheduleID.uuidString)-main"]
        for weekday in 1...7 {
            identifiers.append("\(scheduleID.uuidString)-main-weekday-\(weekday)")
        }
        for occurrenceIndex in 0..<maxFiniteRepeatOccurrences {
            identifiers.append("\(scheduleID.uuidString)-main-occ-\(occurrenceIndex)")
        }
        return identifiers
    }

    private nonisolated static func bundledAlarmNotificationSound() -> UNNotificationSound {
        if Bundle.main.url(
            forResource: bundledAlarmSoundResource,
            withExtension: bundledAlarmSoundExtension
        ) != nil {
            return UNNotificationSound(named: bundledAlarmSoundName)
        }
        return .default
    }

    private nonisolated static func bundledNotificationSound(fileName: String?) -> UNNotificationSound {
        let resolvedFileName: String? = {
            guard let fileName else { return nil }
            if let option = AlarmSoundOption(rawValue: fileName),
               let bundledName = option.bestAvailableBundledSoundFileName {
                return bundledName
            }
            return fileName
        }()

        guard let fileName = resolvedFileName else { return bundledAlarmNotificationSound() }

        let normalizedName: String = {
            let trimmed = fileName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return bundledAlarmSoundResource }
            if let dotIndex = trimmed.lastIndex(of: ".") {
                return String(trimmed[..<dotIndex])
            }
            return trimmed
        }()

        if Bundle.main.url(
            forResource: normalizedName,
            withExtension: bundledAlarmSoundExtension
        ) != nil {
            let soundName = UNNotificationSoundName("\(normalizedName).\(bundledAlarmSoundExtension)")
            return UNNotificationSound(named: soundName)
        }

        return bundledAlarmNotificationSound()
    }

    private func mainIdentifier(for scheduleID: UUID, weekday: Int? = nil) -> String {
        if let weekday {
            return "\(scheduleID.uuidString)-main-weekday-\(weekday)"
        }
        return "\(scheduleID.uuidString)-main"
    }

    private func mainIdentifier(for scheduleID: UUID, occurrenceIndex: Int) -> String {
        "\(scheduleID.uuidString)-main-occ-\(occurrenceIndex)"
    }

    private func earlyIdentifier(for scheduleID: UUID, weekday: Int? = nil, minutesBefore: Int = 0) -> String {
        let suffix = minutesBefore > 0 ? "-\(minutesBefore)m" : ""
        if let weekday {
            return "\(scheduleID.uuidString)-early-weekday-\(weekday)\(suffix)"
        }
        return "\(scheduleID.uuidString)-early\(suffix)"
    }

    private func earlyIdentifier(for scheduleID: UUID, occurrenceIndex: Int, minutesBefore: Int = 0) -> String {
        let suffix = minutesBefore > 0 ? "-\(minutesBefore)m" : ""
        return "\(scheduleID.uuidString)-early-occ-\(occurrenceIndex)\(suffix)"
    }

    private func allIdentifiers(for scheduleID: UUID) -> [String] {
        let rootMainIdentifiers = mainIdentifiers(for: scheduleID)
        var identifiers = rootMainIdentifiers
        identifiers.append(earlyIdentifier(for: scheduleID))
        for rootIdentifier in rootMainIdentifiers {
            identifiers.append(contentsOf: Self.alarmFollowUpIdentifiers(for: rootIdentifier))
        }

        // Common early reminder offsets to clean up (covers most practical values)
        let commonMinutes = [0, 5, 10, 15, 30, 45, 60, 90, 120, 180, 240, 360, 720, 1440]

        for weekday in 1...7 {
            for mins in commonMinutes {
                identifiers.append(earlyIdentifier(for: scheduleID, weekday: weekday, minutesBefore: mins))
            }
        }
        for occurrenceIndex in 0..<Self.maxFiniteRepeatOccurrences {
            for mins in commonMinutes {
                identifiers.append(earlyIdentifier(for: scheduleID, occurrenceIndex: occurrenceIndex, minutesBefore: mins))
            }
        }
        for mins in commonMinutes {
            identifiers.append(earlyIdentifier(for: scheduleID, minutesBefore: mins))
        }

        return identifiers
    }

    private func mainIdentifiers(for scheduleID: UUID) -> [String] {
        var identifiers = [mainIdentifier(for: scheduleID)]
        for weekday in 1...7 {
            identifiers.append(mainIdentifier(for: scheduleID, weekday: weekday))
        }
        for occurrenceIndex in 0..<Self.maxFiniteRepeatOccurrences {
            identifiers.append(mainIdentifier(for: scheduleID, occurrenceIndex: occurrenceIndex))
        }
        return identifiers
    }

    private nonisolated static func alarmFollowUpIdentifier(
        for rootIdentifier: String,
        offsetSeconds: Int
    ) -> String {
        "\(rootIdentifier)-ring-\(offsetSeconds)"
    }

    private nonisolated static func alarmFollowUpIdentifiers(for rootIdentifier: String) -> [String] {
        let offsets = Array(
            Set(alarmFollowUpOffsetsSeconds + legacyAlarmFollowUpOffsetsSeconds)
        ).sorted()

        return offsets.map {
            alarmFollowUpIdentifier(for: rootIdentifier, offsetSeconds: $0)
        }
    }

    private nonisolated static func isLegacyFollowUpIdentifier(_ identifier: String) -> Bool {
        legacyAlarmFollowUpOffsetsSeconds.contains { offset in
            identifier.hasSuffix("-ring-\(offset)")
        }
    }

    private nonisolated static func alarmBurstRootIdentifier(from requestIdentifier: String) -> String {
        guard let markerRange = requestIdentifier.range(of: "-ring-", options: .backwards) else {
            return requestIdentifier
        }
        return String(requestIdentifier[..<markerRange.lowerBound])
    }

    private nonisolated static func clearAlarmBurstNotifications(
        for requestIdentifier: String,
        center: UNUserNotificationCenter
    ) {
        let rootIdentifier = alarmBurstRootIdentifier(from: requestIdentifier)
        let followUpIdentifiers = alarmFollowUpIdentifiers(for: rootIdentifier)
        // Never remove the root pending request here because repeating alarms use the
        // same root identifier and would get accidentally cancelled.
        center.removePendingNotificationRequests(withIdentifiers: followUpIdentifiers)
        center.removeDeliveredNotifications(withIdentifiers: [rootIdentifier] + followUpIdentifiers)
    }

    private nonisolated static func enqueueRequests(
        _ requests: [UNNotificationRequest],
        context: String
    ) {
        Task {
            for request in requests {
                do {
                    try await UNUserNotificationCenter.current().add(request)
                } catch {
                    Self.logger.error("\(context, privacy: .public) error: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }

    private nonisolated static let pendingTappedScheduleIDKey = "pendingTappedScheduleID"
    private nonisolated static let pendingTappedScheduleTimestampKey = "pendingTappedScheduleTimestamp"
    private nonisolated static let pendingTappedScheduleSessionKey = "pendingTappedScheduleSession"
    private nonisolated static let pendingTappedScheduleMaxAgeSeconds: TimeInterval = 90
    private nonisolated static let currentProcessSessionID = UUID().uuidString
}

private enum NotificationCategoryID {
    static let standardWithSnooze = "SCHEDULE_ALERT_SNOOZE"
    static let flaggedWithSnooze = "FLAGGED_SCHEDULE_SNOOZE"
    static let standardNoSnooze = "SCHEDULE_ALERT"
    static let flaggedNoSnooze = "FLAGGED_SCHEDULE"
    static let pushReminder = "PUSH_REMINDER"
}

private enum NotificationActionID {
    nonisolated static let stop = "STOP_ALARM"
    nonisolated static let snooze = "SNOOZE"
    nonisolated static let markAsRead = "MARK_AS_READ"
    nonisolated static let markComplete = "MARK_COMPLETE"
    // Legacy identifier for already-delivered notifications from older builds.
    nonisolated static let markDone = "MARK_DONE"
}

extension Notification.Name {
    static let didTapScheduleNotification = Notification.Name("didTapScheduleNotification")
    static let didMarkScheduleAsRead = Notification.Name("didMarkScheduleAsRead")
}
