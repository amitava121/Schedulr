import SwiftUI
import FirebaseAuth
import FirebaseCore
import CryptoKit
import OSLog
#if canImport(GoogleSignIn)
import GoogleSignIn
#endif
#if os(iOS)
import UIKit
import AVFoundation
import PhotosUI
import Photos
import UniformTypeIdentifiers
#endif
#if os(macOS)
import AppKit
#endif

private enum PhotoDiagnosticsStore {
    private static let storeKey = "profileImage.diagnostics.v1"

    private static let timestampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static func snapshot() -> [String: String] {
        UserDefaults.standard.dictionary(forKey: storeKey) as? [String: String] ?? [:]
    }

    static func set(_ key: String, _ value: String) {
        var map = snapshot()
        map[key] = value
        map["diag.lastUpdatedAt"] = timestampFormatter.string(from: Date())
        UserDefaults.standard.set(map, forKey: storeKey)
    }

    static func increment(_ key: String) {
        let current = Int(snapshot()[key] ?? "0") ?? 0
        set(key, String(current + 1))
    }

    static func setNow(_ key: String) {
        set(key, timestampFormatter.string(from: Date()))
    }
}

struct FirebaseAccountView: View {
    private static let lockedPickerInstantDismissCountKey = "profileImage.lockedPicker.instantDismiss.count"

    private enum AuthMode: String, CaseIterable, Identifiable {
        case signIn
        case signUp
        case forgotPassword

        var id: String { rawValue }
    }

    private enum AuthField: Hashable {
        case fullName
        case email
        case password
    }

    @Bindable var viewModel: ScheduleViewModel
    @Bindable var firebaseService: FirebaseSyncService
    @Bindable private var settings: AppSettings = .shared
    @Environment(\.dismiss) private var dismiss

    @State private var email = ""
    @State private var password = ""
    @State private var fullName = ""
    @State private var showingConflictReview = false
    @State private var isPerformingAuthAction = false
    @State private var isSigningOut = false
    @State private var authMode: AuthMode = .signIn
    @State private var statusClearTask: Task<Void, Never>?
    @State private var transientStatusMessage: String?
    @State private var manualRestoreStatusMessage: String?
    @State private var syncDiagnosticsStatusMessage: String?
    @State private var photoDiagnosticsStatusMessage: String?
    @State private var profileSaveAttemptCount = 0
    @State private var lastProfileSaveAt: Date?
    @State private var lastProfileSaveNameLength = 0
    @State private var lastProfileSavePhotoBytes = 0
    @State private var lastProfileSaveErrorMessage: String?
    @State private var showSignOutConfirmation = false
    @State private var showProfileEditor = false
    @State private var profileEditorNameDraft = ""
    @State private var profileEditorImageDraft: Data?
    @State private var customProfileImageData: Data?
    @FocusState private var focusedAuthField: AuthField?

    private var syncStatusText: String {
        switch viewModel.syncCoordinator.syncState {
        case .idle:
            return "Idle"
        case .syncing:
            return "In Progress"
        case .conflict:
            return "Conflicts"
        case .error:
            return "Error"
        }
    }

    private var syncProgressPercentText: String {
        let raw = Int((viewModel.syncCoordinator.syncProgress * 100).rounded())
        return "\(min(max(raw, 0), 100))%"
    }

    private var syncStatusColor: Color {
        switch viewModel.syncCoordinator.syncState {
        case .idle:
            return .secondary
        case .syncing:
            return AppTheme.accent
        case .conflict:
            return .orange
        case .error:
            return .red
        }
    }

    /// Keeps metadata text aligned with button titles (not the leading icon glyph).
    private let cloudRowLabelInset: CGFloat = 34

    var body: some View {
        NavigationStack {
            ZStack {
                PremiumAppBackground()
                    .ignoresSafeArea()

                if !firebaseService.isSignedIn {
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 14) {
                            loginSection

                            if let error = transientStatusMessage, !error.isEmpty {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Status")
                                        .font(.headline)
                                    Text(error)
                                        .font(.footnote)
                                        .foregroundStyle(.red)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(14)
                                .background(Color.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .stroke(Color.red.opacity(0.26), lineWidth: 1)
                                )
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .padding(.bottom, 24)
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .simultaneousGesture(
                        TapGesture().onEnded {
                            focusedAuthField = nil
                            dismissKeyboard()
                        }
                    )
                } else {
                    Form {
                        signedInStatusSection
                        cloudBackupSection
                        if let error = transientStatusMessage, !error.isEmpty {
                            Section("Status") {
                                Text(error)
                                    .font(.footnote)
                                    .foregroundStyle(.red)
                            }
                        }
                    }
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
                }
            }
            .navigationTitle("Account")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .preferredColorScheme(settings.preferredColorScheme)
            .sheet(isPresented: $showingConflictReview) {
                ConflictReviewView(viewModel: viewModel)
            }
            .sheet(isPresented: $showProfileEditor) {
                AccountProfileEditorSheet(
                    name: $profileEditorNameDraft,
                    imageData: $profileEditorImageDraft,
                    email: firebaseService.signedInEmail
                ) { updatedName, updatedPhotoData in
                    let trimmedName = updatedName.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmedName.isEmpty else { return }

                    let photoData = updatedPhotoData.map { compressedProfileImageData(from: $0) }
                    profileSaveAttemptCount += 1
                    lastProfileSaveAt = Date()
                    lastProfileSaveNameLength = trimmedName.count
                    lastProfileSavePhotoBytes = photoData?.count ?? 0
                    lastProfileSaveErrorMessage = nil
                    PhotoDiagnosticsStore.increment("diag.profileSaveAttemptCount")
                    PhotoDiagnosticsStore.setNow("diag.lastProfileSaveAttemptAt")
                    PhotoDiagnosticsStore.set("diag.lastProfileSaveNameLength", String(trimmedName.count))
                    PhotoDiagnosticsStore.set("diag.lastProfileSavePhotoBytes", String(photoData?.count ?? 0))
                    PhotoDiagnosticsStore.set("diag.lastProfileSaveFlow", "account-profile-editor")

                    firebaseService.profileDisplayName = trimmedName
                    persistProfileDisplayName(trimmedName)
                    if let photoData {
                        customProfileImageData = photoData
                        firebaseService.profilePhotoData = photoData
                        persistProfileImage(photoData)
                    }

                    await firebaseService.updateProfileMetadata(displayName: trimmedName, photoData: photoData)
                    await MainActor.run {
                        let saveError = firebaseService.lastErrorMessage?.trimmingCharacters(in: .whitespacesAndNewlines)
                        if let saveError, !saveError.isEmpty {
                            lastProfileSaveErrorMessage = saveError
                            PhotoDiagnosticsStore.set("diag.lastProfileSaveError", saveError)
                            PhotoDiagnosticsStore.setNow("diag.lastProfileSaveFailureAt")
                        } else {
                            lastProfileSaveErrorMessage = nil
                            PhotoDiagnosticsStore.set("diag.lastProfileSaveError", "<nil>")
                            PhotoDiagnosticsStore.setNow("diag.lastProfileSaveSuccessAt")
                        }

                        if let latestPhoto = firebaseService.profilePhotoData {
                            customProfileImageData = latestPhoto
                            persistProfileImage(latestPhoto)
                        }
                        showProfileEditor = false
                    }
                }
                .presentationDetents([.height(460)])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(28)
            }
            .alert("Sign Out?", isPresented: $showSignOutConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Sign Out", role: .destructive) {
                    performConfirmedSignOut()
                }
            } message: {
                Text("You will need to sign in again to access cloud backup and sync.")
            }
            .onChange(of: firebaseService.lastErrorMessage) { _, newValue in
                statusClearTask?.cancel()
                guard let newValue, !newValue.isEmpty else {
                    transientStatusMessage = nil
                    return
                }
                transientStatusMessage = newValue
                statusClearTask = Task { @MainActor in
                    try? await Task.sleep(for: .seconds(3))
                    guard !Task.isCancelled else { return }
                    if transientStatusMessage == newValue {
                        transientStatusMessage = nil
                    }
                }
            }
            .onDisappear {
                statusClearTask?.cancel()
            }
            .onAppear {
                loadStoredProfileImageIfNeeded()
                loadStoredProfileNameIfNeeded()
                if let existingError = firebaseService.lastErrorMessage, !existingError.isEmpty {
                    transientStatusMessage = existingError
                    statusClearTask?.cancel()
                    statusClearTask = Task { @MainActor in
                        try? await Task.sleep(for: .seconds(3))
                        guard !Task.isCancelled else { return }
                        if transientStatusMessage == existingError {
                            transientStatusMessage = nil
                        }
                    }
                }
                Task {
                    await firebaseService.refreshProfileMetadata()
                    await MainActor.run {
                        if customProfileImageData == nil {
                            customProfileImageData = firebaseService.profilePhotoData
                        }
                    }
                }
            }
            .onChange(of: firebaseService.signedInEmail) { _, _ in
                loadStoredProfileImageIfNeeded()
                loadStoredProfileNameIfNeeded()
                Task {
                    await firebaseService.ensureProfileSeededFromEmailIfNeeded()
                    await MainActor.run {
                        if customProfileImageData == nil {
                            customProfileImageData = firebaseService.profilePhotoData
                        }
                    }
                }
            }
        }
    }

