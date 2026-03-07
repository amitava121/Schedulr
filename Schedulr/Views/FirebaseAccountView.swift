import SwiftUI
import FirebaseAuth
import FirebaseCore
import CryptoKit
#if canImport(GoogleSignIn)
import GoogleSignIn
#endif
#if os(iOS)
import UIKit
import AVFoundation
#endif
#if os(macOS)
import AppKit
#endif

struct FirebaseAccountView: View {
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
            return "Syncing"
        case .conflict:
            return "Conflicts"
        case .error:
            return "Error"
        }
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

                    let photoData = updatedPhotoData
                    // Reflect changes instantly in the account UI.
                    firebaseService.profileDisplayName = updatedName
                    persistProfileDisplayName(updatedName)
                    if let photoData {
                        customProfileImageData = photoData
                        firebaseService.profilePhotoData = photoData
                        persistProfileImage(photoData)
                    }

                    await firebaseService.updateProfileMetadata(displayName: updatedName, photoData: photoData)
                    await firebaseService.refreshProfileMetadata()
                    await MainActor.run {
                        if let latestPhoto = firebaseService.profilePhotoData {
                            customProfileImageData = latestPhoto
                            persistProfileImage(latestPhoto)
                        }
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
                    .disabled(viewModel.isRestoreInProgress)

                    Spacer()

                    Text(syncStatusText)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(syncStatusColor)
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

                            if let backup = await firebaseService.downloadBackup(), !backup.data.isEmpty {
                                if let version = backup.globalSyncVersion {
                                    viewModel.seedGlobalSyncVersion(version)
                                }
                                viewModel.importBackupData(
                                    backup.data,
                                    includeSchedules: true,
                                    includeSettings: true
                                )
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
private final class RootImagePickerPresenter: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
    var onPicked: ((UIImage?) -> Void)?

    func present(sourceType: UIImagePickerController.SourceType) {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let root = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController
        else { return }

        let picker = UIImagePickerController()
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(sourceType) ? sourceType : .photoLibrary
        picker.allowsEditing = false
        picker.delegate = self
        picker.modalPresentationStyle = .fullScreen

        var topVC = root
        while let presented = topVC.presentedViewController {
            topVC = presented
        }
        topVC.present(picker, animated: true)
    }

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true) { [weak self] in
            self?.onPicked?(nil)
        }
    }

    func imagePickerController(
        _ picker: UIImagePickerController,
        didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
    ) {
        let image = (info[.originalImage] as? UIImage)
        picker.dismiss(animated: true) { [weak self] in
            self?.onPicked?(image)
        }
    }
}

private struct AccountProfileEditorSheet: View {
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
    @State private var pendingCropImage: UIImage?
    @State private var showCropView = false
    @State private var pickerPresenter = RootImagePickerPresenter()

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
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
                        Task {
                            isSaving = true
                            await onSave(trimmed, imageData)
                            isSaving = false
                            dismiss()
                        }
                    }
                    .disabled(!canSave || isSaving)
                }
            }
            .confirmationDialog("Profile Image", isPresented: $showImageSourceDialog, titleVisibility: .visible) {
                Button("Select from Photos") {
                    openPicker(source: .photoLibrary)
                }
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button("Open Camera") {
                        requestAndOpenCameraIfAllowed()
                    }
                }
                Button("Select from Files") {
                    showFileImporter = true
                }
                Button("Cancel", role: .cancel) {}
            }
            .alert("Camera Access", isPresented: $showCameraPermissionAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(cameraPermissionMessage)
            }
            .fullScreenCover(isPresented: $showCropView) {
                if let cropImage = pendingCropImage {
                    ProfileImageCropView(image: cropImage) { croppedData in
                        imageData = croppedData
                        showCropView = false
                        pendingCropImage = nil
                    } onCancel: {
                        showCropView = false
                        pendingCropImage = nil
                    }
                }
            }
            .fileImporter(
                isPresented: $showFileImporter,
                allowedContentTypes: [.image],
                allowsMultipleSelection: false
            ) { result in
                guard case .success(let urls) = result,
                      let url = urls.first
                else { return }

                let started = url.startAccessingSecurityScopedResource()
                defer { if started { url.stopAccessingSecurityScopedResource() } }

                guard let data = try? Data(contentsOf: url),
                      let uiImage = UIImage(data: data)
                else { return }
                pendingCropImage = uiImage
                showCropView = true
            }
        }
    }

    private func openPicker(source: UIImagePickerController.SourceType) {
        pickerPresenter.onPicked = { image in
            if let image {
                pendingCropImage = image
                showCropView = true
            }
        }
        pickerPresenter.present(sourceType: source)
    }

    private func requestAndOpenCameraIfAllowed() {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            cameraPermissionMessage = "Camera is not available on this device."
            showCameraPermissionAlert = true
            return
        }

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            openPicker(source: .camera)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    if granted {
                        self.openPicker(source: .camera)
                    } else {
                        self.cameraPermissionMessage = "Camera access is required to take a profile photo."
                        self.showCameraPermissionAlert = true
                    }
                }
            }
        case .denied, .restricted:
            cameraPermissionMessage = "Please allow camera access in iOS Settings to use this option."
            showCameraPermissionAlert = true
        @unknown default:
            cameraPermissionMessage = "Camera permission status is unavailable."
            showCameraPermissionAlert = true
        }
    }
}

private struct ProfileImageCropView: View {
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
                        let data = renderCroppedImage()
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

        let result = renderer.image { _ in
            UIBezierPath(ovalIn: CGRect(origin: .zero, size: CGSize(width: outputSize, height: outputSize))).addClip()

            let imageAspect = image.size.width / image.size.height
            let containerAspect = containerSize.width / containerSize.height

            var baseW: CGFloat
            var baseH: CGFloat
            if imageAspect > containerAspect {
                baseH = containerSize.height
                baseW = baseH * imageAspect
            } else {
                baseW = containerSize.width
                baseH = baseW / imageAspect
            }

            let displayW = baseW * scale
            let displayH = baseH * scale

            let factor = outputSize / cropDiameter
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
