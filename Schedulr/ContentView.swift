import SwiftUI
import SwiftData
#if os(iOS)
import FirebaseAuth
#if canImport(GoogleSignIn)
import GoogleSignIn
#endif
#endif

struct ContentView: View {
    private static let cloudRestoreHandledSignaturesKey = "cloudRestoreHandledSignatures.v1"

    private enum Route: Hashable {
        case day
        case newSchedule
        case editSchedule(UUID)
    }

    private enum PostAuthDestination {
        case account
        case settings
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
    @State private var isSearchPresented = false
    @State private var isSettingsPresented = false
    @State private var isStatsPresented = false
    @State private var isHeatmapPresented = false
    @State private var isAccountPresented = false
    @State private var pasteboardManager = PasteboardManager.shared
    @State private var pendingPasteboardParse: NLPScheduleParser.ParsedSchedule?
    @State private var firebaseService = FirebaseSyncService.shared
    @State private var cloudRestoreStatusMessage: String?
    @State private var cloudRestoreStatusTask: Task<Void, Never>?
    @State private var quickAddButtonPosition: CGPoint?
    @State private var accentRefreshTick = 0
    @State private var isWeekQuickAddComposerPresented = false
    @State private var weekQuickAddInput = ""
    @State private var isWeekQuickAddProcessing = false
    @State private var showCloudRestorePrompt = false
    @State private var pendingCloudBackupData: Data?
    @State private var pendingCloudBackupSignature: String?
    @State private var restoreSchedulesFromCloud = true
    @State private var restoreSettingsFromCloud = true
    @State private var hasCheckedInitialCloudRestore = false
    @State private var quickAddButtonDidDrag = false
    @State private var quickAddDragStartPosition: CGPoint?
    @State private var pendingPostAuthDestination: PostAuthDestination?
    @State private var isSignedInForWeekToolbar = FirebaseSyncService.shared.isSignedIn
    @State private var hasPerformedLaunchAutoSync = false

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
                            ScheduleFormView(
                                viewModel: viewModel,
                                editingSchedule: schedule,
                                editingOccurrenceDate: viewModel.editingOccurrenceDate
                            )
                            .onDisappear {
                                viewModel.clearEditingOccurrenceDate()
                            }
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
                .onChange(of: firebaseService.isSignedIn) { wasSignedIn, isSignedIn in
                    isSignedInForWeekToolbar = isSignedIn

                    if !isSignedIn {
                        hasPerformedLaunchAutoSync = false
                        hasCheckedInitialCloudRestore = false
                        pendingCloudBackupData = nil
                        pendingCloudBackupSignature = nil
                        showCloudRestorePrompt = false
                        pendingPostAuthDestination = nil
                        viewModel.completeCloudRestoreGate()
                        return
                    }

                    // Ignore same-value updates (for example token refresh churn)
                    // so we do not collapse sheet stacks while already signed in.
                    guard !wasSignedIn else { return }

                    // After any successful auth, always return to Account page
                    // once the cloud backup check flow completes.
                    pendingPostAuthDestination = .account

                    // Dismiss currently open auth host surfaces before showing restore prompt.
                    if isAccountPresented {
                        isAccountPresented = false
                    }
                    if isSettingsPresented {
                        isSettingsPresented = false
                    }

                    hasCheckedInitialCloudRestore = false
                    prepareCloudRestorePrompt(showSuccessBanner: false)
                }
                .onChange(of: isAccountPresented) { _, isPresented in
                    if !isPresented {
                        refreshWeekToolbarAuthState()
                    }
                }
                .onChange(of: AppSettings.shared.firstDayOfWeek) { _, _ in
                    viewModel.prepareDefaultWeekLanding()
                    viewModel.fetchSchedules()
                }
                .onReceive(NotificationCenter.default.publisher(for: .accentColorDidChange)) { _ in
                    accentRefreshTick &+= 1
                }
                .onReceive(NotificationCenter.default.publisher(for: Notification.Name("Schedulr.AuthDidSucceed"))) { _ in
                    // Hide account entry immediately after auth success, before cloud-restore prompt work finishes.
                    isSignedInForWeekToolbar = true

                    // Trigger restore check immediately on auth success instead of waiting
                    // for secondary view updates to propagate auth state.
                    pendingPostAuthDestination = .account
                    if isAccountPresented {
                        isAccountPresented = false
                    }
                    if isSettingsPresented {
                        isSettingsPresented = false
                    }
                    hasCheckedInitialCloudRestore = false
                    prepareCloudRestorePrompt(showSuccessBanner: false)
                }
                .onReceive(NotificationCenter.default.publisher(for: Notification.Name("Schedulr.AuthDidSignOut"))) { _ in
                    // Show account entry immediately after sign-out.
                    isSignedInForWeekToolbar = false
                    pendingCloudBackupData = nil
                    pendingCloudBackupSignature = nil
                    showCloudRestorePrompt = false
                    pendingPostAuthDestination = nil
                    hasCheckedInitialCloudRestore = false
                    viewModel.completeCloudRestoreGate()
                }
                .onReceive(NotificationCenter.default.publisher(for: .didTapScheduleNotification)) { notification in
                    handleNotificationTap(notification.userInfo)
                }
                .onOpenURL { url in
#if os(iOS)
                    if Auth.auth().canHandle(url) {
                        return
                    }
#if canImport(GoogleSignIn)
                    if GIDSignIn.sharedInstance.handle(url) {
                        return
                    }
#endif
#endif
                    handleWidgetCompletionURL(url)
                }
                .onAppear {
                    viewModel.setup(modelContext: modelContext)
                    firebaseService.registerBackupUpdateHandler { data in
                        handleRealtimeBackupUpdate(data)
                    }
                    viewModel.consumeWidgetCompletionRequests()
                    viewModel.prepareDefaultWeekLanding()
                    pasteboardManager.startMonitoring()
                    weekPickerDate = viewModel.selectedDate
                    refreshWeekToolbarAuthState()
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
                .onDisappear {
                    firebaseService.clearBackupUpdateHandler()
                    pasteboardManager.stopMonitoring()
                }
                .confirmationDialog(
                    "Quick Add from Clipboard",
                    isPresented: Binding(
                        get: { pendingPasteboardParse != nil },
                        set: { isPresented in
                            if !isPresented {
                                pendingPasteboardParse = nil
                            }
                        }
                    ),
                    titleVisibility: .visible
                ) {
                    Button("Create Schedule") {
                        createScheduleFromPasteboard(openEditor: false)
                    }
                    Button("Create & Edit") {
                        createScheduleFromPasteboard(openEditor: true)
                    }
                    Button("Cancel", role: .cancel) {
                        pendingPasteboardParse = nil
                    }
                } message: {
                    Text(pasteboardQuickAddSummary)
                }
                .sheet(isPresented: $showCloudRestorePrompt) {
                    CloudRestorePromptView(
                        restoreSchedules: $restoreSchedulesFromCloud,
                        restoreSettings: $restoreSettingsFromCloud,
                        onSkip: {
                            if let signature = pendingCloudBackupSignature {
                                markCloudBackupPromptHandled(signature)
                            }
                            pendingCloudBackupSignature = nil
                            pendingCloudBackupData = nil
                            showCloudRestorePrompt = false
                            viewModel.completeCloudRestoreGate()
                            redirectAfterCloudRestoreFlowIfNeeded()
                        },
                        onRestore: {
                            guard let data = pendingCloudBackupData else {
                                showCloudRestorePrompt = false
                                viewModel.completeCloudRestoreGate()
                                redirectAfterCloudRestoreFlowIfNeeded()
                                return
                            }

                            showCloudRestorePrompt = false
                            if let signature = pendingCloudBackupSignature {
                                markCloudBackupPromptHandled(signature)
                            }
                            pendingCloudBackupSignature = nil
                            pendingCloudBackupData = nil

                            Task { @MainActor in
                                defer {
                                    viewModel.completeCloudRestoreGate()
                                }

                                let result = viewModel.importBackupData(
                                    data,
                                    includeSchedules: restoreSchedulesFromCloud,
                                    includeSettings: restoreSettingsFromCloud
                                )
                                showCloudRestoreStatus(result.userMessage)
                                redirectAfterCloudRestoreFlowIfNeeded()
                            }
                        }
                    )
                }
#if os(iOS)
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .active {
                        refreshWeekToolbarAuthState()
                        // Reset floating button to its default anchor whenever the app is opened.
                        quickAddButtonPosition = nil
                        quickAddButtonDidDrag = false
                        pasteboardManager.startMonitoring()
                        viewModel.consumeWidgetCompletionRequests()
                        handlePendingNotificationNavigation()
                        if AppSettings.shared.autoSyncOnLaunch,
                           FirebaseSyncService.shared.isSignedIn,
                           !hasPerformedLaunchAutoSync
                        {
                            hasPerformedLaunchAutoSync = true
                            viewModel.autoSyncCloudBackupIfEligible()
                        }
                    } else if newPhase == .background {
                        viewModel.autoSyncCloudBackupIfEligible(requirePendingScheduleChanges: true)
                        pasteboardManager.stopMonitoring()
                    }
                }
#endif
        }
    }

    // MARK: - Navigation

    private var weekScheduleScreen: some View {
        scheduleScaffold {
            WeekScheduleView(
                viewModel: viewModel,
                isBulkSelectionMode: viewModel.isBulkSelectionMode,
                selectedScheduleIDs: viewModel.selectedScheduleIDs,
                onToggleScheduleSelection: { scheduleID in
                    viewModel.toggleScheduleSelection(scheduleID)
                }
            )
        }
        .onChange(of: viewModel.currentWeekStart) { _, _ in
            guard !isWeekDatePickerPresented else { return }
            weekPickerDate = viewModel.selectedDate
        }
        .toolbar {
            weekToolbar
        }
#if os(iOS)
        .fullScreenCover(isPresented: $isWeekDatePickerPresented) {
            weekCalendarSheet
        }
        .sheet(isPresented: $isWeekQuickAddComposerPresented) {
            WeekQuickAddComposerView(
                inputText: $weekQuickAddInput,
                isProcessing: isWeekQuickAddProcessing,
                onSave: {
                    Task {
                        await handleWeekQuickAddSubmission(openEditor: false)
                    }
                },
                onReview: {
                    Task {
                        await handleWeekQuickAddSubmission(openEditor: true)
                    }
                }
            )
            .presentationDetents([.height(330), .fraction(0.42)])
            .presentationBackgroundInteraction(.enabled)
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $isSearchPresented) {
            NavigationStack {
                ScheduleSearchView(viewModel: viewModel)
            }
        }
        .sheet(isPresented: $isSettingsPresented) {
            NavigationStack {
                SettingsView(viewModel: viewModel, firebaseService: firebaseService)
            }
        }
        .sheet(isPresented: $isAccountPresented) {
            NavigationStack {
                FirebaseAccountView(viewModel: viewModel, firebaseService: firebaseService)
            }
        }
        .sheet(isPresented: $isStatsPresented) {
            NavigationStack {
                CompletionStatsView(viewModel: viewModel)
            }
        }
        .sheet(isPresented: $isHeatmapPresented) {
            NavigationStack {
                MonthHeatmapView(viewModel: viewModel)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if viewModel.isBulkSelectionMode {
                bulkActionBar
                    .padding(.horizontal, 16)
                    .padding(.bottom, 10)
            }
        }
#else
        .sheet(isPresented: $isWeekDatePickerPresented) {
            weekCalendarSheet
        }
        .sheet(isPresented: $isSearchPresented) {
            NavigationStack {
                ScheduleSearchView(viewModel: viewModel)
            }
        }
        .sheet(isPresented: $isSettingsPresented) {
            NavigationStack {
                SettingsView(viewModel: viewModel, firebaseService: firebaseService)
            }
        }
        .sheet(isPresented: $isAccountPresented) {
            NavigationStack {
                FirebaseAccountView(viewModel: viewModel, firebaseService: firebaseService)
            }
        }
        .sheet(isPresented: $isStatsPresented) {
            NavigationStack {
                CompletionStatsView(viewModel: viewModel)
            }
        }
        .sheet(isPresented: $isHeatmapPresented) {
            NavigationStack {
                MonthHeatmapView(viewModel: viewModel)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if viewModel.isBulkSelectionMode {
                bulkActionBar
                    .padding(.horizontal, 16)
                    .padding(.bottom, 10)
            }
        }
#endif
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

            let hasClipboardContent = pasteboardManager.hasQuickAddContent
            let naturalLanguageEnabled = AppSettings.shared.hotNaturalLanguageEnabled
            let shouldShowFloatingAction = naturalLanguageEnabled || hasClipboardContent

            if viewModel.zoomLevel == .week && shouldShowFloatingAction {
                GeometryReader { proxy in
                    Group {
                        if naturalLanguageEnabled && hasClipboardContent {
                            HStack(spacing: 0) {
                                Button {
                                    guard !quickAddButtonDidDrag else { return }
                                    presentWeekQuickAddComposer()
                                } label: {
                                    Image(systemName: "plus")
                                        .font(.system(size: 17, weight: .bold))
                                        .frame(width: 50, height: 48)
                                }
                                .buttonStyle(.plain)

                                Rectangle()
                                    .fill(Color.white.opacity(0.22))
                                    .frame(width: 1, height: 24)

                                Button {
                                    guard !quickAddButtonDidDrag else { return }
                                    presentPasteboardQuickAdd()
                                } label: {
                                    Image(systemName: "doc.on.clipboard.fill")
                                        .font(.system(size: 16, weight: .semibold))
                                        .frame(width: 50, height: 48)
                                }
                                .buttonStyle(.plain)
                            }
                            .frame(height: 48)
                            .padding(.horizontal, 4)
                        } else {
                            Button {
                                guard !quickAddButtonDidDrag else { return }
                                if naturalLanguageEnabled {
                                    presentWeekQuickAddComposer()
                                } else if hasClipboardContent {
                                    presentPasteboardQuickAdd()
                                }
                            } label: {
                                Image(systemName: naturalLanguageEnabled ? "plus" : "doc.on.clipboard.fill")
                                    .font(.system(size: 18, weight: .bold))
                                    .frame(width: 48, height: 48)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .foregroundStyle(.white)
                    .background {
                        if naturalLanguageEnabled && hasClipboardContent {
                            Capsule(style: .continuous)
                                .fill(AppTheme.accent)
                        } else {
                            Circle()
                                .fill(AppTheme.accent)
                        }
                    }
                    .overlay {
                        if naturalLanguageEnabled && hasClipboardContent {
                            Capsule(style: .continuous)
                                .stroke(Color.white.opacity(0.18), lineWidth: 1)
                        } else {
                            Circle()
                                .stroke(Color.white.opacity(0.18), lineWidth: 1)
                        }
                    }
                    .shadow(color: AppTheme.accent.opacity(0.35), radius: 8, y: 4)
                    .contentShape(Rectangle())
                    .position(quickAddButtonPosition ?? defaultQuickAddButtonPosition(in: proxy.size))
                    .onAppear {
                        if quickAddButtonPosition == nil {
                            quickAddButtonPosition = defaultQuickAddButtonPosition(in: proxy.size)
                        }
                    }
                    .onChange(of: pasteboardManager.hasQuickAddContent) { _, _ in
                        if let current = quickAddButtonPosition {
                            quickAddButtonPosition = clampedQuickAddButtonPosition(current, in: proxy.size)
                        }
                    }
                    .onChange(of: AppSettings.shared.hotNaturalLanguageEnabled) { _, _ in
                        if let current = quickAddButtonPosition {
                            quickAddButtonPosition = clampedQuickAddButtonPosition(current, in: proxy.size)
                        }
                    }
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 8, coordinateSpace: .named("FloatingButtonSpace"))
                            .onChanged { value in
                                if quickAddDragStartPosition == nil {
                                    quickAddDragStartPosition = quickAddButtonPosition ?? defaultQuickAddButtonPosition(in: proxy.size)
                                }

                                let movement = hypot(value.translation.width, value.translation.height)
                                if movement > 2 {
                                    quickAddButtonDidDrag = true
                                }

                                if quickAddButtonDidDrag, let start = quickAddDragStartPosition {
                                    let translatedPoint = CGPoint(
                                        x: start.x + value.translation.width,
                                        y: start.y + value.translation.height
                                    )
                                    quickAddButtonPosition = clampedQuickAddButtonPosition(translatedPoint, in: proxy.size)
                                }
                            }
                            .onEnded { value in
                                if quickAddButtonDidDrag, let start = quickAddDragStartPosition {
                                    let translatedPoint = CGPoint(
                                        x: start.x + value.translation.width,
                                        y: start.y + value.translation.height
                                    )
                                    quickAddButtonPosition = clampedQuickAddButtonPosition(translatedPoint, in: proxy.size)
                                }

                                quickAddDragStartPosition = nil
                                DispatchQueue.main.async {
                                    quickAddButtonDidDrag = false
                                }
                            }
                    )
                }
                .coordinateSpace(name: "FloatingButtonSpace")
            }

            if viewModel.isLoading {
                loadingOverlay
            }

            if let cloudRestoreStatusMessage {
                VStack {
                    Text(cloudRestoreStatusMessage)
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(.regularMaterial, in: Capsule())
                        .overlay {
                            Capsule()
                                .stroke(AppTheme.accent.opacity(0.35), lineWidth: 1)
                        }
                        .padding(.top, 8)
                    Spacer()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(2)
            }

            if viewModel.isRestoreInProgress {
                VStack {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Restoring backup…")
                            .font(.subheadline.weight(.semibold))
                        ProgressView(value: viewModel.restoreProgress)
                        Text("\(Int(viewModel.restoreProgress * 100))%")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(12)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .padding(.top, 8)
                    .padding(.horizontal, 16)

                    Spacer()
                }
                .transition(.opacity)
                .zIndex(3)
            }
        }
    }

    @ToolbarContentBuilder
    private var weekToolbar: some ToolbarContent {
        ToolbarItem(placement: leadingToolbarPlacement) {
            Button {
                guard !isWeekDatePickerPresented else { return }
                presentWeekCalendarSheet()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.headline.weight(.bold))
                    .frame(width: 38, height: 38)
            }
#if !os(macOS)
            .buttonStyle(TransparentCircleButtonStyle())
#endif
        }

        ToolbarItem(placement: .principal) {
            Button {
                presentWeekCalendarSheet()
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
            .buttonStyle(TransparentCircleButtonStyle())
#endif

            if !isSignedInForWeekToolbar {
                Button {
                    isAccountPresented = true
                } label: {
                    Image(systemName: "person.crop.circle")
                        .font(.headline.weight(.semibold))
                        .frame(width: 38, height: 38)
                }
#if !os(macOS)
                .buttonStyle(TransparentCircleButtonStyle())
#endif
            }

            Menu {
                Button {
                    isSearchPresented = true
                } label: {
                    Label("Search", systemImage: "magnifyingglass")
                }

                Button {
                    isSettingsPresented = true
                } label: {
                    Label("Settings", systemImage: "gearshape.fill")
                }

                Button {
                    isStatsPresented = true
                } label: {
                    Label("Analysis", systemImage: "chart.bar.xaxis")
                }

                Button {
                    isHeatmapPresented = true
                } label: {
                    Label("Monthly Heatmap", systemImage: "square.grid.3x3.fill")
                }

                Divider()

                Button {
                    viewModel.toggleBulkSelectionMode()
                } label: {
                    Label(
                        viewModel.isBulkSelectionMode ? "Done Selecting" : "Select Schedules",
                        systemImage: viewModel.isBulkSelectionMode ? "checkmark.circle" : "checklist"
                    )
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.headline.weight(.semibold))
                    .frame(width: 38, height: 38)
            }
            .accessibilityLabel("More")
#if !os(macOS)
            .buttonStyle(TransparentCircleButtonStyle())
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

    private var bulkActionBar: some View {
        HStack(spacing: 10) {
            Text("\(viewModel.selectedScheduleIDs.count) selected")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            Spacer()

            Button("Complete") {
                viewModel.markSelectedSchedulesCompleted(on: viewModel.selectedDate)
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.selectedScheduleIDs.isEmpty)

            Button("Delete", role: .destructive) {
                viewModel.deleteSelectedSchedules()
            }
            .buttonStyle(.bordered)
            .disabled(viewModel.selectedScheduleIDs.isEmpty)

            Button("Cancel") {
                viewModel.clearBulkSelection()
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(AppTheme.borderSoft(for: .light), lineWidth: 1)
        }
    }

    private var weekCalendarSheet: some View {
        WeekFullCalendarView(
            selectedDate: $weekPickerDate,
            schedulesFor: { date in
                viewModel.schedules(for: date)
            },
            onDismiss: {
                viewModel.focus(on: weekPickerDate)
                isWeekDatePickerPresented = false
            }
        )
    }

    private func presentWeekCalendarSheet() {
        weekPickerDate = viewModel.selectedDate
        isWeekDatePickerPresented = true
    }

    private func prepareCloudRestorePrompt(showSuccessBanner: Bool) {
        guard firebaseService.isSignedIn else { return }
        guard !hasCheckedInitialCloudRestore else { return }
        hasCheckedInitialCloudRestore = true

        viewModel.beginCloudRestoreGate()
        Task {
            let result = await firebaseService.downloadBackupWithResult()

            await MainActor.run {
                switch result {
                case .success(let backup) where !backup.data.isEmpty:
                    let signature = cloudBackupSignature(data: backup.data, globalVersion: backup.globalSyncVersion)
                    if let handledSignature = handledCloudBackupPromptSignature(), handledSignature == signature {
                        pendingCloudBackupSignature = nil
                        pendingCloudBackupData = nil
                        showCloudRestorePrompt = false
                        viewModel.completeCloudRestoreGate()
                        redirectAfterCloudRestoreFlowIfNeeded()
                        return
                    }

                    if let version = backup.globalSyncVersion {
                        viewModel.seedGlobalSyncVersion(version)
                    }
                    pendingCloudBackupData = backup.data
                    pendingCloudBackupSignature = signature
                    restoreSchedulesFromCloud = true
                    restoreSettingsFromCloud = true
                    showCloudRestorePrompt = true

                case .missingBackup, .success:
                    pendingCloudBackupSignature = nil
                    viewModel.completeCloudRestoreGate()
                    if showSuccessBanner {
                        showCloudRestoreStatus("No cloud backup found")
                    }
                    viewModel.syncCloudBackupNowIfSignedIn()
                    redirectAfterCloudRestoreFlowIfNeeded()

                case .notConfigured, .authFailed:
                    viewModel.completeCloudRestoreGate()
                    redirectAfterCloudRestoreFlowIfNeeded()

                case .networkError(let msg):
                    viewModel.completeCloudRestoreGate()
                    showCloudRestoreStatus("Restore failed: \(msg)")
                    redirectAfterCloudRestoreFlowIfNeeded()

                case .decodeFailed(let msg):
                    viewModel.completeCloudRestoreGate()
                    showCloudRestoreStatus("Backup corrupt: \(msg)")
                    redirectAfterCloudRestoreFlowIfNeeded()

                case .cacheFallback(let backup):
                    if !backup.data.isEmpty {
                        pendingCloudBackupData = backup.data
                        pendingCloudBackupSignature = cloudBackupSignature(data: backup.data, globalVersion: backup.globalSyncVersion)
                        restoreSchedulesFromCloud = true
                        restoreSettingsFromCloud = true
                        showCloudRestorePrompt = true
                    } else {
                        viewModel.completeCloudRestoreGate()
                        showCloudRestoreStatus("Using cached backup (offline)")
                        redirectAfterCloudRestoreFlowIfNeeded()
                    }
                }
            }
        }
    }

    private func redirectAfterCloudRestoreFlowIfNeeded() {
        guard let destination = pendingPostAuthDestination else { return }
        pendingPostAuthDestination = nil

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(180))
            switch destination {
            case .account:
                isAccountPresented = true
            case .settings:
                isSettingsPresented = true
            }
        }
    }

    private func handleRealtimeBackupUpdate(_ data: Data) {
        guard !showCloudRestorePrompt else { return }
        guard pendingCloudBackupData == nil else { return }
        guard !viewModel.isRestoreInProgress else { return }
        let result = viewModel.importBackupData(data)
        if !result.succeeded {
            showCloudRestoreStatus(result.userMessage)
        }
    }

    private func showCloudRestoreStatus(_ message: String) {
        cloudRestoreStatusTask?.cancel()
        withAnimation(.easeOut(duration: 0.2)) {
            cloudRestoreStatusMessage = message
        }

        cloudRestoreStatusTask = Task {
            try? await Task.sleep(for: .seconds(2.2))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(.easeIn(duration: 0.2)) {
                    cloudRestoreStatusMessage = nil
                }
            }
        }
    }

    private func cloudBackupSignature(data: Data, globalVersion: Int?) -> String {
        let prefix = data.prefix(64).map { String(format: "%02x", $0) }.joined()
        let suffix = data.suffix(64).map { String(format: "%02x", $0) }.joined()
        let versionToken = globalVersion.map(String.init) ?? "none"
        return "\(versionToken)|\(data.count)|\(prefix)|\(suffix)"
    }

    private func cloudRestorePromptAccountKey() -> String {
        let email = firebaseService.signedInEmail?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return email?.isEmpty == false ? email! : "unknown"
    }

    private func handledCloudBackupPromptSignature() -> String? {
        let defaults = UserDefaults.standard
        guard let map = defaults.dictionary(forKey: Self.cloudRestoreHandledSignaturesKey) as? [String: String] else {
            return nil
        }
        return map[cloudRestorePromptAccountKey()]
    }

    private func markCloudBackupPromptHandled(_ signature: String) {
        let defaults = UserDefaults.standard
        var map = defaults.dictionary(forKey: Self.cloudRestoreHandledSignaturesKey) as? [String: String] ?? [:]
        map[cloudRestorePromptAccountKey()] = signature
        defaults.set(map, forKey: Self.cloudRestoreHandledSignaturesKey)
    }

    private func defaultQuickAddButtonPosition(in size: CGSize) -> CGPoint {
        let trailingInset: CGFloat = (AppSettings.shared.hotNaturalLanguageEnabled && pasteboardManager.hasQuickAddContent) ? 88 : 56
        return CGPoint(x: max(72, size.width - trailingInset), y: max(72, size.height - 62))
    }

    private func clampedQuickAddButtonPosition(_ point: CGPoint, in size: CGSize) -> CGPoint {
        let horizontalPadding: CGFloat = (AppSettings.shared.hotNaturalLanguageEnabled && pasteboardManager.hasQuickAddContent) ? 92 : 62
        let verticalPadding: CGFloat = 34
        return CGPoint(
            x: min(max(point.x, horizontalPadding), size.width - horizontalPadding),
            y: min(max(point.y, verticalPadding), size.height - verticalPadding)
        )
    }

    private func refreshWeekToolbarAuthState() {
        isSignedInForWeekToolbar = firebaseService.isSignedIn
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

    private func presentForm(_ route: Route) {
        let sourceContextIsDay = navigationPath.contains(.day)
        while let last = navigationPath.last, last != .day {
            switch last {
            case .newSchedule, .editSchedule:
                navigationPath.removeLast()
            case .day:
                break
            }
        }

        if !sourceContextIsDay {
            navigationPath = []
            navigationPath.append(route)
        } else {
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
              components.scheme?.lowercased() == "schedulr",
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

    private var pasteboardQuickAddSummary: String {
        guard let pendingPasteboardParse else {
            return "Create a schedule from detected clipboard text."
        }

        let title = pendingPasteboardParse.title.isEmpty ? "Untitled" : pendingPasteboardParse.title
        if let date = pendingPasteboardParse.date {
            return "\(title) • \(SchedulePreviewFormatter.string(from: date))"
        }

        return "\(title)"
    }

    private func presentPasteboardQuickAdd() {
        if PasteboardManager.shared.detectedText != nil {
            // Because we only know `hasStrings` is true until user taps the button,
            // we must do the actual read NOW. This will trigger the iOS prompt if they
            // haven't permanently allowed it, but it only happens exactly when they tap it.
            Task {
                if let parseResult = await PasteboardManager.shared.parseAndCreateScheduleFromActualPasteboard() {
                    pendingPasteboardParse = parseResult.parsed
                    if parseResult.internetUnavailable {
                        showCloudRestoreStatus("Turn on internet connection for better result.")
                    }
                } else {
                    HapticManager.notification(.warning)
                }
            }
        }
    }

    private func createScheduleFromPasteboard(openEditor: Bool) {
        guard let parsed = pendingPasteboardParse else { return }
        pendingPasteboardParse = nil

        let scheduledDate = parsed.date ?? Date().addingTimeInterval(3600)
        let calendarName = AppSettings.shared.defaultCalendar
        let schedule = Schedule(
            title: parsed.title.isEmpty ? "New Schedule" : parsed.title,
            scheduledDate: scheduledDate,
            repeatPattern: parsed.repeatPattern,
            listName: calendarName,
            tags: parsed.tags,
            priority: parsed.priority
        )

        viewModel.addSchedule(schedule)
        pasteboardManager.markCurrentClipboardAsConsumed()
        pasteboardManager.dismissDetection()

        if openEditor {
            viewModel.startEditingSchedule(schedule, on: scheduledDate)
        }
    }

    private func presentWeekQuickAddComposer() {
        weekQuickAddInput = ""
        isWeekQuickAddComposerPresented = true
    }

    @MainActor
    private func handleWeekQuickAddSubmission(openEditor: Bool) async {
        let input = weekQuickAddInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else {
            HapticManager.notification(.warning)
            return
        }

        isWeekQuickAddProcessing = true
        let parseResult = await NLPScheduleRouter.shared.parse(input)
        isWeekQuickAddProcessing = false

        if parseResult.internetUnavailable {
            showCloudRestoreStatus("Turn on internet connection for better result.")
        }

        let parsed = parseResult.parsed
        let scheduledDate = parsed.date ?? viewModel.selectedDate

        if openEditor {
            pasteboardManager.dismissDetection()
            viewModel.setPendingNewScheduleNLPInput(input)
            let selectedIndex = min(max(viewModel.selectedDayIndex, 0), 6)
            viewModel.startAddingSchedule(on: scheduledDate, dayIndex: selectedIndex)
            viewModel.pendingNewScheduleDate = scheduledDate
            isWeekQuickAddComposerPresented = false
            return
        }

        let calendarName = AppSettings.shared.defaultCalendar
        let schedule = Schedule(
            title: parsed.title.isEmpty ? "New Schedule" : parsed.title,
            scheduledDate: scheduledDate,
            repeatPattern: parsed.repeatPattern,
            listName: calendarName,
            tags: parsed.tags,
            priority: parsed.priority
        )
        schedule.alertDeliveryOption = parsed.deliveryOption ?? .push
        schedule.isUrgent = schedule.alertDeliveryOption == .alarm
        schedule.earlyReminderMinutes = parsed.earlyReminderMinutes

        viewModel.addSchedule(schedule)
        pasteboardManager.dismissDetection()
        viewModel.focus(on: scheduledDate)
        isWeekQuickAddComposerPresented = false
        weekQuickAddInput = ""
    }
}

private struct CloudRestorePromptView: View {
    @Binding var restoreSchedules: Bool
    @Binding var restoreSettings: Bool
    var onSkip: () -> Void
    var onRestore: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Restore Options") {
                    Toggle("Schedules", isOn: $restoreSchedules)
                    Toggle("Settings", isOn: $restoreSettings)
                }

                Section {
                    Button("Restore") {
                        onRestore()
                    }
                    .disabled(!restoreSchedules && !restoreSettings)

                    Button("Skip", role: .cancel) {
                        onSkip()
                    }
                } footer: {
                    Text("Both options are pre-selected. Uncheck any item you do not want to restore.")
                }
            }
            .navigationTitle("Cloud Backup Found")
            .navigationBarTitleDisplayMode(.inline)
        }
        .interactiveDismissDisabled(true)
    }
}

private struct WeekQuickAddComposerView: View {
    @Binding var inputText: String
    let isProcessing: Bool
    var onSave: () -> Void
    var onReview: () -> Void

    @FocusState private var isInputFocused: Bool
    @Environment(\.dismiss) private var dismiss

    private var trimmedInput: String {
        inputText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isActionDisabled: Bool {
        trimmedInput.isEmpty || isProcessing
    }

    private var actionButtonOpacity: Double {
        isActionDisabled ? 0.58 : 1
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                Text("Type a natural sentence and create instantly, or review before saving.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                TextField(
                    "Type schedule, e.g. call mom tomorrow 8pm #family",
                    text: $inputText,
                    axis: .vertical
                )
                .lineLimit(3...6)
                .padding(.top, 4)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.primary.opacity(0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                )
                .focused($isInputFocused)

                HStack(spacing: 10) {
                    Button {
                        guard !isActionDisabled else { return }
                        onSave()
                    } label: {
                        Label("Save", systemImage: "checkmark")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.accent)
                    .opacity(actionButtonOpacity)
                    .allowsHitTesting(!isActionDisabled)

                    Button {
                        guard !isActionDisabled else { return }
                        onReview()
                    } label: {
                        Label("Review", systemImage: "square.and.pencil")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                    .opacity(actionButtonOpacity)
                    .allowsHitTesting(!isActionDisabled)
                }
                .controlSize(.large)

                if isProcessing {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Analyzing your request...")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .navigationTitle("Quick Add")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(isProcessing)
                }
            }
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    isInputFocused = true
                }
            }
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Schedule.self, inMemory: true)
}