    private var signedInStatusSection: some View {
        Section {
            HStack(spacing: 16) {
                profileAvatar

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 10) {
                        Text(userDisplayName)
                            .font(.headline)

                        editProfileButton
                    }

                    Text(firebaseService.signedInEmail ?? "Anonymous account")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer()
            }
            .padding(.vertical, 8)
        }
        .listRowBackground(Color.clear)
    }

    private var loginSection: some View {
        VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Spacer()
                    orbLogo
                    Spacer()
                }

                VStack(alignment: .center, spacing: 6) {
                    Text(authHeadline)
                        .font(.system(size: 37, weight: .bold, design: .rounded))
                        .frame(maxWidth: .infinity, alignment: .center)
                    Text(authSubtitle)
                        .font(.system(size: 16, weight: .regular, design: .rounded))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.center)
                }

                VStack(spacing: 12) {
                    if authMode == .signUp {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Full Name*")
                                .font(.footnote.weight(.medium))
                                .foregroundStyle(.secondary)

                            TextField(
                                "",
                                text: $fullName,
                                prompt: Text("Alex Smith").foregroundStyle(Color.gray.opacity(0.62))
                            )
                                .textInputAutocapitalization(.words)
                                .focused($focusedAuthField, equals: .fullName)
                                .foregroundStyle(.white)
                                .tint(.white)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 12)
                                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(Color.white.opacity(0.11), lineWidth: 1)
                                )
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Email address*")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(.secondary)

                        TextField(
                            "",
                            text: $email,
                            prompt: Text("example@gmail.com").foregroundStyle(Color.gray.opacity(0.62))
                        )
                            .textInputAutocapitalization(.never)
                            .keyboardType(.emailAddress)
                            .autocorrectionDisabled(true)
                            .focused($focusedAuthField, equals: .email)
                            .foregroundStyle(.white)
                            .tint(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(Color.white.opacity(0.11), lineWidth: 1)
                            )
                    }

                    if authMode != .forgotPassword {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Password*")
                                .font(.footnote.weight(.medium))
                                .foregroundStyle(.secondary)

                            SecureField(
                                "",
                                text: $password,
                                prompt: Text("@Sn123hsn#").foregroundStyle(Color.gray.opacity(0.62))
                            )
                                .focused($focusedAuthField, equals: .password)
                                .foregroundStyle(.white)
                                .tint(.white)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 12)
                                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(Color.white.opacity(0.11), lineWidth: 1)
                                )
                        }
                    }
                }

                Group {
                    if authMode == .signIn {
                        primaryAuthButton(
                            title: "Sign in",
                            systemImage: "sparkles"
                        ) {
                            await performAuthAction {
                                await firebaseService.signIn(
                                    email: email.trimmingCharacters(in: .whitespacesAndNewlines),
                                    password: password
                                )
                                await dismissAfterAuthIfNeeded()
                            }
                        }

                        HStack {
                            Spacer()
                            Button("Forgot Password?") {
                                authMode = .forgotPassword
                            }
                            .buttonStyle(.plain)
                            .font(.footnote.weight(.bold))
                            .foregroundStyle(.white.opacity(0.9))
                        }
                    } else if authMode == .signUp {
                        primaryAuthButton(
                            title: "Register",
                            systemImage: "sparkles"
                        ) {
                            await performAuthAction {
                                await firebaseService.signUp(
                                    email: email.trimmingCharacters(in: .whitespacesAndNewlines),
                                    password: password
                                )

                                let trimmedName = fullName.trimmingCharacters(in: .whitespacesAndNewlines)
                                if firebaseService.isSignedIn, !trimmedName.isEmpty {
                                    await firebaseService.updateProfileMetadata(displayName: trimmedName)
                                }

                                await dismissAfterAuthIfNeeded()
                            }
                        }
                    } else {
                        primaryAuthButton(
                            title: "Send Code",
                            systemImage: "sparkles"
                        ) {
                            await performAuthAction {
                                await firebaseService.sendPasswordReset(
                                    email: email.trimmingCharacters(in: .whitespacesAndNewlines)
                                )
                            }
                        }

                        HStack {
                            Spacer()
                            Button("Already have an account? Sign In") {
                                authMode = .signIn
                            }
                            .buttonStyle(.plain)
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(.white.opacity(0.9))
                        }
                    }
                }

#if os(iOS) && canImport(GoogleSignIn)
                if authMode != .forgotPassword {
                    HStack {
                        Rectangle()
                            .fill(Color.white.opacity(0.12))
                            .frame(height: 1)
                        Text("Or continue with")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Rectangle()
                            .fill(Color.white.opacity(0.12))
                            .frame(height: 1)
                    }

                    Button {
                        Task {
                            await performAuthAction {
                                handleGoogleSignIn()
                            }
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image("GoogleLogo")
                                .resizable()
                                .interpolation(.high)
                                .antialiased(true)
                                .frame(width: 16, height: 16)
                            Text("Google")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.black.opacity(0.88))
                        }
                        .frame(width: 170)
                        .padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)
                    .background(.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.black.opacity(0.12), lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.12), radius: 8, y: 4)
                    .frame(maxWidth: .infinity)
                    .disabled(isPerformingAuthAction)
                    .opacity(isPerformingAuthAction ? 0.6 : 1)

                    HStack {
                        Spacer()
                        if authMode == .signIn {
                            Text("Don't have an account?")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            Button("Sign up") {
                                authMode = .signUp
                            }
                            .buttonStyle(.plain)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.white)
                        } else {
                            Text("Already have an account?")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            Button("Sign In") {
                                authMode = .signIn
                            }
                            .buttonStyle(.plain)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.white)
                        }
                        Spacer()
                    }
                }
