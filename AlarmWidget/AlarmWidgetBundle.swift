import SwiftUI
import WidgetKit
import AppIntents
import ActivityKit

struct AlarmActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var scheduleTitle: String
        var scheduledTime: Date
        var isSnoozing: Bool
        var snoozeUntil: Date?
        var elapsedSeconds: Int
    }

    var scheduleID: String
    var alarmSoundName: String
}

@main
struct AlarmWidgetBundle: WidgetBundle {
    var body: some Widget {
        AlarmStatusWidget()
        if #available(iOSApplicationExtension 16.1, *) {
            AlarmLiveActivityWidget()
        }
    }
}

@available(iOSApplicationExtension 16.1, *)
private struct AlarmLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AlarmActivityAttributes.self) { context in
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: context.state.isSnoozing ? "zzz" : "alarm.fill")
                        .foregroundStyle(.red)
                    Text(context.state.isSnoozing ? "Alarm Snoozed" : "Alarm Active")
                        .font(.headline)
                }

                Text(context.state.scheduleTitle)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)

                if context.state.isSnoozing, let snoozeUntil = context.state.snoozeUntil {
                    Text("Snoozed until \(snoozeUntil, style: .time)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Scheduled at \(context.state.scheduledTime, style: .time)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .activityBackgroundTint(Color.black.opacity(0.2))
            .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: context.state.isSnoozing ? "zzz" : "alarm.fill")
                        .foregroundStyle(.red)
                }

                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.isSnoozing ? "Snoozed" : "Ringing")
                        .font(.caption2.weight(.semibold))
                }

                DynamicIslandExpandedRegion(.center) {
                    Text(context.state.scheduleTitle)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                }

                DynamicIslandExpandedRegion(.bottom) {
                    if context.state.isSnoozing, let snoozeUntil = context.state.snoozeUntil {
                        Text("Until \(snoozeUntil, style: .time)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Alarm at \(context.state.scheduledTime, style: .time)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } compactLeading: {
                Image(systemName: context.state.isSnoozing ? "zzz" : "alarm.fill")
            } compactTrailing: {
                Text(context.state.isSnoozing ? "ZZZ" : "ALM")
                    .font(.caption2.weight(.semibold))
            } minimal: {
                Image(systemName: context.state.isSnoozing ? "zzz" : "alarm.fill")
            }
            .keylineTint(.red)
        }
    }
}

private struct AlarmEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetScheduleSnapshot
}

private struct AlarmProvider: TimelineProvider {
    private static let appGroupID = "group.com.bittu.Schedulr"
    private static let snapshotKey = "widget.scheduleSnapshot.v1"

    func placeholder(in context: Context) -> AlarmEntry {
        AlarmEntry(date: Date(), snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (AlarmEntry) -> Void) {
        completion(AlarmEntry(date: Date(), snapshot: loadSnapshot() ?? .placeholder))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<AlarmEntry>) -> Void) {
        let now = Date()
        let snapshot = loadSnapshot() ?? .empty
        var entries: [AlarmEntry] = [AlarmEntry(date: now, snapshot: snapshot)]
        entries.append(contentsOf: transitionEntries(from: now, snapshot: snapshot))

        let nextRefresh = nextRefreshDate(from: now, snapshot: snapshot)
        let timeline = Timeline(entries: entries, policy: .after(nextRefresh))
        completion(timeline)
    }

    private func loadSnapshot() -> WidgetScheduleSnapshot? {
        guard let defaults = UserDefaults(suiteName: Self.appGroupID),
              let data = defaults.data(forKey: Self.snapshotKey)
        else {
            return nil
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(WidgetScheduleSnapshot.self, from: data)
    }

    private func nextRefreshDate(from now: Date, snapshot: WidgetScheduleSnapshot) -> Date {
        let fallback = now.addingTimeInterval(3 * 60)
        let nearestUpcoming = snapshot.upcoming
            .map(\.scheduledDate)
            .filter { $0 > now }
            .min()

        guard let nearestUpcoming else {
            return fallback
        }

        let nextEventRefresh = nearestUpcoming.addingTimeInterval(1)
        return min(fallback, max(nextEventRefresh, now.addingTimeInterval(10)))
    }

    private func transitionEntries(from now: Date, snapshot: WidgetScheduleSnapshot) -> [AlarmEntry] {
        let transitionDates = (snapshot.upcoming + snapshot.past)
            .map(\.scheduledDate)
            .filter { $0 > now }
            .map { $0.addingTimeInterval(1) }
            .sorted()

        var unique: [Date] = []
        unique.reserveCapacity(transitionDates.count)
        for date in transitionDates {
            if let last = unique.last,
               abs(last.timeIntervalSince(date)) < 0.5
            {
                continue
            }
            unique.append(date)
        }

        return unique.prefix(12).map { AlarmEntry(date: $0, snapshot: snapshot) }
    }
}

private struct AlarmStatusWidget: Widget {
    let kind = "AlarmStatusWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: AlarmProvider()) { entry in
            AlarmStatusView(entry: entry)
        }
        .configurationDisplayName("Schedulr")
        .description("Quick reminder glance view.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge])
        .contentMarginsDisabled()
    }
}

