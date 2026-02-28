import SwiftUI
#if os(iOS)
import UIKit
#endif

struct ScheduleFormView: View {
    private enum FocusField: Hashable {
        case title
        case notes
        case url
    }

    @Bindable var viewModel: ScheduleViewModel
    @State private var formVM = ScheduleFormViewModel()
    @State private var isKeyboardVisible = false
    @State private var isAlarmSoundPickerPresented = false
    @State private var alarmSoundPickerButtonFrame: CGRect = .zero
    @FocusState private var focusedField: FocusField?
    var editingSchedule: Schedule?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            formBackground
                .contentShape(Rectangle())
                .onTapGesture {
                    dismissKeyboard()
                    isAlarmSoundPickerPresented = false
                }

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 14) {
                    mainSection
                    dateTimeSection
                    detailsSection
                }
                .padding(.horizontal, 16)
                .padding(.top, 18)
                .padding(.bottom, contentBottomPadding)
            }
#if os(iOS)
            .defaultScrollAnchor(.top)
            .scrollDismissesKeyboard(.immediately)
#endif

            alarmSoundPickerOverlay
        }
        .coordinateSpace(name: "ScheduleFormSpace")
        .ignoresSafeArea(.keyboard, edges: .bottom)
#if os(macOS)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            formActionBar
        }
#endif
        .animation(nil, value: focusedField)
        .navigationTitle(formVM.isEditing ? "Edit Schedule" : "New Schedule")
#if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
#else
        .frame(minWidth: 640, minHeight: 780)
#endif
#if !os(macOS)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
                    .fontWeight(.semibold)
                    .disabled(!formVM.isValid)
                    .keyboardShortcut(.defaultAction)
            }
        }
#endif
        .onAppear {
#if os(iOS)
            KeyboardWarmup.prewarmIfNeeded()
#endif

            if let editingSchedule {
                formVM.configure(with: editingSchedule)
            } else {
                formVM.reset()
                if let pendingDate = viewModel.pendingNewScheduleDate {
                    formVM.scheduledDate = pendingDate
                }
            }
        }
        .onChange(of: formVM.repeatPattern) { _, _ in
            formVM.sanitizeRepeatEndConfiguration()
        }
        .onChange(of: formVM.scheduledDate) { _, _ in
            formVM.sanitizeRepeatEndConfiguration()
        }
#if os(iOS)
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            isKeyboardVisible = true
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            isKeyboardVisible = false
        }
        .onChange(of: isAlarmSoundPickerPresented) { _, isPresented in
            guard !isPresented else { return }
            NotificationManager.shared.stopPreviewAlarmSound()
        }
        .onChange(of: formVM.alertDeliveryOption) { _, delivery in
            guard delivery != .alarm else { return }
            isAlarmSoundPickerPresented = false
            NotificationManager.shared.stopPreviewAlarmSound()
        }
        .onDisappear {
            NotificationManager.shared.stopPreviewAlarmSound()
        }
        .onPreferenceChange(AlarmSoundPickerButtonFramePreferenceKey.self) { frame in
            guard !frame.isEmpty else { return }
            alarmSoundPickerButtonFrame = frame
        }
