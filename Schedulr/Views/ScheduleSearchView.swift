import SwiftUI

struct ScheduleSearchView: View {
    @Bindable var viewModel: ScheduleViewModel
    @State private var searchText = ""
    @State private var filterPriority: SchedulePriority?
    @State private var filterCompletion: CompletionFilter = .all
    @State private var filterCalendar: String?
    @State private var filterTag: String?
    @State private var filterAlertType: AlertDeliveryOption?
    @State private var filterDateRange: DateRangeFilter = .all
    @State private var showingFilters = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    enum CompletionFilter: String, CaseIterable {
        case all = "All"
        case pending = "Pending"
        case completed = "Completed"
    }

    enum DateRangeFilter: String, CaseIterable {
        case all = "All Time"
        case today = "Today"
        case thisWeek = "This Week"
        case thisMonth = "This Month"
        case past = "Past"
        case upcoming = "Upcoming"
    }

    private var filteredSchedules: [Schedule] {
        var results = viewModel.visibleSchedules

        // Text search
        if !searchText.isEmpty {
            let query = searchText.lowercased()
            results = results.filter { schedule in
                schedule.title.lowercased().contains(query) ||
                (schedule.notes?.lowercased().contains(query) ?? false) ||
                schedule.tags.contains(where: { $0.lowercased().contains(query) }) ||
                schedule.listName.lowercased().contains(query)
            }
        }

        // Priority filter
        if let priority = filterPriority {
            results = results.filter { $0.priority == priority }
        }

        // Completion filter
        switch filterCompletion {
        case .pending:
            results = results.filter { !$0.isCompleted }
        case .completed:
            results = results.filter { $0.isCompleted }
        case .all:
            break
        }

        // Calendar filter
        if let calendar = filterCalendar {
            results = results.filter { $0.listName == calendar }
        }

        // Tag filter
        if let tag = filterTag {
            results = results.filter { $0.tags.contains(tag) }
        }

        // Alert type filter
        if let alertType = filterAlertType {
            results = results.filter { $0.alertDeliveryOption == alertType }
        }

        // Date range filter
        let calendar = Calendar.current
        let now = Date()
        switch filterDateRange {
        case .all:
            break
        case .today:
            results = results.filter { calendar.isDateInToday($0.scheduledDate) }
        case .thisWeek:
            let weekStart = now.startOfWeek
            let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart) ?? now
            results = results.filter { $0.scheduledDate >= weekStart && $0.scheduledDate < weekEnd }
        case .thisMonth:
            let comps = calendar.dateComponents([.year, .month], from: now)
            let monthStart = calendar.date(from: comps) ?? now
            let monthEnd = calendar.date(byAdding: .month, value: 1, to: monthStart) ?? now
            results = results.filter { $0.scheduledDate >= monthStart && $0.scheduledDate < monthEnd }
        case .past:
            results = results.filter { $0.scheduledDate < now }
        case .upcoming:
            results = results.filter { $0.scheduledDate >= now }
        }

