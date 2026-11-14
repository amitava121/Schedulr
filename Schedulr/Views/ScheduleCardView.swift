import SwiftUI
import SchedulrLogic
import UIKit

struct ScheduleCardView: View {
    @Environment(\.colorScheme) private var colorScheme
    let schedule: Schedule
    var isCompact: Bool = true
    var showTrailingTime: Bool = true
    var headerTrailingPadding: CGFloat = 0
    var completionOverride: Bool? = nil
    var displayDate: Date? = nil
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

            if isCompact {
                Text(schedule.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isEffectivelyCompleted ? .secondary : .primary)
                    .strikethrough(isEffectivelyCompleted, color: .secondary)
                    .lineLimit(1)
            } else {
                FirstLineInsetTitle(
                    title: schedule.title,
                    trailingInset: headerTrailingPadding,
                    isCompleted: isEffectivelyCompleted
                )
                .fixedSize(horizontal: false, vertical: true)
            }

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

            if isOverdue && isCompact {
                overdueBadge
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

            HStack(spacing: 8) {
                Label("\(displayDateString) • \(schedule.timeString)", systemImage: "calendar")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer(minLength: 8)

                if isOverdue {
                    overdueBadge
                }
            }

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

    private var overdueBadge: some View {
        Text("Overdue")
            .font(.caption2.weight(.bold))
            .foregroundStyle(AppTheme.danger)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(AppTheme.danger.opacity(0.14), in: Capsule(style: .continuous))
    }

    private var displayDateString: String {
        schedule.dateString(for: displayDate ?? schedule.scheduledDate)
    }
}

private struct FirstLineInsetTitle: UIViewRepresentable {
    let title: String
    let trailingInset: CGFloat
    let isCompleted: Bool

    func makeUIView(context: Context) -> FirstLineExclusionTextView {
        let textView = FirstLineExclusionTextView()
        textView.isEditable = false
        textView.isSelectable = false
        textView.isScrollEnabled = false
        textView.isUserInteractionEnabled = false
        textView.backgroundColor = .clear
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.textContainer.lineBreakMode = .byWordWrapping
        textView.textContainer.maximumNumberOfLines = 0
        textView.textContainer.widthTracksTextView = true
        textView.dataDetectorTypes = []
        textView.accessibilityTraits = .staticText
        return textView
    }

    func updateUIView(_ textView: FirstLineExclusionTextView, context: Context) {
        let pointSize = UIFont.preferredFont(forTextStyle: .subheadline).pointSize
        let font = UIFont.systemFont(ofSize: pointSize, weight: .heavy)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: isCompleted ? UIColor.secondaryLabel : UIColor.label,
            .strikethroughStyle: isCompleted ? NSUnderlineStyle.single.rawValue : 0,
            .strikethroughColor: UIColor.secondaryLabel
        ]

        textView.trailingInset = trailingInset
        textView.font = font
        textView.attributedText = NSAttributedString(string: title, attributes: attributes)
        textView.accessibilityLabel = title
        textView.updateExclusion()
        textView.invalidateIntrinsicContentSize()
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        uiView: FirstLineExclusionTextView,
        context: Context
    ) -> CGSize? {
        guard let width = proposal.width else { return nil }
        uiView.updateExclusion(width: width)
        let size = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: size.height)
    }
}

private final class FirstLineExclusionTextView: UITextView {
    var trailingInset: CGFloat = 0 {
        didSet {
            setNeedsLayout()
            invalidateIntrinsicContentSize()
        }
    }

    override func layoutSubviews() {
        updateExclusion()
        super.layoutSubviews()
    }

    func updateExclusion(width: CGFloat? = nil) {
        let availableWidth = width ?? bounds.width
        guard availableWidth.isFinite, availableWidth > 0 else { return }

        guard trailingInset > 0 else {
            textContainer.exclusionPaths = []
            return
        }

        let firstLineHeight = max(1, (font?.lineHeight ?? 20) - 1)
        let exclusion = CGRect(
            x: availableWidth - trailingInset,
            y: 0,
            width: trailingInset,
            height: firstLineHeight
        )
        textContainer.exclusionPaths = [UIBezierPath(rect: exclusion)]
    }
}

struct CardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }
}
