import UIKit
import SwiftUI

// ═══════════════════════════════════════════════════════════════════
// MARK: - Month Calendar (UICollectionView + CompositionalLayout)
// ═══════════════════════════════════════════════════════════════════

/// A UIKit-backed month calendar that scrolls through thousands of months
/// with O(1) jump-to-today, cell reuse, and prefetching — like Apple Calendar.
struct MonthCalendarCollectionView: UIViewRepresentable {
    let selectedDate: Date
    let onSelectDate: (Date) -> Void
    let onVisibleYearChanged: (Int) -> Void

    // Jump trigger: change from parent to scroll to today instantly
    let jumpToTodayTrigger: UUID

    private static var calendar: Calendar {
        var calendar = Calendar.current
        calendar.firstWeekday = AppSettings.shared.firstDayOfWeek
        return calendar
    }
    private static let totalMonths = 2400 // 200 years (1900–2099)
    private static let baseYear = 1900
    private static let centerIndex: Int = {
        let now = Date()
        let cal = Calendar.current
        let y = cal.component(.year, from: now) - baseYear
        let m = cal.component(.month, from: now) - 1
        return y * 12 + m
    }()

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> UICollectionView {
        let layout = createCompositionalLayout()
        let cv = UICollectionView(frame: .zero, collectionViewLayout: layout)
        cv.backgroundColor = .clear
        cv.showsVerticalScrollIndicator = false
        cv.contentInsetAdjustmentBehavior = .automatic

        // Register cells
        cv.register(MonthSectionCell.self, forCellWithReuseIdentifier: MonthSectionCell.reuseID)

        cv.dataSource = context.coordinator
        cv.delegate = context.coordinator
        cv.prefetchDataSource = context.coordinator

        context.coordinator.collectionView = cv
        context.coordinator.selectedDate = selectedDate

        // Scroll to selected date's month, then enable visible-year callbacks.
        context.coordinator.setVisibleYearCallbacksEnabled(false)
        DispatchQueue.main.async {
            context.coordinator.scrollToDate(selectedDate, animated: false)
            DispatchQueue.main.async {
                context.coordinator.reportYear(for: selectedDate)
                context.coordinator.setVisibleYearCallbacksEnabled(true)
            }
        }

        return cv
    }

    func updateUIView(_ cv: UICollectionView, context: Context) {
        let coord = context.coordinator
        let dateChanged = !Self.calendar.isDate(coord.selectedDate, inSameDayAs: selectedDate)
        coord.selectedDate = selectedDate
        coord.parent = self

        if dateChanged {
            // Reload visible cells to update selection highlight
            cv.reloadItems(at: cv.indexPathsForVisibleItems)
        }

        // Check if jump trigger changed
        if coord.lastJumpTrigger != jumpToTodayTrigger {
            coord.lastJumpTrigger = jumpToTodayTrigger
            coord.setVisibleYearCallbacksEnabled(false)
            let today = Date()
            coord.scrollToDate(today, animated: false)
            DispatchQueue.main.async {
                coord.reportYear(for: today)
                coord.setVisibleYearCallbacksEnabled(true)
            }
        }
    }