private struct AlarmStatusView: View {
    @Environment(\.widgetFamily) private var family
    let entry: AlarmEntry

    private enum SectionKind {
        case upcoming
        case past

        func title(for count: Int) -> String {
            switch self {
            case .upcoming:
                return count == 1 ? "Upcoming schedule" : "Upcoming schedules"
            case .past:
                return count == 1 ? "Past schedule" : "Past schedules"
            }
        }
    }

    private struct ScheduleSection {
        let kind: SectionKind
        let items: [WidgetScheduleItem]
    }

    // MARK: - Data helpers

    private var todaySchedules: [WidgetScheduleItem] {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: entry.date)
        let nextDay = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart

        let merged = (entry.snapshot.past + entry.snapshot.upcoming)
            .filter { $0.scheduledDate >= dayStart && $0.scheduledDate < nextDay }
            .sorted { $0.scheduledDate < $1.scheduledDate }

        var seen = Set<String>()
        return merged.filter { item in
            seen.insert(item.occurrenceID).inserted
        }
    }

    private var upcomingSchedules: [WidgetScheduleItem] {
        todaySchedules
            .filter { isUpcomingSchedule($0) }
            .sorted { $0.scheduledDate < $1.scheduledDate }
    }

    private var pastSchedules: [WidgetScheduleItem] {
        todaySchedules
            .filter { !isUpcomingSchedule($0) }
            .sorted { $0.scheduledDate < $1.scheduledDate }
    }

    private var smallSections: [ScheduleSection] {
        groupedSectionsForThreeRows()
    }

    private var mediumSchedule: WidgetScheduleItem? {
        upcomingSchedules.first ?? pastSchedules.last
    }

    private var largeSections: [ScheduleSection] {
        groupedSectionsForThreeRows()
    }

    private func isUpcomingSchedule(_ schedule: WidgetScheduleItem) -> Bool {
        schedule.scheduledDate >= entry.date && !schedule.isCompleted
    }

    private func groupedSectionsForThreeRows() -> [ScheduleSection] {
        let upcoming = upcomingSchedules
        let past = pastSchedules

        if upcoming.count >= 3 {
            return [ScheduleSection(kind: .upcoming, items: Array(upcoming.prefix(3)))]
        }

        let requiredPastCount: Int
        switch upcoming.count {
        case 2:
            requiredPastCount = 1
        case 1:
            requiredPastCount = 2
        default:
            requiredPastCount = 3
        }

        let selectedPast = Array(past.suffix(requiredPastCount))
        let selectedUpcoming = Array(upcoming.prefix(3 - selectedPast.count))

        var sections: [ScheduleSection] = []
        if !selectedPast.isEmpty {
            sections.append(ScheduleSection(kind: .past, items: selectedPast))
        }
        if !selectedUpcoming.isEmpty {
            sections.append(ScheduleSection(kind: .upcoming, items: selectedUpcoming))
        }

        // Fallback: if there are not enough past schedules, fill with remaining upcoming.
        if sections.isEmpty, !upcoming.isEmpty {
            sections.append(ScheduleSection(kind: .upcoming, items: Array(upcoming.prefix(3))))
        }

        return sections
    }

    // MARK: - Body

    var body: some View {
        Group {
            switch family {
            case .systemSmall:
                smallLayout
            case .systemMedium:
                mediumLayout
            case .systemLarge, .systemExtraLarge:
                largeLayout
            default:
                mediumLayout
            }
        }
        .unredacted()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .containerBackground(for: .widget) {
            Color(.systemBackground)
        }
    }

    // MARK: - Shared header

    private var compactDayText: String {
        let full = entry.date.formatted(.dateTime.weekday(.wide))
        return String(full.prefix(3)).uppercased()
    }

    private func headerText(compactWeekday: Bool) -> some View {
        HStack(alignment: .lastTextBaseline, spacing: 8) {
            Text(compactWeekday ? compactDayText : entry.date.formatted(.dateTime.weekday(.wide)))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.red)
                .textCase(.uppercase)
                .lineLimit(1)

            Text(entry.date, format: .dateTime.day())
                .font(.title2.weight(.bold))
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
        .padding(.trailing, 40)
    }

    private func headerRow(compactWeekday: Bool, showsIcon: Bool) -> some View {
        HStack(alignment: .top, spacing: 8) {
            HStack(alignment: .lastTextBaseline, spacing: 8) {
                Text(compactWeekday ? compactDayText : entry.date.formatted(.dateTime.weekday(.wide)))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.red)
                    .textCase(.uppercase)
                    .lineLimit(1)

                Text(entry.date, format: .dateTime.day())
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
            .padding(.trailing, 40)

            Spacer(minLength: 0)
            if showsIcon {
                cornerIcon
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var cornerIcon: some View {
        Image("WidgetAppGlyph")
            .resizable()
            .scaledToFit()
            .frame(width: 30, height: 30)
    }

    private var noScheduleText: some View {
        Text("No schedules for today")
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    private func sectionHeading(_ text: String) -> some View {
        Text(text)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }

    // MARK: - Small layout

    private var smallLayout: some View {
        ZStack(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: 4) {
                if smallSections.isEmpty {
                    noScheduleText
                } else {
                    ForEach(Array(smallSections.enumerated()), id: \.offset) { _, section in
                        VStack(alignment: .leading, spacing: 2) {
                            sectionHeading(section.kind.title(for: section.items.count))

                            ForEach(section.items, id: \.occurrenceID) { schedule in
                                HStack(alignment: .center, spacing: 5) {
                                    completionButton(for: schedule)
                                    Text(schedule.title)
                                        .font(.caption.weight(.semibold))
                                        .lineLimit(1)
                                        .offset(y: -1)
                                    Spacer(minLength: 0)
                                    Text(schedule.scheduledDate, format: .dateTime.hour().minute())
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }

                Spacer(minLength: 0)
            }
            // Keep section title directly below day/date while avoiding overlap.
            .padding(.top, 44)
            .padding(.leading, 10)
            .padding(.trailing, 24)
            .padding(.bottom, 10)

            headerText(compactWeekday: true)
                .padding(.top, 10)
                .padding(.leading, 10)
        }
        .overlay(alignment: .topTrailing) {
            cornerIcon
                .padding(.top, 10)
                .padding(.trailing, 10)
        }
    }

    // MARK: - Medium layout

    private var mediumLayout: some View {
        ZStack(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: 6) {
            if let schedule = mediumSchedule {
                sectionHeading(isUpcomingSchedule(schedule) ? "Upcoming schedule" : "Past schedule")

                HStack(alignment: .top, spacing: 8) {
                    // Keep the completion radio button at the far-left edge.
                    completionButton(for: schedule)

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(schedule.title)
                                .font(.headline.weight(.semibold))
                                .lineLimit(1)
                                .offset(y: -1)

                            Spacer(minLength: 0)

                            Text(schedule.scheduledDate, format: .dateTime.hour().minute())
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        if let notes = schedule.notes, !notes.isEmpty {
                            Text(notes)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .minimumScaleFactor(0.55)
                                .allowsTightening(true)
                        }

                        if let urlString = schedule.urlString, !urlString.isEmpty {
                            Label(urlString, systemImage: "link")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        HStack(spacing: 10) {
                            Label(schedule.deliveryName, systemImage: schedule.deliveryIcon)
                            Label(schedule.repeatPatternName, systemImage: "arrow.2.squarepath")
                            Label(schedule.normalizedPriorityName, systemImage: schedule.priorityIcon)
                                .foregroundStyle(schedule.priorityTint)

                            if let early = schedule.earlyReminderMinutes, early > 0 {
                                Label("\(early)m early", systemImage: "clock.badge")
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                noScheduleText
            }

            Spacer(minLength: 0)
        }
            // Keep section title directly below day/date while avoiding overlap.
            .padding(.top, 44)
            .padding(.leading, 12)
            .padding(.trailing, 24)
            .padding(.bottom, 10)

            headerRow(compactWeekday: false, showsIcon: true)
                .padding(.top, 10)
                .padding(.leading, 10)
                .padding(.trailing, 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Large layout (3 cards)

    private var largeLayout: some View {
        ZStack(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: 6) {
                if largeSections.isEmpty {
                    noScheduleText
                    Spacer(minLength: 0)
                } else {
                    ForEach(Array(largeSections.enumerated()), id: \.offset) { _, section in
                        VStack(alignment: .leading, spacing: 2) {
                            sectionHeading(section.kind.title(for: section.items.count))

                            ForEach(section.items, id: \.occurrenceID) { schedule in
                                scheduleCard(for: schedule)
                            }
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
            // Keep section title directly below day/date while avoiding overlap.
            .padding(.top, 44)
            .padding(.leading, 12)
            .padding(.trailing, 24)
            .padding(.bottom, 10)

            headerRow(compactWeekday: false, showsIcon: true)
                .padding(.top, 10)
                .padding(.leading, 10)
                .padding(.trailing, 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Reusable card row for large widget

    private func scheduleCard(for schedule: WidgetScheduleItem) -> some View {
        HStack(alignment: .top, spacing: 8) {
            completionButton(for: schedule)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(schedule.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .offset(y: -1)
                    Spacer(minLength: 0)
                    Text(schedule.scheduledDate, format: .dateTime.hour().minute())
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                Text(schedule.scheduledDate, format: .dateTime.day().month().year())
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    Label(schedule.deliveryName, systemImage: schedule.deliveryIcon)
                    Label(schedule.repeatPatternName, systemImage: "arrow.2.squarepath")
                    Label(schedule.normalizedPriorityName, systemImage: schedule.priorityIcon)
                        .foregroundStyle(schedule.priorityTint)
                    if let early = schedule.earlyReminderMinutes, early > 0 {
                        Label("\(early)m early", systemImage: "clock.badge")
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }

    // MARK: - Completion button

    private func completionButton(for schedule: WidgetScheduleItem) -> some View {
        Button(
            intent: MarkScheduleCompleteIntent(
                scheduleID: schedule.id,
                occurrenceDate: schedule.scheduledDate
            )
        ) {
            Image(systemName: schedule.isCompleted ? "checkmark.circle.fill" : "circle")
                .font(.callout)
                .foregroundStyle(schedule.isCompleted ? .green : .secondary)
                .frame(width: 18, height: 18)
        }
        .buttonStyle(.plain)
    }

}

private struct WidgetScheduleSnapshot: Codable {
    var updatedAt: Date
    var upcoming: [WidgetScheduleItem]
    var past: [WidgetScheduleItem]

    static let empty = WidgetScheduleSnapshot(updatedAt: Date(), upcoming: [], past: [])

    static let placeholder = WidgetScheduleSnapshot(
        updatedAt: Date(),
        upcoming: [
            WidgetScheduleItem(
                id: UUID().uuidString,
                title: "Standup Meeting",
                scheduledDate: Date().addingTimeInterval(60 * 60),
                notes: "Daily sync",
                urlString: nil,
                repeatPatternName: "Daily",
                deliveryName: "Alarm",
                priorityName: "Medium",
                earlyReminderMinutes: 5,
                isCompleted: false
            )
        ],
        past: [
            WidgetScheduleItem(
                id: UUID().uuidString,
                title: "Morning Review",
                scheduledDate: Date().addingTimeInterval(-60 * 60),
                notes: nil,
                urlString: nil,
                repeatPatternName: "Never",
                deliveryName: "Push",
                priorityName: "None",
                earlyReminderMinutes: nil,
                isCompleted: true
            )
        ]
    )
}

private struct WidgetScheduleItem: Codable {
    var id: String
    var title: String
    var scheduledDate: Date
    var notes: String?
    var urlString: String?
    var repeatPatternName: String
    var deliveryName: String
    var priorityName: String
    var earlyReminderMinutes: Int?
    var isCompleted: Bool

    var occurrenceID: String {
        "\(id)-\(scheduledDate.timeIntervalSince1970)"
    }

    var deliveryIcon: String {
        deliveryName.localizedCaseInsensitiveContains("alarm") ? "alarm" : "bell"
    }

    var priorityIcon: String {
        "exclamationmark.triangle"
    }

    var normalizedPriorityName: String {
        switch priorityName.lowercased() {
        case "high":
            return "HIGH"
        case "medium":
            return "MEDIUM"
        case "low":
            return "LOW"
        default:
            return "NONE"
        }
    }

    var priorityTint: Color {
        switch normalizedPriorityName {
        case "HIGH":
            return .red
        case "MEDIUM":
            return .orange
        case "LOW":
            return .yellow
        default:
            return .secondary
        }
    }
}

private struct MarkScheduleCompleteIntent: AppIntent {
    static var title: LocalizedStringResource = "Mark Schedule Complete"
    static var description = IntentDescription("Marks a schedule as complete from the widget.")
    static var openAppWhenRun: Bool = true

    @Parameter(title: "Schedule ID")
    var scheduleID: String

    @Parameter(title: "Occurrence Date")
    var occurrenceDate: Date

    init(scheduleID: String, occurrenceDate: Date) {
        self.scheduleID = scheduleID
        self.occurrenceDate = occurrenceDate
    }

    init() {
        self.scheduleID = ""
        self.occurrenceDate = Date()
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        var components = URLComponents()
        components.scheme = "schedulr"
        components.host = "complete"
        components.queryItems = [
            URLQueryItem(name: "scheduleID", value: scheduleID),
            URLQueryItem(name: "occurrence", value: String(occurrenceDate.timeIntervalSince1970))
        ]

        guard let url = components.url else {
            return .result()
        }

        return .result(opensIntent: OpenURLIntent(url))
    }
}
