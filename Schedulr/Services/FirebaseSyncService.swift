import Foundation
import Network
import FirebaseAuth
import FirebaseCore
import FirebaseFirestore

enum FirebaseSyncError: LocalizedError {
    case notConfigured
    case authFailed
    case firestoreFailed
    case missingBackup
    case staleVersion
    case deltaConflict
    case retryExhausted

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Firebase is not configured."
        case .authFailed:
            return "Authentication failed. Check your credentials."
        case .firestoreFailed:
            return "Firestore sync failed."
        case .missingBackup:
            return "No cloud backup found for this account."
        case .staleVersion:
            return "Cloud has a newer version. Pull latest changes before pushing."
        case .deltaConflict:
            return "A conflicting delta exists for this schedule."
        case .retryExhausted:
            return "Sync retry attempts exhausted."
        }
    }
}

struct ScheduleDelta: Codable, Identifiable {
    var id: String { scheduleID }
    var scheduleID: String
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
    var repeatPatternRaw: String
    var repeatWeekdays: [Int]
    var excludedOccurrenceDates: [Date]
    var repeatEndOptionRaw: String
    var repeatEndDate: Date?
    var alertDeliveryRaw: String
    var alarmSoundRaw: String
    var alarmSnoozeEnabled: Bool
    var alarmSnoozeMinutes: Int
    var earlyReminderMinutes: Int?
    var additionalReminderMinutes: [Int]
    var timeZoneIdentifier: String?
    var listName: String
    var tags: [String]
    var isFlagged: Bool
    var isCompleted: Bool
    var priorityRaw: Int
    var repeatInterval: Int
    var repeatEndCount: Int
    var syncVersion: Int
    var conflictResolutionTag: String?
    var deviceID: String
    var clientUpdatedAt: Date
    var serverUpdatedAt: Date?

    init(schedule: Schedule, deviceID: String) {
        self.scheduleID = schedule.id.uuidString
        self.createdAt = schedule.createdAt
        self.updatedAt = schedule.updatedAt
        self.deletedAt = schedule.deletedAt
        self.isSoftDeleted = schedule.isSoftDeleted
        self.lastModifiedDeviceID = schedule.lastModifiedDeviceID
        self.title = schedule.title
        self.notes = schedule.notes
        self.urlString = schedule.urlString
        self.scheduledDate = schedule.scheduledDate
        self.isUrgent = schedule.isUrgent
        self.repeatPatternRaw = schedule.repeatPatternRaw
        self.repeatWeekdays = schedule.repeatWeekdays
        self.excludedOccurrenceDates = schedule.excludedOccurrenceDates
        self.repeatEndOptionRaw = schedule.repeatEndOptionRaw
        self.repeatEndDate = schedule.repeatEndDate
        self.alertDeliveryRaw = schedule.alertDeliveryRaw
        self.alarmSoundRaw = schedule.alarmSoundRaw
        self.alarmSnoozeEnabled = schedule.alarmSnoozeEnabled
        self.alarmSnoozeMinutes = schedule.alarmSnoozeMinutes
        self.earlyReminderMinutes = schedule.earlyReminderMinutes
        self.additionalReminderMinutes = schedule.additionalReminderMinutes
        self.timeZoneIdentifier = schedule.timeZoneIdentifier
        self.listName = schedule.listName
        self.tags = schedule.tags
        self.isFlagged = schedule.isFlagged
        self.isCompleted = schedule.isCompleted
        self.priorityRaw = schedule.priorityRaw
        self.repeatInterval = schedule.repeatInterval
        self.repeatEndCount = schedule.repeatEndCount
        self.syncVersion = schedule.syncVersion
        self.conflictResolutionTag = schedule.conflictResolutionTag
        self.deviceID = deviceID
        self.clientUpdatedAt = schedule.updatedAt
        self.serverUpdatedAt = nil
    }

