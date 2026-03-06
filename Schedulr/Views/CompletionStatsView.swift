import SwiftUI

// MARK: - Stats Model

struct ScheduleStats {
    var totalSchedules: Int = 0
    var completedCount: Int = 0
    var pendingCount: Int = 0
    var overdueCount: Int = 0
    var streakDays: Int = 0
    var longestStreak: Int = 0
    var busiestDay: String = "—"
    var busiestDayCount: Int = 0
    var mostMissedHour: String = "—"
    var completionRate: Double = 0
    var tagDistribution: [(tag: String, count: Int)] = []
    var priorityDistribution: [(priority: SchedulePriority, count: Int)] = []
    var weekdayDistribution: [(day: String, count: Int)] = []
}

// MARK: - Stats Calculator

enum StatsCalculator {
    private static let weekdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        return formatter
    }()

    private static let hourFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.dateFormat = "h a"
        return formatter
    }()

    static func compute(from schedules: [Schedule], recurringCompletions: [UUID: Set<Date>]) -> ScheduleStats {
        var stats = ScheduleStats()
        let calendar = Calendar.current
        let now = Date()
        let active = schedules.filter { !$0.isSoftDeleted }

        stats.totalSchedules = active.count
        stats.completedCount = active.filter { $0.isCompleted }.count
        stats.pendingCount = active.filter { !$0.isCompleted }.count
        stats.overdueCount = active.filter { !$0.isCompleted && $0.scheduledDate < now && $0.repeatPattern == .never }.count

        if stats.totalSchedules > 0 {
            stats.completionRate = Double(stats.completedCount) / Double(stats.totalSchedules) * 100
        }

        // Streak calculation
        let streaks = calculateStreaks(schedules: active, recurringCompletions: recurringCompletions, calendar: calendar)
        stats.streakDays = streaks.current
        stats.longestStreak = streaks.longest

        // Busiest day of week
        let weekdaySymbols = weekdayFormatter.weekdaySymbols ?? []

        var weekdayCounts: [Int: Int] = [:]
        for schedule in active {
            let weekday = calendar.component(.weekday, from: schedule.scheduledDate)
            weekdayCounts[weekday, default: 0] += 1
        }

        if let busiest = weekdayCounts.max(by: { $0.value < $1.value }) {
            let index = busiest.key - 1
            if index >= 0 && index < weekdaySymbols.count {
                stats.busiestDay = weekdaySymbols[index]
                stats.busiestDayCount = busiest.value
            }
        }

        stats.weekdayDistribution = (1...7).map { day in
            let name = day - 1 < weekdaySymbols.count ? String(weekdaySymbols[day - 1].prefix(3)) : "\(day)"
            return (day: name, count: weekdayCounts[day, default: 0])
        }

        // Most common missed hour
        let missed = active.filter { !$0.isCompleted && $0.scheduledDate < now && $0.repeatPattern == .never }
        var hourCounts: [Int: Int] = [:]
        for schedule in missed {
            let hour = calendar.component(.hour, from: schedule.scheduledDate)
            hourCounts[hour, default: 0] += 1
        }
        if let peakHour = hourCounts.max(by: { $0.value < $1.value }) {
            let date = calendar.date(bySettingHour: peakHour.key, minute: 0, second: 0, of: now) ?? now
            stats.mostMissedHour = hourFormatter.string(from: date)
        }

        // Tag distribution
        var tagCounts: [String: Int] = [:]
        for schedule in active {
            for tag in schedule.tags {
                tagCounts[tag, default: 0] += 1
            }
        }
        stats.tagDistribution = tagCounts.map { ($0.key, $0.value) }
            .sorted { $0.1 > $1.1 }

        // Priority distribution
        var priorityCounts: [SchedulePriority: Int] = [:]
        for schedule in active {
            priorityCounts[schedule.priority, default: 0] += 1
        }
        stats.priorityDistribution = priorityCounts.map { ($0.key, $0.value) }
            .sorted { $0.0.rawValue > $1.0.rawValue }

        return stats
    }

    private static func calculateStreaks(
        schedules: [Schedule],
        recurringCompletions: [UUID: Set<Date>],
        calendar: Calendar
    ) -> (current: Int, longest: Int) {
        // Gather all completion dates
        var completionDates = Set<Date>()

        for schedule in schedules {
            if schedule.repeatPattern == .never && schedule.isCompleted {
                completionDates.insert(schedule.scheduledDate.startOfDay)
            }
        }

        for (_, days) in recurringCompletions {
            completionDates.formUnion(days)
        }

        guard !completionDates.isEmpty else { return (0, 0) }

        let sortedDates = completionDates.sorted(by: >)
        let today = Date().startOfDay

        // Current streak (consecutive days ending today or yesterday)
        var currentStreak = 0
        var checkDate = today

        // Allow today or yesterday as the start
        if !completionDates.contains(today) {
            if let yesterday = calendar.date(byAdding: .day, value: -1, to: today),
               completionDates.contains(yesterday) {
                checkDate = yesterday
            } else {
                // No recent completion, streak is 0
                return (0, longestStreak(from: sortedDates, calendar: calendar))
            }
        }

        while completionDates.contains(checkDate) {
            currentStreak += 1
            guard let prev = calendar.date(byAdding: .day, value: -1, to: checkDate) else { break }
            checkDate = prev
        }

        return (currentStreak, max(currentStreak, longestStreak(from: sortedDates, calendar: calendar)))
    }

    private static func longestStreak(from sortedDates: [Date], calendar: Calendar) -> Int {
        guard !sortedDates.isEmpty else { return 0 }
        let ascending = sortedDates.reversed()
        var longest = 1
        var current = 1

        var previous: Date?
        for date in ascending {
            if let prev = previous {
                let diff = calendar.dateComponents([.day], from: prev, to: date).day ?? 0
                if diff == 1 {
                    current += 1
                    longest = max(longest, current)
                } else if diff > 1 {
                    current = 1
                }
            }
            previous = date
        }

        return longest
    }
}

