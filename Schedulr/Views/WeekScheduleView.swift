import SwiftUI

struct WeekScheduleView: View {
    @Bindable var viewModel: ScheduleViewModel
    var isBulkSelectionMode: Bool = false
    var selectedScheduleIDs: Set<UUID> = []
    var onToggleScheduleSelection: (UUID) -> Void = { _ in }
    @State private var pendingRecurringDelete: PendingRecurringDelete?
    @State private var exportURL: URL?

    private struct PendingRecurringDelete: Identifiable {
        let id = UUID()
        let schedule: Schedule
        let occurrenceDate: Date
    }

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
                            viewModel.startEditingSchedule(schedule, on: item.date)
                        },
                        onToggleScheduleCompletion: { schedule in
                            viewModel.toggleScheduleCompletion(schedule, on: item.date)
                        },
                        onDeleteSchedule: { schedule in
                            requestDelete(schedule, occurrenceDate: item.date)
                        },
                        onExportToCalendar: { schedule in
                            exportToCalendar(schedule)
                        },
                        onExportScheduleICS: { schedule in
                            exportScheduleICS(schedule)
                        },
                        onDropSchedule: { scheduleID, targetDay in
                            handleDrop(scheduleID: scheduleID, targetDay: targetDay)
                        },
                        isBulkSelectionMode: isBulkSelectionMode,
                        selectedScheduleIDs: selectedScheduleIDs,
                        onToggleScheduleSelection: onToggleScheduleSelection
                    )
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

    private func requestDelete(_ schedule: Schedule, occurrenceDate: Date) {
        guard schedule.repeatPattern != .never else {
            viewModel.deleteSchedule(schedule)
            return
        }
        pendingRecurringDelete = PendingRecurringDelete(schedule: schedule, occurrenceDate: occurrenceDate)
    }

    private func shouldShowMonthHeader(item: DayItem) -> Bool {
        guard item.index > 0 else { return false }
        let previous = viewModel.weekDates[item.index - 1]
        return !Calendar.current.isDate(item.date, equalTo: previous, toGranularity: .month)
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

    private func handleDrop(scheduleID: UUID, targetDay: Date) -> Bool {
        guard let schedule = viewModel.schedule(withID: scheduleID) else { return false }
        let updatedDate = targetDay.startOfDay.mergingTime(from: schedule.scheduledDate)
        guard updatedDate != schedule.scheduledDate else { return false }
        viewModel.rescheduleSchedule(schedule, to: updatedDate)
        HapticManager.selection()
        return true
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
    var onExportToCalendar: (Schedule) -> Void
    var onExportScheduleICS: (Schedule) -> Void
    var onDropSchedule: (UUID, Date) -> Bool
    var isBulkSelectionMode: Bool
    var selectedScheduleIDs: Set<UUID>
    var onToggleScheduleSelection: (UUID) -> Void

    private let rowShape = RoundedRectangle(cornerRadius: 24, style: .continuous)
    @State private var hasAutoScrolled = false
    @State private var autoScrollTask: Task<Void, Never>?
    @State private var isDropTargeted = false

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
            .overlay {
                if isDropTargeted {
                    rowShape
                        .strokeBorder(AppTheme.accent, lineWidth: 2)
                        .allowsHitTesting(false)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                onTapDay()
            }
            .dropDestination(for: String.self) { items, _ in
                guard let payload = items.first,
                      let scheduleID = UUID(uuidString: payload)
                else {
                    return false
                }
                return onDropSchedule(scheduleID, date)
            } isTargeted: { targeted in
                isDropTargeted = targeted
            }
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
                        isSelectionMode: isBulkSelectionMode,
                        isSelected: selectedScheduleIDs.contains(schedule.id),
                        onOpenDay: onTapDay,
                        onEdit: { onEditSchedule(schedule) },
                        onToggleComplete: { onToggleScheduleCompletion(schedule) },
                        onDelete: { onDeleteSchedule(schedule) },
                        onExportToCalendar: { onExportToCalendar(schedule) },
                        onExportICS: { onExportScheduleICS(schedule) },
                        onToggleSelected: { onToggleScheduleSelection(schedule.id) },
                        dragPayload: schedule.id.uuidString
                    )
                    .id(schedule.id)
                }
            }

            if schedules.count <= 1 {
                Color.clear
                    .frame(width: 140, height: 1)
                    .accessibilityHidden(true)
            }
        }
    }

    private var emptyScheduleStrip: some View {
        Text("No schedules")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(width: 186, height: 72)
            .background(
                AppTheme.surfaceSecondary(for: colorScheme)
                    .opacity(colorScheme == .dark ? 0.52 : 0.64),
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
            .fill(
                LinearGradient(
                    colors: [
                        AppTheme.surfaceSecondary(for: colorScheme)
                            .opacity(colorScheme == .dark ? 0.56 : 0.68),
                        AppTheme.surfaceTertiary(for: colorScheme)
                            .opacity(colorScheme == .dark ? 0.48 : 0.60)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
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
    let isSelectionMode: Bool
    let isSelected: Bool
    var onOpenDay: () -> Void
    var onEdit: () -> Void
    var onToggleComplete: () -> Void
    var onDelete: () -> Void
    var onExportToCalendar: () -> Void
    var onExportICS: () -> Void
    var onToggleSelected: () -> Void
    let dragPayload: String

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
                    if isSelectionMode {
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(isSelected ? AppTheme.accent : .secondary)
                            .frame(width: 24, height: 24)
                    } else {
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
                if isSelectionMode && isSelected {
                    cardShape
                        .strokeBorder(AppTheme.accent.opacity(0.82), lineWidth: 1.8)
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
        .onTapGesture {
            if isSelectionMode {
                onToggleSelected()
            } else {
                onOpenDay()
            }
        }
        .draggable(isSelectionMode ? "" : dragPayload)
        .contextMenu {
            if !isSelectionMode {
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
                Button(action: onExportToCalendar) {
                    Label("Export to Calendar", systemImage: "calendar.badge.plus")
                }
                Button(action: onExportICS) {
                    Label("Share ICS", systemImage: "square.and.arrow.up")
                }
            }
        }
    }
}
