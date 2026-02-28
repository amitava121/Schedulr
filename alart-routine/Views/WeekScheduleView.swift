import SwiftUI

struct WeekScheduleView: View {
    @Bindable var viewModel: ScheduleViewModel

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 14) {
                ForEach(viewModel.dayItems) { item in
                    if shouldShowMonthHeader(item: item) {
                        MonthChangeHeader(title: item.date.monthYearString)
                    }
                    DayStripRowView(
                        date: item.date,
                        schedules: item.schedules,
                        isScheduleCompletedOnDate: { schedule, occurrenceDate in
                            viewModel.isScheduleCompleted(schedule, on: occurrenceDate)
                        },
                        onTapDay: {
                            viewModel.zoomToDay(index: item.index)
                        },
                        onEditSchedule: { schedule in
                            viewModel.editingSchedule = schedule
                        },
                        onToggleScheduleCompletion: { schedule in
                            viewModel.toggleScheduleCompletion(schedule, on: item.date)
                        },
                        onDeleteSchedule: { schedule in
                            viewModel.deleteSchedule(schedule)
                        }
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 18)
        }
    }

    private func shouldShowMonthHeader(item: DayItem) -> Bool {
        guard item.index > 0 else { return false }
        let previous = viewModel.weekDates[item.index - 1]
        return !Calendar.current.isDate(item.date, equalTo: previous, toGranularity: .month)
    }
}

// MARK: - Month Change Header

private struct MonthChangeHeader: View {
    @Environment(\.colorScheme) private var colorScheme
    let title: String

    var body: some View {
        HStack(spacing: 12) {
            line
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .fixedSize()
            line
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity)
    }

    private var line: some View {
        Capsule(style: .continuous)
            .fill(AppTheme.borderSoft(for: colorScheme))
            .frame(height: 1)
    }
}

// MARK: - Day Strip Row

private struct DayStripRowView: View {
    @Environment(\.colorScheme) private var colorScheme

    let date: Date
    let schedules: [Schedule]
    var isScheduleCompletedOnDate: (Schedule, Date) -> Bool
    var onTapDay: () -> Void
    var onEditSchedule: (Schedule) -> Void
    var onToggleScheduleCompletion: (Schedule) -> Void
    var onDeleteSchedule: (Schedule) -> Void

    private let rowShape = RoundedRectangle(cornerRadius: 24, style: .continuous)
    @State private var hasAutoScrolled = false
    @State private var autoScrollTask: Task<Void, Never>?

    var body: some View {
        scheduleStrip
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .leading) {
                dayLabel
                    .padding(.leading, 8)
            }
            .frame(height: 102)
            .padding(2)
            .clipShape(rowShape)
            .background { rowSurface }
            .overlay {
                rowBorder
                    .allowsHitTesting(false)
            }
            .contentShape(Rectangle())
            .gesture(
                TapGesture().onEnded {
                    onTapDay()
                },
                including: .gesture
            )
    }

    // MARK: Day Label

    private var dayLabel: some View {
        VStack(spacing: 5) {
            Text(date.shortDayName.uppercased())
                .font(.caption.weight(.black))
                .kerning(0.6)
                .foregroundStyle(
                    date.isToday
                        ? AppTheme.accent
                        : .secondary
                )
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(
                    Capsule(style: .continuous)
                        .fill(AppTheme.chipFill(for: colorScheme))
                )

            Text(date.dayNumber)
                .font(.title3.weight(.heavy))
                .foregroundStyle(date.isToday ? .white : .primary)
                .frame(width: 34, height: 34)
                .background { dayBadge }
        }
        .frame(maxHeight: .infinity)
    }

    @ViewBuilder
    private var dayBadge: some View {
        if date.isToday {
            Circle()
                .fill(.clear)
                .glassEffect(
                    .regular.tint(AppTheme.accentSoft.opacity(0.66)),
                    in: Circle()
                )
        } else {
            Circle()
                .fill(AppTheme.surfaceSecondary(for: colorScheme))
        }
    }

    // MARK: Schedule Strip

    /// The ID of the schedule card to auto-scroll to (next upcoming or current).
    private var autoScrollTargetID: UUID? {
        guard date.isToday, !schedules.isEmpty else { return nil }
        let now = Date()
        // Find the first schedule whose time is >= now (upcoming)
        let sorted = schedules.sorted { $0.scheduledDate < $1.scheduledDate }
        if let upcoming = sorted.first(where: { $0.scheduledDate >= now }) {
            return upcoming.id
        }
        // All schedules are in the past — scroll to the last one
        return sorted.last?.id
    }

    @ViewBuilder
    private var scheduleStrip: some View {
        if schedules.count > 1 {
            ScrollViewReader { hProxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    scheduleCards
                        .padding(.leading, 90)
                        .padding(.trailing, 14)
                }
                .onAppear {
                    scheduleAutoScrollIfNeeded(using: hProxy)
                }
                .onChange(of: schedules.map(\.id)) { _, _ in
                    scheduleAutoScrollIfNeeded(using: hProxy)
                }
                .onDisappear {
                    autoScrollTask?.cancel()
                    autoScrollTask = nil
                }
            }
        } else {
            scheduleCards
                .padding(.leading, 90)
                .padding(.trailing, 14)
        }
    }

    private func scheduleAutoScrollIfNeeded(using proxy: ScrollViewProxy) {
        guard !hasAutoScrolled, let target = autoScrollTargetID else { return }
        hasAutoScrolled = true

        autoScrollTask?.cancel()
        autoScrollTask = Task { @MainActor in
            // Wait for the row layout pass, then scroll with a smoother animation.
            try? await Task.sleep(for: .milliseconds(60))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.55)) {
                proxy.scrollTo(target, anchor: .center)
            }
        }
    }

    private var scheduleCards: some View {
        HStack(spacing: 12) {
            if schedules.isEmpty {
                emptyScheduleStrip
            } else {
                ForEach(schedules, id: \.id) { schedule in
                    let isCompleted = isScheduleCompletedOnDate(schedule, date)
                    ScheduleStripCardView(
                        schedule: schedule,
                        isCompleted: isCompleted,
                        onEdit: { onEditSchedule(schedule) },
                        onToggleComplete: { onToggleScheduleCompletion(schedule) },
                        onDelete: { onDeleteSchedule(schedule) }
                    )
                    .id(schedule.id)
                }
            }
        }
    }

    private var emptyScheduleStrip: some View {
        Text("No schedules")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(width: 186, height: 72)
            .background(
                AppTheme.panelGradient(for: colorScheme),
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(AppTheme.borderSoft(for: colorScheme), lineWidth: 1)
            }
    }

    // MARK: Row Background

    private var rowSurface: some View {
        rowShape
            .fill(AppTheme.panelGradient(for: colorScheme))
            .shadow(
                color: AppTheme.cardShadow(for: colorScheme),
                radius: 8,
                y: 3
            )
    }



    private var rowBorder: some View {
        rowShape
            .strokeBorder(
                AppTheme.borderStrong(for: colorScheme),
                lineWidth: colorScheme == .dark ? 0.7 : 0.8
            )
    }
}

