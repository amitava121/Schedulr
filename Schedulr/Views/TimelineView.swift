import SwiftUI

struct TimelineView: View {
    var hourHeight: CGFloat = TimelineConstants.weekHourHeight
    var showHalfHours: Bool = false

    private static func hourLabels() -> [Int: String] {
        var labels: [Int: String] = [:]
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        switch AppSettings.shared.timeFormatPreference {
        case .system:
            formatter.setLocalizedDateFormatFromTemplate("ha")
        case .twelveHour:
            formatter.dateFormat = "ha"
        case .twentyFourHour:
            formatter.dateFormat = "HH"
        }
        let calendar = Calendar.current
        let baseDate = Date()

        for hour in 0..<24 {
            let date = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: baseDate) ?? baseDate
            labels[hour] = formatter.string(from: date).lowercased()
        }
        return labels
    }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(TimelineConstants.startHour..<TimelineConstants.endHour, id: \.self) { hour in
                HStack(alignment: .top, spacing: 4) {
                    Text(hourLabel(hour))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .frame(width: 36, alignment: .trailing)

                    VStack(spacing: 0) {
                        Divider()
                            .foregroundStyle(.quaternary)

                        if showHalfHours {
                            Spacer()
                            Divider()
                                .foregroundStyle(.quaternary.opacity(0.5))
                        }

                        Spacer()
                    }
                }
                .frame(height: hourHeight)
            }
        }
    }

    private func hourLabel(_ hour: Int) -> String {
        Self.hourLabels()[hour] ?? "\(hour)"
    }
}

struct TimelineOverlayView: View {
    let schedules: [Schedule]
    var hourHeight: CGFloat = TimelineConstants.weekHourHeight
    var isCompact: Bool = true
    var onTapSchedule: ((Schedule) -> Void)? = nil
    var onDeleteSchedule: ((Schedule) -> Void)? = nil

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(schedules, id: \.id) { schedule in
                ScheduleCardView(
                    schedule: schedule,
                    isCompact: isCompact,
                    onTap: { onTapSchedule?(schedule) },
                    onDelete: { onDeleteSchedule?(schedule) }
                )
                .padding(.leading, 40)
                .padding(.trailing, 4)
                .offset(y: yOffset(for: schedule))
            }
        }
        .frame(
            height: CGFloat(TimelineConstants.totalHours) * hourHeight,
            alignment: .topLeading
        )
    }

    private func yOffset(for schedule: Schedule) -> CGFloat {
        let offset = schedule.hourOffset - CGFloat(TimelineConstants.startHour)
        return max(0, offset * hourHeight)
    }
}
