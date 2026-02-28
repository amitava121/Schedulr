import SwiftUI

struct DayScheduleView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Bindable var viewModel: ScheduleViewModel

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
    }

    private var dayHeader: some View {
        let cardShape = RoundedRectangle(cornerRadius: 24, style: .continuous)

        return HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(viewModel.selectedDate.fullDayString)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.primary)

                Text("\(daySchedules.count) routine\(daySchedules.count == 1 ? "" : "s")")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                addScheduleForSelectedDay()
            } label: {
                Label("Add", systemImage: "plus")
                    .font(.subheadline.weight(.bold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .foregroundStyle(.primary)
            }
            .buttonStyle(LiquidGlassCapsuleButtonStyle())
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
                        viewModel.editingSchedule = schedule
                    },
                    onToggleComplete: {
                        viewModel.toggleScheduleCompletion(schedule, on: viewModel.selectedDate)
                    },
                    onDelete: {
                        viewModel.deleteSchedule(schedule)
                    }
                )
            }
        }
    }

    private func addScheduleForSelectedDay() {
        viewModel.startAddingSchedule(
            on: viewModel.selectedDate,
            dayIndex: viewModel.selectedDayIndex
        )
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

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            timelineMarker

            cardWithActionsWithPreview
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
        }
    }

    private var cardWithActions: some View {
        ZStack(alignment: .topTrailing) {
            ScheduleCardView(
                schedule: schedule,
                isCompact: false,
                showTrailingTime: false,
                completionOverride: isCompleted,
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
        VStack(spacing: 6) {
            Text(schedule.timeString)
                .font(.caption2.weight(.heavy))
                .foregroundStyle(.primary)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(AppTheme.surfaceTertiary(for: colorScheme), in: Capsule(style: .continuous))

            Circle()
                .fill(isCompleted ? AppTheme.success : AppTheme.mutedTimeline(for: colorScheme))
                .frame(width: 10, height: 10)

            if index < totalCount - 1 {
                Capsule(style: .continuous)
                    .fill(
                        hasScheduleTimePassed
                            ? AppTheme.success.opacity(0.42)
                            : AppTheme.mutedTimeline(for: colorScheme).opacity(0.28)
                    )
                    .frame(width: 2, height: 78)
                    .padding(.top, 2)
            }
        }
        .frame(width: 56)
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

private struct SchedulePreviewCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let schedule: Schedule

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(schedule.title)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                Spacer(minLength: 8)

                if schedule.isCompleted {
                    Label("Done", systemImage: "checkmark.circle.fill")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(AppTheme.success)
                }
            }

            Label("\(schedule.dateString) • \(schedule.timeString)", systemImage: "calendar")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if let notes = schedule.notes, !notes.isEmpty {
                Text(notes)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .lineLimit(4)
            }

            HStack(spacing: 10) {
                Label(schedule.repeatPattern.displayName, systemImage: "repeat")
                Label(schedule.alertDeliveryOption.displayName, systemImage: schedule.alertDeliveryOption == .alarm ? "alarm" : "bell.badge")
                if schedule.priority != .none {
                    Label(schedule.priority.displayName, systemImage: schedule.priority.iconName)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if !schedule.tags.isEmpty {
                HStack(spacing: 6) {
                    ForEach(schedule.tags.prefix(4), id: \.self) { tag in
                        Text(tag)
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(AppTheme.chipFill(for: colorScheme))
                            )
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(AppTheme.surfaceSecondary(for: colorScheme))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(AppTheme.borderSoft(for: colorScheme), lineWidth: 1)
        }
        .padding(6)
    }
}
