import Foundation
import OSLog

struct RestoreResult {
    var restoredCount: Int = 0
    var skippedCount: Int = 0
    var mergedCount: Int = 0
    var conflictCount: Int = 0
    var settingsApplied: Bool = false
    var failure: RestoreFailure?
    var warnings: [String] = []

    var succeeded: Bool { failure == nil }

    var userMessage: String {
        if let failure {
            return failure.userMessage
        }
        if restoredCount == 0 && mergedCount == 0 && skippedCount == 0 && !settingsApplied {
            return "Cloud data restored (no changes)."
        }
        var parts: [String] = []
        if restoredCount > 0 { parts.append("\(restoredCount) added") }
        if mergedCount > 0 { parts.append("\(mergedCount) merged") }
        if skippedCount > 0 { parts.append("\(skippedCount) unchanged") }
        if conflictCount > 0 { parts.append("\(conflictCount) conflicts") }
        if settingsApplied { parts.append("settings updated") }
        return "Restored: " + parts.joined(separator: ", ") + "."
    }

    enum RestoreFailure {
        case noModelContext
        case decodeFailed
        case emptyPayload

        var userMessage: String {
            switch self {
            case .noModelContext: return "Restore failed: database unavailable."
            case .decodeFailed: return "Restore failed: cloud data is corrupted or unreadable."
            case .emptyPayload: return "Restore failed: backup is empty."
            }
        }
    }
}

struct SyncRunReport {
    var deltaPushSucceeded: Bool = true
    var deltaPullSucceeded: Bool = true
    var backupUploadSucceeded: Bool = false
    var offlineQueueChanged: Bool = false
    var conflictsRemaining: Int = 0
    var deltaPushCount: Int = 0
    var deltaPullCount: Int = 0
    var failure: SyncFailure?
    var warnings: [String] = []

    var succeeded: Bool { failure == nil && deltaPushSucceeded && deltaPullSucceeded && backupUploadSucceeded }

    var userMessage: String {
        if let failure {
            return failure.userMessage
        }
        var parts: [String] = []
        if deltaPushCount > 0 { parts.append("\(deltaPushCount) pushed") }
        if deltaPullCount > 0 { parts.append("\(deltaPullCount) pulled") }
        if conflictsRemaining > 0 { parts.append("\(conflictsRemaining) conflicts") }
        if !backupUploadSucceeded { parts.append("backup upload failed") }
        if parts.isEmpty { return "Sync complete." }
        return "Sync: " + parts.joined(separator: ", ") + "."
    }

    enum SyncFailure {
        case notSignedIn
        case networkUnavailable
        case staleVersion
        case firestoreFailed(String)
        case bothFailed

        var userMessage: String {
            switch self {
            case .notSignedIn: return "Not signed in."
            case .networkUnavailable: return "No internet connection."
            case .staleVersion: return "Cloud has a newer version. Pull latest changes first."
            case .firestoreFailed(let detail): return "Sync failed: \(detail)"
            case .bothFailed: return "Sync failed: both delta and backup paths failed."
            }
        }
    }
}

