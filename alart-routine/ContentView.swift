import SwiftUI
import SwiftData

struct ContentView: View {
    private enum Route: Hashable {
        case day
        case newSchedule
        case editSchedule(UUID)
    }

    private enum FormSourceContext {
        case week
        case day
    }

    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @State private var viewModel = ScheduleViewModel()
    @State private var hasRequestedNotificationPermissions = false
    @State private var pendingLaunchResync = false
    @State private var navigationPath: [Route] = []
    @State private var isSyncingNavigation = false
    @State private var pendingNotificationNavigationTask: Task<Void, Never>?
    @State private var isWeekDatePickerPresented = false
    @State private var weekPickerDate = Date()

    var body: some View {
        NavigationStack(path: $navigationPath) {
            weekScheduleScreen
                .navigationTitle(viewModel.weekTitle)
#if !os(macOS)
                .navigationBarTitleDisplayMode(.inline)
#else
                .toolbarBackground(.visible, for: .windowToolbar)
                .toolbarBackground(.regularMaterial, for: .windowToolbar)
#endif
                .navigationDestination(for: Route.self) { route in
                    switch route {
                    case .day:
                        dayScheduleScreen
                    case .newSchedule:
                        ScheduleFormView(viewModel: viewModel)
                            .onDisappear {
                                viewModel.clearPendingNewScheduleDate()
                            }
                    case .editSchedule(let scheduleID):
                        if let schedule = viewModel.schedule(withID: scheduleID) {
                            ScheduleFormView(viewModel: viewModel, editingSchedule: schedule)
                        } else {
                            ContentUnavailableView(
                                "Schedule Unavailable",
                                systemImage: "exclamationmark.triangle",
                                description: Text("This schedule no longer exists.")
                            )
                        }
                    }
                }
                .onChange(of: viewModel.showingAddForm) { _, shouldPresent in
                    guard shouldPresent else { return }
                    presentForm(.newSchedule)
                    viewModel.showingAddForm = false
                }
                .onChange(of: viewModel.editingSchedule?.id) { _, scheduleID in
                    guard let scheduleID else { return }
                    presentForm(.editSchedule(scheduleID))
                    viewModel.editingSchedule = nil
                }
                .onChange(of: viewModel.zoomLevel) { _, newZoomLevel in
                    syncNavigationPathForZoomLevel(newZoomLevel)
                }
                .onChange(of: navigationPath) { _, path in
                    syncZoomLevelForNavigationPath(path)
                }
                .onReceive(NotificationCenter.default.publisher(for: .didTapScheduleNotification)) { notification in
                    handleNotificationTap(notification.userInfo)
                }
                .onOpenURL { url in
                    handleWidgetCompletionURL(url)
                }
                .onAppear {
                    viewModel.setup(modelContext: modelContext)
                    viewModel.consumeWidgetCompletionRequests()
                    viewModel.prepareDefaultWeekLanding()
                    weekPickerDate = viewModel.selectedDate
#if os(iOS)
                    KeyboardWarmup.prewarmIfNeeded()
#endif
                    handlePendingNotificationNavigation()
                    guard !hasRequestedNotificationPermissions else { return }
                    hasRequestedNotificationPermissions = true
                    Task {
                        await NotificationManager.shared.requestAuthorization()
                        try? await Task.sleep(for: .seconds(1.5))
                        if !isPresentingForm {
                            viewModel.resyncAllScheduleNotifications()
                            handlePendingNotificationNavigation()
                        } else {
                            pendingLaunchResync = true
                        }
                    }
                }
#if os(iOS)
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .active {
                        viewModel.consumeWidgetCompletionRequests()
                        handlePendingNotificationNavigation()
                    }
                }
#endif
        }
    }

    // MARK: - Navigation

    private var weekScheduleScreen: some View {
        scheduleScaffold {
            WeekScheduleView(viewModel: viewModel)
        }
        .onChange(of: viewModel.currentWeekStart) { _, _ in
            guard !isWeekDatePickerPresented else { return }
            weekPickerDate = viewModel.selectedDate
        }
        .toolbar {
            weekToolbar
        }
    }

    private var dayScheduleScreen: some View {
        scheduleScaffold {
            DayScheduleView(viewModel: viewModel)
        }
        .navigationTitle(viewModel.dayTitle)
#if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(false)
#endif
        .toolbar {
            dayToolbar
        }
    }

    @ViewBuilder
    private func scheduleScaffold<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ZStack {
            PremiumAppBackground()
            content()

            if viewModel.isLoading {
                loadingOverlay
            }
        }
    }

    @ToolbarContentBuilder
    private var weekToolbar: some ToolbarContent {
        ToolbarItem(placement: leadingToolbarPlacement) {
            Button {
                viewModel.goToPreviousWeek()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.headline.weight(.bold))
                    .frame(width: 38, height: 38)
            }
#if !os(macOS)
            .buttonStyle(LiquidGlassCircleButtonStyle())
#endif
        }

        ToolbarItem(placement: .principal) {
            Button {
                weekPickerDate = viewModel.selectedDate
                isWeekDatePickerPresented = true
            } label: {
                HStack(spacing: 6) {
                    Text(viewModel.weekTitle)
                        .font(.headline.weight(.semibold))
                        .lineLimit(1)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.accent)
                }
            }
            .buttonStyle(.plain)
