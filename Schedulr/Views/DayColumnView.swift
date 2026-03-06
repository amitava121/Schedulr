import SwiftUI

struct DayColumnView: View {
    let date: Date
    let schedules: [Schedule]
    let hourHeight: CGFloat
    var onTapSchedule: ((Schedule) -> Void)? = nil
    var onDeleteSchedule: ((Schedule) -> Void)? = nil

    var body: some View {
        VStack(spacing: 0) {
            dayHeader
            ScrollView(.vertical, showsIndicators: false) {
                ZStack(alignment: .topLeading) {
                    TimelineView(hourHeight: hourHeight)
                    TimelineOverlayView(
                        schedules: schedules,
                        hourHeight: hourHeight,
                        isCompact: true,
                        onTapSchedule: onTapSchedule,
                        onDeleteSchedule: onDeleteSchedule
                    )
                }
            }
        }
    }

    private var dayHeader: some View {
        VStack(spacing: 2) {
            Text(date.shortDayName)
                .font(.caption.weight(.bold))
                .foregroundStyle(date.isToday ? AppTheme.accent : .secondary)

            Text(date.dayNumber)
                .font(.title3.weight(.heavy))
                .foregroundStyle(date.isToday ? .white : .primary)
                .frame(width: 32, height: 32)
                .glassEffect(
                    .regular
                        .tint(
                            date.isToday
                                ? AppTheme.accentSoft.opacity(0.68)
                                : Color.clear
                        ),
                    in: Circle()
                )
        }
        .padding(.vertical, 8)
    }
}
