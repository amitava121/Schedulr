import Foundation
import SwiftData
import FirebaseAuth
@preconcurrency import FirebaseFirestore
import OSLog

@MainActor
final class RealtimeSyncCoordinator {
    static let shared = RealtimeSyncCoordinator()

    nonisolated private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.bittu.Schedulr",
        category: "sync"
    )

    private var listener: ListenerRegistration?
    private let db: Firestore
    private var activeContext: ModelContext?

    private init() {
        let firestore = Firestore.firestore()
        // Firestore persistent local cache is enabled by default on Apple platforms.
        self.db = firestore
    }

    func startListening(context: ModelContext) {
        activeContext = context
        guard let uid = Auth.auth().currentUser?.uid else {
            stopListening()
            return
        }

        listener?.remove()
        listener = db.collection("users").document(uid).collection("schedules")
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self else { return }
                guard let snapshot else {
                    if let error {
                        Self.logger.error("Realtime listener error: \(error.localizedDescription, privacy: .public)")
                    }
                    return
                }

                Task { @MainActor in
                    for diff in snapshot.documentChanges {
                        if diff.document.metadata.hasPendingWrites {
                            continue
                        }

                        let data = diff.document.data()
                        let documentID = diff.document.documentID

                        switch diff.type {
                        case .added, .modified:
                            self.processIncomingCloudChange(data: data, documentID: documentID, context: context)
                        case .removed:
                            self.processIncomingCloudDeletion(documentID: documentID, context: context)
                        }
                    }

                    try? context.save()
                }
            }
    }

    func stopListening() {
        listener?.remove()
        listener = nil
        activeContext = nil
    }

    func pushLocalChange(schedule: Schedule) {
        guard let uid = Auth.auth().currentUser?.uid else {
            schedule.syncStatus = "failed"
            return
        }

        let scheduleID = schedule.id
        schedule.syncStatus = "pending"

        var payload = scheduleDictionary(from: schedule)
        payload["updatedAt"] = FieldValue.serverTimestamp()
        payload["clientUpdatedAt"] = Timestamp(date: schedule.updatedAt)

        db.collection("users").document(uid).collection("schedules")
            .document(schedule.id.uuidString)
            .setData(payload, merge: true) { error in
                DispatchQueue.main.async {
                    self.updateLocalSyncStatus(scheduleID: scheduleID, status: (error == nil) ? "synced" : "failed")
                }
            }
    }

    func pushGranularChange(schedule: Schedule, changedFields: [String: Any]) {
        guard let uid = Auth.auth().currentUser?.uid else {
            schedule.syncStatus = "failed"
            return
        }

        let scheduleID = schedule.id
        schedule.syncStatus = "pending"

        var payload = changedFields
        payload["updatedAt"] = FieldValue.serverTimestamp()
        payload["clientUpdatedAt"] = Timestamp(date: schedule.updatedAt)

        db.collection("users").document(uid).collection("schedules")
            .document(schedule.id.uuidString)
            .setData(payload, merge: true) { error in
                DispatchQueue.main.async {
                    self.updateLocalSyncStatus(scheduleID: scheduleID, status: (error == nil) ? "synced" : "failed")
                }
            }
    }

    func pushLocalDeletion(schedule: Schedule) {
        guard let uid = Auth.auth().currentUser?.uid else {
            schedule.syncStatus = "failed"
            return
        }

        let scheduleID = schedule.id
        schedule.isSoftDeleted = true
        schedule.deletedAt = Date()
        schedule.updatedAt = Date()
        schedule.syncStatus = "pending"

        db.collection("users").document(uid).collection("schedules")
            .document(schedule.id.uuidString)
            .setData([
                "isSoftDeleted": true,
                "deletedAt": FieldValue.serverTimestamp(),
                "updatedAt": FieldValue.serverTimestamp(),
                "clientUpdatedAt": Timestamp(date: schedule.updatedAt)
            ], merge: true) { error in
                DispatchQueue.main.async {
                    self.updateLocalSyncStatus(scheduleID: scheduleID, status: (error == nil) ? "synced" : "failed")
                }
            }
    }

    private func updateLocalSyncStatus(scheduleID: UUID, status: String) {
        guard let context = activeContext else { return }
        let descriptor = FetchDescriptor<Schedule>(predicate: #Predicate { $0.id == scheduleID })
        if let schedule = try? context.fetch(descriptor).first {
            schedule.syncStatus = status
            try? context.save()
        }
    }

    private func processIncomingCloudChange(data: [String: Any], documentID: String, context: ModelContext) {
        guard let scheduleID = UUID(uuidString: documentID) else { return }

        if let isSoftDeleted = boolValue(data["isSoftDeleted"]), isSoftDeleted {
            processIncomingCloudDeletion(documentID: documentID, context: context)
            return
        }

        if timestampValue(data["deletedAt"]) != nil {
            processIncomingCloudDeletion(documentID: documentID, context: context)
            return
        }

        let cloudTimestamp = timestampValue(data["updatedAt"])
            ?? timestampValue(data["serverUpdatedAt"])
            ?? timestampValue(data["clientUpdatedAt"])
            ?? Date.distantPast

        let descriptor = FetchDescriptor<Schedule>(predicate: #Predicate { $0.id == scheduleID })
        let localMatch = try? context.fetch(descriptor).first
        let localTimestamp = localMatch?.updatedAt ?? Date.distantPast

        guard cloudTimestamp > localTimestamp || localMatch == nil else { return }

        if let existing = localMatch {
            applyCloudData(data, to: existing, cloudTimestamp: cloudTimestamp)
        } else {
            let newSchedule = makeScheduleFromCloudData(data, id: scheduleID, cloudTimestamp: cloudTimestamp)
            context.insert(newSchedule)
        }
    }

    private func processIncomingCloudDeletion(documentID: String, context: ModelContext) {
        guard let scheduleID = UUID(uuidString: documentID) else { return }
        let descriptor = FetchDescriptor<Schedule>(predicate: #Predicate { $0.id == scheduleID })
        if let localMatch = try? context.fetch(descriptor).first {
            localMatch.isSoftDeleted = true
            localMatch.deletedAt = localMatch.deletedAt ?? Date()
            localMatch.syncStatus = "synced"
        }
    }

    private func makeScheduleFromCloudData(_ data: [String: Any], id: UUID, cloudTimestamp: Date) -> Schedule {
        let createdAt = timestampValue(data["createdAt"]) ?? cloudTimestamp
        let schedule = Schedule(
            id: id,
            createdAt: createdAt,
            updatedAt: cloudTimestamp,
            deletedAt: timestampValue(data["deletedAt"]),
            isSoftDeleted: boolValue(data["isSoftDeleted"]) ?? false,
            lastModifiedDeviceID: stringValue(data["lastModifiedDeviceID"]) ?? stringValue(data["writerDeviceID"]) ?? "",
            syncVersion: intValue(data["syncVersion"]) ?? 0,
            lastSyncedVersion: intValue(data["lastSyncedVersion"]) ?? 0,
            conflictResolutionTag: stringValue(data["conflictResolutionTag"]),
            title: stringValue(data["title"]) ?? "Untitled",
            notes: stringValue(data["notes"]),
            urlString: stringValue(data["urlString"]),
            scheduledDate: timestampValue(data["scheduledDate"]) ?? Date(),
            isUrgent: boolValue(data["isUrgent"]) ?? false,
            repeatPattern: RepeatPattern(rawValue: stringValue(data["repeatPatternRaw"]) ?? "") ?? .never,
            repeatWeekdays: intArrayValue(data["repeatWeekdays"]) ?? Array(1...7),
            repeatInterval: intValue(data["repeatInterval"]) ?? 1,
            repeatEndCount: intValue(data["repeatEndCount"]) ?? 0,
            excludedOccurrenceDates: timestampArrayValue(data["excludedOccurrenceDates"]),
            repeatEndOption: RepeatEndOption(rawValue: stringValue(data["repeatEndOptionRaw"]) ?? "") ?? .never,
            repeatEndDate: timestampValue(data["repeatEndDate"]),
            alertDeliveryOption: AlertDeliveryOption(rawValue: stringValue(data["alertDeliveryRaw"]) ?? "") ?? .push,
            alarmSoundOption: AlarmSoundOption(rawValue: stringValue(data["alarmSoundRaw"]) ?? "") ?? .defaultRingtone,
            alarmSnoozeEnabled: boolValue(data["alarmSnoozeEnabled"]) ?? true,
            alarmSnoozeMinutes: intValue(data["alarmSnoozeMinutes"]) ?? 10,
            earlyReminderMinutes: intValue(data["earlyReminderMinutes"]),
            additionalReminderMinutes: intArrayValue(data["additionalReminderMinutes"]) ?? [],
            timeZoneIdentifier: stringValue(data["timeZoneIdentifier"]),
            listName: stringValue(data["listName"]) ?? ScheduleViewModel.defaultCalendarName,
            tags: stringArrayValue(data["tags"]) ?? [],
            isFlagged: boolValue(data["isFlagged"]) ?? false,
            isCompleted: boolValue(data["isCompleted"]) ?? false,
            priority: SchedulePriority(rawValue: intValue(data["priorityRaw"]) ?? 0) ?? .none
        )
        schedule.syncStatus = "synced"
        return schedule
    }

    private func applyCloudData(_ data: [String: Any], to schedule: Schedule, cloudTimestamp: Date) {
        schedule.createdAt = timestampValue(data["createdAt"]) ?? schedule.createdAt
        schedule.updatedAt = cloudTimestamp
        schedule.deletedAt = timestampValue(data["deletedAt"])
        schedule.isSoftDeleted = boolValue(data["isSoftDeleted"]) ?? schedule.isSoftDeleted
        schedule.lastModifiedDeviceID = stringValue(data["lastModifiedDeviceID"]) ?? stringValue(data["writerDeviceID"]) ?? schedule.lastModifiedDeviceID
        schedule.syncVersion = intValue(data["syncVersion"]) ?? schedule.syncVersion
        schedule.lastSyncedVersion = intValue(data["lastSyncedVersion"]) ?? schedule.lastSyncedVersion
        schedule.conflictResolutionTag = stringValue(data["conflictResolutionTag"])
        schedule.title = stringValue(data["title"]) ?? schedule.title
        schedule.notes = stringValue(data["notes"])
        schedule.urlString = stringValue(data["urlString"])
        schedule.scheduledDate = timestampValue(data["scheduledDate"]) ?? schedule.scheduledDate
        schedule.isUrgent = boolValue(data["isUrgent"]) ?? schedule.isUrgent
        schedule.repeatPatternRaw = stringValue(data["repeatPatternRaw"]) ?? schedule.repeatPatternRaw
        schedule.repeatWeekdays = intArrayValue(data["repeatWeekdays"]) ?? schedule.repeatWeekdays
        schedule.repeatInterval = intValue(data["repeatInterval"]) ?? schedule.repeatInterval
        schedule.repeatEndCount = intValue(data["repeatEndCount"]) ?? schedule.repeatEndCount
        schedule.excludedOccurrenceDates = timestampArrayValue(data["excludedOccurrenceDates"])
        schedule.repeatEndOptionRaw = stringValue(data["repeatEndOptionRaw"]) ?? schedule.repeatEndOptionRaw
        schedule.repeatEndDate = timestampValue(data["repeatEndDate"])
        schedule.alertDeliveryRaw = stringValue(data["alertDeliveryRaw"]) ?? schedule.alertDeliveryRaw
        schedule.alarmSoundRaw = stringValue(data["alarmSoundRaw"]) ?? schedule.alarmSoundRaw
        schedule.alarmSnoozeEnabled = boolValue(data["alarmSnoozeEnabled"]) ?? schedule.alarmSnoozeEnabled
        schedule.alarmSnoozeMinutes = intValue(data["alarmSnoozeMinutes"]) ?? schedule.alarmSnoozeMinutes
        schedule.earlyReminderMinutes = intValue(data["earlyReminderMinutes"])
        schedule.additionalReminderMinutes = intArrayValue(data["additionalReminderMinutes"]) ?? schedule.additionalReminderMinutes
        schedule.timeZoneIdentifier = stringValue(data["timeZoneIdentifier"])
        schedule.listName = stringValue(data["listName"]) ?? schedule.listName
        schedule.tags = stringArrayValue(data["tags"]) ?? schedule.tags
        schedule.isFlagged = boolValue(data["isFlagged"]) ?? schedule.isFlagged
        schedule.isCompleted = boolValue(data["isCompleted"]) ?? schedule.isCompleted
        schedule.priorityRaw = intValue(data["priorityRaw"]) ?? schedule.priorityRaw
        schedule.syncStatus = "synced"
    }

    private func scheduleDictionary(from schedule: Schedule) -> [String: Any] {
        [
            "scheduleID": schedule.id.uuidString,
            "createdAt": Timestamp(date: schedule.createdAt),
            "updatedAt": Timestamp(date: schedule.updatedAt),
            "deletedAt": schedule.deletedAt.map { Timestamp(date: $0) } as Any,
            "isSoftDeleted": schedule.isSoftDeleted,
            "lastModifiedDeviceID": schedule.lastModifiedDeviceID,
            "syncVersion": schedule.syncVersion,
            "lastSyncedVersion": schedule.lastSyncedVersion,
            "conflictResolutionTag": schedule.conflictResolutionTag as Any,
            "title": schedule.title,
            "notes": schedule.notes as Any,
            "urlString": schedule.urlString as Any,
            "scheduledDate": Timestamp(date: schedule.scheduledDate),
            "isUrgent": schedule.isUrgent,
            "repeatPatternRaw": schedule.repeatPatternRaw,
            "repeatWeekdays": schedule.repeatWeekdays,
            "repeatInterval": schedule.repeatInterval,
            "repeatEndCount": schedule.repeatEndCount,
            "excludedOccurrenceDates": schedule.excludedOccurrenceDates.map { Timestamp(date: $0) },
            "repeatEndOptionRaw": schedule.repeatEndOptionRaw,
            "repeatEndDate": schedule.repeatEndDate.map { Timestamp(date: $0) } as Any,
            "alertDeliveryRaw": schedule.alertDeliveryRaw,
            "alarmSoundRaw": schedule.alarmSoundRaw,
            "alarmSnoozeEnabled": schedule.alarmSnoozeEnabled,
            "alarmSnoozeMinutes": schedule.alarmSnoozeMinutes,
            "earlyReminderMinutes": schedule.earlyReminderMinutes as Any,
            "additionalReminderMinutes": schedule.additionalReminderMinutes,
            "timeZoneIdentifier": schedule.timeZoneIdentifier as Any,
            "listName": schedule.listName,
            "tags": schedule.tags,
            "isFlagged": schedule.isFlagged,
            "isCompleted": schedule.isCompleted,
            "priorityRaw": schedule.priorityRaw
        ]
    }

    private func stringValue(_ value: Any?) -> String? {
        if let string = value as? String { return string }
        return nil
    }

    private func boolValue(_ value: Any?) -> Bool? {
        if let bool = value as? Bool { return bool }
        if let number = value as? NSNumber { return number.boolValue }
        return nil
    }

    private func intValue(_ value: Any?) -> Int? {
        if let int = value as? Int { return int }
        if let number = value as? NSNumber { return number.intValue }
        if let string = value as? String { return Int(string) }
        return nil
    }

    private func intArrayValue(_ value: Any?) -> [Int]? {
        if let values = value as? [Int] { return values }
        if let values = value as? [NSNumber] { return values.map(\.intValue) }
        return nil
    }

    private func stringArrayValue(_ value: Any?) -> [String]? {
        if let values = value as? [String] { return values }
        if let values = value as? [Any] { return values.compactMap { $0 as? String } }
        return nil
    }

    private func timestampValue(_ value: Any?) -> Date? {
        if let timestamp = value as? Timestamp { return timestamp.dateValue() }
        if let date = value as? Date { return date }
        if let string = value as? String {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return formatter.date(from: string)
        }
        return nil
    }

    private func timestampArrayValue(_ value: Any?) -> [Date] {
        if let timestamps = value as? [Timestamp] {
            return timestamps.map { $0.dateValue() }
        }
        if let dates = value as? [Date] {
            return dates
        }
        if let values = value as? [Any] {
            return values.compactMap { timestampValue($0) }
        }
        return []
    }
}