#endif
    }

    // MARK: - Sections

    private var mainSection: some View {
        ScheduleFormSectionCard(
            title: "Details",
            systemImage: "square.and.pencil",
            reduceEffects: isKeyboardVisible
        ) {
            VStack(alignment: .leading, spacing: 12) {
                inputField(
                    "Title",
                    text: $formVM.title,
                    prompt: "What should you do?",
                    focus: .title
                )

                inputField(
                    "Notes",
                    text: $formVM.notes,
                    prompt: "Optional notes",
                    axis: .vertical,
                    focus: .notes
                )

                inputField(
                    "URL",
                    text: $formVM.urlString,
                    prompt: "https://",
                    focus: .url
                )
#if os(iOS) || os(visionOS)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    .autocorrectionDisabled()
#else
                    .textCase(nil)
#endif

                if !formVM.isURLValid {
                    Text("Enter a valid URL.")
                        .font(.caption2)
                        .foregroundStyle(AppTheme.danger)
                }
            }
        }
    }

    private var dateTimeSection: some View {
        ScheduleFormSectionCard(
            title: "Date & Time",
            systemImage: "calendar.badge.clock",
            reduceEffects: isKeyboardVisible
        ) {
            VStack(alignment: .leading, spacing: 14) {
                toggleRow("Include Date", isOn: $formVM.hasDate)

                if formVM.hasDate {
                    DatePicker(
                        "Date",
                        selection: $formVM.scheduledDate,
                        in: scheduleDateSelectionRange,
                        displayedComponents: .date
                    )
#if os(iOS)
                    .datePickerStyle(.compact)
                    .environment(\.locale, Locale.autoupdatingCurrent)
#else
                    .datePickerStyle(.graphical)
#endif
                    .id(formVM.hasDate)
                }

                toggleRow("Include Time", isOn: $formVM.hasTime)

                if formVM.hasTime {
                    DatePicker(
                        "Time",
                        selection: $formVM.scheduledDate,
                        in: scheduleDateSelectionRange,
                        displayedComponents: .hourAndMinute
                    )
                    .datePickerStyle(.compact)
                }

                if formVM.isScheduleDateInPast {
                    Text("Past date/time is not allowed. Please choose a future time.")
                        .font(.caption2)
                        .foregroundStyle(AppTheme.danger)
                }
            }
        }
    }

    private var detailsSection: some View {
        ScheduleFormSectionCard(
            title: "Rules",
            systemImage: "slider.horizontal.3",
            reduceEffects: isKeyboardVisible
        ) {
            VStack(alignment: .leading, spacing: 12) {
                pickerRow("Repeat") {
                    Picker("Repeat", selection: $formVM.repeatPattern) {
                        ForEach(RepeatPattern.allCases) { pattern in
                            Text(pattern.displayName).tag(pattern)
                        }
                    }
                    .pickerStyle(.menu)
                }

                if formVM.repeatPattern == .daily {
                    dailyRepeatWeekdaySelector
                    repeatEndControls
                } else if formVM.repeatPattern != .never {
                    repeatEndControls
                }

                pickerRow("Alert") {
                    Picker("Alert", selection: $formVM.alertDeliveryOption) {
                        ForEach(AlertDeliveryOption.allCases) { option in
                            Text(option.displayName).tag(option)
                        }
                    }
                    .pickerStyle(.menu)
                }

                if formVM.alertDeliveryOption == .alarm {
                    alarmOptionsInfo
                }

                pickerRow("Early Reminder") {
                    Picker("Early Reminder", selection: $formVM.earlyReminderChoice) {
                        ForEach(ScheduleFormViewModel.earlyReminderChoices, id: \.id) { choice in
                            Text(formVM.earlyReminderDisplayName(for: choice))
                                .tag(choice)
                        }
                    }
                    .pickerStyle(.menu)
                }

                if formVM.earlyReminderChoice == .custom {
                    customEarlyReminderInput
                }

                pickerRow("Priority") {
                    Picker("Priority", selection: $formVM.priority) {
                        ForEach(SchedulePriority.allCases) { priority in
                            Label(priority.displayName, systemImage: priority.iconName)
                                .tag(priority)
                        }
                    }
                    .pickerStyle(.menu)
                }
            }
        }
    }

    // MARK: - UI Helpers

    @ViewBuilder
    private var alarmOptionsInfo: some View {
        VStack(alignment: .leading, spacing: 8) {
            pickerRow("Alarm Sound") {
#if os(iOS)
                Button {
                    dismissKeyboard()
                    isAlarmSoundPickerPresented = true
                } label: {
                    HStack(spacing: 6) {
                        Text(formVM.alarmSoundOption.displayName)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption2)
                    }
                }
                .buttonStyle(.bordered)
                .background {
                    GeometryReader { geometry in
                        Color.clear.preference(
                            key: AlarmSoundPickerButtonFramePreferenceKey.self,
                            value: geometry.frame(in: .named("ScheduleFormSpace"))
                        )
                    }
                }
#else
                Picker("Alarm Sound", selection: $formVM.alarmSoundOption) {
                    ForEach(AlarmSoundOption.selectableCases) { option in
                        Text(option.displayName).tag(option)
                    }
                }
                .pickerStyle(.menu)
#endif
            }

            toggleRow("Snooze", isOn: $formVM.alarmSnoozeEnabled)

            if formVM.alarmSnoozeEnabled {
                pickerRow("Snooze Time") {
                    Picker("Snooze Time", selection: $formVM.alarmSnoozeChoice) {
                        ForEach(ScheduleFormViewModel.snoozeChoices, id: \.id) { choice in
                            Text(formVM.snoozeDisplayName(for: choice)).tag(choice)
                        }
                    }
                    .pickerStyle(.menu)
                }

                if formVM.alarmSnoozeChoice == .custom {
                    customAlarmSnoozeInput
                }
            }
        }
    }

    @ViewBuilder
    private var alarmSoundPickerOverlay: some View {
#if os(iOS)
        if isAlarmSoundPickerPresented {
            GeometryReader { geometry in
                let pickerSize = CGSize(width: 320, height: 300)
                let origin = alarmSoundPickerOrigin(
                    in: geometry.size,
                    pickerSize: pickerSize
                )

                ZStack(alignment: .topLeading) {
                    Color.black.opacity(0.001)
                        .ignoresSafeArea()
                        .onTapGesture {
                            isAlarmSoundPickerPresented = false
                        }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Alarm Sound")
                            .font(.headline)
                            .padding(.top, 16)
                            .padding(.horizontal, 16)

                        Picker(
                            "Alarm Sound",
                            selection: Binding(
                                get: { formVM.alarmSoundOption },
                                set: { option in
                                    guard formVM.alarmSoundOption != option else { return }
                                    formVM.alarmSoundOption = option
                                    NotificationManager.shared.previewAlarmSound(option)
                                }
                            )
                        ) {
                            ForEach(AlarmSoundOption.selectableCases) { option in
                                Text(option.displayName)
                                    .tag(option)
                            }
                        }
                        .pickerStyle(.wheel)
                        .labelsHidden()
                        .frame(maxWidth: .infinity)
                    }
                    .frame(width: pickerSize.width, height: pickerSize.height)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .shadow(color: Color.black.opacity(0.14), radius: 14, y: 6)
                    .position(
                        x: origin.x + pickerSize.width / 2,
                        y: origin.y + pickerSize.height / 2
                    )
                }
            }
            .zIndex(20)
            .transition(.opacity)
        }