#if !os(macOS)
            .buttonStyle(LiquidGlassCapsuleButtonStyle())
#endif
            .popover(
                isPresented: $isWeekDatePickerPresented,
                attachmentAnchor: .rect(.bounds),
                arrowEdge: .top
            ) {
                weekDatePickerPopover
            }
        }

        ToolbarItemGroup(placement: trailingToolbarPlacement) {
            Button {
                let date = viewModel.selectedDate
                let index = min(max(viewModel.selectedDayIndex, 0), 6)
                viewModel.startAddingSchedule(on: date, dayIndex: index)
            } label: {
                Image(systemName: "plus")
                    .font(.headline.weight(.black))
                    .frame(width: 38, height: 38)
            }
#if !os(macOS)
            .buttonStyle(LiquidGlassCircleButtonStyle())
#endif
        }
    }

    @ToolbarContentBuilder
    private var dayToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: trailingToolbarPlacement) {
            Button {
                viewModel.goToPreviousDay()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.headline.weight(.bold))
                    .frame(width: 38, height: 38)
            }
#if !os(macOS)
            .buttonStyle(LiquidGlassCircleButtonStyle())
#endif

            Button {
                viewModel.goToNextDay()
            } label: {
                Image(systemName: "chevron.right")
                    .font(.headline.weight(.bold))
                    .frame(width: 38, height: 38)
            }
#if !os(macOS)
            .buttonStyle(LiquidGlassCircleButtonStyle())
