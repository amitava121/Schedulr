import SwiftUI
import SchedulrLogic

struct DayScheduleView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Bindable var viewModel: ScheduleViewModel
    @State private var pendingRecurringDelete: PendingRecurringDelete?
    @State private var exportURL: URL?

    private struct PendingRecurringDelete: Identifiable {
        let id = UUID()
        let schedule: Schedule
        let occurrenceDate: Date
    }

    private var daySchedules: [Schedule] {
        viewModel.schedules(for: viewModel.selectedDate)
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 16) {
                dayHeader

                if daySchedules.isEmpty {
                    EmptyStateView(onAddTapped: addScheduleForSelectedDay)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 28)
                } else {
                    routineStack
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 18)
        }
        .confirmationDialog(
            "Delete Repeating Schedule",
            isPresented: Binding(
                get: { pendingRecurringDelete != nil },
                set: { isPresented in
                    if !isPresented {
                        pendingRecurringDelete = nil
                    }
                }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete This Day Only") {
                guard let pendingRecurringDelete else { return }
                viewModel.deleteSchedule(
                    pendingRecurringDelete.schedule,
                    on: pendingRecurringDelete.occurrenceDate,
                    scope: .thisDayOnly
                )
                self.pendingRecurringDelete = nil
            }

            Button("Delete All") {
                guard let pendingRecurringDelete else { return }
                viewModel.deleteSchedule(
                    pendingRecurringDelete.schedule,
                    on: pendingRecurringDelete.occurrenceDate,
                    scope: .all
                )
                self.pendingRecurringDelete = nil
            }

            Button("Cancel", role: .cancel) {
                pendingRecurringDelete = nil
            }
        } message: {
            Text("Choose whether to delete only this occurrence or the full repeating schedule.")
        }
        .sheet(isPresented: Binding(
            get: { exportURL != nil },
            set: { isPresented in
                if !isPresented {
                    exportURL = nil
                }
            }
        )) {
            if let exportURL {
                ShareSheetView(items: [exportURL])
            }
        }
    }

    private var dayHeader: some View {
        let cardShape = RoundedRectangle(cornerRadius: 24, style: .continuous)

        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 12) {
                Text(viewModel.selectedDate.fullDayString)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .layoutPriority(1)

                Spacer(minLength: 8)

                HStack(spacing: 8) {
                    Button {
                        viewModel.performUndo()
                    } label: {
                        Image(systemName: "arrow.uturn.backward")
                            .font(.subheadline.weight(.bold))
                            .frame(width: 30, height: 30)
                    }
                    .buttonStyle(.plain)
                    .disabled(!viewModel.canUndo)
                    .accessibilityLabel(viewModel.undoActionName.map { "Undo \($0)" } ?? "Undo")

                    Button {
                        viewModel.performRedo()
                    } label: {
                        Image(systemName: "arrow.uturn.forward")
                            .font(.subheadline.weight(.bold))
                            .frame(width: 30, height: 30)
                    }
                    .buttonStyle(.plain)
                    .disabled(!viewModel.canRedo)
                    .accessibilityLabel(viewModel.redoActionName.map { "Redo \($0)" } ?? "Redo")
                }
            }

            HStack(alignment: .center, spacing: 12) {
                Text("\(daySchedules.count) routine\(daySchedules.count == 1 ? "" : "s")")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer(minLength: 8)

                Button {
                    addScheduleForSelectedDay()
                } label: {
                    Label("Add", systemImage: "plus")
                        .font(.subheadline.weight(.bold))
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.capsule)
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background {
            cardShape
                .fill(AppTheme.panelGradient(for: colorScheme))
                .shadow(color: AppTheme.cardShadow(for: colorScheme), radius: 8, y: 3)
        }
        .overlay {
            cardShape
                .stroke(AppTheme.borderSoft(for: colorScheme), lineWidth: 1)
        }
    }

    private var routineStack: some View {
                LazyVStack(spacing: 10) {
            ForEach(Array(daySchedules.enumerated()), id: \.1.id) { index, schedule in
                RoutineStackRow(
                    schedule: schedule,
                    occurrenceDate: viewModel.selectedDate,
                    isCompleted: viewModel.isScheduleCompleted(schedule, on: viewModel.selectedDate),
                    index: index,
                    totalCount: daySchedules.count,
                    onEdit: {
                        viewModel.startEditingSchedule(schedule, on: viewModel.selectedDate)
                    },
                    onToggleComplete: {
                        viewModel.toggleScheduleCompletion(schedule, on: viewModel.selectedDate)
                    },
                    onDelete: {
                        requestDelete(schedule, occurrenceDate: viewModel.selectedDate)
                    },
                    onExportToCalendar: {
                        exportToCalendar(schedule)
                    },
                    onExportICS: {
                        exportScheduleICS(schedule)
                    },
                    onDropSchedule: { scheduleID, targetTime in
                        handleDrop(scheduleID: scheduleID, targetTime: targetTime)
                    }
                )
            }
        }
    }

    private func requestDelete(_ schedule: Schedule, occurrenceDate: Date) {
        guard schedule.repeatPattern != .never else {
            viewModel.deleteSchedule(schedule)
            return
        }
        pendingRecurringDelete = PendingRecurringDelete(schedule: schedule, occurrenceDate: occurrenceDate)
    }

    private func addScheduleForSelectedDay() {
        viewModel.startAddingSchedule(
            on: viewModel.selectedDate,
            dayIndex: viewModel.selectedDayIndex
        )
    }

    private func exportToCalendar(_ schedule: Schedule) {
        Task {
            let succeeded = await EventKitExportService.exportToCalendar(schedule: schedule)
            HapticManager.notification(succeeded ? .success : .warning)
        }
    }

    private func exportScheduleICS(_ schedule: Schedule) {
        guard let url = EventKitExportService.saveICSFile(for: schedule) else {
            HapticManager.notification(.warning)
            return
        }
        exportURL = url
    }

    private func handleDrop(scheduleID: UUID, targetTime: Date) -> Bool {
        guard let schedule = viewModel.schedule(withID: scheduleID) else { return false }
        let updatedDate = viewModel.selectedDate.startOfDay.mergingTime(from: targetTime)
        guard updatedDate != schedule.scheduledDate else { return false }
        viewModel.rescheduleSchedule(schedule, to: updatedDate)
        HapticManager.selection()
        return true
    }
}

