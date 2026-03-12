import Foundation
import OSLog
import SwiftData
import SwiftUI
#if os(iOS)
import UIKit
#endif
#if canImport(WidgetKit)
import WidgetKit
#endif

enum ZoomLevel {
    case week
    case day
}

enum RecurringChangeScope {
    case all
    case thisDayOnly
}

/// Stable identity for a day row — avoids creating new arrays / tuples each render.
struct DayItem: Identifiable {
    let id: Date          // startOfDay is unique per row
    let index: Int
    let date: Date
    let schedules: [Schedule]
}

struct HeatmapDaySummary {
    let total: Int
    let completed: Int

    var completionRate: Double {
        guard total > 0 else { return 0 }
        return Double(completed) / Double(total)
    }

    static let empty = HeatmapDaySummary(total: 0, completed: 0)
}

@Observable
final class ScheduleViewModel {
    private static let syncLogger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.bittu.Schedulr",
        category: "sync"
    )
    private static let recurringCompletionStorageKey = "scheduleRecurringCompletion.v1"
    private static let widgetAppGroupID = "group.com.bittu.Schedulr"
    private static let widgetSnapshotKey = "widget.scheduleSnapshot.v1"
    private static let widgetCompletionRequestsKey = "widget.completeRequests.v1"
    private static let localBackupFileName = "schedule-backup-v1.json"
    private static let mergeLogStorageKey = "scheduleMergeLog.v1"
    private static let deviceIDStorageKey = "scheduleDeviceID.v1"
    private static let maxCachedDayBuckets = 140
    private static let calendarNamesStorageKey = "scheduleCalendarNames.v1"
    private static let lastRestoreCompletedAtKey = "scheduleLastRestoreCompletedAt.v1"
    private static let globalSyncVersionKey = "sync.globalVersion.v1"
    private static let lastAutoCloudUploadAtKey = "sync.lastAutoCloudUploadAt.v1"
    private static let autoSyncUnlockedAccountIDsKey = "sync.autoUnlockedAccountIDs.v1"
    private static let autoSyncMinBatteryLevel: Float = 0.35
    private static let autoSyncIntervalWithChanges: TimeInterval = 90
    private static let autoSyncIntervalWithChangesWhileCharging: TimeInterval = 60
    private static let autoSyncIntervalWithoutChanges: TimeInterval = 6 * 60 * 60
    private static let autoSyncIntervalWithoutChangesWhileCharging: TimeInterval = 30 * 60
    static let defaultCalendarName = "Reminders"

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

    private struct WidgetCompletionRequest: Codable {
        var scheduleID: String
        var occurrenceDate: Date
    }

    nonisolated private struct BackupPayload: Codable {
        var version: Int
        var exportedAt: Date
        var schedules: [BackupScheduleItem]
        var calendarNames: [String]?
        var recurringCompletionBySchedule: [String: [TimeInterval]]?
        var appSettings: BackupAppSettings?
        var globalSyncVersion: Int?
    }

    nonisolated private struct BackupAppSettings: Codable {
        var defaultAlertStyle: AlertDeliveryOption
        var defaultSnoozeDuration: Int
        var defaultEarlyReminderMinutes: Int
        var defaultRepeatPattern: RepeatPattern
        var defaultPriority: SchedulePriority
        var defaultCalendar: String
        var hotNaturalLanguageEnabled: Bool
        var firstDayOfWeek: Int
        var timeFormatPreferenceRawValue: String
        var accentColorHex: String
        var appearanceMode: Int
        var hapticFeedbackEnabled: Bool
        var notificationBadgeEnabled: Bool
        var autoSyncOnLaunch: Bool
        var showAlternativeCalendar: Bool
        var alternativeCalendarOptionRawValue: String
        var defaultTimeZoneOverride: String?
        var conflictDetectionEnabled: Bool
        var suppressNotificationsDuringFocus: Bool
        var dailyDigestEnabled: Bool
        var dailyDigestHour: Int
        var dailyDigestMinute: Int
        var settingsUpdatedAt: Date?
    }

    nonisolated private struct BackupScheduleItem: Codable {
        var id: UUID
        var createdAt: Date
        var updatedAt: Date
        var deletedAt: Date?
        var isSoftDeleted: Bool
        var lastModifiedDeviceID: String
        var title: String
        var notes: String?
        var urlString: String?
        var scheduledDate: Date
        var isUrgent: Bool
        var repeatPattern: RepeatPattern
        var repeatWeekdays: [Int]
        var excludedOccurrenceDates: [Date]
        var repeatEndOption: RepeatEndOption
        var repeatEndDate: Date?
        var alertDeliveryOption: AlertDeliveryOption
        var alarmSoundOption: AlarmSoundOption
        var alarmSnoozeEnabled: Bool
        var alarmSnoozeMinutes: Int
        var earlyReminderMinutes: Int?
        var listName: String
        var tags: [String]
        var isFlagged: Bool
        var isCompleted: Bool
        var priority: SchedulePriority
        var repeatInterval: Int?
        var repeatEndCount: Int?
        var additionalReminderMinutes: [Int]?
        var timeZoneIdentifier: String?
    }

    private struct MergeLogEntry: Codable {
        var scheduleID: UUID
        var winnerUpdatedAt: Date
        var loserUpdatedAt: Date
        var mergedAt: Date
    }

    var schedules: [Schedule] = []
    var zoomLevel: ZoomLevel = .week
    var selectedDayIndex: Int = 0
    var isLoading = false
    var showingAddForm = false
    var editingSchedule: Schedule?
    var editingOccurrenceDate: Date?
    var pendingNewScheduleDate: Date?
    var pendingNewScheduleNLPInput: String?
    var calendarNames: [String] = ["Reminders"]
    var canUndo = false
    var canRedo = false
    var undoActionName: String?
    var redoActionName: String?
    var isBulkSelectionMode = false
    var selectedScheduleIDs: Set<UUID> = []
    var isRestoreInProgress = false
    var restoreProgress: Double = 0
    var lastRestoreCompletedAt: Date? = UserDefaults.standard.object(forKey: ScheduleViewModel.lastRestoreCompletedAtKey) as? Date
    var pendingConflictScheduleIDs: [UUID] = []
    var isSyncNowInProgress = false
    var syncCoordinator = SyncCoordinator.shared

    /// Cached week dates — rebuilt only when `currentWeekStart` changes.
    private(set) var weekDates: [Date] = []
    /// Pre-built rows for the current week with schedules attached.
    private(set) var dayItems: [DayItem] = []

    private var _currentWeekStart: Date = Date().startOfWeek

    var currentWeekStart: Date {
        get { _currentWeekStart }
        set {
            guard newValue != _currentWeekStart else { return }
            _currentWeekStart = newValue
            rebuildWeek()
        }
    }

    private var modelContext: ModelContext?
    private var schedulesByDay: [Date: [Schedule]] = [:]
    private var dayCacheAccessOrder: [Date] = []
    private var recurringCompletionBySchedule: [UUID: Set<Date>] = [:]
    private var hasLoadedInitialData = false
    private var normalizeTask: Task<Void, Never>?
    private var backupWriteTask: Task<Void, Never>?
    private var lastWidgetReloadAt: Date = .distantPast
    private var lastAutoCloudUploadAt: Date = UserDefaults.standard.object(
        forKey: ScheduleViewModel.lastAutoCloudUploadAtKey
    ) as? Date ?? .distantPast
    private var suppressNextAutoCloudUpload = false
    private var isCloudRestoreInProgress = false
    private var isApplyingUndoRedo = false
    private var dirtyScheduleIDs: Set<UUID> = []
    private var globalSyncVersion: Int = UserDefaults.standard.integer(forKey: ScheduleViewModel.globalSyncVersionKey)

    private var currentDeviceID: String {
        let defaults = UserDefaults.standard
        if let existing = defaults.string(forKey: Self.deviceIDStorageKey), !existing.isEmpty {
            return existing
        }
        let generated = UUID().uuidString
        defaults.set(generated, forKey: Self.deviceIDStorageKey)
        return generated
    }

    var selectedDate: Date {
        weekDates[safe: selectedDayIndex] ?? Date()
    }

    var hasPendingConflicts: Bool {
        !syncCoordinator.pendingConflicts.isEmpty
    }

    var visibleSchedules: [Schedule] {
        schedules.filter { shouldDisplaySchedule($0) }
    }

    var weekTitle: String {
        _currentWeekStart.monthYearString
    }

    var dayTitle: String {
        selectedDate.fullDayString
    }

    func setup(modelContext: ModelContext) {
        self.modelContext = modelContext
        guard !hasLoadedInitialData else { return }
        hasLoadedInitialData = true
        refreshUndoRedoState()
        loadCalendarNames()
        loadRecurringCompletionState()
        rebuildWeek()
        fetchSchedules()
        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.syncCoordinator.drainOfflineQueue(viewModel: self)
        }
        restoreFromLocalBackupIfNeeded()
        consumeWidgetCompletionRequests()
        observeMarkAsReadNotifications()
        observeSiriIntents()
        observeNetworkRecovery()
    }

    func consumeWidgetCompletionRequests() {
        guard let defaults = UserDefaults(suiteName: Self.widgetAppGroupID),
              let rawData = defaults.data(forKey: Self.widgetCompletionRequestsKey)
        else {
            return
        }

          let decoder = JSONDecoder()
          decoder.dateDecodingStrategy = .iso8601
        guard let requests = try? decoder.decode([WidgetCompletionRequest].self, from: rawData),
              !requests.isEmpty
        else {
            defaults.removeObject(forKey: Self.widgetCompletionRequestsKey)
            return
        }

        defaults.removeObject(forKey: Self.widgetCompletionRequestsKey)

        var changed = false
        for request in requests {
            guard let scheduleID = UUID(uuidString: request.scheduleID),
                  let schedule = schedule(withID: scheduleID)
            else {
                continue
            }

            if schedule.repeatPattern == .never {
                guard !schedule.isCompleted else { continue }
                schedule.isCompleted = true
                touch(schedule)
                NotificationManager.shared.cancelNotification(for: schedule)
                changed = true
            } else {
                let day = request.occurrenceDate.startOfDay
                guard !isScheduleCompleted(schedule, on: day) else { continue }
                setRecurringCompletion(for: schedule, on: day, isCompleted: true)
                changed = true
            }
        }

        guard changed else {
            updateWidgetSnapshot()
            return
        }

        saveContext()
        normalizeSchedules()
    }

    func markScheduleCompleted(scheduleID: UUID, occurrenceDate: Date? = nil) {
        guard let schedule = schedule(withID: scheduleID) else { return }

        if schedule.repeatPattern == .never {
            guard !schedule.isCompleted else { return }
            schedule.isCompleted = true
            touch(schedule)
            NotificationManager.shared.cancelNotification(for: schedule)
            saveContext()
            normalizeSchedules()
            return
        }

        let day = (occurrenceDate ?? Date()).startOfDay
        guard !isScheduleCompleted(schedule, on: day) else { return }
        setRecurringCompletion(for: schedule, on: day, isCompleted: true)
    }

    /// Ensures a consistent default landing state on cold launch.
    func prepareDefaultWeekLanding() {
        let today = Date()
        currentWeekStart = today.startOfWeek

        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: today)
        let firstWeekday = AppSettings.shared.firstDayOfWeek
        selectedDayIndex = (weekday - firstWeekday + 7) % 7

        zoomLevel = .week
    }

    private func observeMarkAsReadNotifications() {
        NotificationCenter.default.addObserver(
            forName: .didMarkScheduleAsRead,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self,
                  let scheduleIDString = notification.userInfo?["scheduleID"] as? String,
                  let scheduleID = UUID(uuidString: scheduleIDString),
                  let schedule = self.schedule(withID: scheduleID)
            else { return }

            if schedule.repeatPattern == .never {
                schedule.isCompleted = true
                self.touch(schedule)
                self.saveContext()
                self.normalizeSchedules()
                HapticManager.notification(.success)
                return
            }

            let occurrenceDate = self.occurrenceDate(from: notification.userInfo) ?? Date()
            self.setRecurringCompletion(for: schedule, on: occurrenceDate, isCompleted: true)
            HapticManager.notification(.success)
        }
    }

    func fetchSchedules() {
        guard let modelContext else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let descriptor = FetchDescriptor<Schedule>(
                sortBy: [SortDescriptor(\.scheduledDate)]
            )
            schedules = try modelContext.fetch(descriptor).filter { !$0.isSoftDeleted }
            resolveScheduleConflictsByLatestUpdate()
            pruneRecurringCompletionState()
            normalizeSchedules(immediate: true)
        } catch {
            print("Fetch error: \(error)")
            schedules = []
            schedulesByDay = [:]
            dayCacheAccessOrder = []
        }
    }

    func schedules(for date: Date) -> [Schedule] {
        let day = date.startOfDay
        if let cached = schedulesByDay[day] {
            markDayCacheAccess(for: day)
            return cached
        }

        let calendar = Calendar.current
        let filtered = visibleSchedules.filter { schedule in
            occurs(schedule, on: day, calendar: calendar)
        }
        let sorted = filtered.sorted { lhs, rhs in
            isScheduledEarlier(lhs, than: rhs, calendar: calendar)
        }
        schedulesByDay[day] = sorted
        markDayCacheAccess(for: day)
        trimDayCacheIfNeeded()
        return sorted
    }

    /// Returns a pure month summary used by the heatmap without mutating cache state.
    func monthHeatmapSummary(for month: Date) -> [Date: HeatmapDaySummary] {
        let calendar = Calendar.current
        guard let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: month.startOfDay)),
              let monthRange = calendar.range(of: .day, in: .month, for: monthStart)
        else {
            return [:]
        }

        let visible = visibleSchedules
        var summary: [Date: HeatmapDaySummary] = [:]
        summary.reserveCapacity(monthRange.count)

        for day in monthRange {
            guard let currentDay = calendar.date(byAdding: .day, value: day - 1, to: monthStart)?.startOfDay else {
                continue
            }

            let occurring = visible.filter { schedule in
                occurs(schedule, on: currentDay, calendar: calendar)
            }
            let completed = occurring.filter { schedule in
                isScheduleCompleted(schedule, on: currentDay)
            }.count

            summary[currentDay] = HeatmapDaySummary(total: occurring.count, completed: completed)
        }

        return summary
    }

    /// Pre-compute daily schedule buckets for one or more months so calendar views open faster.
    func prewarmMonthScheduleCache(around date: Date, monthSpan: Int = 0) {
        guard !schedules.isEmpty else { return }

        let calendar = Calendar.current
        let baseMonth = calendar.date(
            from: calendar.dateComponents([.year, .month], from: date.startOfDay)
        ) ?? date.startOfDay

        for monthOffset in (-monthSpan...monthSpan) {
            guard let monthStart = calendar.date(byAdding: .month, value: monthOffset, to: baseMonth),
                  let daysRange = calendar.range(of: .day, in: .month, for: monthStart)
            else {
                continue
            }

            for day in daysRange {
                guard let currentDay = calendar.date(byAdding: .day, value: day - 1, to: monthStart) else {
                    continue
                }
                _ = schedules(for: currentDay.startOfDay)
            }
        }
    }

    func exportBackupData() -> Data? {
        let payload = BackupPayload(
            version: 2,
            exportedAt: Date(),
            schedules: schedules
                .filter { !$0.isSoftDeleted }
                .map { schedule in
                    BackupScheduleItem(
                        id: schedule.id,
                        createdAt: schedule.createdAt,
                        updatedAt: schedule.updatedAt,
                        deletedAt: schedule.deletedAt,
                        isSoftDeleted: schedule.isSoftDeleted,
                        lastModifiedDeviceID: schedule.lastModifiedDeviceID,
                        title: schedule.title,
                        notes: schedule.notes,
                        urlString: schedule.urlString,
                        scheduledDate: schedule.scheduledDate,
                        isUrgent: schedule.isUrgent,
                        repeatPattern: schedule.repeatPattern,
                        repeatWeekdays: schedule.repeatWeekdays,
                        excludedOccurrenceDates: schedule.excludedOccurrenceDates,
                        repeatEndOption: schedule.repeatEndOption,
                        repeatEndDate: schedule.repeatEndDate,
                        alertDeliveryOption: schedule.alertDeliveryOption,
                        alarmSoundOption: schedule.alarmSoundOption,
                        alarmSnoozeEnabled: schedule.alarmSnoozeEnabled,
                        alarmSnoozeMinutes: schedule.alarmSnoozeMinutes,
                        earlyReminderMinutes: schedule.earlyReminderMinutes,
                        listName: schedule.listName,
                        tags: schedule.tags,
                        isFlagged: schedule.isFlagged,
                        isCompleted: schedule.isCompleted,
                        priority: schedule.priority,
                        repeatInterval: schedule.repeatInterval,
                        repeatEndCount: schedule.repeatEndCount,
                        additionalReminderMinutes: schedule.additionalReminderMinutes,
                        timeZoneIdentifier: schedule.timeZoneIdentifier
                    )
                },
            calendarNames: calendarNames,
            recurringCompletionBySchedule: encodedRecurringCompletionStateForBackup(),
            appSettings: backupAppSettingsSnapshot(),
            globalSyncVersion: globalSyncVersion
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try? encoder.encode(payload)
    }

    @discardableResult
    func importBackupData(
        _ data: Data,
        includeSchedules: Bool = true,
        includeSettings: Bool = true,
        preferRemoteOnConflict: Bool = false
    ) -> RestoreResult {
        guard let modelContext else { return RestoreResult(failure: .noModelContext) }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let payload = try? decoder.decode(BackupPayload.self, from: data) else {
            return RestoreResult(failure: .decodeFailed)
        }

        suppressNextAutoCloudUpload = true

        isRestoreInProgress = true
        restoreProgress = 0
        var result = RestoreResult()
        defer {
            isRestoreInProgress = false
            restoreProgress = 1
            let completedAt = Date()
            lastRestoreCompletedAt = completedAt
            UserDefaults.standard.set(completedAt, forKey: Self.lastRestoreCompletedAtKey)
        }

        let scheduleSteps = includeSchedules ? max(payload.schedules.count, 1) : 0
        let totalSteps = max(1, 2 + scheduleSteps)
        var completedSteps = 0

        func advanceProgress(by value: Int = 1) {
            completedSteps += value
            let fraction = min(1, Double(completedSteps) / Double(totalSteps))
            restoreProgress = fraction
        }

        if includeSettings, let backupSettings = payload.appSettings {
            applyBackupAppSettings(backupSettings)
            result.settingsApplied = true
        }
        advanceProgress()

        guard includeSchedules else {
            advanceProgress()
            return result
        }

        if let backupCalendarNames = payload.calendarNames {
            calendarNames = sanitizedCalendarNames(from: calendarNames + backupCalendarNames)
            persistCalendarNames()
        }

        if let encodedRecurringCompletion = payload.recurringCompletionBySchedule {
            mergeRecurringCompletionStateFromBackup(encodedRecurringCompletion)
        }
        advanceProgress()

        let allRecords = (try? modelContext.fetch(FetchDescriptor<Schedule>())) ?? []
        var existingByID = Dictionary(uniqueKeysWithValues: allRecords.map { ($0.id, $0) })

        for backupItem in payload.schedules {
            let remoteSchedule = scheduleFromBackupItem(backupItem)

            if let existing = existingByID[backupItem.id] {
                let resolution: BlobConflictAction = preferRemoteOnConflict
                    ? .keepRemote
                    : SyncConflictResolver.resolveBlobRestoreConflict(localSchedule: existing, remoteSchedule: remoteSchedule)
                switch resolution {
                case .keepLocal:
                    result.skippedCount += 1
                case .keepRemote:
                    apply(backupItem, to: existing)
                    result.mergedCount += 1
                case .merge(let merged):
                    applyScheduleValues(from: merged, to: existing)
                    existing.updatedAt = merged.updatedAt
                    existing.lastModifiedDeviceID = merged.lastModifiedDeviceID
                    existing.syncVersion = max(existing.syncVersion, merged.syncVersion)
                    result.mergedCount += 1
                case .askUser:
                    let localDelta = ScheduleDelta(schedule: existing, deviceID: currentDeviceID)
                    let remoteDelta = ScheduleDelta(schedule: remoteSchedule, deviceID: remoteSchedule.lastModifiedDeviceID)
                    if !syncCoordinator.pendingConflicts.contains(where: { $0.scheduleID == existing.id }) {
                        syncCoordinator.pendingConflicts.append(
                            SyncCoordinator.ConflictRecord(
                                scheduleID: existing.id,
                                local: localDelta,
                                remote: remoteDelta
                            )
                        )
                    }
                    result.conflictCount += 1
                }
                existing.lastSyncedVersion = existing.syncVersion
                advanceProgress()
                continue
            }

            if let sameIdentitySchedule = existingByID.values.first(where: {
                $0.title == backupItem.title && $0.scheduledDate == backupItem.scheduledDate
            }) {
                let resolution: BlobConflictAction = preferRemoteOnConflict
                    ? .keepRemote
                    : SyncConflictResolver.resolveBlobRestoreConflict(localSchedule: sameIdentitySchedule, remoteSchedule: remoteSchedule)
                switch resolution {
                case .keepLocal:
                    result.skippedCount += 1
                case .keepRemote:
                    apply(backupItem, to: sameIdentitySchedule)
                    result.mergedCount += 1
                case .merge(let merged):
                    applyScheduleValues(from: merged, to: sameIdentitySchedule)
                    sameIdentitySchedule.updatedAt = merged.updatedAt
                    sameIdentitySchedule.lastModifiedDeviceID = merged.lastModifiedDeviceID
                    sameIdentitySchedule.syncVersion = max(sameIdentitySchedule.syncVersion, merged.syncVersion)
                    result.mergedCount += 1
                case .askUser:
                    let localDelta = ScheduleDelta(schedule: sameIdentitySchedule, deviceID: currentDeviceID)
                    let remoteDelta = ScheduleDelta(schedule: remoteSchedule, deviceID: remoteSchedule.lastModifiedDeviceID)
                    if !syncCoordinator.pendingConflicts.contains(where: { $0.scheduleID == sameIdentitySchedule.id }) {
                        syncCoordinator.pendingConflicts.append(
                            SyncCoordinator.ConflictRecord(
                                scheduleID: sameIdentitySchedule.id,
                                local: localDelta,
                                remote: remoteDelta
                            )
                        )
                    }
                    result.conflictCount += 1
                }
                sameIdentitySchedule.lastSyncedVersion = sameIdentitySchedule.syncVersion
                advanceProgress()
                continue
            }

            let restored = Schedule(
                id: backupItem.id,
                createdAt: backupItem.createdAt,
                updatedAt: backupItem.updatedAt,
                deletedAt: backupItem.deletedAt,
                isSoftDeleted: backupItem.isSoftDeleted,
                lastModifiedDeviceID: backupItem.lastModifiedDeviceID,
                title: backupItem.title,
                notes: backupItem.notes,
                urlString: backupItem.urlString,
                scheduledDate: backupItem.scheduledDate,
                isUrgent: backupItem.isUrgent,
                repeatPattern: backupItem.repeatPattern,
                repeatWeekdays: backupItem.repeatWeekdays,
                excludedOccurrenceDates: backupItem.excludedOccurrenceDates,
                repeatEndOption: backupItem.repeatEndOption,
                repeatEndDate: backupItem.repeatEndDate,
                alertDeliveryOption: backupItem.alertDeliveryOption,
                alarmSoundOption: backupItem.alarmSoundOption,
                alarmSnoozeEnabled: backupItem.alarmSnoozeEnabled,
                alarmSnoozeMinutes: backupItem.alarmSnoozeMinutes,
                earlyReminderMinutes: backupItem.earlyReminderMinutes,
                listName: backupItem.listName,
                tags: backupItem.tags,
                isFlagged: backupItem.isFlagged,
                isCompleted: backupItem.isCompleted,
                priority: backupItem.priority
            )
            restored.repeatInterval = backupItem.repeatInterval ?? 1
            restored.repeatEndCount = backupItem.repeatEndCount ?? 0
            restored.additionalReminderMinutes = backupItem.additionalReminderMinutes ?? []
            restored.timeZoneIdentifier = backupItem.timeZoneIdentifier
            restored.lastSyncedVersion = restored.syncVersion
            modelContext.insert(restored)
            existingByID[restored.id] = restored
            result.restoredCount += 1
            advanceProgress()
        }

        if let restoredSyncVersion = payload.globalSyncVersion {
            seedGlobalSyncVersion(restoredSyncVersion)
        }

        saveContext()
        fetchSchedules()
        pendingConflictScheduleIDs = Array(Set(syncCoordinator.pendingConflictScheduleIDs))
        restoreProgress = 1
        return result
    }

    func syncCloudBackupNowIfSignedIn() {
        guard !isCloudRestoreInProgress else {
            syncCoordinator.syncLastActivityMessage = "Sync blocked while cloud restore is active."
            Self.syncLogger.warning("Manual sync blocked: cloud restore gate is active")
            return
        }
        guard FirebaseSyncService.shared.isSignedIn else {
            syncCoordinator.syncLastActivityMessage = "Sync blocked: account is signed out."
            Self.syncLogger.warning("Manual sync blocked: user not signed in")
            return
        }
        guard FirebaseSyncService.shared.isNetworkReachable else {
            FirebaseSyncService.shared.lastErrorMessage = "No internet connection"
            syncCoordinator.syncState = .error
            syncCoordinator.syncLastActivityMessage = "Sync blocked: no internet connection."
            Self.syncLogger.warning("Manual sync blocked: no network reachability")
            return
        }

        syncNowWithCoordinator(userInitiated: true)
    }

    func autoSyncCloudBackupIfEligible(requirePendingScheduleChanges: Bool = false) {
        guard !isCloudRestoreInProgress else { return }
        guard FirebaseSyncService.shared.isSignedIn else { return }
        guard isAutoSyncUnlockedForCurrentAccount() else { return }
        guard shouldRunAutomaticCloudSync(requirePendingScheduleChanges: requirePendingScheduleChanges) else { return }

        syncNowWithCoordinator(userInitiated: false)
    }

    func syncNowWithCoordinator(userInitiated: Bool = true) {
        guard !isSyncNowInProgress else {
            syncCoordinator.syncLastActivityMessage = "Sync already running."
            Self.syncLogger.info("Manual sync ignored: sync already in progress")
            return
        }
        isSyncNowInProgress = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            let hardTimeoutSeconds: Double = 90
            let timeoutTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(hardTimeoutSeconds))
                guard let self else { return }
                guard self.isSyncNowInProgress else { return }

                let lastActivity = self.syncCoordinator.syncLastActivityMessage ?? "Unknown phase"
                self.syncCoordinator.syncState = .error
                self.syncCoordinator.syncLastActivityMessage = "Sync timed out. Please try again."
                self.syncCoordinator.lastSyncReport = SyncRunReport(
                    deltaPushSucceeded: false,
                    deltaPullSucceeded: false,
                    backupUploadSucceeded: false,
                    offlineQueueChanged: false,
                    conflictsRemaining: self.syncCoordinator.pendingConflictScheduleIDs.count,
                    deltaPushCount: 0,
                    deltaPullCount: 0,
                    failure: .firestoreFailed("Sync timed out after \(Int(hardTimeoutSeconds))s while: \(lastActivity)"),
                    warnings: ["Hard timeout released sync lock"]
                )
                self.isSyncNowInProgress = false
                Self.syncLogger.error("Hard timeout released stuck sync after \(hardTimeoutSeconds, privacy: .public)s; last activity=\(lastActivity, privacy: .public)")
            }

            defer {
                timeoutTask.cancel()
                self.isSyncNowInProgress = false
            }
            let report = await self.syncCoordinator.syncNow(viewModel: self, userInitiated: userInitiated)
            if report.succeeded {
                FirebaseSyncService.shared.lastSyncedAt = Date()
            }
            if userInitiated, report.succeeded {
                self.unlockAutoSyncForCurrentAccount()
            }
            self.pendingConflictScheduleIDs = Array(Set(self.syncCoordinator.pendingConflictScheduleIDs))
        }
    }

    func beginCloudRestoreGate() {
        isCloudRestoreInProgress = true
    }

    func completeCloudRestoreGate() {
        isCloudRestoreInProgress = false
    }

    func schedule(withID id: UUID) -> Schedule? {
        schedules.first { $0.id == id }
    }

    @discardableResult
    func addCalendar(named rawName: String) -> Bool {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return false }

        let exists = calendarNames.contains { $0.caseInsensitiveCompare(name) == .orderedSame }
        guard !exists else { return false }

        calendarNames.append(name)
        persistCalendarNames()
        scheduleAutomaticCloudUploadIfNeeded()
        return true
    }

    func removeCalendar(named name: String) {
        guard calendarNames.count > 1 else { return }
        guard name.caseInsensitiveCompare(Self.defaultCalendarName) != .orderedSame else { return }
        guard let index = calendarNames.firstIndex(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) else {
            return
        }

        let removed = calendarNames.remove(at: index)
        let fallback = calendarNames.first ?? Self.defaultCalendarName
        var reassigned = false

        for schedule in schedules where schedule.listName.caseInsensitiveCompare(removed) == .orderedSame {
            schedule.listName = fallback
            touch(schedule)
            reassigned = true
        }

        persistCalendarNames()
        if reassigned {
            saveContext()
            normalizeSchedules()
        } else {
            scheduleAutomaticCloudUploadIfNeeded()
        }
    }

    func isScheduleCompleted(_ schedule: Schedule, on occurrenceDate: Date) -> Bool {
        if schedule.repeatPattern == .never {
            return schedule.isCompleted
        }

        let day = occurrenceDate.startOfDay
        return recurringCompletionBySchedule[schedule.id]?.contains(day) ?? false
    }

    func addSchedule(_ schedule: Schedule) {
        guard let modelContext else { return }
        guard !isScheduleDateInPast(schedule.scheduledDate) else {
            HapticManager.notification(.warning)
            return
        }
        schedule.isSoftDeleted = false
        schedule.deletedAt = nil
        touch(schedule)
        modelContext.insert(schedule)
        saveContext()
        schedules.append(schedule)
        if !isApplyingUndoRedo {
            UndoRedoManager.shared.record(.create(ScheduleSnapshot(from: schedule)))
            refreshUndoRedoState()
        }
        normalizeSchedules()
        NotificationManager.shared.scheduleNotification(for: schedule)
        RealtimeSyncCoordinator.shared.pushLocalChange(schedule: schedule)
        pendingNewScheduleDate = nil
        HapticManager.notification(.success)
    }

    func startEditingSchedule(_ schedule: Schedule, on occurrenceDate: Date? = nil) {
        editingSchedule = schedule
        editingOccurrenceDate = occurrenceDate?.startOfDay
    }

    func clearEditingOccurrenceDate() {
        editingOccurrenceDate = nil
    }

    func deleteSchedule(_ schedule: Schedule) {
        guard modelContext != nil else { return }
        let snapshot = ScheduleSnapshot(from: schedule)
        NotificationManager.shared.cancelNotification(for: schedule)
        schedule.isSoftDeleted = true
        schedule.deletedAt = Date()
        touch(schedule)
        saveContext()
        schedules.removeAll { $0.id == schedule.id }
        if recurringCompletionBySchedule.removeValue(forKey: schedule.id) != nil {
            persistRecurringCompletionState()
        }
        if !isApplyingUndoRedo {
            UndoRedoManager.shared.record(.delete(snapshot))
            refreshUndoRedoState()
        }
        normalizeSchedules()
        RealtimeSyncCoordinator.shared.pushLocalDeletion(scheduleID: schedule.id.uuidString)
        HapticManager.notification(.warning)
    }

    func deleteSchedule(
        _ schedule: Schedule,
        on occurrenceDate: Date,
        scope: RecurringChangeScope
    ) {
        guard schedule.repeatPattern != .never, scope == .thisDayOnly else {
            deleteSchedule(schedule)
            return
        }

        excludeOccurrence(schedule, on: occurrenceDate)
        touch(schedule)
        saveContext()
        NotificationManager.shared.updateNotification(for: schedule)
        normalizeSchedules()
        HapticManager.notification(.warning)
    }

    func updateSchedule(_ schedule: Schedule) {
        updateSchedule(schedule, previousSnapshot: nil)
    }

    func updateSchedule(_ schedule: Schedule, previousSnapshot: ScheduleSnapshot?) {
        guard !isScheduleDateInPast(schedule.scheduledDate) else {
            HapticManager.notification(.warning)
            return
        }

        let oldSnapshot = previousSnapshot ?? ScheduleSnapshot(from: schedule)

        if schedule.repeatPattern == .never {
            schedule.excludedOccurrenceDates = []
            if recurringCompletionBySchedule.removeValue(forKey: schedule.id) != nil {
                persistRecurringCompletionState()
            }
        }

        touch(schedule)

        saveContext()
        if schedule.repeatPattern == .never && schedule.isCompleted {
            NotificationManager.shared.cancelNotification(for: schedule)
        } else {
            NotificationManager.shared.updateNotification(for: schedule)
        }
        if !isApplyingUndoRedo {
            let newSnapshot = ScheduleSnapshot(from: schedule)
            UndoRedoManager.shared.record(.update(old: oldSnapshot, new: newSnapshot))
            refreshUndoRedoState()
        }
        normalizeSchedules()
        RealtimeSyncCoordinator.shared.pushLocalChange(schedule: schedule)
    }

    func updateRecurringSchedule(
        _ schedule: Schedule,
        occurrenceDate: Date,
        editedSchedule: Schedule,
        scope: RecurringChangeScope
    ) {
        switch scope {
        case .all:
            let oldSnapshot = ScheduleSnapshot(from: schedule)
            applyScheduleValues(from: editedSchedule, to: schedule)
            updateSchedule(schedule, previousSnapshot: oldSnapshot)

        case .thisDayOnly:
            guard let modelContext else { return }
            guard schedule.repeatPattern != .never else {
                let oldSnapshot = ScheduleSnapshot(from: schedule)
                applyScheduleValues(from: editedSchedule, to: schedule)
                updateSchedule(schedule, previousSnapshot: oldSnapshot)
                return
            }

            excludeOccurrence(schedule, on: occurrenceDate)

            let detachedSchedule = buildDetachedSingleOccurrence(
                from: editedSchedule,
                occurrenceDate: occurrenceDate
            )
            modelContext.insert(detachedSchedule)

            saveContext()
            schedules.append(detachedSchedule)
            NotificationManager.shared.scheduleNotification(for: detachedSchedule)
            NotificationManager.shared.updateNotification(for: schedule)
            normalizeSchedules()
            RealtimeSyncCoordinator.shared.pushLocalChange(schedule: detachedSchedule)
            RealtimeSyncCoordinator.shared.pushLocalChange(schedule: schedule)
        }
    }

    func toggleScheduleCompletion(_ schedule: Schedule, on occurrenceDate: Date? = nil) {
        if schedule.repeatPattern != .never {
            let day = (occurrenceDate ?? selectedDate).startOfDay
            let isNowCompleted = !isScheduleCompleted(schedule, on: day)
            setRecurringCompletion(for: schedule, on: day, isCompleted: isNowCompleted)
            if isNowCompleted {
                HapticManager.notification(.success)
            } else {
                HapticManager.selection()
            }
            return
        }

        schedule.isCompleted.toggle()
        let wasCompleted = !schedule.isCompleted
        touch(schedule)
        saveContext()

        if schedule.isCompleted {
            NotificationManager.shared.cancelNotification(for: schedule)
            HapticManager.notification(.success)
        } else {
            let shouldBeActive = schedule.repeatPattern != .never || schedule.scheduledDate > Date()
            if shouldBeActive {
                NotificationManager.shared.updateNotification(for: schedule)
            }
            HapticManager.selection()
        }

        if !isApplyingUndoRedo {
            UndoRedoManager.shared.record(.complete(id: schedule.id, wasCompleted: wasCompleted))
            refreshUndoRedoState()
        }

        normalizeSchedules()
        RealtimeSyncCoordinator.shared.pushLocalChange(schedule: schedule)
    }

    func resyncAllScheduleNotifications() {
        for schedule in schedules {
            if schedule.isSoftDeleted {
                NotificationManager.shared.cancelNotification(for: schedule)
                continue
            }
            if schedule.repeatPattern == .never && schedule.isCompleted {
                NotificationManager.shared.cancelNotification(for: schedule)
                continue
            }
            let shouldBeActive = schedule.repeatPattern != .never || schedule.scheduledDate > Date()
            if shouldBeActive {
                NotificationManager.shared.updateNotification(for: schedule)
            } else {
                NotificationManager.shared.cancelNotification(for: schedule)
            }
        }
    }

    func rescheduleDailyDigest() {
        DailyDigestService.shared.updateSchedule(
            using: schedules,
            occurrenceMatcher: { schedule, day, calendar in
                self.occurs(schedule, on: day, calendar: calendar)
            }
        )
    }

    func zoomToDay(index: Int) {
        selectedDayIndex = min(max(index, 0), 6)
        zoomLevel = .day
        HapticManager.impact(.medium)
    }

    func zoomToWeek() {
        zoomLevel = .week
        HapticManager.impact(.light)
    }

    func goToPreviousWeek() {
        if let newStart = Calendar.current.date(byAdding: .weekOfYear, value: -1, to: currentWeekStart) {
            currentWeekStart = newStart
        }
    }

    func goToNextWeek() {
        if let newStart = Calendar.current.date(byAdding: .weekOfYear, value: 1, to: currentWeekStart) {
            currentWeekStart = newStart
        }
    }

    func goToPreviousDay() {
        if selectedDayIndex > 0 {
            selectedDayIndex -= 1
        } else {
            goToPreviousWeek()
            selectedDayIndex = 6
        }
        HapticManager.selection()
    }

    func goToNextDay() {
        if selectedDayIndex < 6 {
            selectedDayIndex += 1
        } else {
            goToNextWeek()
            selectedDayIndex = 0
        }
        HapticManager.selection()
    }

    func goToToday() {
        currentWeekStart = Date().startOfWeek
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: Date())
        let firstWeekday = AppSettings.shared.firstDayOfWeek
        selectedDayIndex = (weekday - firstWeekday + 7) % 7
    }

    @discardableResult
    func focusOnSchedule(withID id: UUID) -> Bool {
        guard let schedule = schedule(withID: id) else { return false }
        focus(on: schedule.scheduledDate)
        return true
    }

    func focus(on date: Date) {
        currentWeekStart = date.startOfWeek

        if let index = weekDates.firstIndex(where: { Calendar.current.isDate($0, inSameDayAs: date) }) {
            selectedDayIndex = index
        } else {
            selectedDayIndex = 0
        }

        // Stay on whichever zoom level the user is already on (week or day).
        // Do NOT force zoomLevel = .day here so that notification taps
        // land on the week view with the correct day highlighted.
    }

    func startAddingSchedule(on date: Date, dayIndex: Int) {
        selectedDayIndex = min(max(dayIndex, 0), 6)
        pendingNewScheduleDate = dateWithCurrentTime(from: date)
        showingAddForm = true
    }

    func toggleBulkSelectionMode() {
        isBulkSelectionMode.toggle()
        if !isBulkSelectionMode {
            selectedScheduleIDs.removeAll()
        }
    }

    func clearBulkSelection() {
        selectedScheduleIDs.removeAll()
        isBulkSelectionMode = false
    }

    func isScheduleSelected(_ scheduleID: UUID) -> Bool {
        selectedScheduleIDs.contains(scheduleID)
    }

    func toggleScheduleSelection(_ scheduleID: UUID) {
        if selectedScheduleIDs.contains(scheduleID) {
            selectedScheduleIDs.remove(scheduleID)
        } else {
            selectedScheduleIDs.insert(scheduleID)
        }
    }

    func markSelectedSchedulesCompleted(on occurrenceDate: Date) {
        let selectedIDs = selectedScheduleIDs
        guard !selectedIDs.isEmpty else { return }

        let day = occurrenceDate.startOfDay
        var didChange = false

        for scheduleID in selectedIDs {
            guard let schedule = schedule(withID: scheduleID) else { continue }

            if schedule.repeatPattern == .never {
                guard !schedule.isCompleted else { continue }
                schedule.isCompleted = true
                touch(schedule)
                NotificationManager.shared.cancelNotification(for: schedule)
                didChange = true
            } else {
                var completedDays = recurringCompletionBySchedule[schedule.id] ?? []
                guard !completedDays.contains(day) else { continue }
                completedDays.insert(day)
                recurringCompletionBySchedule[schedule.id] = completedDays
                touch(schedule)
                didChange = true
            }
        }

        guard didChange else {
            clearBulkSelection()
            return
        }

        saveContext()
        persistRecurringCompletionState()
        normalizeSchedules()
        HapticManager.notification(.success)
        clearBulkSelection()
    }

    func deleteSelectedSchedules() {
        let selectedIDs = selectedScheduleIDs
        guard !selectedIDs.isEmpty else { return }

        for scheduleID in selectedIDs {
            guard let schedule = schedule(withID: scheduleID) else { continue }
            deleteSchedule(schedule)
        }

        clearBulkSelection()
    }

    func clearPendingNewScheduleDate() {
        pendingNewScheduleDate = nil
        pendingNewScheduleNLPInput = nil
    }

    func setPendingNewScheduleNLPInput(_ input: String?) {
        let trimmed = input?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        pendingNewScheduleNLPInput = trimmed.isEmpty ? nil : trimmed
    }

    func consumePendingNewScheduleNLPInput() -> String? {
        let value = pendingNewScheduleNLPInput
        pendingNewScheduleNLPInput = nil
        return value
    }

    private func setRecurringCompletion(
        for schedule: Schedule,
        on occurrenceDate: Date,
        isCompleted: Bool
    ) {
        let day = occurrenceDate.startOfDay
        var completedDays = recurringCompletionBySchedule[schedule.id] ?? []

        if isCompleted {
            completedDays.insert(day)
        } else {
            completedDays.remove(day)
        }

        if completedDays.isEmpty {
            recurringCompletionBySchedule.removeValue(forKey: schedule.id)
        } else {
            recurringCompletionBySchedule[schedule.id] = completedDays
        }

        touch(schedule)
        saveContext()
        persistRecurringCompletionState()
        rebuildDayItems()
        updateWidgetSnapshot()
        refreshNotificationBadgeCount()
        scheduleAutomaticCloudUploadIfNeeded()
    }

    private func excludeOccurrence(_ schedule: Schedule, on occurrenceDate: Date) {
        let day = occurrenceDate.startOfDay
        var excludedDays = Set(schedule.excludedOccurrenceDates.map(\.startOfDay))
        excludedDays.insert(day)
        schedule.excludedOccurrenceDates = excludedDays.sorted()

        var completedDays = recurringCompletionBySchedule[schedule.id] ?? []
        completedDays.remove(day)
        if completedDays.isEmpty {
            recurringCompletionBySchedule.removeValue(forKey: schedule.id)
        } else {
            recurringCompletionBySchedule[schedule.id] = completedDays
        }
        touch(schedule)
        persistRecurringCompletionState()
    }

    private func buildDetachedSingleOccurrence(
        from schedule: Schedule,
        occurrenceDate: Date
    ) -> Schedule {
        let detachedDate = occurrenceDate.startOfDay.mergingTime(from: schedule.scheduledDate)

        let detached = Schedule(
            lastModifiedDeviceID: currentDeviceID, title: schedule.title,
            notes: schedule.notes,
            urlString: schedule.urlString,
            scheduledDate: detachedDate,
            isUrgent: schedule.isUrgent,
            repeatPattern: .never,
            repeatWeekdays: schedule.repeatWeekdays,
            excludedOccurrenceDates: [],
            repeatEndOption: .never,
            repeatEndDate: nil,
            alertDeliveryOption: schedule.alertDeliveryOption,
            alarmSoundOption: schedule.alarmSoundOption,
            alarmSnoozeEnabled: schedule.alarmSnoozeEnabled,
            alarmSnoozeMinutes: schedule.alarmSnoozeMinutes,
            earlyReminderMinutes: schedule.earlyReminderMinutes,
            listName: schedule.listName,
            tags: schedule.tags,
            isFlagged: schedule.isFlagged,
            isCompleted: false,
            priority: schedule.priority
        )

        detached.additionalReminderMinutes = schedule.additionalReminderMinutes
        detached.timeZoneIdentifier = schedule.timeZoneIdentifier
        return detached
    }

    private func applyScheduleValues(from source: Schedule, to target: Schedule) {
        target.title = source.title
        target.notes = source.notes
        target.urlString = source.urlString
        target.scheduledDate = source.scheduledDate
        target.isCompleted = source.isCompleted
        target.alertDeliveryOption = source.alertDeliveryOption
        target.isUrgent = source.isUrgent
        target.alarmSoundOption = source.alarmSoundOption
        target.alarmSnoozeEnabled = source.alarmSnoozeEnabled
        target.alarmSnoozeMinutes = source.alarmSnoozeMinutes
        target.repeatPattern = source.repeatPattern
        target.repeatWeekdays = source.repeatWeekdays
        target.repeatEndOption = source.repeatEndOption
        target.repeatEndDate = source.repeatEndDate
        target.earlyReminderMinutes = source.earlyReminderMinutes
        target.listName = source.listName
        target.tags = source.tags
        target.isFlagged = source.isFlagged
        target.priority = source.priority
        target.repeatInterval = source.repeatInterval
        target.repeatEndCount = source.repeatEndCount
        target.additionalReminderMinutes = source.additionalReminderMinutes
        target.timeZoneIdentifier = source.timeZoneIdentifier
    }

    private func occurrenceDate(from userInfo: [AnyHashable: Any]?) -> Date? {
        guard let userInfo else { return nil }

        if let value = userInfo["occurrenceTimestamp"] as? TimeInterval {
            return Date(timeIntervalSince1970: value)
        }

        if let value = userInfo["occurrenceTimestamp"] as? NSNumber {
            return Date(timeIntervalSince1970: value.doubleValue)
        }

        if let value = userInfo["occurrenceTimestamp"] as? String,
           let timestamp = TimeInterval(value)
        {
            return Date(timeIntervalSince1970: timestamp)
        }

        return nil
    }

    private func loadRecurringCompletionState() {
        let defaults = UserDefaults.standard
        guard let raw = defaults.dictionary(forKey: Self.recurringCompletionStorageKey) else {
            recurringCompletionBySchedule = [:]
            return
        }

        var parsed: [UUID: Set<Date>] = [:]
        parsed.reserveCapacity(raw.count)

        for (scheduleIDString, value) in raw {
            guard let scheduleID = UUID(uuidString: scheduleIDString) else { continue }

            let timestamps: [TimeInterval]
            if let numbers = value as? [NSNumber] {
                timestamps = numbers.map(\.doubleValue)
            } else if let doubles = value as? [Double] {
                timestamps = doubles
            } else if let strings = value as? [String] {
                timestamps = strings.compactMap(TimeInterval.init)
            } else {
                continue
            }

            let days = Set(timestamps.map { Date(timeIntervalSince1970: $0).startOfDay })
            if !days.isEmpty {
                parsed[scheduleID] = days
            }
        }

        recurringCompletionBySchedule = parsed
    }

    private func persistRecurringCompletionState() {
        var encoded: [String: [TimeInterval]] = [:]
        encoded.reserveCapacity(recurringCompletionBySchedule.count)

        for (scheduleID, days) in recurringCompletionBySchedule {
            let timestamps = days
                .map(\.timeIntervalSince1970)
                .sorted()

            if !timestamps.isEmpty {
                encoded[scheduleID.uuidString] = timestamps
            }
        }

        UserDefaults.standard.set(encoded, forKey: Self.recurringCompletionStorageKey)
    }

    private func encodedRecurringCompletionStateForBackup() -> [String: [TimeInterval]] {
        var encoded: [String: [TimeInterval]] = [:]
        encoded.reserveCapacity(recurringCompletionBySchedule.count)

        for (scheduleID, days) in recurringCompletionBySchedule {
            let timestamps = days
                .map(\.timeIntervalSince1970)
                .sorted()

            if !timestamps.isEmpty {
                encoded[scheduleID.uuidString] = timestamps
            }
        }

        return encoded
    }

    private func mergeRecurringCompletionStateFromBackup(_ encoded: [String: [TimeInterval]]) {
        guard !encoded.isEmpty else { return }

        for (scheduleIDString, timestamps) in encoded {
            guard let scheduleID = UUID(uuidString: scheduleIDString) else { continue }
            let incomingDays = Set(timestamps.map { Date(timeIntervalSince1970: $0).startOfDay })
            guard !incomingDays.isEmpty else { continue }

            var currentDays = recurringCompletionBySchedule[scheduleID] ?? []
            currentDays.formUnion(incomingDays)
            recurringCompletionBySchedule[scheduleID] = currentDays
        }

        persistRecurringCompletionState()
    }

    private func backupAppSettingsSnapshot() -> BackupAppSettings {
        let settings = AppSettings.shared
        return BackupAppSettings(
            defaultAlertStyle: settings.defaultAlertStyle,
            defaultSnoozeDuration: settings.defaultSnoozeDuration,
            defaultEarlyReminderMinutes: settings.defaultEarlyReminderMinutes,
            defaultRepeatPattern: settings.defaultRepeatPattern,
            defaultPriority: settings.defaultPriority,
            defaultCalendar: settings.defaultCalendar,
            hotNaturalLanguageEnabled: settings.hotNaturalLanguageEnabled,
            firstDayOfWeek: settings.firstDayOfWeek,
            timeFormatPreferenceRawValue: settings.timeFormatPreference.rawValue,
            accentColorHex: settings.accentColorHex,
            appearanceMode: settings.appearanceMode,
            hapticFeedbackEnabled: settings.hapticFeedbackEnabled,
            notificationBadgeEnabled: settings.notificationBadgeEnabled,
            autoSyncOnLaunch: settings.autoSyncOnLaunch,
            showAlternativeCalendar: settings.showAlternativeCalendar,
            alternativeCalendarOptionRawValue: settings.alternativeCalendarOption.rawValue,
            defaultTimeZoneOverride: settings.defaultTimeZoneOverride,
            conflictDetectionEnabled: settings.conflictDetectionEnabled,
            suppressNotificationsDuringFocus: settings.suppressNotificationsDuringFocus,
            dailyDigestEnabled: settings.dailyDigestEnabled,
            dailyDigestHour: settings.dailyDigestHour,
            dailyDigestMinute: settings.dailyDigestMinute,
            settingsUpdatedAt: settings.settingsUpdatedAt
        )
    }

    private func applyBackupAppSettings(_ backup: BackupAppSettings) {
        let settings = AppSettings.shared
        let incomingUpdatedAt = backup.settingsUpdatedAt ?? .distantPast
        guard incomingUpdatedAt > settings.settingsUpdatedAt else { return }

        settings.beginSettingsBatchUpdate()
        settings.defaultAlertStyle = backup.defaultAlertStyle
        settings.defaultSnoozeDuration = backup.defaultSnoozeDuration
        settings.defaultEarlyReminderMinutes = backup.defaultEarlyReminderMinutes
        settings.defaultRepeatPattern = backup.defaultRepeatPattern
        settings.defaultPriority = backup.defaultPriority
        settings.defaultCalendar = backup.defaultCalendar
        settings.hotNaturalLanguageEnabled = backup.hotNaturalLanguageEnabled
        settings.firstDayOfWeek = backup.firstDayOfWeek
        if let mode = TimeFormatPreference(rawValue: backup.timeFormatPreferenceRawValue) {
            settings.timeFormatPreference = mode
        }
        settings.accentColorHex = backup.accentColorHex
        settings.appearanceMode = backup.appearanceMode
        settings.hapticFeedbackEnabled = backup.hapticFeedbackEnabled
        settings.notificationBadgeEnabled = backup.notificationBadgeEnabled
        settings.autoSyncOnLaunch = backup.autoSyncOnLaunch
        settings.showAlternativeCalendar = backup.showAlternativeCalendar
        if let option = AlternativeCalendarOption(rawValue: backup.alternativeCalendarOptionRawValue) {
            settings.alternativeCalendarOption = option
        }
        settings.defaultTimeZoneOverride = backup.defaultTimeZoneOverride
        settings.conflictDetectionEnabled = backup.conflictDetectionEnabled
        settings.suppressNotificationsDuringFocus = backup.suppressNotificationsDuringFocus
        settings.dailyDigestEnabled = backup.dailyDigestEnabled
        settings.dailyDigestHour = backup.dailyDigestHour
        settings.dailyDigestMinute = backup.dailyDigestMinute
        settings.settingsUpdatedAt = incomingUpdatedAt
        settings.endSettingsBatchUpdate(persisting: incomingUpdatedAt)
    }

    private func pruneRecurringCompletionState() {
        let validIDs = Set(
            schedules
                .filter { $0.repeatPattern != .never }
                .map(\.id)
        )

        let staleIDs = recurringCompletionBySchedule.keys.filter { !validIDs.contains($0) }
        guard !staleIDs.isEmpty else { return }

        for staleID in staleIDs {
            recurringCompletionBySchedule.removeValue(forKey: staleID)
        }
        persistRecurringCompletionState()
    }

    private func saveContext() {
        guard let modelContext else { return }
        do {
            try modelContext.save()
        } catch {
            print("Save error: \(error)")
        }
    }

    private func touch(_ schedule: Schedule) {
        schedule.updatedAt = Date()
        schedule.lastModifiedDeviceID = currentDeviceID
        schedule.syncVersion += 1
        dirtyScheduleIDs.insert(schedule.id)
    }

    func consumeDirtyDeltas() -> [ScheduleDelta] {
        let dirtyIDs = dirtyScheduleIDs
        dirtyScheduleIDs.removeAll()
        guard !dirtyIDs.isEmpty else { return [] }
        let dirtySchedules = schedules.filter { dirtyIDs.contains($0.id) }
        return dirtySchedules.map { ScheduleDelta(schedule: $0, deviceID: currentDeviceID) }
    }

    func requeue(scheduleID: UUID) {
        dirtyScheduleIDs.insert(scheduleID)
    }

    func markClean(scheduleID: UUID, syncedVersion: Int) {
        if let schedule = schedules.first(where: { $0.id == scheduleID }) {
            schedule.lastSyncedVersion = max(schedule.lastSyncedVersion, syncedVersion)
        }
        dirtyScheduleIDs.remove(scheduleID)
    }

    func localDelta(for scheduleID: UUID) -> ScheduleDelta? {
        guard let schedule = schedules.first(where: { $0.id == scheduleID }) else { return nil }
        return ScheduleDelta(schedule: schedule, deviceID: currentDeviceID)
    }

    func applyResolvedDelta(_ delta: ScheduleDelta) {
        guard let modelContext else { return }
        guard let scheduleID = UUID(uuidString: delta.scheduleID) else { return }

        if let existing = schedules.first(where: { $0.id == scheduleID }) {
            apply(delta, to: existing)
        } else {
            let newSchedule = Schedule(
                id: scheduleID,
                createdAt: delta.createdAt,
                updatedAt: delta.updatedAt,
                deletedAt: delta.deletedAt,
                isSoftDeleted: delta.isSoftDeleted,
                lastModifiedDeviceID: delta.lastModifiedDeviceID,
                syncVersion: delta.syncVersion,
                lastSyncedVersion: delta.syncVersion,
                conflictResolutionTag: delta.conflictResolutionTag,
                title: delta.title,
                notes: delta.notes,
                urlString: delta.urlString,
                scheduledDate: delta.scheduledDate,
                isUrgent: delta.isUrgent,
                repeatPattern: RepeatPattern(rawValue: delta.repeatPatternRaw) ?? .never,
                repeatWeekdays: delta.repeatWeekdays,
                excludedOccurrenceDates: delta.excludedOccurrenceDates,
                repeatEndOption: RepeatEndOption(rawValue: delta.repeatEndOptionRaw) ?? .never,
                repeatEndDate: delta.repeatEndDate,
                alertDeliveryOption: AlertDeliveryOption(rawValue: delta.alertDeliveryRaw) ?? .push,
                alarmSoundOption: AlarmSoundOption(rawValue: delta.alarmSoundRaw) ?? .defaultRingtone,
                alarmSnoozeEnabled: delta.alarmSnoozeEnabled,
                alarmSnoozeMinutes: delta.alarmSnoozeMinutes,
                earlyReminderMinutes: delta.earlyReminderMinutes,
                listName: delta.listName,
                tags: delta.tags,
                isFlagged: delta.isFlagged,
                isCompleted: delta.isCompleted,
                priority: SchedulePriority(rawValue: delta.priorityRaw) ?? .none
            )
            newSchedule.repeatInterval = delta.repeatInterval
            newSchedule.repeatEndCount = delta.repeatEndCount
            newSchedule.additionalReminderMinutes = delta.additionalReminderMinutes
            newSchedule.timeZoneIdentifier = delta.timeZoneIdentifier
            modelContext.insert(newSchedule)
            schedules.append(newSchedule)
        }

        markClean(scheduleID: scheduleID, syncedVersion: delta.syncVersion)
        saveContext()
        normalizeSchedules(immediate: true)
    }

    func enqueueConflict(scheduleID: UUID) {
        if !pendingConflictScheduleIDs.contains(scheduleID) {
            pendingConflictScheduleIDs.append(scheduleID)
        }
    }

    func currentGlobalSyncVersion() -> Int {
        globalSyncVersion
    }

    func bumpGlobalSyncVersion() {
        globalSyncVersion += 1
        UserDefaults.standard.set(globalSyncVersion, forKey: Self.globalSyncVersionKey)
    }

    func seedGlobalSyncVersion(_ value: Int) {
        guard value >= 0 else { return }
        globalSyncVersion = max(globalSyncVersion, value)
        UserDefaults.standard.set(globalSyncVersion, forKey: Self.globalSyncVersionKey)
    }

    func clearPendingConflicts() {
        pendingConflictScheduleIDs.removeAll()
        syncCoordinator.clearPendingConflicts()
    }

    private func resolveScheduleConflictsByLatestUpdate() {
        guard let modelContext else { return }

        var winnerByID: [UUID: Schedule] = [:]
        var duplicateLosers: [Schedule] = []

        for schedule in schedules {
            guard let existing = winnerByID[schedule.id] else {
                winnerByID[schedule.id] = schedule
                continue
            }

            let winner: Schedule
            let loser: Schedule
            if schedule.updatedAt > existing.updatedAt {
                winner = schedule
                loser = existing
            } else if schedule.updatedAt < existing.updatedAt {
                winner = existing
                loser = schedule
            } else if !schedule.isSoftDeleted && existing.isSoftDeleted {
                winner = schedule
                loser = existing
            } else {
                winner = existing
                loser = schedule
            }

            winnerByID[schedule.id] = winner
            duplicateLosers.append(loser)
            appendMergeLog(
                scheduleID: schedule.id,
                winnerUpdatedAt: winner.updatedAt,
                loserUpdatedAt: loser.updatedAt
            )
        }

        guard !duplicateLosers.isEmpty else {
            schedules = Array(winnerByID.values)
            return
        }

        for duplicate in duplicateLosers {
            modelContext.delete(duplicate)
        }
        saveContext()
        schedules = Array(winnerByID.values)
    }

    private func appendMergeLog(scheduleID: UUID, winnerUpdatedAt: Date, loserUpdatedAt: Date) {
        let defaults = UserDefaults.standard
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        var entries: [MergeLogEntry] = []
        if let data = defaults.data(forKey: Self.mergeLogStorageKey),
           let decoded = try? decoder.decode([MergeLogEntry].self, from: data)
        {
            entries = decoded
        }

        entries.append(
            MergeLogEntry(
                scheduleID: scheduleID,
                winnerUpdatedAt: winnerUpdatedAt,
                loserUpdatedAt: loserUpdatedAt,
                mergedAt: Date()
            )
        )

        if entries.count > 100 {
            entries = Array(entries.suffix(100))
        }

        if let encoded = try? encoder.encode(entries) {
            defaults.set(encoded, forKey: Self.mergeLogStorageKey)
        }
    }

    private func localBackupFileURL() -> URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent(Self.localBackupFileName)
    }

    private func restoreFromLocalBackupIfNeeded() {
        guard let modelContext, schedules.isEmpty, let fileURL = localBackupFileURL() else { return }
        guard let data = try? Data(contentsOf: fileURL) else { return }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let payload = try? decoder.decode(BackupPayload.self, from: data) else { return }
        guard !payload.schedules.isEmpty else { return }

        let allRecords = (try? modelContext.fetch(FetchDescriptor<Schedule>())) ?? []
        var existingByID = Dictionary(uniqueKeysWithValues: allRecords.map { ($0.id, $0) })

        for backupItem in payload.schedules {
            if let existing = existingByID[backupItem.id] {
                if backupItem.updatedAt > existing.updatedAt {
                    apply(backupItem, to: existing)
                }
                continue
            }

            let restored = Schedule(
                id: backupItem.id,
                createdAt: backupItem.createdAt,
                updatedAt: backupItem.updatedAt,
                deletedAt: backupItem.deletedAt,
                isSoftDeleted: backupItem.isSoftDeleted,
                lastModifiedDeviceID: backupItem.lastModifiedDeviceID,
                title: backupItem.title,
                notes: backupItem.notes,
                urlString: backupItem.urlString,
                scheduledDate: backupItem.scheduledDate,
                isUrgent: backupItem.isUrgent,
                repeatPattern: backupItem.repeatPattern,
                repeatWeekdays: backupItem.repeatWeekdays,
                excludedOccurrenceDates: backupItem.excludedOccurrenceDates,
                repeatEndOption: backupItem.repeatEndOption,
                repeatEndDate: backupItem.repeatEndDate,
                alertDeliveryOption: backupItem.alertDeliveryOption,
                alarmSoundOption: backupItem.alarmSoundOption,
                alarmSnoozeEnabled: backupItem.alarmSnoozeEnabled,
                alarmSnoozeMinutes: backupItem.alarmSnoozeMinutes,
                earlyReminderMinutes: backupItem.earlyReminderMinutes,
                listName: backupItem.listName,
                tags: backupItem.tags,
                isFlagged: backupItem.isFlagged,
                isCompleted: backupItem.isCompleted,
                priority: backupItem.priority
            )
            restored.repeatInterval = backupItem.repeatInterval ?? 1
            restored.repeatEndCount = backupItem.repeatEndCount ?? 0
            restored.additionalReminderMinutes = backupItem.additionalReminderMinutes ?? []
            restored.timeZoneIdentifier = backupItem.timeZoneIdentifier
            modelContext.insert(restored)
            existingByID[restored.id] = restored
        }

        saveContext()
        fetchSchedules()
    }

    private func apply(_ backupItem: BackupScheduleItem, to schedule: Schedule) {
        schedule.createdAt = backupItem.createdAt
        schedule.updatedAt = backupItem.updatedAt
        schedule.deletedAt = backupItem.deletedAt
        schedule.isSoftDeleted = backupItem.isSoftDeleted
        schedule.lastModifiedDeviceID = backupItem.lastModifiedDeviceID
        schedule.title = backupItem.title
        schedule.notes = backupItem.notes
        schedule.urlString = backupItem.urlString
        schedule.scheduledDate = backupItem.scheduledDate
        schedule.isUrgent = backupItem.isUrgent
        schedule.repeatPattern = backupItem.repeatPattern
        schedule.repeatWeekdays = backupItem.repeatWeekdays
        schedule.excludedOccurrenceDates = backupItem.excludedOccurrenceDates
        schedule.repeatEndOption = backupItem.repeatEndOption
        schedule.repeatEndDate = backupItem.repeatEndDate
        schedule.alertDeliveryOption = backupItem.alertDeliveryOption
        schedule.alarmSoundOption = backupItem.alarmSoundOption
        schedule.alarmSnoozeEnabled = backupItem.alarmSnoozeEnabled
        schedule.alarmSnoozeMinutes = backupItem.alarmSnoozeMinutes
        schedule.earlyReminderMinutes = backupItem.earlyReminderMinutes
        schedule.listName = backupItem.listName
        schedule.tags = backupItem.tags
        schedule.isFlagged = backupItem.isFlagged
        schedule.isCompleted = backupItem.isCompleted
        schedule.priority = backupItem.priority
        schedule.repeatInterval = backupItem.repeatInterval ?? 1
        schedule.repeatEndCount = backupItem.repeatEndCount ?? 0
        schedule.additionalReminderMinutes = backupItem.additionalReminderMinutes ?? []
        schedule.timeZoneIdentifier = backupItem.timeZoneIdentifier
    }

    private func scheduleFromBackupItem(_ backupItem: BackupScheduleItem) -> Schedule {
        let schedule = Schedule(
            id: backupItem.id,
            createdAt: backupItem.createdAt,
            updatedAt: backupItem.updatedAt,
            deletedAt: backupItem.deletedAt,
            isSoftDeleted: backupItem.isSoftDeleted,
            lastModifiedDeviceID: backupItem.lastModifiedDeviceID,
            syncVersion: 0,
            lastSyncedVersion: 0,
            conflictResolutionTag: nil,
            title: backupItem.title,
            notes: backupItem.notes,
            urlString: backupItem.urlString,
            scheduledDate: backupItem.scheduledDate,
            isUrgent: backupItem.isUrgent,
            repeatPattern: backupItem.repeatPattern,
            repeatWeekdays: backupItem.repeatWeekdays,
            excludedOccurrenceDates: backupItem.excludedOccurrenceDates,
            repeatEndOption: backupItem.repeatEndOption,
            repeatEndDate: backupItem.repeatEndDate,
            alertDeliveryOption: backupItem.alertDeliveryOption,
            alarmSoundOption: backupItem.alarmSoundOption,
            alarmSnoozeEnabled: backupItem.alarmSnoozeEnabled,
            alarmSnoozeMinutes: backupItem.alarmSnoozeMinutes,
            earlyReminderMinutes: backupItem.earlyReminderMinutes,
            listName: backupItem.listName,
            tags: backupItem.tags,
            isFlagged: backupItem.isFlagged,
            isCompleted: backupItem.isCompleted,
            priority: backupItem.priority
        )
        schedule.repeatInterval = backupItem.repeatInterval ?? 1
        schedule.repeatEndCount = backupItem.repeatEndCount ?? 0
        schedule.additionalReminderMinutes = backupItem.additionalReminderMinutes ?? []
        schedule.timeZoneIdentifier = backupItem.timeZoneIdentifier
        return schedule
    }

    private func apply(_ delta: ScheduleDelta, to schedule: Schedule) {
        schedule.createdAt = delta.createdAt
        schedule.updatedAt = delta.updatedAt
        schedule.deletedAt = delta.deletedAt
        schedule.isSoftDeleted = delta.isSoftDeleted
        schedule.lastModifiedDeviceID = delta.lastModifiedDeviceID
        schedule.title = delta.title
        schedule.notes = delta.notes
        schedule.urlString = delta.urlString
        schedule.scheduledDate = delta.scheduledDate
        schedule.isUrgent = delta.isUrgent
        schedule.repeatPattern = RepeatPattern(rawValue: delta.repeatPatternRaw) ?? schedule.repeatPattern
        schedule.repeatWeekdays = delta.repeatWeekdays
        schedule.excludedOccurrenceDates = delta.excludedOccurrenceDates
        schedule.repeatEndOption = RepeatEndOption(rawValue: delta.repeatEndOptionRaw) ?? schedule.repeatEndOption
        schedule.repeatEndDate = delta.repeatEndDate
        schedule.alertDeliveryOption = AlertDeliveryOption(rawValue: delta.alertDeliveryRaw) ?? schedule.alertDeliveryOption
        schedule.alarmSoundOption = AlarmSoundOption(rawValue: delta.alarmSoundRaw) ?? schedule.alarmSoundOption
        schedule.alarmSnoozeEnabled = delta.alarmSnoozeEnabled
        schedule.alarmSnoozeMinutes = delta.alarmSnoozeMinutes
        schedule.earlyReminderMinutes = delta.earlyReminderMinutes
        schedule.listName = delta.listName
        schedule.tags = delta.tags
        schedule.isFlagged = delta.isFlagged
        schedule.isCompleted = delta.isCompleted
        schedule.priority = SchedulePriority(rawValue: delta.priorityRaw) ?? schedule.priority
        schedule.repeatInterval = delta.repeatInterval
        schedule.repeatEndCount = delta.repeatEndCount
        schedule.additionalReminderMinutes = delta.additionalReminderMinutes
        schedule.timeZoneIdentifier = delta.timeZoneIdentifier
        schedule.syncVersion = delta.syncVersion
        schedule.lastSyncedVersion = max(schedule.lastSyncedVersion, delta.syncVersion)
        schedule.conflictResolutionTag = delta.conflictResolutionTag
    }

    private func writeLocalBackupSnapshot() {
        guard let fileURL = localBackupFileURL() else { return }

        let payload = BackupPayload(
            version: 1,
            exportedAt: Date(),
            schedules: schedules
                .filter { !$0.isSoftDeleted }
                .map { schedule in
                    BackupScheduleItem(
                        id: schedule.id,
                        createdAt: schedule.createdAt,
                        updatedAt: schedule.updatedAt,
                        deletedAt: schedule.deletedAt,
                        isSoftDeleted: schedule.isSoftDeleted,
                        lastModifiedDeviceID: schedule.lastModifiedDeviceID,
                        title: schedule.title,
                        notes: schedule.notes,
                        urlString: schedule.urlString,
                        scheduledDate: schedule.scheduledDate,
                        isUrgent: schedule.isUrgent,
                        repeatPattern: schedule.repeatPattern,
                        repeatWeekdays: schedule.repeatWeekdays,
                        excludedOccurrenceDates: schedule.excludedOccurrenceDates,
                        repeatEndOption: schedule.repeatEndOption,
                        repeatEndDate: schedule.repeatEndDate,
                        alertDeliveryOption: schedule.alertDeliveryOption,
                        alarmSoundOption: schedule.alarmSoundOption,
                        alarmSnoozeEnabled: schedule.alarmSnoozeEnabled,
                        alarmSnoozeMinutes: schedule.alarmSnoozeMinutes,
                        earlyReminderMinutes: schedule.earlyReminderMinutes,
                        listName: schedule.listName,
                        tags: schedule.tags,
                        isFlagged: schedule.isFlagged,
                        isCompleted: schedule.isCompleted,
                        priority: schedule.priority,
                        repeatInterval: schedule.repeatInterval,
                        repeatEndCount: schedule.repeatEndCount,
                        additionalReminderMinutes: schedule.additionalReminderMinutes,
                        timeZoneIdentifier: schedule.timeZoneIdentifier
                    )
                },
            globalSyncVersion: globalSyncVersion
        )

        backupWriteTask?.cancel()
        backupWriteTask = Task.detached(priority: .utility) {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            guard let data = try? encoder.encode(payload) else { return }
            try? data.write(to: fileURL, options: [.atomic])
        }
    }

    private func isScheduleDateInPast(_ date: Date) -> Bool {
        let calendar = Calendar.current
        let now = Date()
        var nowComponents = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: now)
        nowComponents.second = 0
        let minimumAllowedDate = calendar.date(from: nowComponents) ?? now
        return date < minimumAllowedDate
    }

    private func dateWithCurrentTime(from date: Date) -> Date {
        let calendar = Calendar.current
        var dayComponents = calendar.dateComponents([.year, .month, .day], from: date)
        let nowComponents = calendar.dateComponents([.hour, .minute], from: Date())
        dayComponents.hour = nowComponents.hour
        dayComponents.minute = nowComponents.minute
        dayComponents.second = 0
        return calendar.date(from: dayComponents) ?? date
    }

    private func loadCalendarNames() {
        let stored = UserDefaults.standard.array(forKey: Self.calendarNamesStorageKey) as? [String] ?? []
        calendarNames = sanitizedCalendarNames(from: stored)
        persistCalendarNames()
    }

    private func persistCalendarNames() {
        UserDefaults.standard.set(calendarNames, forKey: Self.calendarNamesStorageKey)
    }

    private func sanitizedCalendarNames(from names: [String]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []

        func appendIfNeeded(_ value: String) {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            let key = trimmed.lowercased()
            guard !seen.contains(key) else { return }
            seen.insert(key)
            result.append(trimmed)
        }

        appendIfNeeded(Self.defaultCalendarName)
        names.forEach(appendIfNeeded)
        return result
    }

    private func syncCalendarNamesFromSchedules() {
        var merged = calendarNames
        var seen = Set(merged.map { $0.lowercased() })

        for schedule in schedules {
            let name = schedule.listName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }
            let key = name.lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            merged.append(name)
        }

        let sanitized = sanitizedCalendarNames(from: merged)
        guard sanitized != calendarNames else { return }
        calendarNames = sanitized
        persistCalendarNames()
    }

    private func normalizeSchedules(immediate: Bool = false) {
        if immediate {
            normalizeTask?.cancel()
            normalizeTask = nil
            performNormalization()
            return
        }

        normalizeTask?.cancel()
        normalizeTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            self?.performNormalization()
        }
    }

    private func performNormalization() {
        schedules = schedules.filter { !$0.isSoftDeleted }
        schedules.sort { $0.scheduledDate < $1.scheduledDate }
        syncCalendarNamesFromSchedules()
        rebuildScheduleIndex()
        rebuildDayItems()
        updateWidgetSnapshot()
        refreshNotificationBadgeCount()
        rescheduleDailyDigest()
        writeLocalBackupSnapshot()
        scheduleAutomaticCloudUploadIfNeeded()
    }

    private func scheduleAutomaticCloudUploadIfNeeded() {
        if suppressNextAutoCloudUpload {
            suppressNextAutoCloudUpload = false
            return
        }

        guard !isCloudRestoreInProgress else { return }
        guard FirebaseSyncService.shared.isSignedIn else { return }
        guard isAutoSyncUnlockedForCurrentAccount() else { return }
        guard !dirtyScheduleIDs.isEmpty else { return }
        guard shouldRunAutomaticCloudSync(requirePendingScheduleChanges: true) else { return }

        syncNowWithCoordinator(userInitiated: false)
    }

    private func isAutoSyncUnlockedForCurrentAccount() -> Bool {
        guard let accountID = FirebaseSyncService.shared.signedInUserID, !accountID.isEmpty else {
            return false
        }
        let unlocked = UserDefaults.standard.stringArray(forKey: Self.autoSyncUnlockedAccountIDsKey) ?? []
        return Set(unlocked).contains(accountID)
    }

    private func unlockAutoSyncForCurrentAccount() {
        guard let accountID = FirebaseSyncService.shared.signedInUserID, !accountID.isEmpty else {
            return
        }

        var unlocked = Set(UserDefaults.standard.stringArray(forKey: Self.autoSyncUnlockedAccountIDsKey) ?? [])
        guard !unlocked.contains(accountID) else { return }
        unlocked.insert(accountID)
        UserDefaults.standard.set(Array(unlocked), forKey: Self.autoSyncUnlockedAccountIDsKey)
        Self.syncLogger.info("Auto-sync unlocked after manual sync for account \(accountID, privacy: .private(mask: .hash))")
    }

    private func shouldRunAutomaticCloudSync(requirePendingScheduleChanges: Bool) -> Bool {
        let syncService = FirebaseSyncService.shared
        guard syncService.isNetworkReachable else { return false }
        guard syncService.isOnWiFi else { return false }
        guard !syncService.isNetworkConstrained else { return false }

        let processInfo = ProcessInfo.processInfo
        #if os(iOS)
        guard !processInfo.isLowPowerModeEnabled else { return false }
        #endif
        switch processInfo.thermalState {
        case .serious, .critical:
            return false
        default:
            break
        }

        var isCharging = false
        #if os(iOS)
        let device = UIDevice.current
        let wasMonitoringBattery = device.isBatteryMonitoringEnabled
        if !wasMonitoringBattery {
            device.isBatteryMonitoringEnabled = true
        }
        defer {
            if !wasMonitoringBattery {
                device.isBatteryMonitoringEnabled = false
            }
        }

        let batteryState = device.batteryState
        isCharging = batteryState == .charging || batteryState == .full
        let batteryLevel = device.batteryLevel
        if !isCharging, batteryLevel >= 0, batteryLevel < Self.autoSyncMinBatteryLevel {
            return false
        }
        #endif

        let minimumInterval: TimeInterval
        if requirePendingScheduleChanges, isCharging {
            minimumInterval = Self.autoSyncIntervalWithChangesWhileCharging
        } else if requirePendingScheduleChanges {
            minimumInterval = Self.autoSyncIntervalWithChanges
        } else if isCharging {
            minimumInterval = Self.autoSyncIntervalWithoutChangesWhileCharging
        } else {
            minimumInterval = Self.autoSyncIntervalWithoutChanges
        }

        let now = Date()
        guard now.timeIntervalSince(lastAutoCloudUploadAt) >= minimumInterval else { return false }
        lastAutoCloudUploadAt = now
        UserDefaults.standard.set(now, forKey: Self.lastAutoCloudUploadAtKey)
        return true
    }

    private func rebuildWeek() {
        weekDates = _currentWeekStart.weekDates
        rebuildScheduleIndex()
        rebuildDayItems()
    }

    private func rebuildDayItems() {
        dayItems = weekDates.enumerated().map { index, date in
            DayItem(
                id: date.startOfDay,
                index: index,
                date: date,
                schedules: schedulesByDay[date.startOfDay] ?? []
            )
        }
    }

    private func rebuildScheduleIndex() {
        let calendar = Calendar.current
        var grouped: [Date: [Schedule]] = [:]
        grouped.reserveCapacity(weekDates.count)

        for weekDay in weekDates {
            grouped[weekDay.startOfDay] = []
        }

        for schedule in visibleSchedules where !schedule.isSoftDeleted {
            for weekDay in weekDates {
                let day = weekDay.startOfDay
                if occurs(schedule, on: day, calendar: calendar) {
                    grouped[day, default: []].append(schedule)
                }
            }
        }

        for day in grouped.keys {
            grouped[day]?.sort { lhs, rhs in
                isScheduledEarlier(lhs, than: rhs, calendar: calendar)
            }
        }

        schedulesByDay = grouped
        dayCacheAccessOrder = weekDates.map(\.startOfDay)
    }

    private func markDayCacheAccess(for day: Date) {
        if dayCacheAccessOrder.last == day {
            return
        }

        if let existingIndex = dayCacheAccessOrder.firstIndex(of: day) {
            dayCacheAccessOrder.remove(at: existingIndex)
        }
        dayCacheAccessOrder.append(day)
    }

    private func trimDayCacheIfNeeded() {
        guard schedulesByDay.count > Self.maxCachedDayBuckets else { return }

        let protectedWeekDays = Set(weekDates.map(\.startOfDay))

        var orderIndex = 0
        while schedulesByDay.count > Self.maxCachedDayBuckets && orderIndex < dayCacheAccessOrder.count {
            let candidate = dayCacheAccessOrder[orderIndex]
            if protectedWeekDays.contains(candidate) {
                orderIndex += 1
                continue
            }

            schedulesByDay.removeValue(forKey: candidate)
            dayCacheAccessOrder.remove(at: orderIndex)
        }
    }

    private func isScheduledEarlier(
        _ lhs: Schedule,
        than rhs: Schedule,
        calendar: Calendar
    ) -> Bool {
        let lhm = calendar.component(.hour, from: lhs.scheduledDate) * 60
            + calendar.component(.minute, from: lhs.scheduledDate)
        let rhm = calendar.component(.hour, from: rhs.scheduledDate) * 60
            + calendar.component(.minute, from: rhs.scheduledDate)

        if lhm == rhm {
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
        return lhm < rhm
    }

    private func occurs(
        _ schedule: Schedule,
        on day: Date,
        calendar: Calendar
    ) -> Bool {
        guard !schedule.isSoftDeleted else { return false }
        let scheduleCalendar = scheduleCalendar(for: schedule, base: calendar)
        let startDay = scheduleCalendar.startOfDay(for: schedule.scheduledDate)
        let targetDay = scheduleCalendar.startOfDay(for: day)

        guard targetDay >= startDay else { return false }

        // ⚡ Bolt Optimization: Avoid allocating an Array and Set on every `occurs` call
        // `excludedOccurrenceDates` is usually small, so linear search is faster than
        // allocating new collections when this is called frequently (e.g. in loops)
        if schedule.excludedOccurrenceDates.contains(where: { scheduleCalendar.startOfDay(for: $0) == targetDay }) {
            return false
        }

        if schedule.repeatEndOption == .onDate,
           let endDateRaw = schedule.repeatEndDate,
           let endDate = Optional(scheduleCalendar.startOfDay(for: endDateRaw)),
           targetDay > endDate
        {
            return false
        }

        if schedule.repeatEndOption == .afterCount, schedule.repeatEndCount > 0 {
            let count = countOccurrences(of: schedule, before: targetDay, calendar: scheduleCalendar)
            if count >= schedule.repeatEndCount { return false }
        }

        return matchesRepeatPattern(
            schedule,
            startDay: startDay,
            targetDay: targetDay,
            calendar: scheduleCalendar
        )
    }

    private func matchesRepeatPattern(
        _ schedule: Schedule,
        startDay: Date,
        targetDay: Date,
        calendar: Calendar
    ) -> Bool {

        switch schedule.repeatPattern {
        case .never:
            return calendar.isDate(targetDay, inSameDayAs: startDay)

        case .daily:
            let weekdays = normalizedWeekdays(schedule.repeatWeekdays)
            let weekday = calendar.component(.weekday, from: targetDay)
            return weekdays.contains(weekday)

        case .weekdays:
            let weekday = calendar.component(.weekday, from: targetDay)
            return (2...6).contains(weekday) // Mon-Fri

        case .weekly:
            return calendar.component(.weekday, from: targetDay) == calendar.component(.weekday, from: startDay)

        case .biweekly:
            guard calendar.component(.weekday, from: targetDay) == calendar.component(.weekday, from: startDay) else { return false }
            let weeks = calendar.dateComponents([.weekOfYear], from: startDay, to: targetDay).weekOfYear ?? 0
            return weeks % 2 == 0

        case .monthly:
            return calendar.component(.day, from: targetDay) == calendar.component(.day, from: startDay)

        case .yearly:
            let targetMonth = calendar.component(.month, from: targetDay)
            let targetDayOfMonth = calendar.component(.day, from: targetDay)
            let startMonth = calendar.component(.month, from: startDay)
            let startDayOfMonth = calendar.component(.day, from: startDay)
            return targetMonth == startMonth && targetDayOfMonth == startDayOfMonth

        case .everyNDays:
            let interval = max(1, schedule.repeatInterval)
            let days = calendar.dateComponents([.day], from: startDay, to: targetDay).day ?? 0
            return days % interval == 0

        case .everyNWeeks:
            guard calendar.component(.weekday, from: targetDay) == calendar.component(.weekday, from: startDay) else { return false }
            let weeks = calendar.dateComponents([.weekOfYear], from: startDay, to: targetDay).weekOfYear ?? 0
            return weeks % max(1, schedule.repeatInterval) == 0

        case .everyNMonths:
            guard calendar.component(.day, from: targetDay) == calendar.component(.day, from: startDay) else { return false }
            let months = calendar.dateComponents([.month], from: startDay, to: targetDay).month ?? 0
            return months % max(1, schedule.repeatInterval) == 0

        case .customWeekdays:
            let weekday = calendar.component(.weekday, from: targetDay)
            return schedule.repeatWeekdays.contains(weekday)
        }
    }

    private func countOccurrences(of schedule: Schedule, before targetDay: Date, calendar: Calendar) -> Int {
        let startDay = calendar.startOfDay(for: schedule.scheduledDate)
        var count = 0
        var current = startDay

        // ⚡ Bolt Optimization: Use a local Set but compute it lazily ONLY if there are actually excluded dates.
        // It's worth building a Set here because we are in a loop (`current < targetDay`).
        let excludedDays = schedule.excludedOccurrenceDates.isEmpty ? Set<Date>() : Set(schedule.excludedOccurrenceDates.map { calendar.startOfDay(for: $0) })

        // Limit iteration to avoid infinite loops
        let maxIterations = schedule.repeatEndCount + 100
        var iterations = 0

        while current < targetDay && iterations < maxIterations {
            let isOccurrence = matchesRepeatPattern(
                schedule,
                startDay: startDay,
                targetDay: current,
                calendar: calendar
            )

            if isOccurrence, !excludedDays.contains(current) {
                count += 1
            }

            if schedule.repeatEndOption == .afterCount,
               schedule.repeatEndCount > 0,
               count >= schedule.repeatEndCount {
                break
            }

            iterations += 1

            switch schedule.repeatPattern {
            case .never: return count
            case .daily, .weekdays:
                current = calendar.date(byAdding: .day, value: 1, to: current) ?? current
            case .weekly:
                current = calendar.date(byAdding: .weekOfYear, value: 1, to: current) ?? current
            case .biweekly:
                current = calendar.date(byAdding: .weekOfYear, value: 2, to: current) ?? current
            case .monthly:
                current = calendar.date(byAdding: .month, value: 1, to: current) ?? current
            case .yearly:
                current = calendar.date(byAdding: .year, value: 1, to: current) ?? current
            case .everyNDays:
                current = calendar.date(byAdding: .day, value: max(1, schedule.repeatInterval), to: current) ?? current
            case .everyNWeeks:
                current = calendar.date(byAdding: .weekOfYear, value: max(1, schedule.repeatInterval), to: current) ?? current
            case .everyNMonths:
                current = calendar.date(byAdding: .month, value: max(1, schedule.repeatInterval), to: current) ?? current
            case .customWeekdays:
                current = calendar.date(byAdding: .day, value: 1, to: current) ?? current
            }
        }
        return count
    }

    private func normalizedWeekdays(_ weekdays: [Int]) -> [Int] {
        let valid = Set(weekdays.filter { (1...7).contains($0) })
        return valid.isEmpty ? Array(1...7) : valid.sorted()
    }

    private func scheduleCalendar(for schedule: Schedule, base: Calendar = .current) -> Calendar {
        var calendar = base
        if let tz = schedule.scheduleTimeZone {
            calendar.timeZone = tz
        }
        return calendar
    }

    private func updateWidgetSnapshot() {
        guard let defaults = UserDefaults(suiteName: Self.widgetAppGroupID) else { return }

        let now = Date()
        let calendar = Calendar.current
        let today = now.startOfDay

        let todayItems = schedules
            .filter { occurs($0, on: today, calendar: calendar) }
            .map { schedule -> WidgetScheduleItem in
                let occurrenceDate = occurrenceDate(for: schedule, on: today, calendar: calendar)
                let occurrenceCompleted = isScheduleCompleted(schedule, on: occurrenceDate)
                return makeWidgetItem(
                    from: schedule,
                    occurrenceDate: occurrenceDate,
                    isCompleted: occurrenceCompleted
                )
            }
            .sorted { lhs, rhs in
                lhs.scheduledDate < rhs.scheduledDate
            }

        let upcomingItems = todayItems
            .filter { $0.scheduledDate >= now }
            .prefix(6)

        let pastItems = todayItems
            .filter { $0.scheduledDate < now || $0.isCompleted }
            .suffix(6)
            .reversed()

        let snapshot = WidgetScheduleSnapshot(
            updatedAt: now,
            upcoming: Array(upcomingItems),
            past: Array(pastItems)
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let encoded = try? encoder.encode(snapshot) else { return }

        defaults.set(encoded, forKey: Self.widgetSnapshotKey)

#if canImport(WidgetKit)
    let nowForReload = Date()
    guard nowForReload.timeIntervalSince(lastWidgetReloadAt) >= 1.5 else { return }
    lastWidgetReloadAt = nowForReload
    Task { @MainActor in
        WidgetCenter.shared.reloadTimelines(ofKind: "AlarmStatusWidget")
    }
#endif
    }

    private func makeWidgetItem(
        from schedule: Schedule,
        occurrenceDate: Date,
        isCompleted: Bool
    ) -> WidgetScheduleItem {
        WidgetScheduleItem(
            id: schedule.id.uuidString,
            title: schedule.title,
            scheduledDate: occurrenceDate,
            notes: schedule.notes,
            urlString: schedule.urlString,
            repeatPatternName: schedule.repeatPattern.displayName,
            deliveryName: schedule.alertDeliveryOption.displayName,
            priorityName: schedule.priority.displayName,
            earlyReminderMinutes: schedule.earlyReminderMinutes,
            isCompleted: isCompleted
        )
    }

    private func occurrenceDate(for schedule: Schedule, on day: Date, calendar: Calendar) -> Date {
        let dayComponents = calendar.dateComponents([.year, .month, .day], from: day)
        let timeComponents = calendar.dateComponents([.hour, .minute, .second], from: schedule.scheduledDate)
        var merged = DateComponents()
        merged.year = dayComponents.year
        merged.month = dayComponents.month
        merged.day = dayComponents.day
        merged.hour = timeComponents.hour
        merged.minute = timeComponents.minute
        merged.second = timeComponents.second ?? 0
        return calendar.date(from: merged) ?? schedule.scheduledDate
    }

    // MARK: - New Feature Methods

    /// Delete all completed (non-recurring) schedules.
    func deleteAllCompleted() {
        guard modelContext != nil else { return }
        let completed = schedules.filter { $0.isCompleted && $0.repeatPattern == .never }
        for schedule in completed {
            NotificationManager.shared.cancelNotification(for: schedule)
            schedule.isSoftDeleted = true
            schedule.deletedAt = Date()
            touch(schedule)
        }
        saveContext()
        schedules.removeAll { $0.isSoftDeleted }
        normalizeSchedules()
    }

    /// Reset all data — removes all schedules and recurring completion state.
    func resetAllData() {
        guard let modelContext else { return }
        for schedule in schedules {
            NotificationManager.shared.cancelNotification(for: schedule)
            modelContext.delete(schedule)
        }
        schedules.removeAll()
        recurringCompletionBySchedule.removeAll()
        persistRecurringCompletionState()
        schedulesByDay.removeAll()
        dayCacheAccessOrder.removeAll()

        calendarNames = [Self.defaultCalendarName]
        persistCalendarNames()
        UserDefaults.standard.removeObject(forKey: Self.calendarNamesStorageKey)
        UserDefaults.standard.removeObject(forKey: Self.mergeLogStorageKey)

        if let backupURL = localBackupFileURL() {
            try? FileManager.default.removeItem(at: backupURL)
        }

        if let widgetDefaults = UserDefaults(suiteName: Self.widgetAppGroupID) {
            widgetDefaults.removeObject(forKey: Self.widgetSnapshotKey)
            widgetDefaults.removeObject(forKey: Self.widgetCompletionRequestsKey)
        }

        UndoRedoManager.shared.clear()
        refreshUndoRedoState()

        saveContext()
        rebuildDayItems()
        updateWidgetSnapshot()
        refreshNotificationBadgeCount()
    }

    /// Export schedules as CSV data.
    func exportAsCSV() -> Data? {
        var csv = "Title,Date,Time,Priority,Calendar,Tags,Repeat,Completed,Notes\n"
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm"

        for schedule in schedules where !schedule.isSoftDeleted {
            let title = csvEscape(schedule.title)
            let date = dateFormatter.string(from: schedule.scheduledDate)
            let time = timeFormatter.string(from: schedule.scheduledDate)
            let priority = schedule.priority.displayName
            let calendar = csvEscape(schedule.listName)
            let tags = csvEscape(schedule.tags.joined(separator: "; "))
            let repeatPattern = schedule.repeatPattern.displayName
            let completed = schedule.isCompleted ? "Yes" : "No"
            let notes = csvEscape(schedule.notes ?? "")
            csv += "\(title),\(date),\(time),\(priority),\(calendar),\(tags),\(repeatPattern),\(completed),\(notes)\n"
        }

        return csv.data(using: .utf8)
    }

    private func csvEscape(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return value
    }

    /// Rename a tag across all schedules.
    func renameTag(_ oldName: String, to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, oldName != trimmed else { return }

        var changed = false
        for schedule in schedules {
            if let index = schedule.tags.firstIndex(of: oldName) {
                schedule.tags[index] = trimmed
                // Remove duplicates
                schedule.tags = Array(NSOrderedSet(array: schedule.tags)) as? [String] ?? schedule.tags
                touch(schedule)
                changed = true
            }
        }

        if changed {
            saveContext()
            normalizeSchedules()
        }
    }

    /// Delete a tag from all schedules.
    func deleteTag(_ tagName: String) {
        var changed = false
        for schedule in schedules {
            if schedule.tags.contains(tagName) {
                schedule.tags.removeAll { $0 == tagName }
                touch(schedule)
                changed = true
            }
        }

        if changed {
            saveContext()
            normalizeSchedules()
        }
    }

    /// Merge one tag into another across all schedules.
    func mergeTags(source: String, into target: String) {
        var changed = false
        for schedule in schedules {
            if schedule.tags.contains(source) {
                schedule.tags.removeAll { $0 == source }
                if !schedule.tags.contains(target) {
                    schedule.tags.append(target)
                }
                touch(schedule)
                changed = true
            }
        }

        if changed {
            saveContext()
            normalizeSchedules()
        }
    }

    /// All unique tags across all schedules.
    var allTags: [String] {
        let tags = schedules.flatMap(\.tags)
        return Array(Set(tags)).sorted()
    }

    /// Recurring completion data for stats computation.
    var recurringCompletionData: [UUID: Set<Date>] {
        recurringCompletionBySchedule
    }

    /// Reschedule a schedule to a new date (for drag & drop).
    func rescheduleSchedule(_ schedule: Schedule, to newDate: Date) {
        let oldDate = schedule.scheduledDate
        schedule.scheduledDate = newDate
        touch(schedule)
        saveContext()
        NotificationManager.shared.updateNotification(for: schedule)
        normalizeSchedules()

        // Record for undo
        if !isApplyingUndoRedo {
            UndoRedoManager.shared.record(
                .reschedule(id: schedule.id, oldDate: oldDate, newDate: newDate)
            )
            refreshUndoRedoState()
        }
    }

    func performUndo() {
        UndoRedoManager.shared.undo(using: self)
        refreshUndoRedoState()
    }

    func performRedo() {
        UndoRedoManager.shared.redo(using: self)
        refreshUndoRedoState()
    }

    // MARK: - Siri Intent Observers

    func observeSiriIntents() {
        NotificationCenter.default.addObserver(
            forName: .siriAddScheduleRequest,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let userInfo = notification.userInfo,
                  let title = userInfo["title"] as? String,
                  let date = userInfo["date"] as? Date
            else { return }

            let priorityRaw = userInfo["priority"] as? Int ?? 0
            let priority = SchedulePriority(rawValue: priorityRaw) ?? .none
            let notes = userInfo["notes"] as? String

            let schedule = Schedule(
                lastModifiedDeviceID: self?.currentDeviceID ?? "",
                title: title,
                notes: notes,
                scheduledDate: date,
                priority: priority
            )
            self?.addSchedule(schedule)
        }

        NotificationCenter.default.addObserver(
            forName: .siriCompleteScheduleRequest,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let userInfo = notification.userInfo,
                  let title = userInfo["title"] as? String
            else { return }

            // Find matching schedule
            if let schedule = self?.schedules.first(where: {
                $0.title.localizedCaseInsensitiveCompare(title) == .orderedSame && !$0.isCompleted
            }) {
                self?.toggleScheduleCompletion(schedule)
            }
        }

        // Focus filter changes
        NotificationCenter.default.addObserver(
            forName: .focusFilterChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.normalizeSchedules()
            self?.resyncAllScheduleNotifications()
        }
    }

    private var networkRecoveryTask: Task<Void, Never>? {
        get { _networkRecoveryTask }
        set { _networkRecoveryTask = newValue }
    }
    private var _networkRecoveryTask: Task<Void, Never>?

    func observeNetworkRecovery() {
        networkRecoveryTask?.cancel()
        networkRecoveryTask = Task { [weak self] in
            var wasOffline = !FirebaseSyncService.shared.isNetworkReachable
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled else { break }

                let isOnline = FirebaseSyncService.shared.isNetworkReachable
                if wasOffline && isOnline, let self {
                    await self.syncCoordinator.drainOfflineQueue(viewModel: self)
                }
                wasOffline = !isOnline
            }
        }
    }
}