// MARK: - Stats View

struct CompletionStatsView: View {
    @Bindable var viewModel: ScheduleViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var cachedStats = ScheduleStats()
    @State private var statsCacheKey = ""

    private var stats: ScheduleStats {
        cachedStats
    }

    private var computedStatsCacheKey: String {
        let scheduleHash = viewModel.schedules.reduce(into: Hasher()) { hasher, schedule in
            hasher.combine(schedule.id)
            hasher.combine(schedule.updatedAt.timeIntervalSinceReferenceDate)
            hasher.combine(schedule.isCompleted)
        }.finalize()
        let recurringHash = viewModel.recurringCompletionData.reduce(into: Hasher()) { hasher, element in
            hasher.combine(element.key)
            hasher.combine(element.value.count)
        }.finalize()
        return "\(scheduleHash)-\(recurringHash)-\(viewModel.schedules.count)-\(viewModel.recurringCompletionData.count)"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    overviewGrid
                    streakCard
                    completionRateCard
                    weekdayChart
                    if !stats.priorityDistribution.isEmpty {
                        priorityBreakdown
                    }
                    if !stats.tagDistribution.isEmpty {
                        tagBreakdown
                    }
                    insightsCard
                }
                .padding(16)
            }
            .background(PremiumAppBackground())
            .navigationTitle("Statistics")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.large)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                refreshStatsIfNeeded()
            }
            .onChange(of: computedStatsCacheKey) { _, _ in
                refreshStatsIfNeeded()
            }
        }
    }

    private func refreshStatsIfNeeded() {
        let nextKey = computedStatsCacheKey
        guard nextKey != statsCacheKey else { return }
        cachedStats = StatsCalculator.compute(
            from: viewModel.schedules,
            recurringCompletions: viewModel.recurringCompletionData
        )
        statsCacheKey = nextKey
    }

    private var overviewGrid: some View {
        LazyVGrid(columns: [
            GridItem(.flexible()),
            GridItem(.flexible())
        ], spacing: 12) {
            statCard("Total", value: "\(stats.totalSchedules)", icon: "calendar", color: AppTheme.accent)
            statCard("Completed", value: "\(stats.completedCount)", icon: "checkmark.circle.fill", color: AppTheme.success)
            statCard("Pending", value: "\(stats.pendingCount)", icon: "clock", color: AppTheme.warning)
            statCard("Overdue", value: "\(stats.overdueCount)", icon: "exclamationmark.triangle.fill", color: AppTheme.danger)
        }
    }

    private func statCard(_ title: String, value: String, icon: String, color: Color) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
            Text(value)
                .font(.title.bold())
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .background(AppTheme.surfacePrimary(for: colorScheme), in: RoundedRectangle(cornerRadius: 16))
    }

    private var streakCard: some View {
        HStack(spacing: 20) {
            VStack {
                Text("\(stats.streakDays)")
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                    .foregroundStyle(stats.streakDays > 0 ? AppTheme.success : .secondary)
                Text("Current Streak")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider().frame(height: 60)

            VStack {
                Text("\(stats.longestStreak)")
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.accent)
                Text("Longest Streak")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .background(AppTheme.surfacePrimary(for: colorScheme), in: RoundedRectangle(cornerRadius: 16))
    }

    private var completionRateCard: some View {
        VStack(spacing: 8) {
            Text("Completion Rate")
                .font(.headline)

            ZStack {
                Circle()
                    .stroke(AppTheme.surfaceSecondary(for: colorScheme), lineWidth: 12)
                Circle()
                    .trim(from: 0, to: stats.completionRate / 100)
                    .stroke(AppTheme.success, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut, value: stats.completionRate)
                Text(String(format: "%.0f%%", stats.completionRate))
                    .font(.title2.bold())
            }
            .frame(width: 100, height: 100)
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .background(AppTheme.surfacePrimary(for: colorScheme), in: RoundedRectangle(cornerRadius: 16))
    }

    private var weekdayChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Schedule Distribution")
                .font(.headline)

            HStack(alignment: .bottom, spacing: 4) {
                ForEach(stats.weekdayDistribution, id: \.day) { item in
                    VStack(spacing: 4) {
                        let maxCount = stats.weekdayDistribution.map(\.count).max() ?? 1
                        let height = maxCount > 0 ? CGFloat(item.count) / CGFloat(maxCount) * 80 : 0

                        Text("\(item.count)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)

                        RoundedRectangle(cornerRadius: 4)
                            .fill(AppTheme.accent.opacity(0.7))
                            .frame(height: max(4, height))

                        Text(item.day)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(16)
        .background(AppTheme.surfacePrimary(for: colorScheme), in: RoundedRectangle(cornerRadius: 16))
    }

    private var priorityBreakdown: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("By Priority")
                .font(.headline)

            ForEach(stats.priorityDistribution, id: \.priority) { item in
                HStack {
                    Image(systemName: item.priority.iconName)
                        .foregroundStyle(item.priority.tintColor)
                    Text(item.priority.displayName)
                    Spacer()
                    Text("\(item.count)")
                        .fontWeight(.semibold)
                }
            }
        }
        .padding(16)
        .background(AppTheme.surfacePrimary(for: colorScheme), in: RoundedRectangle(cornerRadius: 16))
    }

    private var tagBreakdown: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Top Tags")
                .font(.headline)

            ForEach(stats.tagDistribution.prefix(10), id: \.tag) { item in
                HStack {
                    Image(systemName: "tag.fill")
                        .font(.caption)
                        .foregroundStyle(AppTheme.accent)
                    Text(item.tag)
                    Spacer()
                    Text("\(item.count)")
                        .fontWeight(.semibold)
                }
            }
        }
        .padding(16)
        .background(AppTheme.surfacePrimary(for: colorScheme), in: RoundedRectangle(cornerRadius: 16))
    }

    private var insightsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Insights")
                .font(.headline)

            insightRow(icon: "calendar.badge.clock", text: "Busiest day: \(stats.busiestDay) (\(stats.busiestDayCount) schedules)")
            insightRow(icon: "clock.badge.exclamationmark", text: "Most missed hour: \(stats.mostMissedHour)")
        }
        .padding(16)
        .background(AppTheme.surfacePrimary(for: colorScheme), in: RoundedRectangle(cornerRadius: 16))
    }

    private func insightRow(icon: String, text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(AppTheme.accent)
                .frame(width: 24)
            Text(text)
                .font(.subheadline)
        }
    }
}
