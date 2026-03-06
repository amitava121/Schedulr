import SwiftUI

struct ScheduleCardView: View {
    @Environment(\.colorScheme) private var colorScheme
    let schedule: Schedule
    var isCompact: Bool = true
    var showTrailingTime: Bool = true
    var completionOverride: Bool? = nil
    var onTap: (() -> Void)? = nil
    var onDelete: (() -> Void)? = nil

    private let cardShape = RoundedRectangle(cornerRadius: TimelineConstants.cardCornerRadius, style: .continuous)
    private var isEffectivelyCompleted: Bool {
        completionOverride ?? schedule.isCompleted
    }
    private var isOverdue: Bool {
        !isEffectivelyCompleted && schedule.repeatPattern == .never && schedule.scheduledDate < Date()
    }

    var body: some View {
        Group {
            if let onDelete {
                tappableCard
                    .contextMenu {
                        Button(role: .destructive) {
                            onDelete()
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
            } else {
                tappableCard
            }
        }
    }

    @ViewBuilder
    private var tappableCard: some View {
        if let onTap {
            Button(action: onTap) {
                cardContent
            }
            .buttonStyle(CardButtonStyle())
            .contentShape(cardShape)
        } else {
            cardContent
                .contentShape(cardShape)
        }
    }

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: isCompact ? 5 : 9) {
            headerRow
            if !isCompact {
                detailSection
            }
        }
        .padding(isCompact ? 9 : 13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            cardShape.fill(
                AppTheme.stackCardGradient(
                    for: colorScheme,
                    priority: schedule.priority,
                    completed: isEffectivelyCompleted
                )
            )
        )
        .opacity(isEffectivelyCompleted ? 0.72 : 1)
        .overlay {
            ZStack {
                cardShape
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(colorScheme == .dark ? 0.14 : 0.38),
                                Color.clear
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .blendMode(.screen)

                if schedule.isUrgent {
                    cardShape
                        .strokeBorder(AppTheme.danger.opacity(0.55), lineWidth: 1.6)
                }
                if isEffectivelyCompleted {
                    cardShape
                        .strokeBorder(AppTheme.success.opacity(0.52), lineWidth: 1.5)
                }

                cardShape
                    .strokeBorder(
                        AppTheme.stackCardBorder(
                            for: colorScheme,
                            priority: schedule.priority,
                            completed: isEffectivelyCompleted
                        ),
                        lineWidth: 1.0
                    )
            }
        }
        .shadow(color: AppTheme.cardShadow(for: colorScheme), radius: 8, y: 3)
    }

    // MARK: - Header

    private var headerRow: some View {
        HStack(spacing: 6) {
            if schedule.isUrgent {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(isCompact ? .caption2 : .caption)
                    .foregroundStyle(AppTheme.danger)
                    .symbolRenderingMode(.hierarchical)
            }

            Text(schedule.title)
                .font(isCompact ? .caption.weight(.semibold) : .subheadline.weight(.heavy))
                .foregroundStyle(isEffectivelyCompleted ? .secondary : .primary)
                .strikethrough(isEffectivelyCompleted, color: .secondary)
                .lineLimit(isCompact ? 1 : 2)

            Spacer(minLength: 0)

            if schedule.isFlagged {
                Image(systemName: "flag.fill")
                    .font(.caption2)
                    .foregroundStyle(AppTheme.warning)
            }

            if showTrailingTime {
                Text(schedule.timeString)
                    .font(isCompact ? .caption2.weight(.medium) : .caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            if isOverdue {
                Text("Overdue")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(AppTheme.danger)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(AppTheme.danger.opacity(0.14), in: Capsule(style: .continuous))
            }
        }
    }

    // MARK: - Details

    private var detailSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let notes = schedule.notes, !notes.isEmpty {
                Text(notes)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }

            if let rawURL = schedule.urlString?.trimmingCharacters(in: .whitespacesAndNewlines),
               !rawURL.isEmpty
            {
                if let url = URL(string: rawURL), let scheme = url.scheme, !scheme.isEmpty {
                    Link(destination: url) {
                        Label(url.absoluteString, systemImage: "link")
                            .font(.caption)
                            .foregroundStyle(AppTheme.accent)
                            .lineLimit(1)
                    }
                } else {
                    Label(rawURL, systemImage: "link")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Label("\(schedule.dateString) • \(schedule.timeString)", systemImage: "calendar")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Label(
                    schedule.alertDeliveryOption.displayName,
                    systemImage: schedule.alertDeliveryOption == .alarm ? "alarm" : "bell.badge"
                )
                Label(schedule.repeatPattern.displayName, systemImage: "repeat")
                Image(systemName: schedule.priority.iconName)
                    .foregroundStyle(schedule.priority == .none ? .secondary : schedule.priority.tintColor)
                    .accessibilityLabel("Priority \(schedule.priority.displayName)")

                if let earlyReminderMinutes = schedule.earlyReminderMinutes {
                    Label("\(earlyReminderMinutes)m early", systemImage: "clock.badge")
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)

            if !schedule.tags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 5) {
                        ForEach(schedule.tags, id: \.self) { tag in
                            Text(tag)
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(AppTheme.chipFill(for: colorScheme), in: Capsule())
                        }
                    }
                }
            }
        }
    }
}

struct CardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }
}