#endif
        }
        .padding(.horizontal, 6)
    }

    private var orbLogo: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            AppTheme.accent,
                            AppTheme.accentSoft,
                            Color.black.opacity(0.6)
                        ],
                        center: .center,
                        startRadius: 4,
                        endRadius: 48
                    )
                )
                .frame(width: 64, height: 64)

            Image("AppLogoGlyph")
                .resizable()
                .scaledToFit()
                .frame(width: 42, height: 42)

            Circle()
                .stroke(AppTheme.accent.opacity(0.45), lineWidth: 1)
                .frame(width: 78, height: 78)
        }
    }

    private var authHeadline: String {
        switch authMode {
        case .signIn:
            return "Welcome Back!"
        case .signUp:
            return "Create Your Account?"
        case .forgotPassword:
            return "Forgot Password?"
        }
    }

    private var authSubtitle: String {
        switch authMode {
        case .signIn:
            return "Sign in to access smart, personalized schedule management across your devices."
        case .signUp:
            return "Create your account to explore exciting automation and seamless cloud backup."
        case .forgotPassword:
            return "Enter your email and we'll send a password reset link instantly."
        }
    }

    @ViewBuilder
    private func primaryAuthButton(
        title: String,
        systemImage: String,
        action: @escaping () async -> Void
    ) -> some View {
        Button {
            Task {
                await action()
            }
        } label: {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.black.opacity(0.9))
        .background(
            LinearGradient(
                colors: [
                    AppTheme.accent,
                    AppTheme.accentSoft
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .shadow(color: AppTheme.accent.opacity(0.3), radius: 14, y: 8)
        .opacity(isPerformingAuthAction ? 0.6 : 1)
        .disabled(isPerformingAuthAction)
    }

    private var cloudBackupSection: some View {
        Section("Cloud Setting") {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Button {
                        viewModel.syncCloudBackupNowIfSignedIn()
                    } label: {
                        Label("Sync Now", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(AppTheme.accent)
                    .disabled(viewModel.isRestoreInProgress || viewModel.isSyncNowInProgress)

                    Spacer()

                    if viewModel.isSyncNowInProgress {
                        HStack(spacing: 8) {
                            ProgressView(value: viewModel.syncCoordinator.syncProgress)
                                .frame(width: 88)
                            Text(syncProgressPercentText)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(AppTheme.accent)
                        }
                    } else {
                        Text(syncStatusText)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(syncStatusColor)
                    }
                }

                if let lastSyncedAt = firebaseService.lastSyncedAt {
                    HStack(alignment: .firstTextBaseline, spacing: 0) {
                        Color.clear
                            .frame(width: cloudRowLabelInset, height: 1)
                        Text("Last synced: \(lastSyncedAt.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                    }
                }

                if let syncActivity = viewModel.syncCoordinator.syncLastActivityMessage,
                   !syncActivity.isEmpty {
                    HStack(alignment: .firstTextBaseline, spacing: 0) {
                        Color.clear
                            .frame(width: cloudRowLabelInset, height: 1)
                        Text(syncActivity)
                            .font(.caption)
                            .foregroundStyle(viewModel.syncCoordinator.syncState == .error ? .red : .secondary)
                        Spacer(minLength: 0)
                    }
                }

                HStack {
                    Button {
                        copySyncDiagnosticsToClipboard()
                    } label: {
                        Label("Copy Sync Diagnostics", systemImage: "doc.on.doc")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)

                    Spacer()
                }

                HStack {
                    Button {
                        copyPhotoDiagnosticsToClipboard()
                    } label: {
                        Label("Copy Photo Diagnostics", systemImage: "photo.on.rectangle.angled")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)

                    Spacer()
                }

                if let syncDiagnosticsStatusMessage, !syncDiagnosticsStatusMessage.isEmpty {
                    HStack(alignment: .firstTextBaseline, spacing: 0) {
                        Color.clear
                            .frame(width: cloudRowLabelInset, height: 1)
                        Text(syncDiagnosticsStatusMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                    }
                }

                if let photoDiagnosticsStatusMessage, !photoDiagnosticsStatusMessage.isEmpty {
                    HStack(alignment: .firstTextBaseline, spacing: 0) {
                        Color.clear
                            .frame(width: cloudRowLabelInset, height: 1)
                        Text(photoDiagnosticsStatusMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                    }
                }
            }

            if !viewModel.syncCoordinator.pendingConflicts.isEmpty {
                HStack {
                    Button {
                        showingConflictReview = true
                    } label: {
                        Label("Resolve Conflicts", systemImage: "exclamationmark.arrow.trianglehead.2.clockwise.rotate.90")
                    }
                    .buttonStyle(.plain)
                    Spacer()
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Button {
                        Task {
                            viewModel.beginCloudRestoreGate()
                            defer {
                                viewModel.completeCloudRestoreGate()
                            }

                            let downloadResult = await firebaseService.downloadBackupWithResult()
                            switch downloadResult {
                            case .success(let backup) where !backup.data.isEmpty:
                                if let version = backup.globalSyncVersion {
                                    viewModel.seedGlobalSyncVersion(version)
                                }
                                let restoreResult = viewModel.importBackupData(
                                    backup.data,
                                    includeSchedules: true,
                                    includeSettings: true
                                )
                                manualRestoreStatusMessage = restoreResult.userMessage

                            case .missingBackup, .success:
                                manualRestoreStatusMessage = "No cloud backup found."

                            case .notConfigured, .authFailed:
                                manualRestoreStatusMessage = "Not signed in."

                            case .networkError(let msg):
                                manualRestoreStatusMessage = "Download failed: \(msg)"

                            case .decodeFailed(let msg):
                                manualRestoreStatusMessage = "Backup corrupt: \(msg)"

                            case .cacheFallback(let backup) where !backup.data.isEmpty:
                                if let version = backup.globalSyncVersion {
                                    viewModel.seedGlobalSyncVersion(version)
                                }
                                let restoreResult = viewModel.importBackupData(
                                    backup.data,
                                    includeSchedules: true,
                                    includeSettings: true
                                )
                                manualRestoreStatusMessage = restoreResult.userMessage + " (cached)"

                            case .cacheFallback:
                                manualRestoreStatusMessage = "No cached backup available."
                            }
                        }
                    } label: {
                        Label("Restore", systemImage: "arrow.counterclockwise.circle")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(AppTheme.accent)
                    .disabled(viewModel.isRestoreInProgress)

                    Spacer()
                }

                if viewModel.isRestoreInProgress {
                    HStack(alignment: .top, spacing: 0) {
                        Color.clear
                            .frame(width: cloudRowLabelInset, height: 1)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Restoration Progress")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            ProgressView(value: viewModel.restoreProgress)
                            Text("\(Int(viewModel.restoreProgress * 100))%")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                } else if let lastRestore = viewModel.lastRestoreCompletedAt {
                    HStack(alignment: .firstTextBaseline, spacing: 0) {
                        Color.clear
                            .frame(width: cloudRowLabelInset, height: 1)
                        Text("Last restore: \(lastRestore.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                    }
                }

                if let msg = manualRestoreStatusMessage {
                    HStack(alignment: .firstTextBaseline, spacing: 0) {
                        Color.clear
                            .frame(width: cloudRowLabelInset, height: 1)
                        Text(msg)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                    }
                    .onAppear {
                        Task {
                            try? await Task.sleep(for: .seconds(4))
                            manualRestoreStatusMessage = nil
                        }
                    }
                }
            }

            HStack {
                Button(role: .destructive) {
                    showSignOutConfirmation = true
                } label: {
                    if isSigningOut {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Signing Out...")
                        }
                    } else {
                        Text("Sign Out")
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.red)
                .disabled(isSigningOut)

                Spacer()
            }
        }
    }

    @MainActor
    private func performConfirmedSignOut() {
        guard !isSigningOut else { return }
        isSigningOut = true
        showSignOutConfirmation = false

        // Dismiss immediately for a snappy response, then complete auth teardown.
        dismiss()

        Task { @MainActor in
            firebaseService.signOut()
            NotificationCenter.default.post(name: Notification.Name("Schedulr.AuthDidSignOut"), object: nil)
            isSigningOut = false
        }
    }

    private var userDisplayName: String {
        if let storedDisplayName = storedProfileDisplayName(), !storedDisplayName.isEmpty {
            return storedDisplayName
        }

        if let profileDisplayName = firebaseService.profileDisplayName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !profileDisplayName.isEmpty
        {
            return profileDisplayName
        }

        guard let email = firebaseService.signedInEmail,
              let localPart = email.split(separator: "@").first,
              !localPart.isEmpty
        else {
            return "User"
        }

        return localPart
            .replacingOccurrences(of: ".", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }
            .joined(separator: " ")
    }

    private func copySyncDiagnosticsToClipboard() {
        let diagnostics = buildSyncDiagnosticsPayload()

#if os(iOS)
        UIPasteboard.general.string = diagnostics
#elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(diagnostics, forType: .string)
#endif

        syncDiagnosticsStatusMessage = "Sync diagnostics copied to clipboard."
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(4))
            syncDiagnosticsStatusMessage = nil
        }
    }

    private func buildSyncDiagnosticsPayload() -> String {
        let report = viewModel.syncCoordinator.lastSyncReport
        let state = String(describing: viewModel.syncCoordinator.syncState)
        let progress = Int((viewModel.syncCoordinator.syncProgress * 100).rounded())
        let activity = viewModel.syncCoordinator.syncLastActivityMessage ?? "<nil>"
        let firebaseError = firebaseService.lastErrorMessage ?? "<nil>"

        var lines: [String] = []
        lines.append("Timestamp: \(Date().formatted(date: .abbreviated, time: .standard))")
        lines.append("SyncState: \(state)")
        lines.append("SyncProgress: \(progress)%")
        lines.append("SyncLastActivityMessage: \(activity)")
        lines.append("FirebaseLastErrorMessage: \(firebaseError)")

        if let report {
            lines.append("Report.succeeded: \(report.succeeded)")
            lines.append("Report.userMessage: \(report.userMessage)")
            lines.append("Report.deltaPushSucceeded: \(report.deltaPushSucceeded)")
            lines.append("Report.deltaPullSucceeded: \(report.deltaPullSucceeded)")
            lines.append("Report.backupUploadSucceeded: \(report.backupUploadSucceeded)")
            lines.append("Report.deltaPushCount: \(report.deltaPushCount)")
            lines.append("Report.deltaPullCount: \(report.deltaPullCount)")
            lines.append("Report.conflictsRemaining: \(report.conflictsRemaining)")
            lines.append("Report.failure: \(String(describing: report.failure))")
            if !report.warnings.isEmpty {
                lines.append("Report.warnings: \(report.warnings.joined(separator: " | "))")
            }
        } else {
            lines.append("Report: <nil>")
        }

        return lines.joined(separator: "\n")
    }

    private func copyPhotoDiagnosticsToClipboard() {
        let diagnostics = buildPhotoDiagnosticsPayload()

#if os(iOS)
        UIPasteboard.general.string = diagnostics
#elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(diagnostics, forType: .string)
#endif

        photoDiagnosticsStatusMessage = "Photo diagnostics copied to clipboard."
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(4))
            photoDiagnosticsStatusMessage = nil
        }
    }

    private func buildPhotoDiagnosticsPayload() -> String {
        let diag = PhotoDiagnosticsStore.snapshot()
        let email = firebaseService.signedInEmail ?? "<nil>"
        let firebaseDisplayName = firebaseService.profileDisplayName ?? "<nil>"
        let resolvedDisplayName = userDisplayName
        let storedDisplayName = storedProfileDisplayName() ?? "<nil>"
        let customImageBytes = customProfileImageData?.count ?? 0
        let firebaseImageBytes = firebaseService.profilePhotoData?.count ?? 0
        let storedImageBytes: Int = {
            guard let key = profileImageStorageKey() else { return 0 }
            return UserDefaults.standard.data(forKey: key)?.count ?? 0
        }()
        let lockedDismissCount = UserDefaults.standard.integer(forKey: Self.lockedPickerInstantDismissCountKey)
        let firebaseError = firebaseService.lastErrorMessage ?? "<nil>"
        let saveError = lastProfileSaveErrorMessage ?? "<nil>"
        let saveAt = lastProfileSaveAt?.formatted(date: .abbreviated, time: .standard) ?? "<nil>"
        let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "<nil>"
        let appBuild = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "<nil>"
        let firestoreDatabaseID = (Bundle.main.object(forInfoDictionaryKey: "FIRESTORE_DATABASE_ID") as? String) ?? "(default)"
        let diagLastPickerFlow = diag["diag.lastPickerFlow"] ?? "<nil>"
        let diagLastPickerPath = diag["diag.lastPickerPath"] ?? "<nil>"
        let diagLastPickerRequestReason = diag["diag.lastPickerRequestReason"] ?? "<nil>"
        let diagLastPermissionReadWrite = diag["diag.lastPermission.readWrite"] ?? "<nil>"
        let diagLastPHPickerResult = diag["diag.lastPHPickerResult"] ?? "<nil>"
        let diagLastFileImporterResult = diag["diag.lastFileImporterResult"] ?? "<nil>"
        let diagLastCropResult = diag["diag.lastCropResult"] ?? "<nil>"

        var lines: [String] = []
        lines.append("Timestamp: \(Date().formatted(date: .abbreviated, time: .standard))")
        lines.append("AppVersion: \(appVersion) (\(appBuild))")
        lines.append("FirestoreDatabaseID: \(firestoreDatabaseID)")
        lines.append("SignedInEmail: \(email)")
        lines.append("ResolvedDisplayName: \(resolvedDisplayName)")
        lines.append("FirebaseProfileDisplayName: \(firebaseDisplayName)")
        lines.append("StoredProfileDisplayName: \(storedDisplayName)")
        lines.append("CustomProfileImageBytes: \(customImageBytes)")
        lines.append("FirebaseProfileImageBytes: \(firebaseImageBytes)")
        lines.append("StoredProfileImageBytes: \(storedImageBytes)")
        lines.append("LockedPickerInstantDismissCount: \(lockedDismissCount)")
        lines.append("ProfileSaveAttemptCount: \(profileSaveAttemptCount)")
        lines.append("LastProfileSaveAt: \(saveAt)")
        lines.append("LastProfileSaveNameLength: \(lastProfileSaveNameLength)")
        lines.append("LastProfileSavePhotoBytes: \(lastProfileSavePhotoBytes)")
        lines.append("LastProfileSaveError: \(saveError)")
        lines.append("FirebaseLastErrorMessage: \(firebaseError)")
        lines.append("Diag.lastPickerFlow: \(diagLastPickerFlow)")
        lines.append("Diag.lastPickerPath: \(diagLastPickerPath)")
        lines.append("Diag.lastPickerRequestReason: \(diagLastPickerRequestReason)")
        lines.append("Diag.lastPermission.readWrite: \(diagLastPermissionReadWrite)")
        lines.append("Diag.lastPHPickerResult: \(diagLastPHPickerResult)")
        lines.append("Diag.lastPHPickerPresentError: \(diag["diag.lastPHPickerPresentError"] ?? "<nil>")")
        lines.append("Diag.lastFileImporterResult: \(diagLastFileImporterResult)")
        lines.append("Diag.lastCropResult: \(diagLastCropResult)")
        lines.append("Diag.phpickerPresentCount: \(diag["diag.phpickerPresentCount"] ?? "0")")
        lines.append("Diag.phpickerInstantDismissCount: \(diag["diag.phpickerInstantDismissCount"] ?? "0")")
        lines.append("Diag.phpickerSilentDismissCount: \(diag["diag.phpickerSilentDismissCount"] ?? "0")")
        lines.append("Diag.phpickerSelectionCount: \(diag["diag.phpickerSelectionCount"] ?? "0")")
        lines.append("Diag.fileImporterSelectionCount: \(diag["diag.fileImporterSelectionCount"] ?? "0")")
        lines.append("Diag.fileImporterFailureCount: \(diag["diag.fileImporterFailureCount"] ?? "0")")
        lines.append("Diag.cropUseCount: \(diag["diag.cropUseCount"] ?? "0")")
        lines.append("Diag.cropCancelCount: \(diag["diag.cropCancelCount"] ?? "0")")
        lines.append("Diag.lastUpdatedAt: \(diag["diag.lastUpdatedAt"] ?? "<nil>")")
        lines.append("Diag.lastProfileSaveAttemptAt: \(diag["diag.lastProfileSaveAttemptAt"] ?? "<nil>")")
        lines.append("Diag.lastProfileSaveSuccessAt: \(diag["diag.lastProfileSaveSuccessAt"] ?? "<nil>")")
        lines.append("Diag.lastProfileSaveFailureAt: \(diag["diag.lastProfileSaveFailureAt"] ?? "<nil>")")
        lines.append("Diag.lastProfileSaveError: \(diag["diag.lastProfileSaveError"] ?? "<nil>")")

#if os(iOS)
        lines.append("DeviceModel: \(UIDevice.current.model)")
        lines.append("SystemVersion: iOS \(UIDevice.current.systemVersion)")
        lines.append("PhotoAuth(readWrite): \(photoAuthorizationDescription(PHPhotoLibrary.authorizationStatus(for: .readWrite)))")
        lines.append("PhotoAuth(addOnly): \(photoAuthorizationDescription(PHPhotoLibrary.authorizationStatus(for: .addOnly)))")
        lines.append("CameraAuth(video): \(cameraAuthorizationDescription(AVCaptureDevice.authorizationStatus(for: .video)))")
#else
        lines.append("PhotoAuth: not-applicable-on-this-platform")
        lines.append("CameraAuth: not-applicable-on-this-platform")
#endif

        lines.append("ExpectedProfileDocPaths: users/{uid} and users/{uid}/profile/current")
        return lines.joined(separator: "\n")
    }

#if os(iOS)
    private func photoAuthorizationDescription(_ status: PHAuthorizationStatus) -> String {
        switch status {
        case .authorized:
            return "authorized"
        case .limited:
            return "limited"
        case .denied:
            return "denied"
        case .restricted:
            return "restricted"
        case .notDetermined:
            return "notDetermined"
        @unknown default:
            return "unknown"
        }
    }

    private func cameraAuthorizationDescription(_ status: AVAuthorizationStatus) -> String {
        switch status {
        case .authorized:
            return "authorized"
        case .denied:
            return "denied"
        case .restricted:
            return "restricted"
        case .notDetermined:
            return "notDetermined"
        @unknown default:
            return "unknown"
        }
    }
#endif

    @ViewBuilder
    private var profileAvatar: some View {
        if let profilePhotoData = customProfileImageData ?? firebaseService.profilePhotoData {
            #if os(iOS)
            if let image = UIImage(data: profilePhotoData) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 68, height: 68)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color.white.opacity(0.14), lineWidth: 1))
            } else {
                defaultProfileAvatar
            }
            #elseif os(macOS)
            if let image = NSImage(data: profilePhotoData) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 68, height: 68)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color.white.opacity(0.14), lineWidth: 1))
            } else {
                defaultProfileAvatar
            }
            #else
            defaultProfileAvatar
            #endif
        } else if let url = gravatarURL {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                default:
                    Image(systemName: "person.crop.circle.fill")
                        .resizable()
                        .scaledToFit()
                        .padding(12)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 68, height: 68)
            .background(Circle().fill(.quaternary))
            .clipShape(Circle())
            .overlay(Circle().stroke(Color.white.opacity(0.14), lineWidth: 1))
        } else {
            defaultProfileAvatar
        }
    }

    private var defaultProfileAvatar: some View {
        ZStack {
            Circle()
                .fill(.quaternary)
                .frame(width: 68, height: 68)
            Image(systemName: "person.crop.circle.fill")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(.secondary)
        }
    }

    private var editProfileButton: some View {
        Button {
            profileEditorNameDraft = userDisplayName
            profileEditorImageDraft = customProfileImageData ?? firebaseService.profilePhotoData
            showProfileEditor = true
        } label: {
            Text("Edit")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(AppTheme.accent)
        }
        .buttonStyle(.plain)
    }

    private var gravatarURL: URL? {
        guard let email = firebaseService.signedInEmail?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !email.isEmpty
        else {
            return nil
        }

        let hash = Insecure.MD5.hash(data: Data(email.utf8))
            .map { String(format: "%02hhx", $0) }
            .joined()
        return URL(string: "https://www.gravatar.com/avatar/\(hash)?d=404&s=160")
    }

    private func profileImageStorageKey() -> String? {
        guard let email = firebaseService.signedInEmail?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !email.isEmpty
        else {
            return nil
        }
        return "profile.image.\(email)"
    }

    private func profileDisplayNameStorageKey() -> String? {
        guard let email = firebaseService.signedInEmail?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !email.isEmpty
        else {
            return nil
        }
        return "profile.displayName.\(email)"
    }

    private func storedProfileDisplayName() -> String? {
        guard let key = profileDisplayNameStorageKey() else { return nil }
        let value = UserDefaults.standard.string(forKey: key)?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value, !value.isEmpty else { return nil }
        return value
    }

    private func loadStoredProfileNameIfNeeded() {
        guard let storedName = storedProfileDisplayName(), !storedName.isEmpty else { return }
        firebaseService.profileDisplayName = storedName
    }

    private func persistProfileDisplayName(_ value: String) {
        guard let key = profileDisplayNameStorageKey() else { return }
        UserDefaults.standard.set(value.trimmingCharacters(in: .whitespacesAndNewlines), forKey: key)
    }

    private func loadStoredProfileImageIfNeeded() {
        guard let key = profileImageStorageKey() else {
            customProfileImageData = nil
            return
        }
        customProfileImageData = UserDefaults.standard.data(forKey: key)
    }

    private func persistProfileImage(_ data: Data) {
        guard let key = profileImageStorageKey() else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    private func compressedProfileImageData(from data: Data) -> Data {
        #if os(iOS)
        guard let image = UIImage(data: data) else { return data }
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 240, height: 240))
        let reduced = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: CGSize(width: 240, height: 240)))
        }
        return reduced.jpegData(compressionQuality: 0.72) ?? data
        #elseif os(macOS)
        guard let image = NSImage(data: data) else { return data }
        let targetSize = NSSize(width: 240, height: 240)
        let resized = NSImage(size: targetSize)
        resized.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: targetSize),
                   from: .zero,
                   operation: .copy,
                   fraction: 1.0)
        resized.unlockFocus()

        guard let tiff = resized.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let jpeg = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.72])
        else {
            return data
        }
        return jpeg
        #else
        return data
        #endif
    }

