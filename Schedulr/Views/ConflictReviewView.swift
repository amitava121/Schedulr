import SwiftUI

struct ConflictReviewView: View {
    @Bindable var viewModel: ScheduleViewModel
    @Environment(\.dismiss) private var dismiss

    private var conflicts: [SyncCoordinator.ConflictRecord] {
        viewModel.syncCoordinator.pendingConflicts
    }

    var body: some View {
        NavigationStack {
            List {
                if conflicts.isEmpty {
                    Text("No conflicts to review.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(conflicts) { record in
                        VStack(alignment: .leading, spacing: 12) {
                            Text(record.local.title)
                                .font(.headline)

                            HStack(alignment: .top, spacing: 16) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Mine")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                    Text(record.local.updatedAt.formatted(date: .abbreviated, time: .shortened))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                    Text(record.local.lastModifiedDeviceID)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                    Text(record.local.scheduledDate.formatted(date: .abbreviated, time: .shortened))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                VStack(alignment: .trailing, spacing: 4) {
                                    Text("Cloud")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                    Text(record.remote.updatedAt.formatted(date: .abbreviated, time: .shortened))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                    Text(record.remote.lastModifiedDeviceID)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                    Text(record.remote.scheduledDate.formatted(date: .abbreviated, time: .shortened))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            HStack(spacing: 10) {
                                Button("Keep Mine") {
                                    resolve(record, choice: .useLocal)
                                }
                                .buttonStyle(.bordered)

                                Button("Keep Cloud") {
                                    resolve(record, choice: .useRemote)
                                }
                                .buttonStyle(.bordered)

                                Button("Merge") {
                                    resolve(
                                        record,
                                        choice: .merge(
                                            SyncConflictResolver.localWithUnion(local: record.local, remote: record.remote)
                                        )
                                    )
                                }
                                .buttonStyle(.borderedProminent)
                            }
                            .font(.caption)

                            Text(SyncConflictResolver.conflictSummary(local: record.local, remote: record.remote))
                                .font(.caption2)
                                .foregroundStyle(.secondary)

                            if let tag = viewModel.schedule(withID: record.scheduleID)?.conflictResolutionTag,
                               !tag.isEmpty {
                                Text("Resolution: \(tag)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                if !conflicts.isEmpty {
                    Section {
                        Button("Accept All Cloud") {
                            keepAllCloud()
                        }

                        Button("Keep All Mine") {
                            keepAllMine()
                        }
                    }
                }
            }
            .navigationTitle("Conflict Review")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func resolve(_ record: SyncCoordinator.ConflictRecord, choice: MergeOutcome) {
        viewModel.syncCoordinator.resolveConflictManually(record, choice: choice)
        viewModel.pendingConflictScheduleIDs = Array(Set(viewModel.syncCoordinator.pendingConflictScheduleIDs))
    }

    private func keepAllMine() {
        let snapshot = conflicts
        for record in snapshot {
            resolve(record, choice: .useLocal)
        }
    }

    private func keepAllCloud() {
        let snapshot = conflicts
        for record in snapshot {
            resolve(record, choice: .useRemote)
        }
    }
}
