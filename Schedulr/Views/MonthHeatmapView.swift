import SwiftUI

struct MonthHeatmapView: View {
    @Bindable var viewModel: ScheduleViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var displayedMonth = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: Date())) ?? Date()
    @State private var daySummaries: [Date: HeatmapDaySummary] = [:]

    private var calendar: Calendar { Calendar.current }

    private var monthTitle: String {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.setLocalizedDateFormatFromTemplate("MMMM yyyy")
        return formatter.string(from: displayedMonth)
    }

    private var monthDays: [Date] {
        guard let monthRange = calendar.range(of: .day, in: .month, for: displayedMonth),
              let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: displayedMonth))
        else {
            return []
        }

        return monthRange.compactMap { day in
            calendar.date(byAdding: .day, value: day - 1, to: monthStart)?.startOfDay
        }
    }

    private var leadingPlaceholders: Int {
        guard let first = monthDays.first else { return 0 }
        let weekday = calendar.component(.weekday, from: first)
        return (weekday - calendar.firstWeekday + 7) % 7
    }

    private var weekdayHeaders: [String] {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        let symbols = formatter.shortWeekdaySymbols ?? ["S", "M", "T", "W", "T", "F", "S"]
        let first = max(1, min(calendar.firstWeekday, 7)) - 1
        return Array(symbols[first...] + symbols[..<first]).map { String($0.prefix(1)) }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                header

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 7), spacing: 8) {
                    ForEach(Array(weekdayHeaders.enumerated()), id: \.offset) { _, day in
                        Text(day)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                    }

                    ForEach(0..<leadingPlaceholders, id: \.self) { _ in
                        Color.clear
                            .frame(height: 34)
                    }

                    ForEach(monthDays, id: \.self) { day in
                        let summary = daySummaries[day] ?? .empty

                        VStack(spacing: 3) {
                            Text("\(calendar.component(.day, from: day))")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(day.isToday ? .white : .primary)

                            if summary.total > 0 {
                                Text("\(summary.completed)/\(summary.total)")
                                    .font(.system(size: 8, weight: .medium))
                                    .foregroundStyle(day.isToday ? .white.opacity(0.92) : .secondary)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 34)
                        .background {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(cellFillColor(rate: summary.completionRate, isToday: day.isToday))
                        }
                    }
                }

                legend
                Spacer(minLength: 0)
            }
            .padding(16)
            .background(PremiumAppBackground())
            .navigationTitle("Monthly Heatmap")
#if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                refreshSummary()
            }
            .onChange(of: displayedMonth) { _, _ in
                refreshSummary()
            }
            .onChange(of: viewModel.schedules.count) { _, _ in
                refreshSummary()
            }
            .onChange(of: viewModel.recurringCompletionData.count) { _, _ in
                refreshSummary()
            }
        }
    }

    private func refreshSummary() {
        daySummaries = viewModel.monthHeatmapSummary(for: displayedMonth)
    }

    private var header: some View {
        HStack {
            Button {
                displayedMonth = calendar.date(byAdding: .month, value: -1, to: displayedMonth) ?? displayedMonth
            } label: {
                Image(systemName: "chevron.left")
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.glass)

            Spacer()

            Text(monthTitle)
                .font(.headline.weight(.semibold))

            Spacer()

            Button {
                displayedMonth = calendar.date(byAdding: .month, value: 1, to: displayedMonth) ?? displayedMonth
            } label: {
                Image(systemName: "chevron.right")
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.glass)
        }
    }

    private var legend: some View {
        HStack(spacing: 8) {
            Text("Completion")
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach([0.0, 0.25, 0.5, 0.75, 1.0], id: \.self) { value in
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(cellFillColor(rate: value, isToday: false))
                    .frame(width: 20, height: 10)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func cellFillColor(rate: Double, isToday: Bool) -> Color {
        if isToday { return AppTheme.accent }
        if rate >= 1.0 { return AppTheme.success.opacity(colorScheme == .dark ? 0.85 : 0.75) }
        if rate >= 0.75 { return AppTheme.success.opacity(colorScheme == .dark ? 0.65 : 0.55) }
        if rate >= 0.5 { return AppTheme.accent.opacity(colorScheme == .dark ? 0.52 : 0.42) }
        if rate > 0 { return AppTheme.warning.opacity(colorScheme == .dark ? 0.45 : 0.32) }
        return AppTheme.surfaceSecondary(for: colorScheme)
    }
}