#if os(iOS)
    private func handleGoogleSignIn() {
#if canImport(GoogleSignIn)
        Task { @MainActor in
            guard let clientID = FirebaseApp.app()?.options.clientID else {
                firebaseService.lastErrorMessage = "Google Sign-In is not configured."
                return
            }

            guard let configPath = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"),
                  let config = NSDictionary(contentsOfFile: configPath),
                  let requiredScheme = config["REVERSED_CLIENT_ID"] as? String,
                  !requiredScheme.isEmpty
            else {
                firebaseService.lastErrorMessage = "GoogleService-Info.plist is missing REVERSED_CLIENT_ID."
                return
            }

            let configuredSchemes = (Bundle.main.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]])?
                .flatMap { $0["CFBundleURLSchemes"] as? [String] ?? [] } ?? []
            if !configuredSchemes.contains(requiredScheme) {
                firebaseService.lastErrorMessage = "Google Sign-In URL scheme is missing in Info.plist."
                return
            }

            let configuration = GIDConfiguration(clientID: clientID)
            GIDSignIn.sharedInstance.configuration = configuration

            guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                  let rootViewController = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController
            else {
                firebaseService.lastErrorMessage = "Unable to present Google Sign-In."
                return
            }

            do {
                let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: rootViewController)
                guard let idToken = result.user.idToken?.tokenString else {
                    firebaseService.lastErrorMessage = "Google Sign-In token is missing."
                    return
                }

                let credential = GoogleAuthProvider.credential(
                    withIDToken: idToken,
                    accessToken: result.user.accessToken.tokenString
                )

                await firebaseService.signInWithCredential(credential)
                await dismissAfterAuthIfNeeded()
            } catch {
                firebaseService.lastErrorMessage = error.localizedDescription
            }
        }