        return results.sorted { $0.scheduledDate > $1.scheduledDate }
    }

    private var activeFilterCount: Int {
        var count = 0
        if filterPriority != nil { count += 1 }
        if filterCompletion != .all { count += 1 }
        if filterCalendar != nil { count += 1 }
        if filterTag != nil { count += 1 }
        if filterAlertType != nil { count += 1 }
        if filterDateRange != .all { count += 1 }
        return count
    }

    var body: some View {
        NavigationStack {
            ZStack {
                PremiumAppBackground()

                VStack(spacing: 0) {
                    if showingFilters {
                        filterBar
                    }

                    if filteredSchedules.isEmpty {
                        emptySearchState
                    } else {
                        resultsList
                    }
                }
            }
            .navigationTitle("Search")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .searchable(text: $searchText, prompt: "Search schedules...")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        withAnimation(.snappy) { showingFilters.toggle() }
                    } label: {
                        Image(systemName: activeFilterCount > 0 ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                    }
                }
            }
        }
    }

    // MARK: - Filter Bar

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // Date range
                Menu {
                    ForEach(DateRangeFilter.allCases, id: \.self) { range in
                        Button {
                            filterDateRange = range
                        } label: {
                            if filterDateRange == range {
                                Label(range.rawValue, systemImage: "checkmark")
                            } else {
                                Text(range.rawValue)
                            }
                        }
                    }
                } label: {
                    filterChip("Date: \(filterDateRange.rawValue)", isActive: filterDateRange != .all)
                }

                // Priority
                Menu {
                    Button("Any") { filterPriority = nil }
                    ForEach(SchedulePriority.allCases) { priority in
                        Button {
                            filterPriority = priority
                        } label: {
                            if filterPriority == priority {
                                Label(priority.displayName, systemImage: "checkmark")
                            } else {
                                Text(priority.displayName)
                            }
                        }
                    }
                } label: {
                    filterChip("Priority: \(filterPriority?.displayName ?? "Any")", isActive: filterPriority != nil)
                }

                // Status
                Menu {
                    ForEach(CompletionFilter.allCases, id: \.self) { filter in
                        Button {
                            filterCompletion = filter
                        } label: {
                            if filterCompletion == filter {
                                Label(filter.rawValue, systemImage: "checkmark")
                            } else {
                                Text(filter.rawValue)
                            }
                        }
                    }
                } label: {
                    filterChip("Status: \(filterCompletion.rawValue)", isActive: filterCompletion != .all)
                }

                // Calendar
                Menu {
                    Button("Any") { filterCalendar = nil }
                    ForEach(viewModel.calendarNames, id: \.self) { name in
                        Button {
                            filterCalendar = name
                        } label: {
                            if filterCalendar == name {
                                Label(name, systemImage: "checkmark")
                            } else {
                                Text(name)
                            }
                        }
                    }
                } label: {
                    filterChip("Calendar: \(filterCalendar ?? "Any")", isActive: filterCalendar != nil)
                }

                // Tag
                if !allTags.isEmpty {
                    Menu {
                        Button("Any") { filterTag = nil }
                        ForEach(allTags, id: \.self) { tag in
                            Button {
                                filterTag = tag
                            } label: {
                                if filterTag == tag {
                                    Label(tag, systemImage: "checkmark")
                                } else {
                                    Text(tag)
                                }
                            }
                        }
                    } label: {
                        filterChip("Tag: \(filterTag ?? "Any")", isActive: filterTag != nil)
                    }
                }

                // Alert type
                Menu {
                    Button("Any") { filterAlertType = nil }
                    ForEach(AlertDeliveryOption.allCases) { option in
                        Button {
                            filterAlertType = option
                        } label: {
                            if filterAlertType == option {
                                Label(option.displayName, systemImage: "checkmark")
                            } else {
                                Text(option.displayName)
                            }
                        }
                    }
                } label: {
                    filterChip("Alert: \(filterAlertType?.displayName ?? "Any")", isActive: filterAlertType != nil)
                }

                if activeFilterCount > 0 {
                    Button("Clear All") {
                        clearFilters()
                    }
                    .font(.caption)
                    .foregroundStyle(.red)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }

    private var allTags: [String] {
        let tags = viewModel.visibleSchedules.flatMap(\.tags)
        return Array(Set(tags)).sorted()
    }

    private func filterChip(_ text: String, isActive: Bool) -> some View {
        Text(text)
            .font(.caption)
            .fontWeight(isActive ? .semibold : .regular)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                isActive
                    ? AppTheme.accent.opacity(0.2)
                    : AppTheme.surfaceSecondary(for: colorScheme).opacity(0.5),
                in: Capsule()
            )
            .foregroundStyle(isActive ? AppTheme.accent : .primary)
    }

    private func clearFilters() {
        filterPriority = nil
        filterCompletion = .all
        filterCalendar = nil
        filterTag = nil
        filterAlertType = nil
        filterDateRange = .all
    }

    // MARK: - Results

    private var resultsList: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                Text("\(filteredSchedules.count) result\(filteredSchedules.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)

                ForEach(filteredSchedules, id: \.id) { schedule in
                    SearchResultCard(schedule: schedule, viewModel: viewModel)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }

    private var emptySearchState: some View {
        ContentUnavailableView {
            Label(searchText.isEmpty ? "Search Schedules" : "No Results", systemImage: "magnifyingglass")
        } description: {
            Text(searchText.isEmpty
                 ? "Search by title, notes, tags, or calendar name."
                 : "No schedules match your search criteria.")
        } actions: {
            if activeFilterCount > 0 {
                Button("Clear Filters") { clearFilters() }
            }
        }
    }
}

// MARK: - Search Result Card

private struct SearchResultCard: View {
    let schedule: Schedule
    @Bindable var viewModel: ScheduleViewModel
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 12) {
            priorityStripe

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(schedule.title)
                        .font(.headline)
                        .strikethrough(schedule.isCompleted)
                        .foregroundStyle(schedule.isCompleted ? .secondary : .primary)

                    if schedule.isFlagged {
                        Image(systemName: "flag.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }

                HStack(spacing: 6) {
                    Image(systemName: "clock")
                        .font(.caption2)
                    Text(schedule.scheduledDate, style: .date)
                        .font(.caption)
                    Text(schedule.timeString)
                        .font(.caption)
                }
                .foregroundStyle(.secondary)

                if !schedule.tags.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 4) {
                            ForEach(schedule.tags, id: \.self) { tag in
                                Text(tag)
                                    .font(.caption2)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(AppTheme.chipFill(for: colorScheme), in: Capsule())
                            }
                        }
                    }
                }
            }

            Spacer()

            VStack(spacing: 4) {
                Image(systemName: schedule.alertDeliveryOption == .alarm ? "alarm.fill" : "bell.fill")
                    .font(.caption)
                    .foregroundStyle(schedule.alertDeliveryOption == .alarm ? AppTheme.warning : .secondary)

                Text(schedule.listName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(AppTheme.surfacePrimary(for: colorScheme), in: RoundedRectangle(cornerRadius: 12))
    }

    private var priorityStripe: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(schedule.priority.tintColor)
            .frame(width: 4, height: 44)
    }
}