    init(
        scheduleID: String,
        createdAt: Date,
        updatedAt: Date,
        deletedAt: Date?,
        isSoftDeleted: Bool,
        lastModifiedDeviceID: String,
        title: String,
        notes: String?,
        urlString: String?,
        scheduledDate: Date,
        isUrgent: Bool,
        repeatPatternRaw: String,
        repeatWeekdays: [Int],
        excludedOccurrenceDates: [Date],
        repeatEndOptionRaw: String,
        repeatEndDate: Date?,
        alertDeliveryRaw: String,
        alarmSoundRaw: String,
        alarmSnoozeEnabled: Bool,
        alarmSnoozeMinutes: Int,
        earlyReminderMinutes: Int?,
        additionalReminderMinutes: [Int],
        timeZoneIdentifier: String?,
        listName: String,
        tags: [String],
        isFlagged: Bool,
        isCompleted: Bool,
        priorityRaw: Int,
        repeatInterval: Int,
        repeatEndCount: Int,
        syncVersion: Int,
        conflictResolutionTag: String?,
        deviceID: String,
        clientUpdatedAt: Date,
        serverUpdatedAt: Date?
    ) {
        self.scheduleID = scheduleID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.isSoftDeleted = isSoftDeleted
        self.lastModifiedDeviceID = lastModifiedDeviceID
        self.title = title
        self.notes = notes
        self.urlString = urlString
        self.scheduledDate = scheduledDate
        self.isUrgent = isUrgent
        self.repeatPatternRaw = repeatPatternRaw
        self.repeatWeekdays = repeatWeekdays
        self.excludedOccurrenceDates = excludedOccurrenceDates
        self.repeatEndOptionRaw = repeatEndOptionRaw
        self.repeatEndDate = repeatEndDate
        self.alertDeliveryRaw = alertDeliveryRaw
        self.alarmSoundRaw = alarmSoundRaw
        self.alarmSnoozeEnabled = alarmSnoozeEnabled
        self.alarmSnoozeMinutes = alarmSnoozeMinutes
        self.earlyReminderMinutes = earlyReminderMinutes
        self.additionalReminderMinutes = additionalReminderMinutes
        self.timeZoneIdentifier = timeZoneIdentifier
        self.listName = listName
        self.tags = tags
        self.isFlagged = isFlagged
        self.isCompleted = isCompleted
        self.priorityRaw = priorityRaw
        self.repeatInterval = repeatInterval
        self.repeatEndCount = repeatEndCount
        self.syncVersion = syncVersion
        self.conflictResolutionTag = conflictResolutionTag
        self.deviceID = deviceID
        self.clientUpdatedAt = clientUpdatedAt
        self.serverUpdatedAt = serverUpdatedAt
    }

    func firestoreData() -> [String: Any] {
        [
            "scheduleID": scheduleID,
            "createdAt": Timestamp(date: createdAt),
            "updatedAt": Timestamp(date: updatedAt),
            "deletedAt": deletedAt.map { Timestamp(date: $0) } as Any,
            "isSoftDeleted": isSoftDeleted,
            "lastModifiedDeviceID": lastModifiedDeviceID,
            "title": title,
            "notes": notes as Any,
            "urlString": urlString as Any,
            "scheduledDate": Timestamp(date: scheduledDate),
            "isUrgent": isUrgent,
            "repeatPatternRaw": repeatPatternRaw,
            "repeatWeekdays": repeatWeekdays,
            "excludedOccurrenceDates": excludedOccurrenceDates.map { Timestamp(date: $0) },
            "repeatEndOptionRaw": repeatEndOptionRaw,
            "repeatEndDate": repeatEndDate.map { Timestamp(date: $0) } as Any,
            "alertDeliveryRaw": alertDeliveryRaw,
            "alarmSoundRaw": alarmSoundRaw,
            "alarmSnoozeEnabled": alarmSnoozeEnabled,
            "alarmSnoozeMinutes": alarmSnoozeMinutes,
            "earlyReminderMinutes": earlyReminderMinutes as Any,
            "additionalReminderMinutes": additionalReminderMinutes,
            "timeZoneIdentifier": timeZoneIdentifier as Any,
            "listName": listName,
            "tags": tags,
            "isFlagged": isFlagged,
            "isCompleted": isCompleted,
            "priorityRaw": priorityRaw,
            "repeatInterval": repeatInterval,
            "repeatEndCount": repeatEndCount,
            "syncVersion": syncVersion,
            "conflictResolutionTag": conflictResolutionTag as Any,
            "deviceID": deviceID,
            "clientUpdatedAt": Timestamp(date: clientUpdatedAt),
            "serverUpdatedAt": FieldValue.serverTimestamp()
        ]
    }

