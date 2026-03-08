import Foundation
import Network
import FirebaseAuth
import FirebaseCore
import FirebaseFirestore
#if canImport(FirebaseStorage)
import FirebaseStorage
#endif

enum NetworkCondition {
    case offline
    case constrained
    case expensive
    case optimal
}

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

enum ProfileMetadataError: LocalizedError {
    case storageUploadFailed
    case invalidPhotoURL

    var errorDescription: String? {
        switch self {
        case .storageUploadFailed:
            return "Profile photo upload failed."
        case .invalidPhotoURL:
            return "Uploaded profile photo URL is invalid."
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

enum BackupDownloadResult {
    case success(CloudBackupDownload)
    case missingBackup
    case notConfigured
    case authFailed
    case networkError(String)
    case decodeFailed(String)
    case cacheFallback(CloudBackupDownload)

    var backup: CloudBackupDownload? {
        switch self {
        case .success(let b), .cacheFallback(let b): return b
        default: return nil
        }
    }

    var userMessage: String {
        switch self {
        case .success: return "Cloud backup downloaded."
        case .missingBackup: return "No cloud backup found for this account."
        case .notConfigured: return "Firebase is not configured."
        case .authFailed: return "Not signed in."
        case .networkError(let detail): return "Network error: \(detail)"
        case .decodeFailed(let detail): return "Cloud data is unreadable: \(detail)"
        case .cacheFallback: return "Using cached backup (server unreachable)."
        }
    }
}

@MainActor
@Observable
final class FirebaseSyncService {
    static let shared = FirebaseSyncService()
    private static let installMarkerKey = "schedulr.install.marker.v1"
    private static let deviceIDStorageKey = "scheduleDeviceID.v1"
    private static let firestoreDatabaseInfoKey = "FIRESTORE_DATABASE_ID"
    private static let legacyFirestoreDatabaseInfoKey = "FirestoreDatabaseID"
    private static let inlineBackupByteLimit = 700_000

    private static let iso8601WithFractionalSecondsFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let iso8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    var isBusy = false
    var lastErrorMessage: String?
    var lastSyncedAt: Date?
    var isNetworkReachable = false
    var isOnWiFi = false
    var isNetworkConstrained = false
    var isNetworkExpensive = false
    var networkCondition: NetworkCondition = .offline
    var profileDisplayName: String?
    var profilePhotoData: Data?

    private var configuredFirestoreDatabaseID: String? {
        let primary = Bundle.main.object(forInfoDictionaryKey: Self.firestoreDatabaseInfoKey) as? String
        let legacy = Bundle.main.object(forInfoDictionaryKey: Self.legacyFirestoreDatabaseInfoKey) as? String
        let raw = (primary ?? legacy)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !raw.isEmpty else { return nil }
        if raw == "(default)" || raw.caseInsensitiveCompare("default") == .orderedSame {
            return nil
        }
        return raw
    }

    // Defaults to Firestore "(default)" unless FIRESTORE_DATABASE_ID is configured in Info.plist.
    private var firestore: Firestore {
        guard let app = FirebaseApp.app() else { return Firestore.firestore() }
        if let configuredFirestoreDatabaseID {
            return Firestore.firestore(app: app, database: configuredFirestoreDatabaseID)
        }
        return Firestore.firestore(app: app)
    }

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
            Task { @MainActor [weak self] in
                self?.applyNetworkPath(path)
            }
        }
        networkMonitor.start(queue: networkMonitorQueue)

        let initialPath = networkMonitor.currentPath
        Task { @MainActor [weak self] in
            self?.applyNetworkPath(initialPath)
        }
    }

    private func applyNetworkPath(_ path: NWPath) {
        let isReachable = path.status == .satisfied
        let onWiFi = path.usesInterfaceType(.wifi) || path.usesInterfaceType(.wiredEthernet)
        let constrained = path.isConstrained
        let expensive = path.isExpensive

        isNetworkReachable = isReachable
        isOnWiFi = isReachable && onWiFi
        isNetworkConstrained = constrained
        isNetworkExpensive = expensive

        if !isReachable {
            networkCondition = .offline
        } else if constrained {
            networkCondition = .constrained
        } else if expensive {
            networkCondition = .expensive
        } else {
            networkCondition = .optimal
        }
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

    private func fallbackDisplayName(from email: String?) -> String {
        guard let email,
              let localPart = email.split(separator: "@").first,
              !localPart.isEmpty
        else {
            return "User"
        }

        return localPart
            .replacingOccurrences(of: ".", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }
            .joined(separator: " ")
    }

    private func resolvedDisplayName(for user: User) -> String {
        let authDisplayName = user.displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let authDisplayName, !authDisplayName.isEmpty {
            return authDisplayName
        }
        return fallbackDisplayName(from: user.email)
    }

    private func authProfilePhotoData(for user: User) async -> Data? {
        guard var photoURL = user.photoURL else { return nil }

        // Ask Google-hosted avatars for a predictable, high-quality size.
        if photoURL.host?.contains("googleusercontent.com") == true {
            if var components = URLComponents(url: photoURL, resolvingAgainstBaseURL: false) {
                var queryItems = components.queryItems ?? []
                queryItems.removeAll { $0.name == "sz" }
                queryItems.append(URLQueryItem(name: "sz", value: "256"))
                components.queryItems = queryItems
                if let sizedURL = components.url {
                    photoURL = sizedURL
                }
            }
        }

        do {
            let (data, response) = try await URLSession.shared.data(from: photoURL)
            guard let http = response as? HTTPURLResponse,
                  (200...299).contains(http.statusCode),
                  !data.isEmpty
            else {
                return nil
            }
            return data
        } catch {
            return nil
        }
    }

    private func remoteProfilePhotoData(from url: URL) async -> Data? {
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse,
                  (200...299).contains(http.statusCode),
                  !data.isEmpty
            else {
                return nil
            }
            return data
        } catch {
            return nil
        }
    }

    private func uploadProfilePhoto(userID: String, photoData: Data) async throws -> URL {
#if canImport(FirebaseStorage)
        let storagePath = "users/\(userID)/profile_image.jpg"
        let storageRef = Storage.storage().reference().child(storagePath)
        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"

        _ = try await storageRef.putDataAsync(photoData, metadata: metadata)
        let downloadURL = try await storageRef.downloadURL()
        guard !downloadURL.absoluteString.isEmpty else {
            throw ProfileMetadataError.invalidPhotoURL
        }
        return downloadURL
#else
        _ = userID
        _ = photoData
        throw ProfileMetadataError.storageUploadFailed
#endif
    }

    private func applyProfileFields(from data: [String: Any], fallbackEmail: String?) {
        let cloudDisplayName = (data["profileDisplayName"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let authDisplayName = Auth.auth().currentUser?.displayName?.trimmingCharacters(in: .whitespacesAndNewlines)

        if let cloudDisplayName, !cloudDisplayName.isEmpty {
            profileDisplayName = cloudDisplayName
        } else if let authDisplayName, !authDisplayName.isEmpty {
            profileDisplayName = authDisplayName
        } else {
            profileDisplayName = fallbackDisplayName(from: fallbackEmail)
        }

        if let photoURLString = (data["profilePhotoURL"] as? String) ?? (data["photoURL"] as? String),
           let photoURL = URL(string: photoURLString)
        {
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let downloaded = await self.remoteProfilePhotoData(from: photoURL) {
                    self.profilePhotoData = downloaded
                }
            }
            return
        }

        if let base64 = data["profilePhotoBase64"] as? String,
           let decoded = Data(base64Encoded: base64)
        {
            profilePhotoData = decoded
        }
    }

    private func persistProfileDocument(userID: String, payload: [String: Any]) async throws {
        let profileDocument = firestore
            .collection("users")
            .document(userID)
            .collection("profile")
            .document("current")
        try await profileDocument.setData(payload, merge: true)
    }

    func refreshProfileMetadata() async {
        guard FirebaseApp.app() != nil else { return }
        guard let user = Auth.auth().currentUser else {
            profileDisplayName = nil
            profilePhotoData = nil
            return
        }

        let userDocument = firestore.collection("users").document(user.uid)
        let profileDocument = userDocument.collection("profile").document("current")

        do {
            let profileSnapshot = try await profileDocument.getDocument(source: .server)
            if let profileData = profileSnapshot.data(), !profileData.isEmpty {
                applyProfileFields(from: profileData, fallbackEmail: user.email)
                if profilePhotoData == nil, let authPhoto = await authProfilePhotoData(for: user) {
                    profilePhotoData = authPhoto
                }
                return
            }

            let userSnapshot = try await userDocument.getDocument(source: .server)
            applyProfileFields(from: userSnapshot.data() ?? [:], fallbackEmail: user.email)
            if profilePhotoData == nil, let authPhoto = await authProfilePhotoData(for: user) {
                profilePhotoData = authPhoto
            }
            return
        } catch {
            do {
                let cachedProfile = try await profileDocument.getDocument(source: .cache)
                if let profileData = cachedProfile.data(), !profileData.isEmpty {
                    applyProfileFields(from: profileData, fallbackEmail: user.email)
                    if profilePhotoData == nil, let authPhoto = await authProfilePhotoData(for: user) {
                        profilePhotoData = authPhoto
                    }
                    return
                }

                let cachedUser = try await userDocument.getDocument(source: .cache)
                applyProfileFields(from: cachedUser.data() ?? [:], fallbackEmail: user.email)
                if profilePhotoData == nil, let authPhoto = await authProfilePhotoData(for: user) {
                    profilePhotoData = authPhoto
                }
            } catch {
                profileDisplayName = resolvedDisplayName(for: user)
                profilePhotoData = await authProfilePhotoData(for: user)
            }
        }
    }

    func updateProfileMetadata(displayName: String? = nil, photoData: Data? = nil) async {
        guard FirebaseApp.app() != nil else {
            lastErrorMessage = FirebaseSyncError.notConfigured.localizedDescription
            return
        }

        guard let user = Auth.auth().currentUser else {
            lastErrorMessage = FirebaseSyncError.authFailed.localizedDescription
            return
        }

        var payload: [String: Any] = [
            "email": user.email ?? "",
            "writerDeviceID": currentDeviceID,
            "updatedAt": FieldValue.serverTimestamp()
        ]

        if let displayName {
            let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                payload["profileDisplayName"] = trimmed
            }
        }

        do {
            var uploadedPhotoURL: URL?
            if let photoData {
                uploadedPhotoURL = try await uploadProfilePhoto(userID: user.uid, photoData: photoData)
                guard let uploadedPhotoURL else { throw ProfileMetadataError.storageUploadFailed }
                payload["profilePhotoURL"] = uploadedPhotoURL.absoluteString
                payload["photoURL"] = uploadedPhotoURL.absoluteString
                // Clear oversized legacy payload when URL-backed photo storage is active.
                payload["profilePhotoBase64"] = FieldValue.delete()
            }

            let userDocument = firestore.collection("users").document(user.uid)
            let profileDocument = userDocument.collection("profile").document("current")
            let batch = firestore.batch()
            batch.setData(payload, forDocument: userDocument, merge: true)
            batch.setData(payload, forDocument: profileDocument, merge: true)
            try await batch.commit()

            let hasDisplayNameChange = displayName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            if hasDisplayNameChange || uploadedPhotoURL != nil {
                let request = user.createProfileChangeRequest()
                if let displayName,
                   !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                {
                    request.displayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
                }
                if let uploadedPhotoURL {
                    request.photoURL = uploadedPhotoURL
                }
                try await request.commitChanges()
            }

            if let displayName,
               !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            {
                profileDisplayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if let photoData {
                profilePhotoData = photoData
            }

            lastErrorMessage = nil
        } catch {
            lastErrorMessage = (error as NSError).localizedDescription
        }
    }

    func ensureProfileSeededFromEmailIfNeeded() async {
        guard FirebaseApp.app() != nil else { return }
        guard let user = Auth.auth().currentUser else { return }

        let seededName = resolvedDisplayName(for: user)

        if user.displayName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
            let request = user.createProfileChangeRequest()
            request.displayName = seededName
            try? await request.commitChanges()
        }

        do {
            let document = firestore.collection("users").document(user.uid)
            let snapshot = try? await document.getDocument(source: .server)
            let profileSnapshot = try? await document.collection("profile").document("current").getDocument(source: .server)
            let existingName = ((profileSnapshot?.data()?["profileDisplayName"] as? String)
                ?? (snapshot?.data()?["profileDisplayName"] as? String))?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let existingPhotoBase64 = ((profileSnapshot?.data()?["profilePhotoBase64"] as? String)
                ?? (snapshot?.data()?["profilePhotoBase64"] as? String))?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let existingPhotoURL = ((profileSnapshot?.data()?["profilePhotoURL"] as? String)
                ?? (snapshot?.data()?["profilePhotoURL"] as? String)
                ?? (profileSnapshot?.data()?["photoURL"] as? String)
                ?? (snapshot?.data()?["photoURL"] as? String))?
                .trimmingCharacters(in: .whitespacesAndNewlines)

            let needsNameSeed = existingName?.isEmpty != false
            let needsPhotoSeed = (existingPhotoURL?.isEmpty != false) && (existingPhotoBase64?.isEmpty != false)

            if needsNameSeed || needsPhotoSeed {
                var payload: [String: Any] = [
                    "email": user.email ?? "",
                    "writerDeviceID": currentDeviceID,
                    "updatedAt": FieldValue.serverTimestamp()
                ]

                if needsNameSeed {
                    payload["profileDisplayName"] = seededName
                }

                if needsPhotoSeed, let authPhoto = await authProfilePhotoData(for: user) {
                    if let uploadedURL = try? await uploadProfilePhoto(userID: user.uid, photoData: authPhoto) {
                        payload["profilePhotoURL"] = uploadedURL.absoluteString
                        payload["photoURL"] = uploadedURL.absoluteString
                        payload["profilePhotoBase64"] = FieldValue.delete()
                    } else {
                        payload["profilePhotoBase64"] = authPhoto.base64EncodedString()
                    }
                    profilePhotoData = authPhoto
                }

                try await document.setData(payload, merge: true)
                try await persistProfileDocument(userID: user.uid, payload: payload)
            }

            await refreshProfileMetadata()
        } catch {
            // Keep local fallback name even if cloud write is deferred or fails.
            profileDisplayName = seededName
            if profilePhotoData == nil {
                profilePhotoData = await authProfilePhotoData(for: user)
            }
        }
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
            await ensureProfileSeededFromEmailIfNeeded()
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
            await ensureProfileSeededFromEmailIfNeeded()
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
            await ensureProfileSeededFromEmailIfNeeded()
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
            await ensureProfileSeededFromEmailIfNeeded()
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
            profileDisplayName = nil
            profilePhotoData = nil
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
            let document = firestore.collection("users").document(user.uid)
            try await persistStructuredBackupData(
                from: backupData,
                userDocument: document,
                globalSyncVersion: nil
            )
            let payload = makeUserBackupPayload(
                email: user.email,
                backupData: backupData,
                globalSyncVersion: nil
            )
            try await document.setData(payload, merge: true)
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

        let document = firestore
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
            let snapshot = try await firestore
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

        let document = firestore.collection("users").document(user.uid)

        do {
            let serverVersion: Int
            if let serverSnapshot = try? await document.getDocument(source: .server) {
                serverVersion = serverSnapshot.data()?["globalSyncVersion"] as? Int ?? 0
            } else if let cacheSnapshot = try? await document.getDocument(source: .cache) {
                serverVersion = cacheSnapshot.data()?["globalSyncVersion"] as? Int ?? 0
            } else {
                serverVersion = 0
            }

            guard currentVersion >= serverVersion else {
                throw FirebaseSyncError.staleVersion
            }

            let needsStructured = backupData.count > Self.inlineBackupByteLimit
            if needsStructured {
                try await persistStructuredBackupData(
                    from: backupData,
                    userDocument: document,
                    globalSyncVersion: currentVersion
                )
            }
            let payload = makeUserBackupPayload(
                email: user.email,
                backupData: backupData,
                globalSyncVersion: currentVersion
            )
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
        let result = await downloadBackupWithResult()
        return result.backup
    }

    func downloadBackupWithResult() async -> BackupDownloadResult {
        guard FirebaseApp.app() != nil else {
            lastErrorMessage = FirebaseSyncError.notConfigured.localizedDescription
            return .notConfigured
        }

        guard let user = Auth.auth().currentUser else {
            lastErrorMessage = FirebaseSyncError.authFailed.localizedDescription
            return .authFailed
        }

        isBusy = true
        defer { isBusy = false }

        let document = firestore.collection("users").document(user.uid)

        do {
            let serverSnapshot = try await document.getDocument(source: .server)
            if let backup = backupData(from: serverSnapshot) {
                if let updatedAt = serverSnapshot.data()?["updatedAt"] as? Timestamp {
                    lastSyncedAt = updatedAt.dateValue()
                }
                lastErrorMessage = nil
                return .success(backup)
            }

            if let structuredBackup = await structuredBackupData(
                userID: user.uid,
                source: .server,
                globalSyncVersion: serverSnapshot.data()?["globalSyncVersion"] as? Int
            ) {
                if let updatedAt = serverSnapshot.data()?["updatedAt"] as? Timestamp {
                    lastSyncedAt = updatedAt.dateValue()
                }
                lastErrorMessage = nil
                return .success(structuredBackup)
            }

            lastErrorMessage = FirebaseSyncError.missingBackup.localizedDescription
            return .missingBackup
        } catch {
            // Server unavailable — fall back to cache.
            do {
                let cacheSnapshot = try await document.getDocument(source: .cache)
                if let backup = backupData(from: cacheSnapshot) {
                    if let updatedAt = cacheSnapshot.data()?["updatedAt"] as? Timestamp {
                        lastSyncedAt = updatedAt.dateValue()
                    }
                    lastErrorMessage = nil
                    return .cacheFallback(backup)
                }

                if let structuredBackup = await structuredBackupData(
                    userID: user.uid,
                    source: .cache,
                    globalSyncVersion: cacheSnapshot.data()?["globalSyncVersion"] as? Int
                ) {
                    if let updatedAt = cacheSnapshot.data()?["updatedAt"] as? Timestamp {
                        lastSyncedAt = updatedAt.dateValue()
                    }
                    lastErrorMessage = nil
                    return .cacheFallback(structuredBackup)
                }

                lastErrorMessage = FirebaseSyncError.missingBackup.localizedDescription
                return .missingBackup
            } catch {
                let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                lastErrorMessage = message
                return .networkError(message)
            }
        }
    }

    private func makeUserBackupPayload(
        email: String?,
        backupData: Data,
        globalSyncVersion: Int?
    ) -> [String: Any] {
        var payload: [String: Any] = [
            "email": email ?? "",
            "writerDeviceID": currentDeviceID,
            "updatedAt": FieldValue.serverTimestamp(),
            "backupSizeBytes": backupData.count
        ]

        if let globalSyncVersion {
            payload["globalSyncVersion"] = globalSyncVersion
        }

        if backupData.count <= Self.inlineBackupByteLimit {
            payload["backupBase64"] = backupData.base64EncodedString()
            payload["backupStorageMode"] = "inline"
        } else {
            // Avoid Firestore's 1MB single-document limit by storing normalized docs.
            payload["backupBase64"] = FieldValue.delete()
            payload["backupStorageMode"] = "structured"
        }

        return payload
    }

    private func persistStructuredBackupData(
        from backupData: Data,
        userDocument: DocumentReference,
        globalSyncVersion: Int?
    ) async throws {
        guard let backupRoot = (try? JSONSerialization.jsonObject(with: backupData)) as? [String: Any] else {
            return
        }

        try await persistSettingsDocument(
            fromBackupRoot: backupRoot,
            userDocument: userDocument,
            globalSyncVersion: globalSyncVersion
        )
        try await persistSchedulesCollection(fromBackupRoot: backupRoot, userDocument: userDocument)
    }

    private func persistSettingsDocument(
        fromBackupRoot backupRoot: [String: Any],
        userDocument: DocumentReference,
        globalSyncVersion: Int?
    ) async throws {
        var settingsData = backupRoot["appSettings"] as? [String: Any] ?? [:]
        let calendarNames = (backupRoot["calendarNames"] as? [Any])?.compactMap { $0 as? String } ?? []
        let resolvedGlobalVersion = globalSyncVersion ?? (backupRoot["globalSyncVersion"] as? Int)

        guard !settingsData.isEmpty || !calendarNames.isEmpty || resolvedGlobalVersion != nil else {
            return
        }

        convertDateField(in: &settingsData, key: "settingsUpdatedAt")
        if !calendarNames.isEmpty {
            settingsData["calendarNames"] = calendarNames
        }
        if let version = resolvedGlobalVersion {
            settingsData["globalSyncVersion"] = version
        }
        settingsData["writerDeviceID"] = currentDeviceID
        settingsData["updatedAt"] = FieldValue.serverTimestamp()

        try await userDocument
            .collection("settings")
            .document("current")
            .setData(settingsData, merge: true)
    }

    private func persistSchedulesCollection(
        fromBackupRoot backupRoot: [String: Any],
        userDocument: DocumentReference
    ) async throws {
        let scheduleCollection = userDocument.collection("schedules")
        guard let rawSchedules = backupRoot["schedules"] as? [Any] else { return }

        let existingSnapshot = try await scheduleCollection.getDocuments()
        var incomingIDs: Set<String> = []
        var normalizedSchedules: [(id: String, data: [String: Any])] = []

        for rawSchedule in rawSchedules {
            guard var schedule = rawSchedule as? [String: Any],
                  let scheduleID = (schedule["id"] as? String)?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                  !scheduleID.isEmpty
            else {
                continue
            }

            incomingIDs.insert(scheduleID)
            schedule.removeValue(forKey: "id")
            normalizeScheduleDateFields(in: &schedule)
            schedule["scheduleID"] = scheduleID
            schedule["writerDeviceID"] = currentDeviceID
            schedule["updatedAt"] = FieldValue.serverTimestamp()
            normalizedSchedules.append((id: scheduleID, data: schedule))
        }

        let staleIDs = Set(existingSnapshot.documents.map(\.documentID)).subtracting(incomingIDs)
        var batch = firestore.batch()
        var operationCount = 0

        func commitBatchIfNeeded(force: Bool = false) async throws {
            guard operationCount > 0 else { return }
            if !force, operationCount < 450 { return }
            try await batch.commit()
            batch = firestore.batch()
            operationCount = 0
        }

        for schedule in normalizedSchedules {
            batch.setData(schedule.data, forDocument: scheduleCollection.document(schedule.id), merge: true)
            operationCount += 1
            try await commitBatchIfNeeded()
        }

        for staleID in staleIDs {
            batch.deleteDocument(scheduleCollection.document(staleID))
            operationCount += 1
            try await commitBatchIfNeeded()
        }

        try await commitBatchIfNeeded(force: true)
    }

    private func normalizeScheduleDateFields(in schedule: inout [String: Any]) {
        let scalarDateKeys = ["createdAt", "updatedAt", "deletedAt", "scheduledDate", "repeatEndDate"]
        scalarDateKeys.forEach { key in
            convertDateField(in: &schedule, key: key)
        }

        convertDateArrayField(in: &schedule, key: "excludedOccurrenceDates")
    }

    private func convertDateField(in dictionary: inout [String: Any], key: String) {
        guard let value = dictionary[key] else { return }
        if value is NSNull { return }
        if let timestamp = timestampValue(from: value) {
            dictionary[key] = timestamp
        }
    }

    private func convertDateArrayField(in dictionary: inout [String: Any], key: String) {
        guard let values = dictionary[key] as? [Any] else { return }
        let timestamps = values.compactMap { value -> Timestamp? in
            if value is NSNull { return nil }
            return timestampValue(from: value)
        }
        dictionary[key] = timestamps
    }

    private func timestampValue(from value: Any) -> Timestamp? {
        if let timestamp = value as? Timestamp {
            return timestamp
        }
        if let date = value as? Date {
            return Timestamp(date: date)
        }
        if let text = value as? String,
           let date = Self.iso8601WithFractionalSecondsFormatter.date(from: text)
            ?? Self.iso8601Formatter.date(from: text)
        {
            return Timestamp(date: date)
        }
        return nil
    }

    private func structuredBackupData(
        userID: String,
        source: FirestoreSource,
        globalSyncVersion: Int?
    ) async -> CloudBackupDownload? {
        let userDocument = firestore.collection("users").document(userID)

        do {
            let settingsSnapshot = try await userDocument
                .collection("settings")
                .document("current")
                .getDocument(source: source)
            let schedulesSnapshot = try await userDocument
                .collection("schedules")
                .getDocuments(source: source)

            let schedulePayload = schedulesSnapshot.documents.map { scheduleDocumentJSON(from: $0) }
            let settingsData = settingsSnapshot.data() ?? [:]

            var appSettings: [String: Any] = [:]
            var calendarNames: [String] = []
            for (key, value) in settingsData {
                if key == "calendarNames" {
                    calendarNames = (value as? [Any])?.compactMap { $0 as? String } ?? []
                    continue
                }
                if key == "writerDeviceID" || key == "updatedAt" || key == "globalSyncVersion" {
                    continue
                }
                if let jsonValue = jsonCompatibleValue(from: value) {
                    appSettings[key] = jsonValue
                }
            }

            let resolvedGlobalVersion = globalSyncVersion ?? (settingsData["globalSyncVersion"] as? Int)

            guard !schedulePayload.isEmpty || !appSettings.isEmpty || !calendarNames.isEmpty else {
                return nil
            }

            var payload: [String: Any] = [
                "version": 2,
                "exportedAt": Self.iso8601WithFractionalSecondsFormatter.string(from: Date()),
                "schedules": schedulePayload
            ]

            if !appSettings.isEmpty {
                payload["appSettings"] = appSettings
            }
            if !calendarNames.isEmpty {
                payload["calendarNames"] = calendarNames
            }
            if let resolvedGlobalVersion {
                payload["globalSyncVersion"] = resolvedGlobalVersion
            }

            guard JSONSerialization.isValidJSONObject(payload),
                  let encoded = try? JSONSerialization.data(withJSONObject: payload, options: [])
            else {
                return nil
            }

            return CloudBackupDownload(data: encoded, globalSyncVersion: resolvedGlobalVersion)
        } catch {
            return nil
        }
    }

    private func scheduleDocumentJSON(from document: QueryDocumentSnapshot) -> [String: Any] {
        var json: [String: Any] = ["id": document.documentID]
        for (key, value) in document.data() {
            if key == "scheduleID"
                || key == "writerDeviceID"
                || key == "updatedAt"
                || key == "serverUpdatedAt"
                || key == "clientUpdatedAt"
                || key == "deviceID"
            {
                continue
            }
            if let normalized = jsonCompatibleValue(from: value) {
                json[key] = normalized
            } else {
                json[key] = NSNull()
            }
        }
        return json
    }

    private func jsonCompatibleValue(from value: Any) -> Any? {
        switch value {
        case let timestamp as Timestamp:
            return Self.iso8601WithFractionalSecondsFormatter.string(from: timestamp.dateValue())
        case let date as Date:
            return Self.iso8601WithFractionalSecondsFormatter.string(from: date)
        case let string as String:
            return string
        case let bool as Bool:
            return bool
        case let int as Int:
            return int
        case let double as Double:
            return double.isFinite ? double : nil
        case let number as NSNumber:
            return number
        case let array as [Any]:
            return array.map { element -> Any in
                if element is NSNull { return NSNull() }
                return jsonCompatibleValue(from: element) ?? NSNull()
            }
        case let dictionary as [String: Any]:
            var normalized: [String: Any] = [:]
            for (key, nestedValue) in dictionary {
                if nestedValue is NSNull {
                    normalized[key] = NSNull()
                } else if let mapped = jsonCompatibleValue(from: nestedValue) {
                    normalized[key] = mapped
                }
            }
            return normalized
        case is NSNull:
            return NSNull()
        default:
            return nil
        }
    }

    private func startRealtimeListenerIfNeeded() {
        backupListener?.remove()
        backupListener = nil
        backupListenerTask?.cancel()
        backupListenerTask = nil

        guard isFirebaseConfigured else { return }

        guard let user = Auth.auth().currentUser else { return }

        let userID = user.uid
        let document = firestore.collection("users").document(userID)
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

            Task { @MainActor in
                self.applyProfileFields(from: data, fallbackEmail: Auth.auth().currentUser?.email)
            }

            if let writerDeviceID = data["writerDeviceID"] as? String,
               writerDeviceID == self.currentDeviceID {
                return
            }

            Task { @MainActor in
                if let updatedAt = data["updatedAt"] as? Timestamp {
                    self.lastSyncedAt = updatedAt.dateValue()
                }

                if let inlineBackup = self.backupData(from: snapshot) {
                    self.backupUpdateHandler?(inlineBackup.data)
                    return
                }

                if let structuredBackup = await self.structuredBackupData(
                    userID: userID,
                    source: .server,
                    globalSyncVersion: data["globalSyncVersion"] as? Int
                ) {
                    self.backupUpdateHandler?(structuredBackup.data)
                }
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