#endif
    }

#endif

    @MainActor
    private func dismissAfterAuthIfNeeded() async {
        if firebaseService.isSignedIn {
            NotificationCenter.default.post(name: Notification.Name("Schedulr.AuthDidSucceed"), object: nil)
            dismiss()
        }
    }

    @MainActor
    private func performAuthAction(_ action: () async -> Void) async {
        guard !isPerformingAuthAction else { return }
        isPerformingAuthAction = true
        defer { isPerformingAuthAction = false }
        await action()
    }

    private func dismissKeyboard() {
#if os(iOS)
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
#endif
    }
}

#if os(iOS)
final class PhotoPickerManager: NSObject, PHPickerViewControllerDelegate {
    static let shared = PhotoPickerManager()

    private var completion: ((UIImage?) -> Void)?

    func present(completion: @escaping (UIImage?) -> Void) {
        self.completion = completion

        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = 1

        let picker = PHPickerViewController(configuration: config)
        picker.delegate = self

        DispatchQueue.main.async {
            guard let topVC = self.topViewController() else {
                completion(nil)
                self.completion = nil
                return
            }
            topVC.present(picker, animated: true)
        }
    }

    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        guard let provider = results.first?.itemProvider else {
            picker.dismiss(animated: true) { self.cleanupAndComplete(nil) }
            return
        }

