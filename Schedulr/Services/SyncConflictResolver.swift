import Foundation

struct SyncBackupPayload {
    var schedules: [ScheduleDelta]
    var calendarNames: [String]
    var recurringCompletionBySchedule: [String: [TimeInterval]]
}

enum MergeOutcome {
    case useLocal
    case useRemote
    case merge(ScheduleDelta)
}

enum BlobConflictAction {
    case keepLocal
    case keepRemote
    case merge(Schedule)
    case askUser
}

enum SyncConflictResolver {
    static func localWithUnion(local: ScheduleDelta, remote: ScheduleDelta) -> ScheduleDelta {
        var merged = local
        merged.excludedOccurrenceDates = unionExcludedDates(local: local, remote: remote)
        merged.tags = unionTags(local: local, remote: remote)
        merged.syncVersion = max(local.syncVersion, remote.syncVersion)
        return merged
    }

    static func remoteWithUnion(local: ScheduleDelta, remote: ScheduleDelta) -> ScheduleDelta {
        var merged = remote
        merged.excludedOccurrenceDates = unionExcludedDates(local: local, remote: remote)
        merged.tags = unionTags(local: local, remote: remote)
        merged.syncVersion = max(local.syncVersion, remote.syncVersion)
        return merged
    }

    static func isConflictUserVisible(local: ScheduleDelta, remote: ScheduleDelta) -> Bool {
        if local.title != remote.title { return true }
        if local.scheduledDate != remote.scheduledDate { return true }
        if local.notes != remote.notes { return true }
        return false
    }

    static func conflictSummary(local: ScheduleDelta, remote: ScheduleDelta) -> String {
        var fields: [String] = []
        if local.title != remote.title {
            fields.append("Title")
        }
        if local.scheduledDate != remote.scheduledDate {
            fields.append("Date")
        }
        if local.notes != remote.notes {
            fields.append("Notes")
        }

        if fields.isEmpty {
            return "Differences only in mergeable fields (tags/excluded dates)."
        }
        return "Different fields: \(fields.joined(separator: ", "))"
    }

    static func resolve(local: ScheduleDelta, remote: ScheduleDelta) -> MergeOutcome {
        if local.isSoftDeleted != remote.isSoftDeleted {
            let localDeletedWins = local.isSoftDeleted && remote.deletedAt == nil
            let remoteDeletedWins = remote.isSoftDeleted && local.deletedAt == nil
            if localDeletedWins { return .useLocal }
            if remoteDeletedWins { return .useRemote }
        }

        if local.updatedAt > remote.updatedAt {
            return .useLocal
        }
        if remote.updatedAt > local.updatedAt {
            return .useRemote
        }

        let delta = abs(local.updatedAt.timeIntervalSince(remote.updatedAt))
        if delta <= 1 {
            return local.lastModifiedDeviceID <= remote.lastModifiedDeviceID ? .useLocal : .useRemote
        }

        return .merge(localWithUnion(local: local, remote: remote))
    }

    static func resolveFullBlob(local: SyncBackupPayload, remote: SyncBackupPayload) -> SyncBackupPayload {
        var mergedByID: [String: ScheduleDelta] = [:]

        for item in local.schedules {
            mergedByID[item.scheduleID] = item
        }

        for remoteItem in remote.schedules {
            guard let localItem = mergedByID[remoteItem.scheduleID] else {
                mergedByID[remoteItem.scheduleID] = remoteItem
                continue
            }

            switch resolve(local: localItem, remote: remoteItem) {
            case .useLocal:
                mergedByID[remoteItem.scheduleID] = localWithUnion(local: localItem, remote: remoteItem)
            case .useRemote:
                mergedByID[remoteItem.scheduleID] = remoteWithUnion(local: localItem, remote: remoteItem)
            case .merge(let merged):
                mergedByID[remoteItem.scheduleID] = merged
            }
        }

        let calendarUnion = Array(Set(local.calendarNames + remote.calendarNames)).sorted()

        var recurringUnion = local.recurringCompletionBySchedule
        for (key, values) in remote.recurringCompletionBySchedule {
            let existing = recurringUnion[key] ?? []
            recurringUnion[key] = Array(Set(existing + values)).sorted()
        }

        return SyncBackupPayload(
            schedules: Array(mergedByID.values),
            calendarNames: calendarUnion,
            recurringCompletionBySchedule: recurringUnion
        )
    }