    static func fromSnapshot(_ snapshot: QueryDocumentSnapshot) -> ScheduleDelta? {
        let data = snapshot.data()

        guard
            let scheduleID = data["scheduleID"] as? String,
            let createdAt = (data["createdAt"] as? Timestamp)?.dateValue(),
            let updatedAt = (data["updatedAt"] as? Timestamp)?.dateValue(),
            let isSoftDeleted = data["isSoftDeleted"] as? Bool,
            let lastModifiedDeviceID = data["lastModifiedDeviceID"] as? String,
            let title = data["title"] as? String,
            let scheduledDate = (data["scheduledDate"] as? Timestamp)?.dateValue(),
            let isUrgent = data["isUrgent"] as? Bool,
            let repeatPatternRaw = data["repeatPatternRaw"] as? String,
            let repeatWeekdays = data["repeatWeekdays"] as? [Int],
            let repeatEndOptionRaw = data["repeatEndOptionRaw"] as? String,
            let alertDeliveryRaw = data["alertDeliveryRaw"] as? String,
            let alarmSoundRaw = data["alarmSoundRaw"] as? String,
            let alarmSnoozeEnabled = data["alarmSnoozeEnabled"] as? Bool,
            let alarmSnoozeMinutes = data["alarmSnoozeMinutes"] as? Int,
            let additionalReminderMinutes = data["additionalReminderMinutes"] as? [Int],
            let listName = data["listName"] as? String,
            let tags = data["tags"] as? [String],
            let isFlagged = data["isFlagged"] as? Bool,
            let isCompleted = data["isCompleted"] as? Bool,
            let priorityRaw = data["priorityRaw"] as? Int,
            let repeatInterval = data["repeatInterval"] as? Int,
            let repeatEndCount = data["repeatEndCount"] as? Int,
            let syncVersion = data["syncVersion"] as? Int,
            let deviceID = data["deviceID"] as? String,
            let clientUpdatedAt = (data["clientUpdatedAt"] as? Timestamp)?.dateValue()
        else {
            return nil
        }

        let excludedOccurrenceDates = (data["excludedOccurrenceDates"] as? [Timestamp])?.map { $0.dateValue() } ?? []

        return ScheduleDelta(
            scheduleID: scheduleID,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: (data["deletedAt"] as? Timestamp)?.dateValue(),
            isSoftDeleted: isSoftDeleted,
            lastModifiedDeviceID: lastModifiedDeviceID,
            title: title,
            notes: data["notes"] as? String,
            urlString: data["urlString"] as? String,
            scheduledDate: scheduledDate,
            isUrgent: isUrgent,
            repeatPatternRaw: repeatPatternRaw,
            repeatWeekdays: repeatWeekdays,
            excludedOccurrenceDates: excludedOccurrenceDates,
            repeatEndOptionRaw: repeatEndOptionRaw,
            repeatEndDate: (data["repeatEndDate"] as? Timestamp)?.dateValue(),
            alertDeliveryRaw: alertDeliveryRaw,
            alarmSoundRaw: alarmSoundRaw,
            alarmSnoozeEnabled: alarmSnoozeEnabled,
            alarmSnoozeMinutes: alarmSnoozeMinutes,
            earlyReminderMinutes: data["earlyReminderMinutes"] as? Int,
            additionalReminderMinutes: additionalReminderMinutes,
            timeZoneIdentifier: data["timeZoneIdentifier"] as? String,
            listName: listName,
            tags: tags,
            isFlagged: isFlagged,
            isCompleted: isCompleted,
            priorityRaw: priorityRaw,
            repeatInterval: repeatInterval,
            repeatEndCount: repeatEndCount,
            syncVersion: syncVersion,
            conflictResolutionTag: data["conflictResolutionTag"] as? String,
            deviceID: deviceID,
            clientUpdatedAt: clientUpdatedAt,
            serverUpdatedAt: (data["serverUpdatedAt"] as? Timestamp)?.dateValue()
        )
    }
}

struct ScheduleDeltaDocument: Identifiable {
    var id: String
    var delta: ScheduleDelta
    var serverUpdatedAt: Date?
}

struct CloudBackupDownload {
    var data: Data
    var globalSyncVersion: Int?
}

@MainActor
@Observable
final class FirebaseSyncService {
    static let shared = FirebaseSyncService()
    private static let installMarkerKey = "schedulr.install.marker.v1"
    private static let deviceIDStorageKey = "scheduleDeviceID.v1"

    var isBusy = false
    var lastErrorMessage: String?
    var lastSyncedAt: Date?
    var isNetworkReachable = true