        picker.dismiss(animated: true) {
            self.extractImage(from: provider)
        }
    }

    private func extractImage(from provider: NSItemProvider) {
        if provider.canLoadObject(ofClass: UIImage.self) {
            provider.loadObject(ofClass: UIImage.self) { object, _ in
                if let image = object as? UIImage {
                    self.cleanupAndComplete(image)
                } else {
                    self.extractDataFallback(from: provider)
                }
            }
            return
        }

        extractDataFallback(from: provider)
    }

    private func extractDataFallback(from provider: NSItemProvider) {
        let identifier = UTType.image.identifier
        guard provider.hasItemConformingToTypeIdentifier(identifier) else {
            cleanupAndComplete(nil)
            return
        }

        provider.loadDataRepresentation(forTypeIdentifier: identifier) { data, _ in
            if let data, let image = UIImage(data: data) {
                self.cleanupAndComplete(image)
                return
            }

            provider.loadFileRepresentation(forTypeIdentifier: identifier) { url, _ in
                guard let url,
                      let data = try? Data(contentsOf: url),
                      let image = UIImage(data: data)
                else {
                    self.cleanupAndComplete(nil)
                    return
                }
                self.cleanupAndComplete(image)
            }
        }
    }

    private func cleanupAndComplete(_ image: UIImage?) {
        DispatchQueue.main.async {
            self.completion?(image)
            self.completion = nil
        }
    }

    private func topViewController() -> UIViewController? {
        guard let windowScene = UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene,
              let root = windowScene.windows.first(where: { $0.isKeyWindow })?.rootViewController
        else {
            return nil
        }

        var top = root
        while let presented = top.presentedViewController {
            top = presented
        }
        return top
    }
}

final class UniversalCropManager: NSObject {
    static let shared = UniversalCropManager()

    func presentCrop(for image: UIImage, completion: @escaping (Data?) -> Void) {
        DispatchQueue.main.async {
            let cropView = ProfileImageCropView(image: image) { croppedData in
                self.dismissAndComplete(data: croppedData, completion: completion)
            } onCancel: {
                self.dismissAndComplete(data: nil, completion: completion)
            }

            let hostingController = UIHostingController(rootView: cropView)
            hostingController.modalPresentationStyle = .fullScreen
            hostingController.view.backgroundColor = .black

            guard let topVC = self.topViewController() else {
                completion(nil)
                return
            }
            topVC.present(hostingController, animated: true)
        }
    }

    private func dismissAndComplete(data: Data?, completion: @escaping (Data?) -> Void) {
        DispatchQueue.main.async {
            guard let topVC = self.topViewController() else {
                completion(data)
                return
            }

            topVC.dismiss(animated: true) {
                completion(data)
            }
        }
    }

    private func topViewController() -> UIViewController? {
        guard let windowScene = UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene,
              let root = windowScene.windows.first(where: { $0.isKeyWindow })?.rootViewController
        else {
            return nil
        }

        var top = root
        while let presented = top.presentedViewController {
            top = presented
        }
        return top
    }
}

private struct CameraImagePicker: UIViewControllerRepresentable {
    let onPicked: (UIImage?) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onPicked: onPicked)
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onPicked: (UIImage?) -> Void

        init(onPicked: @escaping (UIImage?) -> Void) {
            self.onPicked = onPicked
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            let image = info[.originalImage] as? UIImage
            onPicked(image)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onPicked(nil)
        }
    }
}