// MARK: - Schedule Strip Card

private struct ScheduleStripCardView: View {
    @Environment(\.colorScheme) private var colorScheme
    let schedule: Schedule
    let isCompleted: Bool
    var onEdit: () -> Void
    var onToggleComplete: () -> Void
    var onDelete: () -> Void

    private let cardShape = RoundedRectangle(cornerRadius: 18, style: .continuous)

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(schedule.title)
                        .font(.subheadline.weight(.heavy))
                        .foregroundStyle(isCompleted ? .secondary : .primary)
                        .strikethrough(isCompleted, color: .secondary)
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        Text(schedule.timeString)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)

                        if schedule.isUrgent {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.caption2)
                                .foregroundStyle(AppTheme.danger)
                                .symbolRenderingMode(.hierarchical)
                        }

                        if schedule.isFlagged {
                            Image(systemName: "flag.fill")
                                .font(.caption2)
                                .foregroundStyle(AppTheme.warning)
                        }
                    }
                }

                Spacer(minLength: 0)

                HStack(spacing: 6) {
                    Button {
                        onToggleComplete()
                    } label: {
                        Image(systemName: isCompleted ? "checkmark.circle.fill" : "checkmark.circle")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(isCompleted ? AppTheme.success : .primary)
                            .frame(width: 24, height: 24)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(isCompleted ? "Mark incomplete" : "Mark complete")

                    Button {
                        onEdit()
                    } label: {
                        Image(systemName: "pencil")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.primary)
                            .frame(width: 24, height: 24)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Edit schedule")
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(width: 186, height: 72, alignment: .leading)
        .background(
            cardShape.fill(
                AppTheme.stackCardGradient(
                    for: colorScheme,
                    priority: schedule.priority,
                    completed: isCompleted
                )
            )
        )
        .opacity(isCompleted ? 0.72 : 1)
        .overlay {
            ZStack {
                cardShape
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(colorScheme == .dark ? 0.12 : 0.35),
                                Color.clear
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .blendMode(.screen)

                if schedule.isUrgent {
                    cardShape
                        .strokeBorder(AppTheme.danger.opacity(0.6), lineWidth: 1.3)
                }
                if isCompleted {
                    cardShape
                        .strokeBorder(AppTheme.success.opacity(0.52), lineWidth: 1.2)
                }

                cardShape
                    .strokeBorder(
                        AppTheme.stackCardBorder(
                            for: colorScheme,
                            priority: schedule.priority,
                            completed: isCompleted
                        ),
                        lineWidth: 1.0
                    )
            }
            .allowsHitTesting(false)
        }
        .shadow(color: AppTheme.cardShadow(for: colorScheme), radius: 7, y: 3)
        .contentShape(cardShape)
        .contextMenu {
            Button(action: onEdit) {
                Label("Edit", systemImage: "pencil")
            }
            Button(action: onToggleComplete) {
                Label(
                    isCompleted ? "Mark Incomplete" : "Mark Complete",
                    systemImage: isCompleted ? "arrow.uturn.backward.circle" : "checkmark.circle"
                )
            }
            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

private struct WeekSchedulePreviewCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let schedule: Schedule

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
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