#endif
        }
    }

    private var leadingToolbarPlacement: ToolbarItemPlacement {
#if os(macOS)
        .navigation
#else
        .topBarLeading
#endif
    }

    private var trailingToolbarPlacement: ToolbarItemPlacement {
#if os(macOS)
        .automatic
#else
        .topBarTrailing
#endif
    }

    private var loadingOverlay: some View {
        ProgressView()
            .controlSize(.large)
            .padding(18)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var weekDatePickerPopover: some View {
        DatePicker(
            "Select Date",
            selection: Binding(
                get: { weekPickerDate },
                set: { newDate in
                    weekPickerDate = newDate
                    viewModel.focus(on: newDate)
                }
            ),
            displayedComponents: .date
        )
        .datePickerStyle(.graphical)
        .labelsHidden()
        .padding(10)
        .frame(minWidth: 320, idealWidth: 340, maxWidth: 360)
        .overlay(alignment: .top) {
            HStack {
                Spacer()
                Button("Today") {
                    let today = Date()
                    weekPickerDate = today
                    viewModel.focus(on: today)
                }
                .font(.headline)
                .foregroundStyle(AppTheme.accent)
                // Keep space for the built-in month arrow controls on the right.
                Spacer()
                    .frame(width: 108)
            }
            // Align with the built-in month/title row.
            .padding(.top, 44)
        }
#if os(iOS)
        .presentationCompactAdaptation(.popover)
#endif
    }

    private var isPresentingForm: Bool {
        guard let last = navigationPath.last else { return false }
        switch last {
        case .newSchedule, .editSchedule:
            return true
        case .day:
            return false
        }
    }

    private var currentFormSourceContext: FormSourceContext {
        if navigationPath.contains(.day) {
            return .day
        }
        return .week
    }

    private func presentForm(_ route: Route) {
        let sourceContext = currentFormSourceContext
        while let last = navigationPath.last, last != .day {
            switch last {
            case .newSchedule, .editSchedule:
                navigationPath.removeLast()
            case .day:
                break
            }
        }

        switch sourceContext {
        case .week:
            navigationPath = []
            navigationPath.append(route)
        case .day:
            if let dayIndex = navigationPath.firstIndex(of: .day) {
                navigationPath = Array(navigationPath.prefix(dayIndex + 1))
            } else {
                navigationPath = [.day]
            }
            navigationPath.append(route)
        }
    }

    private func syncNavigationPathForZoomLevel(_ zoomLevel: ZoomLevel) {
        guard !isPresentingForm, !isSyncingNavigation else { return }
        isSyncingNavigation = true
        defer { isSyncingNavigation = false }
        switch zoomLevel {
        case .week:
            if let dayIndex = navigationPath.firstIndex(of: .day) {
                navigationPath = Array(navigationPath.prefix(dayIndex))
            }
        case .day:
            guard !navigationPath.contains(.day) else { return }
            navigationPath.append(.day)
        }
    }

    private func syncZoomLevelForNavigationPath(_ path: [Route]) {
        isSyncingNavigation = true
        defer { isSyncingNavigation = false }
        if path.contains(.day) {
            if viewModel.zoomLevel != .day {
                viewModel.zoomLevel = .day
            }
        } else if viewModel.zoomLevel != .week {
            viewModel.zoomLevel = .week
        }

        guard pendingLaunchResync else { return }
        let isShowingForm = path.last.map {
            switch $0 {
            case .newSchedule, .editSchedule:
                return true
            case .day:
                return false
            }
        } ?? false
        guard !isShowingForm else { return }

        pendingLaunchResync = false
        Task {
            viewModel.resyncAllScheduleNotifications()
            handlePendingNotificationNavigation()
        }
    }

    /// Make sure the week view is visible after a notification tap.
    /// We intentionally stay on the week view so the user sees the
    /// full-week context with the tapped schedule's day highlighted.
    private func ensureWeekRouteVisible() {
        // If we somehow navigated deeper (into a day detail), pop back.
        if navigationPath.contains(.day) {
            navigationPath = navigationPath.filter { $0 != .day }
        }
        if viewModel.zoomLevel != .week {
            viewModel.zoomLevel = .week
        }
    }

    private func handleNotificationTap(_ userInfo: [AnyHashable: Any]?) {
        if let rawID = userInfo?["scheduleID"] as? String,
           let scheduleID = UUID(uuidString: rawID)
        {
            NotificationManager.shared.acknowledgePendingTappedScheduleID(scheduleID)
            navigateToSchedule(scheduleID)
            return
        }

        handlePendingNotificationNavigation()
    }

    private func handlePendingNotificationNavigation() {
        guard let scheduleID = NotificationManager.shared.consumePendingTappedScheduleID() else { return }
        navigateToSchedule(scheduleID)
    }

    private func navigateToSchedule(_ id: UUID) {
        pendingNotificationNavigationTask?.cancel()
        pendingNotificationNavigationTask = nil

        if viewModel.focusOnSchedule(withID: id) {
            ensureWeekRouteVisible()
            return
        }

        // Cold-launch path: data may still be loading. Retry lightly first, then fetch.
        pendingNotificationNavigationTask = Task { @MainActor in
            defer { pendingNotificationNavigationTask = nil }

            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }

            if viewModel.focusOnSchedule(withID: id) {
                ensureWeekRouteVisible()
                return
            }

            viewModel.fetchSchedules()
            guard !Task.isCancelled else { return }

            if viewModel.focusOnSchedule(withID: id) {
                ensureWeekRouteVisible()
            }
        }
    }

    private func handleWidgetCompletionURL(_ url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == "alartroutine",
              components.host?.lowercased() == "complete"
        else {
            return
        }

        let queryItems = components.queryItems ?? []
        let scheduleIDValue = queryItems.first(where: { $0.name == "scheduleID" })?.value
        let occurrenceValue = queryItems.first(where: { $0.name == "occurrence" })?.value

        guard let scheduleIDString = scheduleIDValue,
              let scheduleID = UUID(uuidString: scheduleIDString)
        else {
            return
        }

        let occurrenceDate: Date?
        if let occurrenceValue,
           let timestamp = TimeInterval(occurrenceValue)
        {
            occurrenceDate = Date(timeIntervalSince1970: timestamp)
        } else {
            occurrenceDate = nil
        }

        viewModel.markScheduleCompleted(scheduleID: scheduleID, occurrenceDate: occurrenceDate)
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Schedule.self, inMemory: true)
}

// MARK: - Liquid Glass Button Styles

struct LiquidGlassCircleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Circle())
            .glassEffect(.regular, in: Circle())
            .scaleEffect(configuration.isPressed ? 0.9 : 1.0)
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }
}

struct LiquidGlassCapsuleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .glassEffect(.regular, in: Capsule())
            .scaleEffect(configuration.isPressed ? 0.93 : 1.0)
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }
}