private struct AccountProfileEditorSheet: View {
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.bittu.Schedulr",
        category: "profile-image"
    )

    @Binding var name: String
    @Binding var imageData: Data?
    let email: String?
    let onSave: (_ name: String, _ imageData: Data?) async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var showImageSourceDialog = false
    @State private var showFileImporter = false
    @State private var showCameraPermissionAlert = false
    @State private var cameraPermissionMessage = ""
    @State private var isSaving = false
    @State private var showCameraPicker = false

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        ZStack {
            NavigationStack {
                VStack(spacing: 18) {
                Button {
                    showImageSourceDialog = true
                } label: {
                    ZStack(alignment: .bottomTrailing) {
                        Group {
                            if let imageData,
                               let uiImage = UIImage(data: imageData)
                            {
                                Image(uiImage: uiImage)
                                    .resizable()
                                    .scaledToFill()
                            } else {
                                Image(systemName: "person.crop.circle.fill")
                                    .resizable()
                                    .scaledToFit()
                                    .padding(16)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(width: 104, height: 104)
                        .background(Circle().fill(.quaternary))
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color.white.opacity(0.16), lineWidth: 1))

                        Image(systemName: "plus")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 28, height: 28)
                            .background(
                                Circle()
                                    .fill(Color.black.opacity(0.32))
                            )
                            .overlay(
                                Circle()
                                    .stroke(Color.white.opacity(0.35), lineWidth: 1)
                            )
                    }
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .center)

                TextField("Display Name", text: $name)
                    .textInputAutocapitalization(.words)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 11)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .frame(maxWidth: .infinity)

                if let email, !email.isEmpty {
                    Text(email)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                }

                Spacer()
                }
                .padding(16)
                .navigationTitle("Edit Profile")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }
                        Task { @MainActor in
                            isSaving = true
                            await onSave(trimmed, imageData)
                            isSaving = false
                        }
                    }
                    .disabled(!canSave || isSaving)
                }
                }
                .confirmationDialog("Profile Image", isPresented: $showImageSourceDialog, titleVisibility: .visible) {
                Button("Select from Photos") {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        PhotoDiagnosticsStore.set("diag.lastPickerFlow", "requested")
                        PhotoDiagnosticsStore.set("diag.lastPickerPath", "isolated-window")
                        PhotoDiagnosticsStore.setNow("diag.lastPickerRequestedAt")
                        PhotoDiagnosticsStore.set("diag.lastPickerRequestReason", "isolated-phpicker-window")
                        PhotoDiagnosticsStore.increment("diag.phpickerPresentCount")
                        PhotoDiagnosticsStore.set("diag.lastPHPickerResult", "pending-native-photospicker")
                        PhotoDiagnosticsStore.setNow("diag.lastPHPickerPresentedAt")

                        PhotoPickerManager.shared.present { selectedImage in
                            DispatchQueue.main.async {
                                guard let selectedImage else {
                                    PhotoDiagnosticsStore.set("diag.lastPHPickerResult", "cancel-or-no-selection")
                                    PhotoDiagnosticsStore.setNow("diag.lastPHPickerResultAt")
                                    return
                                }

                                PhotoDiagnosticsStore.set("diag.lastPickerFlow", "presented")
                                PhotoDiagnosticsStore.set("diag.lastPickerPath", "isolated-window")
                                PhotoDiagnosticsStore.set("diag.lastPHPickerResult", "selected")
                                PhotoDiagnosticsStore.increment("diag.phpickerSelectionCount")
                                PhotoDiagnosticsStore.setNow("diag.lastPHPickerResultAt")

                                UniversalCropManager.shared.presentCrop(for: selectedImage) { croppedData in
                                    guard let croppedData else {
                                        PhotoDiagnosticsStore.set("diag.lastCropResult", "cancel")
                                        PhotoDiagnosticsStore.increment("diag.cropCancelCount")
                                        PhotoDiagnosticsStore.setNow("diag.lastCropAt")
                                        return
                                    }
                                    DispatchQueue.main.async {
                                        PhotoDiagnosticsStore.set("diag.lastCropResult", "use")
                                        PhotoDiagnosticsStore.set("diag.lastCropBytes", String(croppedData.count))
                                        PhotoDiagnosticsStore.increment("diag.cropUseCount")
                                        PhotoDiagnosticsStore.setNow("diag.lastCropAt")
                                        withAnimation {
                                            imageData = croppedData
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button("Open Camera") {
                        PhotoDiagnosticsStore.set("diag.lastPickerFlow", "requested")
                        PhotoDiagnosticsStore.set("diag.lastPickerPath", "camera")
                        PhotoDiagnosticsStore.setNow("diag.lastPickerRequestedAt")
                        requestAndOpenCameraIfAllowed()
                    }
                }
                Button("Select from Files") {
                    PhotoDiagnosticsStore.set("diag.lastPickerFlow", "requested")
                    PhotoDiagnosticsStore.set("diag.lastPickerPath", "files")
                    PhotoDiagnosticsStore.setNow("diag.lastPickerRequestedAt")
                    showFileImporter = true
                }
                Button("Cancel", role: .cancel) {}
                }
                .alert("Camera Access", isPresented: $showCameraPermissionAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(cameraPermissionMessage)
            }
                .fullScreenCover(isPresented: $showCameraPicker) {
                CameraImagePicker { image in
                    showCameraPicker = false

                    if let image {
                        PhotoDiagnosticsStore.set("diag.lastCameraPickerResult", "selected")
                        PhotoDiagnosticsStore.setNow("diag.lastCameraPickerAt")

                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            UniversalCropManager.shared.presentCrop(for: image) { croppedData in
                                guard let croppedData else {
                                    PhotoDiagnosticsStore.set("diag.lastCropResult", "cancel")
                                    PhotoDiagnosticsStore.increment("diag.cropCancelCount")
                                    PhotoDiagnosticsStore.setNow("diag.lastCropAt")
                                    return
                                }
                                DispatchQueue.main.async {
                                    PhotoDiagnosticsStore.set("diag.lastCropResult", "use")
                                    PhotoDiagnosticsStore.set("diag.lastCropBytes", String(croppedData.count))
                                    PhotoDiagnosticsStore.increment("diag.cropUseCount")
                                    PhotoDiagnosticsStore.setNow("diag.lastCropAt")
                                    withAnimation {
                                        imageData = croppedData
                                    }
                                }
                            }
                        }
                    } else {
                        PhotoDiagnosticsStore.set("diag.lastCameraPickerResult", "cancel")
                        PhotoDiagnosticsStore.setNow("diag.lastCameraPickerAt")
                    }
                }
                .ignoresSafeArea()
                }
                .onAppear {
                PhotoDiagnosticsStore.setNow("diag.profileEditorOpenedAt")
                PhotoDiagnosticsStore.set("diag.profileEditorHasExistingImage", String(imageData != nil))
            }
                .fileImporter(
                isPresented: $showFileImporter,
                allowedContentTypes: [.image],
                allowsMultipleSelection: false
            ) { result in
                guard case .success(let urls) = result,
                      let url = urls.first
                else {
                    PhotoDiagnosticsStore.set("diag.lastFileImporterResult", "cancel-or-failure")
                    PhotoDiagnosticsStore.increment("diag.fileImporterFailureCount")
                    PhotoDiagnosticsStore.setNow("diag.lastFileImporterAt")
                    return
                }

                let started = url.startAccessingSecurityScopedResource()
                defer { if started { url.stopAccessingSecurityScopedResource() } }

                guard let data = try? Data(contentsOf: url),
                      let uiImage = UIImage(data: data)
                else {
                    PhotoDiagnosticsStore.set("diag.lastFileImporterResult", "decode-failed")
                    PhotoDiagnosticsStore.increment("diag.fileImporterFailureCount")
                    PhotoDiagnosticsStore.setNow("diag.lastFileImporterAt")
                    return
                }
                PhotoDiagnosticsStore.set("diag.lastFileImporterResult", "selected")
                PhotoDiagnosticsStore.set("diag.lastFileImporterBytes", String(data.count))
                PhotoDiagnosticsStore.increment("diag.fileImporterSelectionCount")
                PhotoDiagnosticsStore.setNow("diag.lastFileImporterAt")

                UniversalCropManager.shared.presentCrop(for: uiImage) { croppedData in
                    guard let croppedData else {
                        PhotoDiagnosticsStore.set("diag.lastCropResult", "cancel")
                        PhotoDiagnosticsStore.increment("diag.cropCancelCount")
                        PhotoDiagnosticsStore.setNow("diag.lastCropAt")
                        return
                    }
                    DispatchQueue.main.async {
                        PhotoDiagnosticsStore.set("diag.lastCropResult", "use")
                        PhotoDiagnosticsStore.set("diag.lastCropBytes", String(croppedData.count))
                        PhotoDiagnosticsStore.increment("diag.cropUseCount")
                        PhotoDiagnosticsStore.setNow("diag.lastCropAt")
                        withAnimation {
                            imageData = croppedData
                        }
                    }
                }
                }
            }
        }
    }

    private func requestAndOpenCameraIfAllowed() {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            PhotoDiagnosticsStore.set("diag.lastCameraPermissionResult", "camera-unavailable")
            cameraPermissionMessage = "Camera is not available on this device."
            showCameraPermissionAlert = true
            return
        }

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            PhotoDiagnosticsStore.set("diag.lastCameraPermissionResult", "authorized")
            PhotoDiagnosticsStore.setNow("diag.lastCameraPermissionCheckedAt")
            showCameraPicker = true
        case .notDetermined:
            PhotoDiagnosticsStore.set("diag.lastCameraPermissionResult", "notDetermined")
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    if granted {
                        PhotoDiagnosticsStore.set("diag.lastCameraPermissionResult", "authorized-after-prompt")
                        PhotoDiagnosticsStore.setNow("diag.lastCameraPermissionCheckedAt")
                        self.showCameraPicker = true
                    } else {
                        PhotoDiagnosticsStore.set("diag.lastCameraPermissionResult", "denied-after-prompt")
                        PhotoDiagnosticsStore.setNow("diag.lastCameraPermissionCheckedAt")
                        self.cameraPermissionMessage = "Camera access is required to take a profile photo."
                        self.showCameraPermissionAlert = true
                    }
                }
            }
        case .denied, .restricted:
            PhotoDiagnosticsStore.set("diag.lastCameraPermissionResult", "denied-or-restricted")
            PhotoDiagnosticsStore.setNow("diag.lastCameraPermissionCheckedAt")
            cameraPermissionMessage = "Please allow camera access in iOS Settings to use this option."
            showCameraPermissionAlert = true
        @unknown default:
            PhotoDiagnosticsStore.set("diag.lastCameraPermissionResult", "unknown")
            PhotoDiagnosticsStore.setNow("diag.lastCameraPermissionCheckedAt")
            cameraPermissionMessage = "Camera permission status is unavailable."
            showCameraPermissionAlert = true
        }
    }

}