    private var backupListener: ListenerRegistration?
    private var backupListenerTask: Task<Void, Never>?
    private var backupUpdateHandler: ((Data) -> Void)?
    private let networkMonitor = NWPathMonitor()
    private let networkMonitorQueue = DispatchQueue(label: "schedulr.firebase.network")
    private var isFirebaseConfigured: Bool { FirebaseApp.app() != nil }
    private var currentDeviceID: String {
        let defaults = UserDefaults.standard
        if let existing = defaults.string(forKey: Self.deviceIDStorageKey), !existing.isEmpty {
            return existing
        }
        let generated = UUID().uuidString
        defaults.set(generated, forKey: Self.deviceIDStorageKey)
        return generated
    }

    private init() {
        startNetworkMonitoring()
        enforceFreshInstallAuthResetIfNeeded()
        if isFirebaseConfigured, Auth.auth().currentUser != nil {
            startRealtimeListenerIfNeeded()
        }
    }

    deinit {
        networkMonitor.cancel()
    }

    private func startNetworkMonitoring() {
        networkMonitor.pathUpdateHandler = { [weak self] path in
            let isReachable = path.status == .satisfied
            Task { @MainActor [weak self] in
                self?.isNetworkReachable = isReachable
            }
        }
        networkMonitor.start(queue: networkMonitorQueue)
    }

    private func enforceFreshInstallAuthResetIfNeeded() {
        let defaults = UserDefaults.standard
        let hasInstallMarker = defaults.bool(forKey: Self.installMarkerKey)

        guard !hasInstallMarker else { return }
        defaults.set(true, forKey: Self.installMarkerKey)

        guard isFirebaseConfigured, Auth.auth().currentUser != nil else { return }

        do {
            try Auth.auth().signOut()
        } catch {
            lastErrorMessage = (error as NSError).localizedDescription
        }
    }

    var isSignedIn: Bool {
        guard isFirebaseConfigured else { return false }
        return Auth.auth().currentUser != nil
    }

    var signedInEmail: String? {
        guard isFirebaseConfigured else { return nil }
        return Auth.auth().currentUser?.email
    }

    func registerBackupUpdateHandler(_ handler: @escaping (Data) -> Void) {
        backupUpdateHandler = handler
    }

    func clearBackupUpdateHandler() {
        backupUpdateHandler = nil
    }

    func signIn(email: String, password: String) async {
        guard FirebaseApp.app() != nil else {
            lastErrorMessage = FirebaseSyncError.notConfigured.localizedDescription
            return
        }

        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedEmail.isEmpty, !password.isEmpty else {
            lastErrorMessage = "Email and password are required."
            return
        }

        isBusy = true
        defer { isBusy = false }

        do {
            _ = try await Auth.auth().signIn(withEmail: normalizedEmail, password: password)
            lastErrorMessage = nil
            startRealtimeListenerIfNeeded()
        } catch {
            lastErrorMessage = (error as NSError).localizedDescription
        }
    }

    func signUp(email: String, password: String) async {
        guard FirebaseApp.app() != nil else {
            lastErrorMessage = FirebaseSyncError.notConfigured.localizedDescription
            return
        }

        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedEmail.isEmpty, !password.isEmpty else {
            lastErrorMessage = "Email and password are required."
            return
        }

        isBusy = true
        defer { isBusy = false }

        do {
            _ = try await Auth.auth().createUser(withEmail: normalizedEmail, password: password)
            lastErrorMessage = nil
            startRealtimeListenerIfNeeded()
        } catch {
            lastErrorMessage = (error as NSError).localizedDescription
        }
    }

    func signInWithCredential(_ credential: AuthCredential) async {
        guard FirebaseApp.app() != nil else {
            lastErrorMessage = FirebaseSyncError.notConfigured.localizedDescription
            return
        }

        isBusy = true
        defer { isBusy = false }

        do {
            _ = try await Auth.auth().signIn(with: credential)
            lastErrorMessage = nil
            startRealtimeListenerIfNeeded()
        } catch {
            lastErrorMessage = (error as NSError).localizedDescription
        }
    }

    func signInAnonymously() async {
        guard FirebaseApp.app() != nil else {
            lastErrorMessage = FirebaseSyncError.notConfigured.localizedDescription
            return
        }

        isBusy = true
        defer { isBusy = false }

        do {
            _ = try await Auth.auth().signInAnonymously()
            lastErrorMessage = nil
            startRealtimeListenerIfNeeded()
        } catch {
            lastErrorMessage = (error as NSError).localizedDescription
        }
    }