private struct WeekFullCalendarView: View {
    private enum CalendarMode {
        case month
        case year
    }

    @Binding var selectedDate: Date
    let schedulesFor: (Date) -> [Schedule]
    let onDismiss: () -> Void

    private let calendar = Calendar.current

    @State private var mode: CalendarMode = .month
    @State private var displayedYear: Int
    @State private var monthJumpTrigger = UUID()
    @State private var yearJumpTrigger = UUID()

    init(
        selectedDate: Binding<Date>,
        schedulesFor: @escaping (Date) -> [Schedule],
        onDismiss: @escaping () -> Void
    ) {
        self._selectedDate = selectedDate
        self.schedulesFor = schedulesFor
        self.onDismiss = onDismiss
        let year = Calendar.current.component(.year, from: selectedDate.wrappedValue)
        self._displayedYear = State(initialValue: year)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                PremiumAppBackground()

                if mode == .month {
                    MonthCalendarCollectionView(
                        selectedDate: selectedDate,
                        onSelectDate: { date in
                            selectedDate = date.startOfDay
                            onDismiss()
                        },
                        onVisibleYearChanged: { year in
                            if displayedYear != year {
                                displayedYear = year
                            }
                        },
                        jumpToTodayTrigger: monthJumpTrigger
                    )
                    .ignoresSafeArea(edges: .bottom)
                } else {
                    YearCalendarCollectionView(
                        selectedDate: selectedDate,
                        onSelectMonth: { year, month in
                            var comps = DateComponents()
                            comps.year = year; comps.month = month; comps.day = 1
                            let targetDate = calendar.date(from: comps) ?? Date()
                            selectedDate = targetDate.startOfDay
                            displayedYear = year
                            withAnimation(.spring(response: 0.56, dampingFraction: 0.86, blendDuration: 0.08)) {
                                mode = .month
                            }
                            // Trigger month view to jump to the selected month
                            monthJumpTrigger = UUID()
                        },
                        onVisibleYearChanged: { year in
                            if displayedYear != year {
                                displayedYear = year
                            }
                        },
                        jumpToTodayTrigger: yearJumpTrigger
                    )
                    .ignoresSafeArea(edges: .bottom)
                }
            }
            .navigationTitle(mode == .month ? "Month" : "Year")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar(mode == .year ? .hidden : .visible, for: .bottomBar)
            .toolbar {
                if mode == .month {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            withAnimation(.snappy(duration: 0.24)) {
                                mode = .year
                            }
                            yearJumpTrigger = UUID()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "chevron.left")
                                Text(verbatim: String(displayedYear))
                                    .monospacedDigit()
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.85)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .fixedSize(horizontal: true, vertical: false)
                        }
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        selectedDate = Date().startOfDay
                        onDismiss()
                    } label: {
                        Image(systemName: "calendar.badge.clock")
                            .font(.headline.weight(.semibold))
                    }
                    .accessibilityLabel("Go to current week")
                }
            }
            .overlay(alignment: .bottomLeading) {
                if mode == .month {
                    Button("Today") {
                        selectedDate = Date().startOfDay
                        displayedYear = calendar.component(.year, from: Date())
                        monthJumpTrigger = UUID()
                    }
                    .buttonStyle(.glass)
                    .padding(.leading, 20)
                    .padding(.bottom, 0)
                }
            }
            .overlay(alignment: .bottomLeading) {
                if mode == .year {
                    Button("Today") {
                        let today = Date().startOfDay
                        let currentYear = calendar.component(.year, from: today)
                        if displayedYear == currentYear {
                            // Already at current year — go to month mode
                            selectedDate = today
                            displayedYear = currentYear
                            withAnimation(.spring(response: 0.56, dampingFraction: 0.86)) {
                                mode = .month
                            }
                            monthJumpTrigger = UUID()
                        } else {
                            // Jump to current year first
                            selectedDate = today
                            displayedYear = currentYear
                            yearJumpTrigger = UUID()
                        }
                    }
                    .buttonStyle(.glass)
                    .padding(.leading, 20)
                    .padding(.bottom, 0)
                }
            }
        }
    }
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