    private func createCompositionalLayout() -> UICollectionViewCompositionalLayout {
        UICollectionViewCompositionalLayout { _, environment in
            let itemSize = NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(1.0),
                heightDimension: .estimated(340) // ~6 weeks × 44pt + header
            )
            let item = NSCollectionLayoutItem(layoutSize: itemSize)
            let group = NSCollectionLayoutGroup.vertical(layoutSize: itemSize, subitems: [item])
            let section = NSCollectionLayoutSection(group: group)
            section.interGroupSpacing = 22
            section.contentInsets = NSDirectionalEdgeInsets(top: 14, leading: 14, bottom: 22, trailing: 14)
            return section
        }
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, UICollectionViewDataSource, UICollectionViewDelegate,
                              UICollectionViewDataSourcePrefetching {
        var parent: MonthCalendarCollectionView
        weak var collectionView: UICollectionView?
        var selectedDate: Date = Date()
        var lastJumpTrigger: UUID = UUID()
        private var cal: Calendar {
            MonthCalendarCollectionView.calendar
        }
        private var lastReportedYear: Int = 0
        private var suppressVisibleYearUpdates = true

        // Prefetch cache: month index → precomputed data
        private var monthDataCache = NSCache<NSNumber, MonthRenderData>()

        init(parent: MonthCalendarCollectionView) {
            self.parent = parent
            self.monthDataCache.countLimit = 24
        }

        // MARK: DataSource

        func collectionView(_ cv: UICollectionView, numberOfItemsInSection section: Int) -> Int {
            MonthCalendarCollectionView.totalMonths
        }

        func collectionView(_ cv: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
            let cell = cv.dequeueReusableCell(withReuseIdentifier: MonthSectionCell.reuseID, for: indexPath) as! MonthSectionCell
            let data = monthData(for: indexPath.item)
            cell.configure(with: data, selectedDate: selectedDate, calendar: cal) { [weak self] date in
                self?.parent.onSelectDate(date)
            }
            return cell
        }

        // MARK: Prefetching

        func collectionView(_ cv: UICollectionView, prefetchItemsAt indexPaths: [IndexPath]) {
            for ip in indexPaths {
                _ = monthData(for: ip.item)
            }
        }

        func collectionView(_ cv: UICollectionView, cancelPrefetchingForItemsAt indexPaths: [IndexPath]) {
            // Optional: no-op, cache handles eviction
        }

        // MARK: Scroll tracking

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            guard !suppressVisibleYearUpdates else { return }
            guard let cv = collectionView else { return }
            let visiblePaths = cv.indexPathsForVisibleItems
            guard let midPath = visiblePaths.sorted(by: { $0.item < $1.item })
                .first(where: { _ in true }) else { return }

            // Pick the cell closest to center
            let centerY = scrollView.contentOffset.y + scrollView.bounds.height / 2
            var closest: IndexPath?
            var closestDist = CGFloat.greatestFiniteMagnitude
            for ip in visiblePaths {
                if let attrs = cv.layoutAttributesForItem(at: ip) {
                    let dist = abs(attrs.frame.midY - centerY)
                    if dist < closestDist {
                        closestDist = dist
                        closest = ip
                    }
                }
            }
            let path = closest ?? midPath
            let (year, _) = yearMonthForIndex(path.item)
            if year != lastReportedYear {
                lastReportedYear = year
                parent.onVisibleYearChanged(year)
            }
        }

        // MARK: Helpers

        func scrollToDate(_ date: Date, animated: Bool) {
            let y = cal.component(.year, from: date)
            let m = cal.component(.month, from: date)
            let index = (y - MonthCalendarCollectionView.baseYear) * 12 + (m - 1)
            guard index >= 0, index < MonthCalendarCollectionView.totalMonths else { return }
            collectionView?.scrollToItem(at: IndexPath(item: index, section: 0),
                                         at: .top, animated: animated)
        }

        func setVisibleYearCallbacksEnabled(_ enabled: Bool) {
            suppressVisibleYearUpdates = !enabled
        }

        func reportYear(for date: Date) {
            let year = cal.component(.year, from: date)
            if year != lastReportedYear {
                lastReportedYear = year
                parent.onVisibleYearChanged(year)
            }
        }

        private func yearMonthForIndex(_ index: Int) -> (Int, Int) {
            let year = MonthCalendarCollectionView.baseYear + index / 12
            let month = (index % 12) + 1
            return (year, month)
        }

        func monthData(for index: Int) -> MonthRenderData {
            let key = NSNumber(value: index)
            if let cached = monthDataCache.object(forKey: key) { return cached }

            let (year, month) = yearMonthForIndex(index)
            let data = MonthRenderData.build(year: year, month: month, calendar: cal)
            monthDataCache.setObject(data, forKey: key)
            return data
        }
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Month data model
// ═══════════════════════════════════════════════════════════════════

/// Pre-computed render data for one month. Held by NSCache, auto-evicted.
final class MonthRenderData: NSObject {
    let year: Int
    let month: Int
    let title: String
    let weeks: [WeekRenderData]

    struct DayCellData {
        let date: Date
        let day: Int
        let isToday: Bool
    }

    struct WeekRenderData {
        let weekNum: Int
        let days: [DayCellData?] // Always length 7
    }

    init(year: Int, month: Int, title: String, weeks: [WeekRenderData]) {
        self.year = year
        self.month = month
        self.title = title
        self.weeks = weeks
    }

    static let titleFormatter: DateFormatter = {
        let f = DateFormatter(); f.locale = .autoupdatingCurrent; f.dateFormat = "LLLL"; return f
    }()