    func sendPasswordReset(email: String) async {
        guard FirebaseApp.app() != nil else {
            lastErrorMessage = FirebaseSyncError.notConfigured.localizedDescription
            return
        }

        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedEmail.isEmpty else {
            lastErrorMessage = "Enter your email to reset password."
            return
        }

        isBusy = true
        defer { isBusy = false }

        do {
            try await Auth.auth().sendPasswordReset(withEmail: normalizedEmail)
            lastErrorMessage = "Password reset email sent."
        } catch {
            lastErrorMessage = (error as NSError).localizedDescription
        }
    }

    func signOut() {
        backupListener?.remove()
        backupListener = nil
        backupListenerTask?.cancel()
        backupListenerTask = nil

        guard isFirebaseConfigured else {
            lastErrorMessage = FirebaseSyncError.notConfigured.localizedDescription
            return
        }

        do {
            try Auth.auth().signOut()
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = (error as NSError).localizedDescription
        }
    }

    func uploadBackup(_ backupData: Data) async {
        guard FirebaseApp.app() != nil else {
            lastErrorMessage = FirebaseSyncError.notConfigured.localizedDescription
            return
        }

        guard let user = Auth.auth().currentUser else {
            lastErrorMessage = FirebaseSyncError.authFailed.localizedDescription
            return
        }

        isBusy = true
        defer { isBusy = false }

        do {
            let backupBase64 = backupData.base64EncodedString()
            let document = Firestore.firestore().collection("users").document(user.uid)
            let payload: [String: Any] = [
                "email": user.email ?? "",
                "backupBase64": backupBase64,
                "writerDeviceID": currentDeviceID,
                "updatedAt": FieldValue.serverTimestamp()
            ]
            try await document.setData(payload, merge: true)
            // Do not mark synced using local device time here.
            // Firestore writes can be queued offline; confirmed sync time is set
            // from server document data in listener/download flows.
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = (error as NSError).localizedDescription
        }
    }

    func uploadDelta(_ delta: ScheduleDelta) async throws {
        guard FirebaseApp.app() != nil else { throw FirebaseSyncError.notConfigured }
        guard let user = Auth.auth().currentUser else { throw FirebaseSyncError.authFailed }

        isBusy = true
        defer { isBusy = false }

        let document = Firestore.firestore()
            .collection("users")
            .document(user.uid)
            .collection("pendingDeltas")
            .document(delta.scheduleID)

        do {
            try await document.setData(delta.firestoreData(), merge: false)
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = error.localizedDescription
            throw FirebaseSyncError.firestoreFailed
        }
    }

    func fetchPendingDeltas() async throws -> [ScheduleDeltaDocument] {
        guard FirebaseApp.app() != nil else { throw FirebaseSyncError.notConfigured }
        guard let user = Auth.auth().currentUser else { throw FirebaseSyncError.authFailed }

        isBusy = true
        defer { isBusy = false }

        do {
            let snapshot = try await Firestore.firestore()
                .collection("users")
                .document(user.uid)
                .collection("pendingDeltas")
                .order(by: "serverUpdatedAt")
                .getDocuments()

            let deltas = snapshot.documents.compactMap { doc -> ScheduleDeltaDocument? in
                guard let delta = ScheduleDelta.fromSnapshot(doc) else { return nil }
                let serverUpdatedAt = (doc.data()["serverUpdatedAt"] as? Timestamp)?.dateValue()
                return ScheduleDeltaDocument(id: doc.documentID, delta: delta, serverUpdatedAt: serverUpdatedAt)
            }

            lastErrorMessage = nil
            return deltas
        } catch {
            lastErrorMessage = error.localizedDescription
            throw FirebaseSyncError.firestoreFailed
        }
    }

    func deleteConfirmedDeltas(_ ids: [String]) async throws {
        guard FirebaseApp.app() != nil else { throw FirebaseSyncError.notConfigured }
        guard let user = Auth.auth().currentUser else { throw FirebaseSyncError.authFailed }
        guard !ids.isEmpty else { return }

        isBusy = true
        defer { isBusy = false }

        let firestore = Firestore.firestore()
        let batch = firestore.batch()
        let collection = firestore.collection("users").document(user.uid).collection("pendingDeltas")

        ids.forEach { id in
            batch.deleteDocument(collection.document(id))
        }

        do {
            try await batch.commit()
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = error.localizedDescription
            throw FirebaseSyncError.firestoreFailed
        }
    }