private struct ProfileImageCropView: View {
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.bittu.Schedulr",
        category: "profile-image"
    )

    let image: UIImage
    let onUse: (Data) -> Void
    let onCancel: () -> Void

    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var containerSize: CGSize = .zero

    private let cropDiameter: CGFloat = 280

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                ZStack {
                    Color.black.ignoresSafeArea()

                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .scaleEffect(scale)
                        .offset(offset)
                        .gesture(
                            SimultaneousGesture(
                                MagnifyGesture()
                                    .onChanged { value in
                                        scale = max(1.0, lastScale * value.magnification)
                                    }
                                    .onEnded { _ in
                                        scale = max(1.0, scale)
                                        lastScale = scale
                                    },
                                DragGesture()
                                    .onChanged { value in
                                        offset = CGSize(
                                            width: lastOffset.width + value.translation.width,
                                            height: lastOffset.height + value.translation.height
                                        )
                                    }
                                    .onEnded { _ in
                                        lastOffset = offset
                                    }
                            )
                        )

                    Rectangle()
                        .fill(Color.black.opacity(0.55))
                        .mask {
                            ZStack {
                                Rectangle()
                                Circle()
                                    .frame(width: cropDiameter, height: cropDiameter)
                                    .blendMode(.destinationOut)
                            }
                            .compositingGroup()
                        }
                        .allowsHitTesting(false)

                    Circle()
                        .stroke(Color.white.opacity(0.6), lineWidth: 1)
                        .frame(width: cropDiameter, height: cropDiameter)
                        .allowsHitTesting(false)

                    VStack {
                        Spacer()
                        Text("Move and Scale")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.white.opacity(0.7))
                            .padding(.bottom, 16)
                    }
                }
                .onAppear { containerSize = geo.size }
                .onChange(of: geo.size) { _, newSize in containerSize = newSize }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onCancel() }
                        .foregroundStyle(.white)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Choose") {
                        logger.debug(
                            "Crop choose tapped; container=\(self.containerSize.debugDescription, privacy: .public) scale=\(self.scale, privacy: .public) offset=(\(self.offset.width, privacy: .public), \(self.offset.height, privacy: .public))"
                        )
                        let data = renderCroppedImage()
                        logger.debug("Crop render finished; output bytes=\(data.count, privacy: .public)")
                        onUse(data)
                    }
                    .foregroundStyle(.white)
                }
            }
        }
    }

    private func renderCroppedImage() -> Data {
        let outputSize: CGFloat = 320
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: outputSize, height: outputSize))

        let safeContainerWidth = max(containerSize.width, 1)
        let safeContainerHeight = max(containerSize.height, 1)
        let safeCropDiameter = max(cropDiameter, 1)
        let containerAspect = safeContainerWidth / safeContainerHeight

        let result = renderer.image { _ in
            UIBezierPath(ovalIn: CGRect(origin: .zero, size: CGSize(width: outputSize, height: outputSize))).addClip()

            let imageAspect = image.size.width / image.size.height

            var baseW: CGFloat
            var baseH: CGFloat
            if imageAspect > containerAspect {
                baseH = safeContainerHeight
                baseW = baseH * imageAspect
            } else {
                baseW = safeContainerWidth
                baseH = baseW / imageAspect
            }

            let displayW = baseW * scale
            let displayH = baseH * scale

            let factor = outputSize / safeCropDiameter
            let drawW = displayW * factor
            let drawH = displayH * factor
            let drawX = (outputSize - drawW) / 2 + offset.width * factor
            let drawY = (outputSize - drawH) / 2 + offset.height * factor

            image.draw(in: CGRect(x: drawX, y: drawY, width: drawW, height: drawH))
        }

        return result.jpegData(compressionQuality: 0.85) ?? Data()
    }
}
#endif
