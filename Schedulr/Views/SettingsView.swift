import SwiftUI
import UserNotifications
#if os(iOS)
import UIKit
#endif

struct SettingsView: View {
    @Bindable var viewModel: ScheduleViewModel
    @Bindable var firebaseService: FirebaseSyncService
    @Bindable private var settings: AppSettings = .shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var showingAccountSettings = false
    @State private var showingResetConfirmation = false
    @State private var showingDeleteAllCompleted = false
    @State private var showingResetAppData = false
    @State private var showingExportSheet = false
    @State private var exportURL: URL?
    @State private var showingCalendarManager = false
    @State private var showingTagManager = false
    @State private var newCalendarName = ""
    @State private var notificationSettings: UNNotificationSettings?
    @State private var settingsCloudSyncTask: Task<Void, Never>?
    @State private var hasPendingSettingsCloudSync = false
    @State private var showingAccentColorPicker = false

    private let weekdayNames: [String] = {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        return formatter.weekdaySymbols ?? ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
    }()

    var body: some View {
        NavigationStack {
            ZStack {
                PremiumAppBackground()
                    .ignoresSafeArea()

                List {
                    accountSection
                    defaultsSection
                    hotSettingsSection
                    calendarTimelineSection
                    appearanceSection
                    behaviorSection
                    permissionsSection
                    dataSection
                    managementSection
                    aboutSection
                }
                .scrollContentBackground(.hidden)
                .background(Color.clear)
            }
            .navigationTitle("Settings")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.large)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                }
            }
            .interactiveDismissDisabled(true)
            .alert("Reset All Settings?", isPresented: $showingResetConfirmation) {
                Button("Reset", role: .destructive) {
                    settings.resetToDefaults()
                    HapticManager.notification(.warning)
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("All settings will be restored to their default values. Your schedules will not be affected.")
            }
            .alert("Delete All Completed?", isPresented: $showingDeleteAllCompleted) {
                Button("Delete", role: .destructive) {
                    viewModel.deleteAllCompleted()
                    HapticManager.notification(.warning)
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("All completed non-recurring schedules will be permanently deleted.")
            }
            .alert("Reset App Data?", isPresented: $showingResetAppData) {
                Button("Reset Everything", role: .destructive) {
                    viewModel.resetAllData()
                    settings.resetToDefaults()
                    HapticManager.notification(.error)
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will permanently delete ALL schedules, settings, and local backups. This cannot be undone.")
            }
            .sheet(isPresented: $showingCalendarManager) {
                CalendarManagerView(viewModel: viewModel)
            }
            .sheet(isPresented: $showingTagManager) {
                TagManagerView(viewModel: viewModel)
            }
            .sheet(isPresented: $showingAccountSettings) {
                FirebaseAccountView(viewModel: viewModel, firebaseService: firebaseService)
            }
            .sheet(isPresented: $showingExportSheet) {
                if let url = exportURL {
                    ShareSheetView(items: [url])
                }
            }
#if os(iOS)
            .background(
                DeferredAccentColorPickerPresenter(
                    isPresented: $showingAccentColorPicker,
                    initialColor: UIColor(settings.accentColor),
                    onApply: { selectedColor in
                        settings.accentColorHex = Color(uiColor: selectedColor).hexString
                    }
                )
            )
#endif
            .onChange(of: settingsCloudSyncToken) { _, _ in
                hasPendingSettingsCloudSync = true
                scheduleSettingsCloudSync()
            }
            .onAppear {
                refreshNotificationPermissionSnapshot()
            }
            .onDisappear {
                let shouldFlushPendingSettingsSync = hasPendingSettingsCloudSync
                settingsCloudSyncTask?.cancel()
                settingsCloudSyncTask = nil
                if shouldFlushPendingSettingsSync {
                    hasPendingSettingsCloudSync = false
                    viewModel.syncCloudBackupNowIfSignedIn()
                }
            }
            .preferredColorScheme(settings.preferredColorScheme)
        }
    }

    // MARK: - Sections

    private var accountSection: some View {
        Section {
            Button {
                showingAccountSettings = true
            } label: {
                HStack {
                    Label(firebaseService.isSignedIn ? "Account Settings" : "Login", systemImage: "person.crop.circle")
                    Spacer()
                    Text(firebaseService.signedInEmail ?? "Not Signed In")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .buttonStyle(.plain)
        } header: {
            Text("Account")
        }
    }

    private var defaultsSection: some View {
        Section {
            Picker("Default Alert Style", selection: $settings.defaultAlertStyle) {
                ForEach(AlertDeliveryOption.allCases) { option in
                    Text(option.displayName).tag(option)
                }
            }

            Picker("Default Snooze", selection: $settings.defaultSnoozeDuration) {
                Text("5 min").tag(5)
                Text("10 min").tag(10)
                Text("15 min").tag(15)
                Text("30 min").tag(30)
            }

            Picker("Default Early Reminder", selection: $settings.defaultEarlyReminderMinutes) {
                Text("None").tag(0)
                Text("5 min").tag(5)
                Text("10 min").tag(10)
                Text("15 min").tag(15)
                Text("30 min").tag(30)
                Text("1 hour").tag(60)
            }

            Picker("Default Repeat", selection: $settings.defaultRepeatPattern) {
                ForEach([RepeatPattern.never, .daily, .weekdays, .weekly, .monthly], id: \.self) { pattern in
                    Text(pattern.displayName).tag(pattern)
                }
            }

            Picker("Default Priority", selection: $settings.defaultPriority) {
                ForEach(SchedulePriority.allCases) { priority in
                    Text(priority.displayName).tag(priority)
                }
            }

            Picker("Default Calendar", selection: $settings.defaultCalendar) {
                ForEach(viewModel.calendarNames, id: \.self) { name in
                    Text(name).tag(name)
                }
            }
        } header: {
            Text("New Schedule Defaults")
        }
    }

    private var calendarTimelineSection: some View {
        Section {
            Picker("First Day of Week", selection: $settings.firstDayOfWeek) {
                ForEach(1...7, id: \.self) { day in
                    Text(weekdayNames[day - 1]).tag(day)
                }
            }

            Picker("Time Format", selection: $settings.timeFormatPreference) {
                ForEach(TimeFormatPreference.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }

            timeZonePicker
        } header: {
            Text("Calendar & Timeline")
        }
    }

    private var hotSettingsSection: some View {
        Section {
            Toggle("Natural Language in Form", isOn: $settings.hotNaturalLanguageEnabled)
        } header: {
            Text("Hot Settings")
        }
    }

    private var timeZonePicker: some View {
        NavigationLink {
            TimeZonePickerView(
                selectedIdentifier: Binding(
                    get: { settings.defaultTimeZoneOverride },
                    set: { settings.defaultTimeZoneOverride = $0 }
                )
            )
        } label: {
            HStack {
                Text("Default Time Zone")
                Spacer()
                Text(settings.defaultTimeZoneOverride ?? "System")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var appearanceSection: some View {
        Section {
            Picker("Appearance", selection: $settings.appearanceMode) {
                Text("System").tag(0)
                Text("Light").tag(1)
                Text("Dark").tag(2)
            }
            .pickerStyle(.menu)

            Button {
                showingAccentColorPicker = true
            } label: {
                HStack {
                    Text("Accent Color")
                    Spacer()
                    Circle()
                        .fill(settings.accentColor)
                        .frame(width: 18, height: 18)
                        .overlay(
                            Circle()
                                .stroke(
                                    AngularGradient(
                                        colors: [.red, .orange, .yellow, .green, .cyan, .blue, .purple, .pink, .red],
                                        center: .center
                                    ),
                                    lineWidth: 2
                                )
                                .padding(-2)
                        )
                        .overlay(Circle().stroke(Color.secondary.opacity(0.24), lineWidth: 1))
                }
            }
            .buttonStyle(.plain)

            Button("Reset Accent Color") {
                settings.accentColorHex = AppSettings.defaultAccentColorHex
            }
            .disabled(settings.accentColorHex.caseInsensitiveCompare(AppSettings.defaultAccentColorHex) == .orderedSame)

            Toggle("Alternative Calendar", isOn: $settings.showAlternativeCalendar)

            if settings.showAlternativeCalendar {
                Picker("Calendar Type", selection: $settings.alternativeCalendarOption) {
                    ForEach(AlternativeCalendarOption.allCases) { option in
                        Text(option.displayName).tag(option)
                    }
                }
                .pickerStyle(.menu)
            }
        } header: {
            Text("Appearance")
        }
    }

    private var behaviorSection: some View {
        Section {
            Toggle("Haptic Feedback", isOn: $settings.hapticFeedbackEnabled)
            Toggle(
                "Notification Badge",
                isOn: Binding(
                    get: { settings.notificationBadgeEnabled },
                    set: { newValue in
                        settings.notificationBadgeEnabled = newValue
                        NotificationManager.shared.applyBadgePreferenceChange()
                    }
                )
            )
            Toggle("Auto-Sync on Launch", isOn: $settings.autoSyncOnLaunch)
            Toggle("Conflict Detection", isOn: $settings.conflictDetectionEnabled)
            Toggle(
                "Daily Digest",
                isOn: Binding(
                    get: { settings.dailyDigestEnabled },
                    set: { newValue in
                        settings.dailyDigestEnabled = newValue
                        viewModel.rescheduleDailyDigest()
                    }
                )
            )
            if settings.dailyDigestEnabled {
                DatePicker(
                    "Digest Time",
                    selection: digestTimeBinding,
                    displayedComponents: .hourAndMinute
                )
                .datePickerStyle(.compact)
            }
            Toggle(
                "Suppress Notifications During Focus",
                isOn: Binding(
                    get: { settings.suppressNotificationsDuringFocus },
                    set: { newValue in
                        settings.suppressNotificationsDuringFocus = newValue
                        viewModel.resyncAllScheduleNotifications()
                    }
                )
            )
        } header: {
            Text("Behavior")
        }
    }

    private var digestTimeBinding: Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(
                    bySettingHour: settings.dailyDigestHour,
                    minute: settings.dailyDigestMinute,
                    second: 0,
                    of: Date()
                ) ?? Date()
            },
            set: { newValue in
                let components = Calendar.current.dateComponents([.hour, .minute], from: newValue)
                settings.dailyDigestHour = components.hour ?? 20
                settings.dailyDigestMinute = components.minute ?? 0
                viewModel.rescheduleDailyDigest()
            }
        )
    }

    private var permissionsSection: some View {
        Section {
            HStack {
                Text("Notification Access")
                Spacer()
                Text(notificationAuthorizationStatusText)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Text("Critical Alerts")
                Spacer()
                Text(criticalAlertStatusText)
                    .foregroundStyle(.secondary)
            }

            Text("Critical alerts can play alarm-style reminders even during Focus and mute modes when entitlement and user permission are both granted.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button("Re-request Permissions") {
                Task {
                    await NotificationManager.shared.requestAuthorization()
                    refreshNotificationPermissionSnapshot()
                }
            }

#if os(iOS)
            Button("Open System Settings") {
                openSystemSettings()
            }
#endif
        } header: {
            Text("Critical Alerts")
        }
    }

    private var dataSection: some View {
        Section {
            Button {
                exportSchedulesAsJSON()
            } label: {
                Label("Export as JSON", systemImage: "square.and.arrow.up")
            }

            Button {
                exportSchedulesAsCSV()
            } label: {
                Label("Export as CSV", systemImage: "tablecells")
            }

            Button(role: .destructive) {
                showingDeleteAllCompleted = true
            } label: {
                Label("Delete All Completed", systemImage: "trash")
            }

            Button(role: .destructive) {
                showingResetAppData = true
            } label: {
                Label("Reset All App Data", systemImage: "exclamationmark.triangle")
            }
        } header: {
            Text("Data Management")
        }
    }

    private var managementSection: some View {
        Section {
            Button {
                showingCalendarManager = true
            } label: {
                Label("Manage Calendars", systemImage: "calendar")
            }

            Button {
                showingTagManager = true
            } label: {
                Label("Manage Tags", systemImage: "tag")
            }
        } header: {
            Text("Organization")
        }
    }

    private var aboutSection: some View {
        Section {
            HStack {
                Text("Version")
                Spacer()
                Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                    .foregroundStyle(.secondary)
            }

            Button("Reset All Settings") {
                showingResetConfirmation = true
            }
            .foregroundStyle(.red)
        } header: {
            Text("About")
        }
    }

    private var notificationAuthorizationStatusText: String {
        guard let status = notificationSettings?.authorizationStatus else { return "Unknown" }
        switch status {
        case .authorized, .provisional, .ephemeral:
            return "Enabled"
        case .denied:
            return "Denied"
        case .notDetermined:
            return "Not Requested"
        @unknown default:
            return "Unknown"
        }
    }

    private var criticalAlertStatusText: String {
        guard let status = notificationSettings?.criticalAlertSetting else { return "Unknown" }
        switch status {
        case .enabled:
            return "Enabled"
        case .disabled:
            return "Disabled"
        case .notSupported:
            return "Not Supported"
        @unknown default:
            return "Unknown"
        }
    }

    private func refreshNotificationPermissionSnapshot() {
        Task {
            let snapshot = await UNUserNotificationCenter.current().notificationSettings()
            await MainActor.run {
                notificationSettings = snapshot
            }
        }
    }

#if os(iOS)
    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
#endif

    // MARK: - Export Helpers

    private func exportSchedulesAsJSON() {
        guard let data = viewModel.exportBackupData() else { return }
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("schedules-export.json")
        try? data.write(to: tempURL, options: [.atomic, .completeFileProtection])
        exportURL = tempURL
        showingExportSheet = true
    }

    private func exportSchedulesAsCSV() {
        guard let csvData = viewModel.exportAsCSV() else { return }
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("schedules-export.csv")
        try? csvData.write(to: tempURL, options: [.atomic, .completeFileProtection])
        exportURL = tempURL
        showingExportSheet = true
    }

    private var settingsCloudSyncToken: String {
        [
            settings.defaultAlertStyle.rawValue,
            String(settings.defaultSnoozeDuration),
            String(settings.defaultEarlyReminderMinutes),
            settings.defaultRepeatPattern.rawValue,
            String(settings.defaultPriority.rawValue),
            settings.defaultCalendar,
            String(settings.hotNaturalLanguageEnabled),
            String(settings.firstDayOfWeek),
            settings.timeFormatPreference.rawValue,
            settings.accentColorHex,
            String(settings.appearanceMode),
            String(settings.hapticFeedbackEnabled),
            String(settings.notificationBadgeEnabled),
            String(settings.autoSyncOnLaunch),
            String(settings.showAlternativeCalendar),
            settings.alternativeCalendarOption.rawValue,
            settings.defaultTimeZoneOverride ?? "",
            String(settings.conflictDetectionEnabled),
            String(settings.suppressNotificationsDuringFocus),
            String(settings.dailyDigestEnabled),
            String(settings.dailyDigestHour),
            String(settings.dailyDigestMinute)
        ].joined(separator: "|")
    }

    private func scheduleSettingsCloudSync() {
        settingsCloudSyncTask?.cancel()
        settingsCloudSyncTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            hasPendingSettingsCloudSync = false
            viewModel.syncCloudBackupNowIfSignedIn()
            settingsCloudSyncTask = nil
        }
    }
}

#if os(iOS)
private struct DeferredAccentColorPickerPresenter: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    let initialColor: UIColor
    let onApply: (UIColor) -> Void

    func makeUIViewController(context: Context) -> UIViewController {
        context.coordinator.hostController.view.backgroundColor = .clear
        return context.coordinator.hostController
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        context.coordinator.onApply = onApply
        if !context.coordinator.isPickerVisible {
            context.coordinator.pendingColor = initialColor
        }

        if isPresented {
            context.coordinator.presentPickerIfNeeded()
        } else {
            context.coordinator.dismissPickerIfNeeded()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(isPresented: $isPresented, onApply: onApply)
    }

    final class Coordinator: NSObject, UIColorPickerViewControllerDelegate, UIAdaptivePresentationControllerDelegate {
        let hostController = UIViewController()
        @Binding var isPresented: Bool
        var onApply: (UIColor) -> Void
        var pendingColor: UIColor = .systemBlue

        private weak var pickerController: UIColorPickerViewController?
        private weak var navigationController: UINavigationController?
        var isPickerVisible: Bool { pickerController != nil }

        init(isPresented: Binding<Bool>, onApply: @escaping (UIColor) -> Void) {
            _isPresented = isPresented
            self.onApply = onApply
        }

        func presentPickerIfNeeded() {
            guard pickerController == nil else { return }
            guard hostController.presentedViewController == nil else { return }

            let picker = UIColorPickerViewController()
            picker.delegate = self
            picker.supportsAlpha = false
            picker.selectedColor = pendingColor
            picker.navigationItem.rightBarButtonItem = UIBarButtonItem(
                title: "Done",
                style: .prominent,
                target: self,
                action: #selector(doneTapped)
            )

            let nav = UINavigationController(rootViewController: picker)
            nav.modalPresentationStyle = .pageSheet
            nav.presentationController?.delegate = self

            if let sheet = nav.sheetPresentationController {
                sheet.detents = [.medium()]
                sheet.selectedDetentIdentifier = .medium
                sheet.prefersGrabberVisible = false
                sheet.preferredCornerRadius = 28
            }

            pickerController = picker
            navigationController = nav
            hostController.present(nav, animated: true)
        }

        func dismissPickerIfNeeded() {
            guard let nav = navigationController else { return }
            nav.dismiss(animated: true)
            navigationController = nil
            pickerController = nil
        }

        @objc
        private func doneTapped() {
            guard let picker = pickerController else { return }
            pendingColor = picker.selectedColor
            onApply(pendingColor)
            dismissPickerIfNeeded()
            if isPresented {
                isPresented = false
            }
        }

        func colorPickerViewControllerDidSelectColor(_ viewController: UIColorPickerViewController) {
            pendingColor = viewController.selectedColor
        }

        func colorPickerViewControllerDidFinish(_ viewController: UIColorPickerViewController) {
            // Dismissal is controlled by Done only.
        }

        func presentationControllerShouldDismiss(_ presentationController: UIPresentationController) -> Bool {
            true
        }

        func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
            navigationController = nil
            pickerController = nil
            if isPresented {
                isPresented = false
            }
        }
    }
}
#endif

// MARK: - Calendar Manager

struct CalendarManagerView: View {
    @Bindable var viewModel: ScheduleViewModel
    @Bindable private var settings: AppSettings = .shared
    @State private var newName = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                PremiumAppBackground()
                    .ignoresSafeArea()

                List {
                    Section {
                        HStack {
                            TextField("New Calendar Name", text: $newName)
                            Button("Add") {
                                if viewModel.addCalendar(named: newName) {
                                    newName = ""
                                }
                            }
                            .disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }

                    Section {
                        ForEach(viewModel.calendarNames, id: \.self) { name in
                            HStack {
                                Image(systemName: "calendar")
                                    .foregroundStyle(AppTheme.accent)
                                Text(name)
                                Spacer()
                                if name == ScheduleViewModel.defaultCalendarName {
                                    Text("Default")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .onDelete { indexSet in
                            for index in indexSet {
                                let name = viewModel.calendarNames[index]
                                viewModel.removeCalendar(named: name)
                            }
                        }
                    }
                }
                .scrollContentBackground(.hidden)
                .background(Color.clear)
            }
            .navigationTitle("Calendars")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .preferredColorScheme(settings.preferredColorScheme)
        }
    }
}

// MARK: - Time Zone Picker

struct TimeZonePickerView: View {
    @Bindable private var settings: AppSettings = .shared
    @Binding var selectedIdentifier: String?
    @State private var searchText = ""
    @Environment(\.dismiss) private var dismiss

    private static let cachedZones: [TimeZone] =
        TimeZone.knownTimeZoneIdentifiers.compactMap { TimeZone(identifier: $0) }

    private var filteredZones: [TimeZone] {
        if searchText.isEmpty { return Self.cachedZones }
        return Self.cachedZones.filter {
            $0.identifier.localizedCaseInsensitiveContains(searchText) ||
            $0.localizedName(for: .standard, locale: .current)?.localizedCaseInsensitiveContains(searchText) == true
        }
    }

    var body: some View {
        ZStack {
            PremiumAppBackground()
                .ignoresSafeArea()

            List {
                Button {
                    selectedIdentifier = nil
                    dismiss()
                } label: {
                    HStack {
                        Text("System Default")
                        Spacer()
                        if selectedIdentifier == nil {
                            Image(systemName: "checkmark")
                                .foregroundStyle(AppTheme.accent)
                        }
                    }
                }

                ForEach(filteredZones, id: \.identifier) { zone in
                    Button {
                        selectedIdentifier = zone.identifier
                        dismiss()
                    } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(zone.identifier.replacingOccurrences(of: "_", with: " "))
                                Text(zone.abbreviation() ?? "")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if selectedIdentifier == zone.identifier {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(AppTheme.accent)
                            }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.clear)
        }
        .searchable(text: $searchText, prompt: "Search time zones")
        .navigationTitle("Time Zone")
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .preferredColorScheme(settings.preferredColorScheme)
    }
}

// MARK: - Share Sheet

#if os(iOS)
struct ShareSheetView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#else
struct ShareSheetView: View {
    let items: [Any]
    var body: some View {
        Text("Export saved to temporary directory")
            .padding()
    }
}
#endif