#endif
    }

    private func alarmSoundPickerOrigin(
        in containerSize: CGSize,
        pickerSize: CGSize
    ) -> CGPoint {
        let horizontalPadding: CGFloat = 12
        let verticalPadding: CGFloat = 12
        let pickerSpacing: CGFloat = 10

        let preferredX = alarmSoundPickerButtonFrame.maxX - pickerSize.width
        let clampedX = min(
            max(horizontalPadding, preferredX),
            max(horizontalPadding, containerSize.width - pickerSize.width - horizontalPadding)
        )

        let belowY = alarmSoundPickerButtonFrame.maxY + pickerSpacing
        let aboveY = alarmSoundPickerButtonFrame.minY - pickerSize.height - pickerSpacing

        let resolvedY: CGFloat
        if belowY + pickerSize.height + verticalPadding <= containerSize.height {
            resolvedY = belowY
        } else if aboveY >= verticalPadding {
            resolvedY = aboveY
        } else {
            resolvedY = min(
                max(verticalPadding, belowY),
                max(verticalPadding, containerSize.height - pickerSize.height - verticalPadding)
            )
        }

        return CGPoint(x: clampedX, y: resolvedY)
    }

    @ViewBuilder
    private var formBackground: some View {
#if os(iOS)
        if isKeyboardVisible {
            AppTheme.surfacePrimary(for: colorScheme)
                .ignoresSafeArea()
        } else {
            PremiumAppBackground()
        }
#else
        PremiumAppBackground()
#endif
    }

    private var inputBackground: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(inputFillColor)
    }

    private var inputBorder: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .stroke(inputBorderColor, lineWidth: 1)
    }

    private var contentBottomPadding: CGFloat {
#if os(macOS)
        110
#else
        18
#endif
    }

    @ViewBuilder
    private var formActionBar: some View {
#if os(macOS)
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)

        HStack(spacing: 10) {
            Spacer()
            Button("Cancel") {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)
            .buttonStyle(.bordered)

            Button("Save") {
                save()
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
            .disabled(!formVM.isValid)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .glassEffect(
            .regular
                .tint(actionBarTint)
                .interactive(),
            in: shape
        )
        .overlay(
            shape
                .stroke(formBorderColor, lineWidth: 1)
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
#else
        EmptyView()
#endif
    }

    private var accentTint: Color {
        AppTheme.accent
    }

    private func toggleRow(_ title: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .lineLimit(1)
            Spacer(minLength: 16)
            Toggle(title, isOn: isOn)
                .labelsHidden()
                .tint(accentTint)
        }
    }

    private var dailyRepeatWeekdaySelector: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Repeat On")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            HStack(spacing: 6) {
                ForEach(weekdaySymbols, id: \.weekday) { weekday in
                    Button {
                        formVM.toggleRepeatWeekday(weekday.weekday)
                    } label: {
                        Text(weekday.symbol)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 7)
                            .background(weekdayChipBackground(isSelected: formVM.isRepeatWeekdaySelected(weekday.weekday)))
                            .overlay(weekdayChipBorder(isSelected: formVM.isRepeatWeekdaySelected(weekday.weekday)))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private var repeatEndControls: some View {
        pickerRow("End Repeat") {
            Picker("End Repeat", selection: $formVM.repeatEndOption) {
                ForEach(RepeatEndOption.allCases) { option in
                    Text(option.displayName).tag(option)
                }
            }
            .pickerStyle(.menu)
        }

        if formVM.repeatEndOption == .onDate {
            datePickerRow(
                "End Date",
                selection: $formVM.repeatEndDate,
                range: formVM.repeatEndDateRange
            )
        }
    }

    private var customEarlyReminderInput: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Text("Custom Time")
                    .foregroundStyle(.secondary)
                Spacer(minLength: 10)
                DatePicker(
                    "Custom Time",
                    selection: $formVM.customEarlyReminderTime,
                    displayedComponents: .hourAndMinute
                )
                .labelsHidden()
                .datePickerStyle(.compact)
            }

            if !formVM.isCustomEarlyReminderValid {
                Text("Select at least 1 minute before the schedule time.")
                    .font(.caption2)
                    .foregroundStyle(AppTheme.danger)
            }
        }
    }

    private var customAlarmSnoozeInput: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Text("Custom Snooze Time")
                    .foregroundStyle(.secondary)
                Spacer(minLength: 10)
                DatePicker(
                    "Custom Snooze Time",
                    selection: $formVM.customAlarmSnoozeTime,
                    displayedComponents: .hourAndMinute
                )
                .labelsHidden()
                .datePickerStyle(.compact)
            }

            if !formVM.isCustomSnoozeValid {
                Text("Select at least 1 minute.")
                    .font(.caption2)
                    .foregroundStyle(AppTheme.danger)
            }
        }
    }

    private var weekdaySymbols: [(weekday: Int, symbol: String)] {
        let calendar = Calendar.current
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let startIndex = calendar.firstWeekday - 1

        return (0..<7).map { offset in
            let index = (startIndex + offset) % 7
            return (weekday: index + 1, symbol: symbols[index].uppercased())
        }
    }

    private func weekdayChipBackground(isSelected: Bool) -> some View {
        Capsule()
            .fill(
                isSelected
                    ? accentTint.opacity(colorScheme == .dark ? 0.42 : 0.28)
                    : AppTheme.chipFill(for: colorScheme)
            )
    }

    private func weekdayChipBorder(isSelected: Bool) -> some View {
        Capsule()
            .stroke(
                isSelected
                    ? accentTint.opacity(0.55)
                    : AppTheme.borderSoft(for: colorScheme),
                lineWidth: 1
            )
    }

    private var formBorderColor: Color {
        AppTheme.borderSoft(for: colorScheme)
    }

    private var inputFillColor: Color {
        AppTheme.surfaceTertiary(for: colorScheme)
    }

    private var inputBorderColor: Color {
        AppTheme.borderSoft(for: colorScheme)
    }

    private var actionBarTint: Color {
        AppTheme.surfaceSecondary(for: colorScheme)
    }

    private func inputField(
        _ label: String,
        text: Binding<String>,
        prompt: String,
        axis: Axis = .horizontal,
        focus: FocusField
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased())
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            Group {
                if axis == .vertical {
                    TextField(prompt, text: text, axis: .vertical)
                        .lineLimit(3...5)
                        .focused($focusedField, equals: focus)
                } else {
                    TextField(prompt, text: text, axis: .horizontal)
                        .lineLimit(1)
                        .focused($focusedField, equals: focus)
                }
            }
            .textFieldStyle(.plain)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(inputBackground)
            .overlay(inputBorder)
        }
    }

    private func pickerRow<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .lineLimit(1)
            Spacer(minLength: 16)
            content()
                .frame(minWidth: 122, alignment: .trailing)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .multilineTextAlignment(.trailing)
                .layoutPriority(1)
                .simultaneousGesture(TapGesture().onEnded {
                    dismissKeyboard()
                })
        }
    }

    private func datePickerRow(
        _ title: String,
        selection: Binding<Date>,
        range: ClosedRange<Date>
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text(title)
                .lineLimit(1)
            Spacer(minLength: 16)
            DatePicker(
                title,
                selection: selection,
                in: range,
                displayedComponents: .date
            )
            .labelsHidden()
            .datePickerStyle(.compact)
            .fixedSize(horizontal: true, vertical: false)
            .simultaneousGesture(TapGesture().onEnded {
                dismissKeyboard()
            })
        }
    }

    private func dismissKeyboard() {
        focusedField = nil
#if os(iOS)
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
#endif
    }

    private var scheduleDateSelectionRange: ClosedRange<Date> {
        Date()...Date.distantFuture
    }

    // MARK: - Actions

    private func save() {
        guard formVM.isValid else {
            HapticManager.notification(.warning)
            return
        }

        if let editingSchedule {
            formVM.applyTo(editingSchedule)
            viewModel.updateSchedule(editingSchedule)
        } else {
            let newSchedule = formVM.buildSchedule()
            viewModel.addSchedule(newSchedule)
        }
        HapticManager.notification(.success)
        dismiss()
    }
}