// MARK: - ScheduleActionHandler Conformance

extension ScheduleViewModel: ScheduleActionHandler {
    func execute(_ action: ScheduleAction) {
        isApplyingUndoRedo = true
        defer { isApplyingUndoRedo = false }
        switch action {
        case .create(let snapshot):
            guard let modelContext else { return }
            let schedule = Schedule(
                id: snapshot.id,
                lastModifiedDeviceID: currentDeviceID,
                title: snapshot.title,
                scheduledDate: snapshot.scheduledDate
            )
            snapshot.apply(to: schedule)
            modelContext.insert(schedule)
            saveContext()
            schedules.append(schedule)

            let shouldBeActive = schedule.repeatPattern != .never || schedule.scheduledDate > Date()
            if schedule.repeatPattern == .never && schedule.isCompleted {
                NotificationManager.shared.cancelNotification(for: schedule)
            } else if shouldBeActive {
                NotificationManager.shared.scheduleNotification(for: schedule)
            } else {
                NotificationManager.shared.cancelNotification(for: schedule)
            }

            normalizeSchedules()

        case .delete(let snapshot):
            if let schedule = schedule(withID: snapshot.id) {
                deleteSchedule(schedule)
            } else if let modelContext {
                let schedule = Schedule(
                    id: snapshot.id,
                    lastModifiedDeviceID: currentDeviceID,
                    title: snapshot.title,
                    scheduledDate: snapshot.scheduledDate
                )
                snapshot.apply(to: schedule)
                modelContext.insert(schedule)
                saveContext()
                schedules.append(schedule)
                deleteSchedule(schedule)
            }

        case .update(_, let newSnapshot):
            if let schedule = schedule(withID: newSnapshot.id) {
                newSnapshot.apply(to: schedule)
                touch(schedule)
                saveContext()

                if schedule.repeatPattern == .never && schedule.isCompleted {
                    NotificationManager.shared.cancelNotification(for: schedule)
                } else {
                    let shouldBeActive = schedule.repeatPattern != .never || schedule.scheduledDate > Date()
                    if shouldBeActive {
                        NotificationManager.shared.updateNotification(for: schedule)
                    } else {
                        NotificationManager.shared.cancelNotification(for: schedule)
                    }
                }

                normalizeSchedules()
            }

        case .complete(let id, let wasCompleted):
            if let schedule = schedule(withID: id) {
                if schedule.repeatPattern == .never {
                    schedule.isCompleted = !wasCompleted
                    touch(schedule)
                    saveContext()

                    if schedule.isCompleted {
                        NotificationManager.shared.cancelNotification(for: schedule)
                    } else {
                        let shouldBeActive = schedule.repeatPattern != .never || schedule.scheduledDate > Date()
                        if shouldBeActive {
                            NotificationManager.shared.updateNotification(for: schedule)
                        } else {
                            NotificationManager.shared.cancelNotification(for: schedule)
                        }
                    }

                    normalizeSchedules()
                }
            }

        case .reschedule(let id, _, let newDate):
            if let schedule = schedule(withID: id) {
                schedule.scheduledDate = newDate
                touch(schedule)
                saveContext()
                NotificationManager.shared.updateNotification(for: schedule)
                normalizeSchedules()
            }
        }

        refreshNotificationBadgeCount()
    }
}

private extension ScheduleViewModel {
    func refreshUndoRedoState() {
        canUndo = UndoRedoManager.shared.canUndo
        canRedo = UndoRedoManager.shared.canRedo
        undoActionName = UndoRedoManager.shared.undoActionName
        redoActionName = UndoRedoManager.shared.redoActionName
    }

    func shouldDisplaySchedule(_ schedule: Schedule) -> Bool {
        FocusFilterState.current.shouldShow(schedule)
    }

    func refreshNotificationBadgeCount() {
        NotificationManager.shared.refreshBadgeCount(
            schedules: schedules,
            occurrenceMatchesDay: { schedule, day, calendar in
                occurs(schedule, on: day, calendar: calendar)
            },
            isOccurrenceCompleted: { schedule, day in
                isScheduleCompleted(schedule, on: day)
            }
        )
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
