import Foundation

@MainActor
@Observable
final class SyncCoordinator {
    static let shared = SyncCoordinator()

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

    var syncState: SyncState = .idle
    var pendingConflicts: [ConflictRecord] = []
    var pendingConflictScheduleIDs: [UUID] { pendingConflicts.map(\.scheduleID) }

    private var attachedViewModel: ScheduleViewModel?

    func pushChanges(dirtySchedules: [ScheduleDelta], viewModel: ScheduleViewModel) async {
        attachedViewModel = viewModel
        guard !dirtySchedules.isEmpty else { return }

        for delta in dirtySchedules {
            var succeeded = false
            var attempt = 0

            while attempt < 3, !succeeded {
                do {
                    try await FirebaseSyncService.shared.uploadDelta(delta)
                    if let scheduleID = UUID(uuidString: delta.scheduleID) {
                        viewModel.markClean(scheduleID: scheduleID, syncedVersion: delta.syncVersion)
                    }
                    succeeded = true
                } catch {
                    attempt += 1
                    if attempt >= 3 {
                        if let scheduleID = UUID(uuidString: delta.scheduleID) {
                            viewModel.requeue(scheduleID: scheduleID)
                        }
                        appendToOfflineQueue([delta])
                        syncState = .error
                        FirebaseSyncService.shared.lastErrorMessage = FirebaseSyncError.retryExhausted.localizedDescription
                    } else {
                        let delaySeconds = pow(2.0, Double(attempt - 1))
                        try? await Task.sleep(for: .seconds(delaySeconds))
                    }
                }
            }
        }
    }

    func syncNow(viewModel: ScheduleViewModel) async {
        await performFullSync(viewModel: viewModel)
        await drainOfflineQueue(viewModel: viewModel)
    }

    func pullAndMerge(viewModel: ScheduleViewModel) async {
        attachedViewModel = viewModel

        do {
            let remoteDeltas = try await FirebaseSyncService.shared.fetchPendingDeltas()
            guard !remoteDeltas.isEmpty else { return }

            var confirmedIDs: [String] = []

            for document in remoteDeltas {
                let remote = document.delta
                guard let scheduleID = UUID(uuidString: remote.scheduleID) else { continue }

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
            }

            try await FirebaseSyncService.shared.deleteConfirmedDeltas(confirmedIDs)

            if let backupData = viewModel.exportBackupData() {
                let nextVersion = viewModel.currentGlobalSyncVersion() + 1
                do {
                    try await FirebaseSyncService.shared.uploadFullBackupWithVersion(backupData, currentVersion: nextVersion)
                    viewModel.seedGlobalSyncVersion(nextVersion)
                } catch let syncError as FirebaseSyncError {
                    if syncError == .staleVersion {
                        syncState = .conflict
                    } else {
                        syncState = .error
                    }
                } catch {
                    syncState = .error
                }
            }
        } catch {
            syncState = .error
        }
    }

    func performFullSync(viewModel: ScheduleViewModel) async {
        attachedViewModel = viewModel
        guard FirebaseSyncService.shared.isSignedIn else { return }

        syncState = .syncing

        let dirty = viewModel.consumeDirtyDeltas()
        await pushChanges(dirtySchedules: dirty, viewModel: viewModel)
        await pullAndMerge(viewModel: viewModel)

        if syncState == .syncing {
            syncState = pendingConflicts.isEmpty ? .idle : .conflict
        }
    }

    func drainOfflineQueue(viewModel: ScheduleViewModel) async {
        attachedViewModel = viewModel
        let queued = loadOfflineQueue()
        guard !queued.isEmpty else { return }

        await pushChanges(dirtySchedules: queued, viewModel: viewModel)

        if syncState != .error {
            clearOfflineQueue()
            return
        }

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