struct TransparentCircleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Circle())
            .scaleEffect(configuration.isPressed ? 0.9 : 1.0)
            .opacity(configuration.isPressed ? 0.72 : 1.0)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }
}

struct TransparentSolidCapsuleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(AppTheme.accent)
            .background(Color.clear, in: Capsule())
            .overlay {
                Capsule()
                    .stroke(AppTheme.accent.opacity(0.9), lineWidth: 1.4)
            }
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .opacity(configuration.isPressed ? 0.85 : 1.0)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }
}

struct SolidFloatingCircleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .background(AppTheme.accent, in: Circle())
            .overlay {
                Circle()
                    .stroke(Color.white.opacity(0.18), lineWidth: 1)
            }
            .shadow(color: AppTheme.accent.opacity(0.35), radius: 8, y: 4)
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .opacity(configuration.isPressed ? 0.86 : 1)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }
}

private enum SchedulePreviewFormatter {
    static func string(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.dateStyle = .medium
        switch AppSettings.shared.timeFormatPreference {
        case .system:
            formatter.timeStyle = .short
        case .twelveHour:
            formatter.dateFormat = "MMM d, yyyy h:mm a"
        case .twentyFourHour:
            formatter.dateFormat = "MMM d, yyyy HH:mm"
        }
        return formatter.string(from: date)
    }
}