@MainActor
@Observable
final class SyncCoordinator {
    static let shared = SyncCoordinator()
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.bittu.Schedulr",
        category: "sync"
    )

    enum SyncState: Equatable {
        case idle
        case syncing
        case conflict
        case error
    }

    struct ConflictRecord: Identifiable {
        let id = UUID()
        let scheduleID: UUID
        let local: ScheduleDelta
        let remote: ScheduleDelta
    }

    private static let uploadQueueKey = "sync.uploadQueue.v1"

    private enum SyncOperationTimeout: LocalizedError {
        case timedOut(operation: String, seconds: Double)

        var errorDescription: String? {
            switch self {
            case .timedOut(let operation, let seconds):
                return "\(operation) timed out after \(Int(seconds))s"
            }
        }
    }

    var syncState: SyncState = .idle
    var pendingConflicts: [ConflictRecord] = []
    var pendingConflictScheduleIDs: [UUID] { pendingConflicts.map(\.scheduleID) }
    var lastSyncReport: SyncRunReport?
    var syncProgress: Double = 0
    var syncLastActivityMessage: String?

    private var attachedViewModel: ScheduleViewModel?

    private func runWithTimeout<T>(
        seconds: Double,
        operation: String,
        work: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await work()
            }
            group.addTask {
                try await Task.sleep(for: .seconds(seconds))
                throw SyncOperationTimeout.timedOut(operation: operation, seconds: seconds)
            }

            guard let result = try await group.next() else {
                throw SyncOperationTimeout.timedOut(operation: operation, seconds: seconds)
            }
            group.cancelAll()
            return result
        }
    }

    func pushChanges(dirtySchedules: [ScheduleDelta], viewModel: ScheduleViewModel) async -> Int {
        attachedViewModel = viewModel
        guard !dirtySchedules.isEmpty else { return 0 }
        var pushedCount = 0

        for delta in dirtySchedules {
            var succeeded = false
            var attempt = 0

            while attempt < 3, !succeeded {
                do {
                    try await runWithTimeout(seconds: 12, operation: "Delta upload") {
                        try await FirebaseSyncService.shared.uploadDelta(delta)
                    }
                    if let scheduleID = UUID(uuidString: delta.scheduleID) {
                        viewModel.markClean(scheduleID: scheduleID, syncedVersion: delta.syncVersion)
                    }
                    succeeded = true
                    pushedCount += 1
                    let target = (Double(pushedCount) / Double(dirtySchedules.count)) * 0.55
                    await advanceProgressSmoothly(to: target)
                } catch {
                    attempt += 1
                    logger.warning("Delta upload retry \(attempt, privacy: .public)/3 for \(delta.scheduleID, privacy: .public): \(error.localizedDescription, privacy: .public)")
                    if attempt >= 3 {
                        if let scheduleID = UUID(uuidString: delta.scheduleID) {
                            viewModel.requeue(scheduleID: scheduleID)
                        }
                        appendToOfflineQueue([delta])
                        syncState = .error
                        syncLastActivityMessage = "Sync failed for one item after retries."
                        FirebaseSyncService.shared.lastErrorMessage = FirebaseSyncError.retryExhausted.localizedDescription
                        logger.error("Delta upload exhausted retries for \(delta.scheduleID, privacy: .public)")
                    } else {
                        let delaySeconds = pow(2.0, Double(attempt - 1))
                        try? await Task.sleep(for: .seconds(delaySeconds))
                    }
                }
            }
        }
        return pushedCount
    }

    private func advanceProgressSmoothly(to target: Double) async {
        let clampedTarget = min(max(target, 0), 1)
        guard clampedTarget > syncProgress else { return }
        let start = syncProgress
        let delta = clampedTarget - start
        let steps = max(1, Int((delta * 100).rounded()))
        for step in 1...steps {
            syncProgress = start + (delta * Double(step) / Double(steps))
            try? await Task.sleep(for: .milliseconds(8))
        }
    }

    @discardableResult
    func syncNow(viewModel: ScheduleViewModel, userInitiated: Bool = true) async -> SyncRunReport {
        let watchdog = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(25))
            guard let self else { return }
            guard self.syncState == .syncing else { return }
            self.syncLastActivityMessage = "Sync is taking longer than expected."
            self.logger.warning("Sync watchdog detected long-running sync (>25s)")
        }
        defer { watchdog.cancel() }

        let report = await performFullSync(viewModel: viewModel, userInitiated: userInitiated)
        await drainOfflineQueue(viewModel: viewModel)
        return report
    }

    @discardableResult
    func pullAndMerge(viewModel: ScheduleViewModel) async -> SyncRunReport {
        attachedViewModel = viewModel
        var report = SyncRunReport()
        logger.info("Pull and merge started")
        syncLastActivityMessage = "Pulling remote changes..."

        do {
            logger.info("Fetching pending deltas from Firestore")
            let remoteDeltas = try await runWithTimeout(seconds: 15, operation: "Fetch pending deltas") {
                try await FirebaseSyncService.shared.fetchPendingDeltas()
            }
            logger.info("Fetched \(remoteDeltas.count, privacy: .public) pending deltas")
            var confirmedIDs: [String] = []

            if !remoteDeltas.isEmpty {
                for (index, document) in remoteDeltas.enumerated() {
                    let remote = document.delta
                    guard let scheduleID = UUID(uuidString: remote.scheduleID) else { continue }

                    logger.debug(
                        "Processing remote delta \(index + 1, privacy: .public)/\(remoteDeltas.count, privacy: .public) schedule=\(remote.scheduleID, privacy: .public)"
                    )

                    if let local = viewModel.localDelta(for: scheduleID), local.syncVersion != remote.syncVersion {
                        let outcome = SyncConflictResolver.resolve(local: local, remote: remote)
                        if SyncConflictResolver.isConflictUserVisible(local: local, remote: remote) {
                            let conflict = ConflictRecord(scheduleID: scheduleID, local: local, remote: remote)
                            if !pendingConflicts.contains(where: { $0.scheduleID == scheduleID }) {
                                pendingConflicts.append(conflict)
                            }
                        }

                        switch outcome {
                        case .useLocal:
                            viewModel.applyResolvedDelta(
                                SyncConflictResolver.localWithUnion(local: local, remote: remote)
                            )
                        case .useRemote:
                            viewModel.applyResolvedDelta(
                                SyncConflictResolver.remoteWithUnion(local: local, remote: remote)
                            )
                        case .merge(let merged):
                            viewModel.applyResolvedDelta(merged)
                        }
                    } else {
                        viewModel.applyResolvedDelta(remote)
                    }

                    confirmedIDs.append(document.id)
                    report.deltaPullCount += 1
                    let pullProgress = Double(report.deltaPullCount) / Double(max(remoteDeltas.count, 1))
                    let target = 0.55 + (pullProgress * 0.30)
                    await advanceProgressSmoothly(to: target)
                }
            }

            if !confirmedIDs.isEmpty {
                syncLastActivityMessage = "Confirming synced changes..."
                logger.info("Deleting \(confirmedIDs.count, privacy: .public) confirmed pending deltas")
                let idsToDelete = confirmedIDs
                try await runWithTimeout(seconds: 15, operation: "Delete confirmed deltas") {
                    try await FirebaseSyncService.shared.deleteConfirmedDeltas(idsToDelete)
                }
                logger.info("Confirmed pending deltas deleted")
            }

            logger.info("Reached post-pull checkpoint; advancing to 85%")
            await advanceProgressSmoothly(to: 0.85)
            syncLastActivityMessage = "Preparing cloud backup upload..."
        } catch {
            report.deltaPullSucceeded = false
            report.warnings.append("Delta pull failed: \(error.localizedDescription)")
            await advanceProgressSmoothly(to: 0.85)
            syncLastActivityMessage = "Delta pull failed."
            logger.error("Delta pull failed: \(error.localizedDescription, privacy: .public)")
        }

        if let backupData = viewModel.exportBackupData() {
            let nextVersion = viewModel.currentGlobalSyncVersion() + 1
            syncLastActivityMessage = "Uploading cloud backup..."
            logger.info(
                "Starting backup upload at version \(nextVersion, privacy: .public), bytes=\(backupData.count, privacy: .public)"
            )
            do {
                try await runWithTimeout(seconds: 25, operation: "Upload full backup") {
                    try await FirebaseSyncService.shared.uploadFullBackupWithVersion(backupData, currentVersion: nextVersion)
                }
                viewModel.seedGlobalSyncVersion(nextVersion)
                report.backupUploadSucceeded = true
                await advanceProgressSmoothly(to: 0.97)
                syncLastActivityMessage = "Finalizing sync..."
                logger.info("Full backup upload succeeded at version \(nextVersion, privacy: .public)")
            } catch let syncError as FirebaseSyncError {
                if syncError == .staleVersion {
                    syncState = .conflict
                    report.failure = .staleVersion
                    syncLastActivityMessage = report.failure?.userMessage
                    logger.warning("Backup upload blocked by stale version")
                } else {
                    syncState = .error
                    report.failure = .firestoreFailed(syncError.localizedDescription)
                    syncLastActivityMessage = report.failure?.userMessage
                    logger.error("Backup upload failed: \(syncError.localizedDescription, privacy: .public)")
                }
                await advanceProgressSmoothly(to: 0.97)
            } catch {
                syncState = .error
                report.failure = .firestoreFailed(error.localizedDescription)
                syncLastActivityMessage = report.failure?.userMessage
                await advanceProgressSmoothly(to: 0.97)
                logger.error("Backup upload failed: \(error.localizedDescription, privacy: .public)")
            }
        } else {
            logger.info("No backup data exported; skipping backup upload phase")
            syncLastActivityMessage = "Finalizing sync..."
        }

        if !report.deltaPullSucceeded {
            if report.backupUploadSucceeded {
                if syncState == .error {
                    syncState = pendingConflicts.isEmpty ? .idle : .conflict
                }
                FirebaseSyncService.shared.lastErrorMessage = "Cloud backup completed, but pending-delta sync failed."
                syncLastActivityMessage = "Backup completed, but delta sync failed."
                logger.warning("Partial sync success: backup uploaded but delta pull failed")
            } else if syncState != .conflict {
                syncState = .error
                report.failure = .bothFailed
                syncLastActivityMessage = report.failure?.userMessage
                logger.error("Sync failed: both delta and backup paths failed")
            }
        }

        report.conflictsRemaining = pendingConflicts.count
        lastSyncReport = report
        return report
    }

    @discardableResult
    func performFullSync(viewModel: ScheduleViewModel, userInitiated: Bool = true) async -> SyncRunReport {
        attachedViewModel = viewModel
        syncProgress = 0
        syncLastActivityMessage = "Sync started."
        guard FirebaseSyncService.shared.isSignedIn else {
            if syncState == .syncing {
                syncState = .idle
            }
            let report = SyncRunReport(failure: .notSignedIn)
            lastSyncReport = report
            syncLastActivityMessage = report.failure?.userMessage
            logger.warning("Sync aborted: not signed in")
            return report
        }

        if userInitiated {
            syncState = .syncing
        }
        logger.info("Sync started (userInitiated=\(userInitiated, privacy: .public))")
        defer {
            if syncState == .syncing {
                syncState = pendingConflicts.isEmpty ? .idle : .conflict
            }
        }

        let dirty = viewModel.consumeDirtyDeltas()
        syncLastActivityMessage = "Uploading local changes..."
        logger.info("Sync push phase started with \(dirty.count, privacy: .public) dirty deltas")
        let pushedCount = await pushChanges(dirtySchedules: dirty, viewModel: viewModel)
        if dirty.isEmpty {
            await advanceProgressSmoothly(to: 0.55)
        }
        var report: SyncRunReport
        do {
            report = try await runWithTimeout(seconds: 45, operation: "Pull and backup phase") {
                await self.pullAndMerge(viewModel: viewModel)
            }
        } catch {
            logger.error("Pull and backup phase timed out or failed: \(error.localizedDescription, privacy: .public)")
            syncState = .error
            syncLastActivityMessage = "Sync timed out during cloud phase."
            report = SyncRunReport(
                deltaPushSucceeded: pushedCount == dirty.count,
                deltaPullSucceeded: false,
                backupUploadSucceeded: false,
                offlineQueueChanged: false,
                conflictsRemaining: pendingConflicts.count,
                deltaPushCount: pushedCount,
                deltaPullCount: 0,
                failure: .firestoreFailed(error.localizedDescription),
                warnings: ["Pull+backup timed out"]
            )
        }
        report.deltaPushCount = pushedCount
        report.deltaPushSucceeded = pushedCount == dirty.count
        logger.info("Advancing final progress from \(self.syncProgress, privacy: .public) to 100%")
        await advanceProgressSmoothly(to: 1)

        logger.info(
            "Sync finished: pushed=\(report.deltaPushCount, privacy: .public), pulled=\(report.deltaPullCount, privacy: .public), backupUploaded=\(report.backupUploadSucceeded, privacy: .public), success=\(report.succeeded, privacy: .public)"
        )
        if report.succeeded {
            syncLastActivityMessage = nil
        } else {
            syncLastActivityMessage = report.userMessage
            logger.warning("Sync finished with warning/failure: \(report.userMessage, privacy: .public)")
        }

        try? await Task.sleep(for: .milliseconds(450))
        syncProgress = 0
        lastSyncReport = report
        return report
    }

    func drainOfflineQueue(viewModel: ScheduleViewModel) async {
        attachedViewModel = viewModel
        let queued = loadOfflineQueue()
        guard !queued.isEmpty else { return }
        syncLastActivityMessage = "Syncing queued offline changes..."
        logger.info("Draining offline queue with \(queued.count, privacy: .public) deltas")

        let pushedCount = await pushChanges(dirtySchedules: queued, viewModel: viewModel)
        logger.info("Offline queue drain result: pushed=\(pushedCount, privacy: .public)/\(queued.count, privacy: .public)")

        if syncState != .error, pushedCount == queued.count {
            clearOfflineQueue()
            syncLastActivityMessage = nil
            logger.info("Offline queue drained successfully")
            return
        }

        syncLastActivityMessage = "Retrying queued sync items shortly."
        logger.warning("Offline queue not fully drained; retry scheduled")

        Task.detached { @MainActor in
            try? await Task.sleep(for: .seconds(30))
            await self.drainOfflineQueue(viewModel: viewModel)
        }
    }

    func resolveConflictManually(_ record: ConflictRecord, choice: MergeOutcome) {
        guard let viewModel = attachedViewModel else { return }

        switch choice {
        case .useLocal:
            viewModel.applyResolvedDelta(
                SyncConflictResolver.localWithUnion(local: record.local, remote: record.remote)
            )
        case .useRemote:
            viewModel.applyResolvedDelta(
                SyncConflictResolver.remoteWithUnion(local: record.local, remote: record.remote)
            )
        case .merge(let merged):
            viewModel.applyResolvedDelta(merged)
        }

        pendingConflicts.removeAll { $0.id == record.id }
        if pendingConflicts.isEmpty, syncState == .conflict {
            syncState = .idle
        }
    }

    func clearPendingConflicts() {
        pendingConflicts.removeAll()
        if syncState == .conflict {
            syncState = .idle
        }
    }

    private func appendToOfflineQueue(_ deltas: [ScheduleDelta]) {
        var existing = loadOfflineQueue()
        existing.append(contentsOf: deltas)
        if existing.count > 500 {
            existing = Array(existing.suffix(500))
        }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(existing) {
            UserDefaults.standard.set(data, forKey: Self.uploadQueueKey)
        }
    }

    private func loadOfflineQueue() -> [ScheduleDelta] {
        guard let data = UserDefaults.standard.data(forKey: Self.uploadQueueKey) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([ScheduleDelta].self, from: data)) ?? []
    }

    private func clearOfflineQueue() {
        UserDefaults.standard.removeObject(forKey: Self.uploadQueueKey)
    }
}