private struct RoutineStackRow: View {
    @Environment(\.colorScheme) private var colorScheme
    let schedule: Schedule
    let occurrenceDate: Date
    let isCompleted: Bool
    let index: Int
    let totalCount: Int
    var onEdit: () -> Void
    var onToggleComplete: () -> Void
    var onDelete: () -> Void
    var onExportToCalendar: () -> Void
    var onExportICS: () -> Void
    var onDropSchedule: (UUID, Date) -> Bool
    @State private var isDropTargeted = false

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            timelineMarker

            cardWithActionsWithPreview
        }
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(AppTheme.accent, lineWidth: 2)
            }
        }
        .draggable(schedule.id.uuidString)
        .dropDestination(for: String.self) { items, _ in
            guard let payload = items.first,
                  let scheduleID = UUID(uuidString: payload)
            else {
                return false
            }
            return onDropSchedule(scheduleID, schedule.scheduledDate)
        } isTargeted: { targeted in
            isDropTargeted = targeted
        }
    }

    private var cardWithActionsWithPreview: some View {
        cardWithActions
            .contentShape(Rectangle())
            .contextMenu {
                Button {
                    onEdit()
                } label: {
                    Label("Edit", systemImage: "pencil")
                }

                Button {
                    onToggleComplete()
                } label: {
                    Label(
                        isCompleted ? "Mark Incomplete" : "Mark Complete",
                        systemImage: isCompleted ? "arrow.uturn.backward.circle" : "checkmark.circle"
                    )
                }

                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Label("Delete", systemImage: "trash")
                }

                Button {
                    onExportToCalendar()
                } label: {
                    Label("Export to Calendar", systemImage: "calendar.badge.plus")
                }

                Button {
                    onExportICS()
                } label: {
                    Label("Share ICS", systemImage: "square.and.arrow.up")
                }
            }
    }

    private var cardWithActions: some View {
        ZStack(alignment: .topTrailing) {
            ScheduleCardView(
                schedule: schedule,
                isCompact: false,
                showTrailingTime: false,
                completionOverride: isCompleted,
                displayDate: occurrenceDate,
                onTap: nil,
                onDelete: nil
            )
            .padding(.top, 2)

            HStack(spacing: 8) {
                Button {
                    onToggleComplete()
                } label: {
                    Image(systemName: isCompleted ? "checkmark.circle.fill" : "checkmark.circle")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(isCompleted ? AppTheme.success : .primary)
                        .frame(width: 30, height: 30)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isCompleted ? "Mark incomplete" : "Mark complete")

                Button {
                    onEdit()
                } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.primary)
                        .frame(width: 30, height: 30)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Edit schedule")
            }
            .padding(.top, 8)
            .padding(.trailing, 10)
        }
    }

    private var timelineMarker: some View {
        Text(schedule.timeString)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.primary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(AppTheme.chipFill(for: colorScheme), in: Capsule(style: .continuous))
            .frame(width: 62, alignment: .leading)
            .overlay(alignment: .topLeading) {
                if index < totalCount - 1 {
                    Capsule(style: .continuous)
                        .fill(
                            hasScheduleTimePassed
                                ? AppTheme.success.opacity(0.42)
                                : AppTheme.mutedTimeline(for: colorScheme).opacity(0.28)
                        )
                        .frame(width: 2, height: 78)
                        .offset(x: 27, y: 24)
                }
            }
            .zIndex(1)
    }

    private var hasScheduleTimePassed: Bool {
        let calendar = Calendar.current
        let targetDay = occurrenceDate.startOfDay
        let today = Date().startOfDay

        if targetDay < today { return true }
        if targetDay > today { return false }

        var components = calendar.dateComponents([.year, .month, .day], from: targetDay)
        let timeComponents = calendar.dateComponents([.hour, .minute, .second], from: schedule.scheduledDate)
        components.hour = timeComponents.hour
        components.minute = timeComponents.minute
        components.second = timeComponents.second ?? 0

        guard let scheduledMoment = calendar.date(from: components) else {
            return schedule.scheduledDate <= Date()
        }
        return scheduledMoment <= Date()
    }

}