    func uploadFullBackupWithVersion(_ backupData: Data, currentVersion: Int) async throws {
        guard FirebaseApp.app() != nil else { throw FirebaseSyncError.notConfigured }
        guard let user = Auth.auth().currentUser else { throw FirebaseSyncError.authFailed }

        isBusy = true
        defer { isBusy = false }

        let document = Firestore.firestore().collection("users").document(user.uid)

        do {
            let snapshot = try await document.getDocument(source: .server)
            let serverVersion = snapshot.data()?["globalSyncVersion"] as? Int ?? 0
            guard currentVersion >= serverVersion else {
                throw FirebaseSyncError.staleVersion
            }

            let payload: [String: Any] = [
                "email": user.email ?? "",
                "backupBase64": backupData.base64EncodedString(),
                "writerDeviceID": currentDeviceID,
                "globalSyncVersion": currentVersion,
                "updatedAt": FieldValue.serverTimestamp()
            ]
            try await document.setData(payload, merge: true)
            lastErrorMessage = nil
        } catch let syncError as FirebaseSyncError {
            lastErrorMessage = syncError.localizedDescription
            throw syncError
        } catch {
            lastErrorMessage = error.localizedDescription
            throw FirebaseSyncError.firestoreFailed
        }
    }

    func downloadBackup() async -> CloudBackupDownload? {
        guard FirebaseApp.app() != nil else {
            lastErrorMessage = FirebaseSyncError.notConfigured.localizedDescription
            return nil
        }

        guard let user = Auth.auth().currentUser else {
            lastErrorMessage = FirebaseSyncError.authFailed.localizedDescription
            return nil
        }

        isBusy = true
        defer { isBusy = false }

        let document = Firestore.firestore().collection("users").document(user.uid)

        do {
            let serverSnapshot = try await document.getDocument(source: .server)
            if let backup = backupData(from: serverSnapshot) {
                if let updatedAt = serverSnapshot.data()?["updatedAt"] as? Timestamp {
                    lastSyncedAt = updatedAt.dateValue()
                }
                lastErrorMessage = nil
                return backup
            }
            throw FirebaseSyncError.missingBackup
        } catch {
            do {
                let cacheSnapshot = try await document.getDocument(source: .cache)
                if let backup = backupData(from: cacheSnapshot) {
                    if let updatedAt = cacheSnapshot.data()?["updatedAt"] as? Timestamp {
                        lastSyncedAt = updatedAt.dateValue()
                    }
                    lastErrorMessage = nil
                    return backup
                }
                throw FirebaseSyncError.missingBackup
            } catch {
                lastErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                return nil
            }
        }
    }

    private func startRealtimeListenerIfNeeded() {
        backupListener?.remove()
        backupListener = nil
        backupListenerTask?.cancel()
        backupListenerTask = nil

        guard isFirebaseConfigured else { return }

        guard let user = Auth.auth().currentUser else { return }

        let document = Firestore.firestore().collection("users").document(user.uid)
        backupListener = document.addSnapshotListener(includeMetadataChanges: true) { [weak self] snapshot, error in
            guard let self else { return }
            if let error {
                Task { @MainActor in
                    self.lastErrorMessage = error.localizedDescription
                }
                return
            }

            guard let snapshot else { return }
            guard !snapshot.metadata.hasPendingWrites, !snapshot.metadata.isFromCache else {
                return
            }
            let data = snapshot.data() ?? [:]

            if let writerDeviceID = data["writerDeviceID"] as? String,
               writerDeviceID == self.currentDeviceID {
                return
            }

            guard let backupBase64 = data["backupBase64"] as? String,
                  let backupData = Data(base64Encoded: backupBase64)
            else {
                return
            }

            Task { @MainActor in
                if let updatedAt = data["updatedAt"] as? Timestamp {
                    self.lastSyncedAt = updatedAt.dateValue()
                }
                self.backupUpdateHandler?(backupData)
            }
        }
    }

    private func backupData(from snapshot: DocumentSnapshot) -> CloudBackupDownload? {
        guard let backupBase64 = snapshot.data()?["backupBase64"] as? String,
              !backupBase64.isEmpty,
              let data = Data(base64Encoded: backupBase64)
        else {
            return nil
        }
        let globalSyncVersion = snapshot.data()?["globalSyncVersion"] as? Int
        return CloudBackupDownload(data: data, globalSyncVersion: globalSyncVersion)
    }
}