// MARK: - Supporting Views

private struct ScheduleFormSectionCard<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    let title: String
    let systemImage: String
    var reduceEffects: Bool = false
    @ViewBuilder let content: Content

    private var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
    }

    private var fillStyle: AnyShapeStyle {
        if reduceEffects {
            return AnyShapeStyle(AppTheme.surfacePrimary(for: colorScheme))
        }
        return AnyShapeStyle(AppTheme.surfaceSecondary(for: colorScheme))
    }

    private var borderOpacity: Double {
        reduceEffects ? 0.92 : 1
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            content
        }
        .padding(16)
        .background {
            cardShape
                .fill(fillStyle)
        }
        .overlay {
            cardShape
                .stroke(AppTheme.borderSoft(for: colorScheme).opacity(borderOpacity), lineWidth: 1)
        }
    }
}

struct TagChip: View {
    @Environment(\.colorScheme) private var colorScheme
    let title: String
    var onRemove: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 4) {
            Text(title)
                .font(.caption)

            if let onRemove {
                Button {
                    onRemove()
                } label: {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(AppTheme.surfaceTertiary(for: colorScheme), in: Capsule())
    }
}

private struct AlarmSoundPickerButtonFramePreferenceKey: PreferenceKey {
    static var defaultValue: CGRect = .zero

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = layout(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: ProposedViewSize(result.sizes[index])
            )
        }
    }

    private func layout(proposal: ProposedViewSize, subviews: Subviews)
        -> (size: CGSize, positions: [CGPoint], sizes: [CGSize])
    {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var sizes: [CGSize] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            sizes.append(size)

            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }

            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }

        return (
            size: CGSize(width: maxWidth, height: y + rowHeight),
            positions: positions,
            sizes: sizes
        )
    }
}