    static func build(year: Int, month: Int, calendar: Calendar) -> MonthRenderData {
        var comps = DateComponents(); comps.year = year; comps.month = month; comps.day = 1
        guard let firstDay = calendar.date(from: comps),
              let daysRange = calendar.range(of: .day, in: .month, for: firstDay) else {
            return MonthRenderData(year: year, month: month, title: "", weeks: [])
        }

        let title = titleFormatter.string(from: firstDay)
        let weekday = calendar.component(.weekday, from: firstDay)
        let leadingEmpty = (weekday - calendar.firstWeekday + 7) % 7

        // Build flat grid
        var grid: [Date?] = Array(repeating: nil, count: leadingEmpty)
        for day in daysRange {
            if let d = calendar.date(byAdding: .day, value: day - 1, to: firstDay) {
                grid.append(calendar.startOfDay(for: d))
            }
        }
        while grid.count % 7 != 0 { grid.append(nil) }

        let today = calendar.startOfDay(for: Date())

        // Chunk into weeks
        var weeks: [WeekRenderData] = []
        for start in stride(from: 0, to: grid.count, by: 7) {
            let end = min(start + 7, grid.count)
            var weekCells = Array(grid[start..<end])
            while weekCells.count < 7 { weekCells.append(nil) }

            let refDate = weekCells.compactMap { $0 }.first ?? firstDay
            let weekNum = calendar.component(.weekOfYear, from: refDate)

            let days: [DayCellData?] = weekCells.map { date in
                guard let date else { return nil }
                let dayNum = calendar.component(.day, from: date)
                return DayCellData(
                    date: date,
                    day: dayNum,
                    isToday: calendar.isDate(date, inSameDayAs: today)
                )
            }
            weeks.append(WeekRenderData(weekNum: weekNum, days: days))
        }

        return MonthRenderData(year: year, month: month, title: title, weeks: weeks)
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - MonthSectionCell (UICollectionViewCell hosting month UI)
// ═══════════════════════════════════════════════════════════════════

final class MonthSectionCell: UICollectionViewCell {
    static let reuseID = "MonthSectionCell"

    private var hostingController: UIHostingController<MonthCellContent>?
    private var tapHandler: ((Date) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.backgroundColor = .clear
        backgroundColor = .clear
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(with data: MonthRenderData, selectedDate: Date, calendar: Calendar,
                   onTap: @escaping (Date) -> Void) {
        self.tapHandler = onTap

        let content = MonthCellContent(data: data, selectedDate: selectedDate,
                                        calendar: calendar, onTap: onTap)

        if let hc = hostingController {
            hc.rootView = content
            hc.view.invalidateIntrinsicContentSize()
        } else {
            let hc = UIHostingController(rootView: content)
            hc.view.backgroundColor = .clear
            hc.view.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(hc.view)
            NSLayoutConstraint.activate([
                hc.view.topAnchor.constraint(equalTo: contentView.topAnchor),
                hc.view.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
                hc.view.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
                hc.view.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            ])
            hostingController = hc
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        // hostingController stays — just rootView will be swapped
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - SwiftUI content for a single month cell
// ═══════════════════════════════════════════════════════════════════

struct MonthCellContent: View {
    @Bindable private var settings: AppSettings = .shared

    let data: MonthRenderData
    let selectedDate: Date
    let calendar: Calendar
    let onTap: (Date) -> Void

    private var weekdaySymbols: [String] {
        var cal = Calendar.current
        cal.firstWeekday = AppSettings.shared.firstDayOfWeek
        let f = DateFormatter()
        f.locale = .autoupdatingCurrent
        let symbols = f.veryShortStandaloneWeekdaySymbols ?? f.veryShortWeekdaySymbols ?? []
        guard symbols.count == 7 else { return ["S","M","T","W","T","F","S"] }
        let start = max(0, cal.firstWeekday - 1)
        return Array(symbols[start...] + symbols[..<start])
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Month title
            Text(data.title)
                .font(.system(size: 32, weight: .bold))
                .padding(.horizontal, 4)

            // Weekday symbols
            HStack(spacing: 8) {
                ForEach(weekdaySymbols, id: \.self) { symbol in
                    Text(symbol)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 2)

            // Week rows
            VStack(spacing: 0) {
                ForEach(Array(data.weeks.enumerated()), id: \.offset) { index, week in
                    HStack(alignment: .top, spacing: 8) {
                        Text("\(week.weekNum)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .frame(width: 22, height: 44, alignment: .trailing)

                        HStack(spacing: 8) {
                            ForEach(0..<7, id: \.self) { i in
                                dayCellView(week.days[i])
                            }
                        }
                    }
                    if index < data.weeks.count - 1 {
                        Divider()
                            .overlay(Color.secondary.opacity(0.35))
                            .padding(.leading, 30)
                            .padding(.vertical, 3)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func dayCellView(_ info: MonthRenderData.DayCellData?) -> some View {
        if let info {
            let isSelected = calendar.isDate(info.date, inSameDayAs: selectedDate)
            let isToday = info.isToday

            Button {
                onTap(info.date)
            } label: {
                VStack(spacing: 1) {
                    Text("\(info.day)")
                        .font(.system(size: 17, weight: isSelected ? .bold : .regular, design: .rounded))
                        .foregroundStyle(isToday || isSelected ? .white : .primary)
                        .frame(width: 28, height: 28)
                        .background {
                            if isToday {
                                Circle().fill(AppTheme.danger)
                            } else if isSelected {
                                Circle().fill(AppTheme.accent)
                            }
                        }
                        .clipShape(Circle())

                    if settings.showAlternativeCalendar {
                        Text(alternativeDayLabel(for: info.date))
                            .font(.system(size: 8))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.plain)
        } else {
            Color.clear.frame(maxWidth: .infinity, minHeight: 44)
        }
    }

    private func alternativeDayLabel(for date: Date) -> String {
        switch settings.alternativeCalendarOption {
        case .bangla:
            return "\(date.banglaDate)"
        default:
            guard let identifier = settings.alternativeCalendarOption.calendarIdentifier else {
                return "\(date.banglaDate)"
            }
            let altCalendar = Calendar(identifier: identifier)
            let day = altCalendar.component(.day, from: date)
            return "\(day)"
        }
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Year Calendar (UICollectionView + CompositionalLayout)
// ═══════════════════════════════════════════════════════════════════

struct YearCalendarCollectionView: UIViewRepresentable {
    let selectedDate: Date
    let onSelectMonth: (Int, Int) -> Void // year, month
    let onVisibleYearChanged: (Int) -> Void
    let jumpToTodayTrigger: UUID

    private static var calendar: Calendar {
        var calendar = Calendar.current
        calendar.firstWeekday = AppSettings.shared.firstDayOfWeek
        return calendar
    }
    private static let baseYear = 1900
    private static let totalYears = 200 // 1900–2099

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> UICollectionView {
        let layout = createCompositionalLayout()
        let cv = UICollectionView(frame: .zero, collectionViewLayout: layout)
        cv.backgroundColor = .clear
        cv.showsVerticalScrollIndicator = false
        cv.contentInsetAdjustmentBehavior = .automatic

        cv.register(YearSectionCell.self, forCellWithReuseIdentifier: YearSectionCell.reuseID)

        cv.dataSource = context.coordinator
        cv.delegate = context.coordinator
        cv.prefetchDataSource = context.coordinator

        context.coordinator.collectionView = cv

        context.coordinator.setVisibleYearCallbacksEnabled(false)
        DispatchQueue.main.async {
            let target = Self.calendar.component(.year, from: self.selectedDate)
            context.coordinator.scrollToYear(target, animated: false)
            DispatchQueue.main.async {
                context.coordinator.reportYear(target)
                context.coordinator.setVisibleYearCallbacksEnabled(true)
            }
        }

        return cv
    }

    func updateUIView(_ cv: UICollectionView, context: Context) {
        let coord = context.coordinator
        coord.parent = self

        if coord.lastJumpTrigger != jumpToTodayTrigger {
            coord.lastJumpTrigger = jumpToTodayTrigger
            let target = Self.calendar.component(.year, from: Date())
            coord.setVisibleYearCallbacksEnabled(false)
            coord.scrollToYear(target, animated: false)
            DispatchQueue.main.async {
                coord.reportYear(target)
                coord.setVisibleYearCallbacksEnabled(true)
            }
        }
    }

    private func createCompositionalLayout() -> UICollectionViewCompositionalLayout {
        UICollectionViewCompositionalLayout { _, environment in
            let itemSize = NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(1.0),
                heightDimension: .estimated(700) // ~year section height
            )
            let item = NSCollectionLayoutItem(layoutSize: itemSize)
            let group = NSCollectionLayoutGroup.vertical(layoutSize: itemSize, subitems: [item])
            let section = NSCollectionLayoutSection(group: group)
            section.interGroupSpacing = 28
            section.contentInsets = NSDirectionalEdgeInsets(top: 16, leading: 14, bottom: 100, trailing: 14)
            return section
        }
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, UICollectionViewDataSource, UICollectionViewDelegate,
                              UICollectionViewDataSourcePrefetching {
        var parent: YearCalendarCollectionView
        weak var collectionView: UICollectionView?
        var lastJumpTrigger: UUID = UUID()
        private var cal: Calendar {
            YearCalendarCollectionView.calendar
        }
        private var lastReportedYear: Int = 0
        private var suppressVisibleYearUpdates = true

        private var yearDataCache = NSCache<NSNumber, YearRenderData>()

        init(parent: YearCalendarCollectionView) {
            self.parent = parent
            self.yearDataCache.countLimit = 12
        }

        func collectionView(_ cv: UICollectionView, numberOfItemsInSection section: Int) -> Int {
            YearCalendarCollectionView.totalYears
        }

        func collectionView(_ cv: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
            let cell = cv.dequeueReusableCell(withReuseIdentifier: YearSectionCell.reuseID, for: indexPath) as! YearSectionCell
            let year = YearCalendarCollectionView.baseYear + indexPath.item
            let data = yearData(for: year)
            cell.configure(with: data, calendar: cal) { [weak self] year, month in
                self?.parent.onSelectMonth(year, month)
            }
            return cell
        }

        func collectionView(_ cv: UICollectionView, prefetchItemsAt indexPaths: [IndexPath]) {
            for ip in indexPaths {
                let year = YearCalendarCollectionView.baseYear + ip.item
                _ = yearData(for: year)
            }
        }

        func collectionView(_ cv: UICollectionView, cancelPrefetchingForItemsAt indexPaths: [IndexPath]) {}

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            guard !suppressVisibleYearUpdates else { return }
            guard let cv = collectionView else { return }
            let centerY = scrollView.contentOffset.y + scrollView.bounds.height / 3
            var closest: IndexPath?
            var closestDist = CGFloat.greatestFiniteMagnitude
            for ip in cv.indexPathsForVisibleItems {
                if let attrs = cv.layoutAttributesForItem(at: ip) {
                    let dist = abs(attrs.frame.midY - centerY)
                    if dist < closestDist { closestDist = dist; closest = ip }
                }
            }
            if let closest {
                let year = YearCalendarCollectionView.baseYear + closest.item
                if year != lastReportedYear {
                    lastReportedYear = year
                    parent.onVisibleYearChanged(year)
                }
            }
        }

        func scrollToYear(_ year: Int, animated: Bool) {
            let index = year - YearCalendarCollectionView.baseYear
            guard index >= 0, index < YearCalendarCollectionView.totalYears else { return }
            collectionView?.scrollToItem(at: IndexPath(item: index, section: 0),
                                         at: .top, animated: animated)
        }

        func setVisibleYearCallbacksEnabled(_ enabled: Bool) {
            suppressVisibleYearUpdates = !enabled
        }

        func reportYear(_ year: Int) {
            if year != lastReportedYear {
                lastReportedYear = year
                parent.onVisibleYearChanged(year)
            }
        }

        private func yearData(for year: Int) -> YearRenderData {
            let key = NSNumber(value: year)
            if let cached = yearDataCache.object(forKey: key) { return cached }
            let data = YearRenderData.build(year: year, calendar: cal)
            yearDataCache.setObject(data, forKey: key)
            return data
        }
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Year data model
// ═══════════════════════════════════════════════════════════════════

final class YearRenderData: NSObject {
    let year: Int
    let months: [MiniMonth]

    struct MiniMonth {
        let month: Int
        let grid: [Int?] // Day numbers or nil for empty cells
        let isCurrentMonth: Bool
    }

    init(year: Int, months: [MiniMonth]) {
        self.year = year
        self.months = months
    }

    static func build(year: Int, calendar: Calendar) -> YearRenderData {
        let now = Date()
        let currentYear = calendar.component(.year, from: now)
        let currentMonth = calendar.component(.month, from: now)

        let months = (1...12).map { month -> MiniMonth in
            var comps = DateComponents(); comps.year = year; comps.month = month; comps.day = 1
            guard let firstDay = calendar.date(from: comps),
                  let daysRange = calendar.range(of: .day, in: .month, for: firstDay) else {
                return MiniMonth(month: month, grid: [], isCurrentMonth: false)
            }
            let firstWeekday = calendar.component(.weekday, from: firstDay)
            let leadingEmpty = (firstWeekday - calendar.firstWeekday + 7) % 7
            var vals: [Int?] = Array(repeating: nil, count: leadingEmpty)
            vals.append(contentsOf: daysRange.map { Optional($0) })
            while vals.count % 7 != 0 { vals.append(nil) }
            return MiniMonth(month: month, grid: vals,
                             isCurrentMonth: year == currentYear && month == currentMonth)
        }

        return YearRenderData(year: year, months: months)
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - YearSectionCell
// ═══════════════════════════════════════════════════════════════════

final class YearSectionCell: UICollectionViewCell {
    static let reuseID = "YearSectionCell"

    private var hostingController: UIHostingController<YearCellContent>?

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.backgroundColor = .clear
        backgroundColor = .clear
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(with data: YearRenderData, calendar: Calendar,
                   onSelectMonth: @escaping (Int, Int) -> Void) {
        let content = YearCellContent(data: data, calendar: calendar, onSelectMonth: onSelectMonth)

        if let hc = hostingController {
            hc.rootView = content
            hc.view.invalidateIntrinsicContentSize()
        } else {
            let hc = UIHostingController(rootView: content)
            hc.view.backgroundColor = .clear
            hc.view.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(hc.view)
            NSLayoutConstraint.activate([
                hc.view.topAnchor.constraint(equalTo: contentView.topAnchor),
                hc.view.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
                hc.view.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
                hc.view.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            ])
            hostingController = hc
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - SwiftUI content for a single year cell
// ═══════════════════════════════════════════════════════════════════

struct YearCellContent: View {
    let data: YearRenderData
    let calendar: Calendar
    let onSelectMonth: (Int, Int) -> Void

    private static let shortMonthSymbols: [String] = {
        let f = DateFormatter(); f.locale = .autoupdatingCurrent
        return f.shortMonthSymbols ?? []
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(verbatim: String(format: "%d", data.year))
                .font(.system(size: 44, weight: .bold))
                .foregroundStyle(AppTheme.danger)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 12) {
                ForEach(data.months, id: \.month) { mini in
                    miniMonthButton(mini)
                        .frame(maxHeight: .infinity, alignment: .top)
                }
            }
        }
    }

    private func miniMonthButton(_ mini: YearRenderData.MiniMonth) -> some View {
        Button {
            onSelectMonth(data.year, mini.month)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Text(shortMonthSymbol(for: mini.month))
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(mini.isCurrentMonth ? AppTheme.danger : .primary)

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 7), spacing: 3) {
                    ForEach(Array(mini.grid.enumerated()), id: \.offset) { _, day in
                        if let day {
                            let todayMark = isTodayDay(day, month: mini.month, year: data.year)
                            Text("\(day)")
                                .font(.system(size: 11, weight: .regular, design: .rounded))
                                .monospacedDigit()
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                                .foregroundStyle(todayMark ? Color.white : Color.primary)
                                .frame(width: 16, height: 18)
                                .frame(maxWidth: .infinity)
                                .background(Circle().fill(todayMark ? AppTheme.danger : Color.clear))
                        } else {
                            Color.clear.frame(maxWidth: .infinity, minHeight: 18)
                        }
                    }
                }
            }
            .frame(minHeight: 140, alignment: .topLeading)
        }
        .buttonStyle(.plain)
    }

    private func shortMonthSymbol(for month: Int) -> String {
        guard month >= 1, month <= Self.shortMonthSymbols.count else { return "" }
        return Self.shortMonthSymbols[month - 1]
    }

    private func isTodayDay(_ day: Int, month: Int, year: Int) -> Bool {
        let t = Date()
        return calendar.component(.year, from: t) == year
            && calendar.component(.month, from: t) == month
            && calendar.component(.day, from: t) == day
    }
}