    static func resolveBlobRestoreConflict(localSchedule: Schedule, remoteSchedule: Schedule) -> BlobConflictAction {
        let sameTitle = localSchedule.title == remoteSchedule.title
        let sameScheduledDate = localSchedule.scheduledDate == remoteSchedule.scheduledDate
        if sameTitle && sameScheduledDate {
            let merged = mergeSchedules(local: localSchedule, remote: remoteSchedule)
            return .merge(merged)
        }

        if localSchedule.updatedAt >= remoteSchedule.updatedAt {
            return .keepLocal
        }
        if remoteSchedule.updatedAt > localSchedule.updatedAt {
            return .keepRemote
        }
        return .askUser
    }

    private static func mergeSchedules(local: Schedule, remote: Schedule) -> Schedule {
        let merged = Schedule(
            id: local.id,
            createdAt: min(local.createdAt, remote.createdAt),
            updatedAt: max(local.updatedAt, remote.updatedAt),
            deletedAt: local.deletedAt ?? remote.deletedAt,
            isSoftDeleted: local.isSoftDeleted || remote.isSoftDeleted,
            lastModifiedDeviceID: local.updatedAt >= remote.updatedAt ? local.lastModifiedDeviceID : remote.lastModifiedDeviceID,
            syncVersion: max(local.syncVersion, remote.syncVersion),
            lastSyncedVersion: max(local.lastSyncedVersion, remote.lastSyncedVersion),
            conflictResolutionTag: nil,
            title: local.title,
            notes: local.notes ?? remote.notes,
            urlString: local.urlString ?? remote.urlString,
            scheduledDate: local.scheduledDate,
            isUrgent: local.isUrgent || remote.isUrgent,
            repeatPattern: local.repeatPattern,
            repeatWeekdays: Array(Set(local.repeatWeekdays + remote.repeatWeekdays)).sorted(),
            excludedOccurrenceDates: Array(Set(local.excludedOccurrenceDates.map(\.startOfDay) + remote.excludedOccurrenceDates.map(\.startOfDay))).sorted(),
            repeatEndOption: local.repeatEndOption,
            repeatEndDate: local.repeatEndDate ?? remote.repeatEndDate,
            alertDeliveryOption: local.alertDeliveryOption,
            alarmSoundOption: local.alarmSoundOption,
            alarmSnoozeEnabled: local.alarmSnoozeEnabled || remote.alarmSnoozeEnabled,
            alarmSnoozeMinutes: max(local.alarmSnoozeMinutes, remote.alarmSnoozeMinutes),
            earlyReminderMinutes: local.earlyReminderMinutes ?? remote.earlyReminderMinutes,
            listName: local.listName,
            tags: Array(Set(local.tags + remote.tags)).sorted(),
            isFlagged: local.isFlagged || remote.isFlagged,
            isCompleted: local.isCompleted || remote.isCompleted,
            priority: local.priority.rawValue >= remote.priority.rawValue ? local.priority : remote.priority
        )

        merged.repeatInterval = max(local.repeatInterval, remote.repeatInterval)
        merged.repeatEndCount = max(local.repeatEndCount, remote.repeatEndCount)
        merged.additionalReminderMinutes = Array(Set(local.additionalReminderMinutes + remote.additionalReminderMinutes)).sorted()
        merged.timeZoneIdentifier = local.timeZoneIdentifier ?? remote.timeZoneIdentifier
        return merged
    }

    private static func unionExcludedDates(local: ScheduleDelta, remote: ScheduleDelta) -> [Date] {
        Array(Set(local.excludedOccurrenceDates.map(\.startOfDay) + remote.excludedOccurrenceDates.map(\.startOfDay))).sorted()
    }

    private static func unionTags(local: ScheduleDelta, remote: ScheduleDelta) -> [String] {
        Array(Set(local.tags + remote.tags)).sorted()
    }
}
