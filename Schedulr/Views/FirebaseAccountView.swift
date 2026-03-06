import SwiftUI
import FirebaseAuth
import FirebaseCore
#if canImport(GoogleSignIn)
import GoogleSignIn
#endif
#if os(iOS)
import UIKit
#endif

struct FirebaseAccountView: View {
    @Bindable var viewModel: ScheduleViewModel
    @Bindable var firebaseService: FirebaseSyncService
    @Bindable private var settings: AppSettings = .shared
    @Environment(\.dismiss) private var dismiss

    @State private var email = ""
    @State private var password = ""
    @State private var showingConflictReview = false
    @State private var restoreSchedulesFromCloud = true
    @State private var restoreSettingsFromCloud = true

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
            return .blue
        case .conflict:
            return .orange
        case .error:
            return .red
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                PremiumAppBackground()
                    .ignoresSafeArea()

                Form {
                    if !firebaseService.isSignedIn {
                        loginSection
                    } else {
                        signedInStatusSection
                        accountSection
                        cloudBackupSection
                    }

                    if let error = firebaseService.lastErrorMessage, !error.isEmpty {
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
        }
    }

    private var signedInStatusSection: some View {
        Section {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(.quaternary)
                        .frame(width: 86, height: 86)
                    Image(systemName: "person.crop.circle.fill.badge.checkmark")
                        .font(.system(size: 44, weight: .semibold))
                        .foregroundStyle(.green)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Signed In")
                        .font(.headline)
                    Text(firebaseService.signedInEmail ?? "Anonymous account")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer()

                Text(firebaseService.isNetworkReachable ? "Online" : "Offline")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(firebaseService.isNetworkReachable ? .green : .orange)
            }
            .padding(.vertical, 8)
        }
    }

    private var loginSection: some View {
        Section("Login") {
            TextField("Email", text: $email)
                .textInputAutocapitalization(.never)
                .keyboardType(.emailAddress)
                .autocorrectionDisabled(true)

            SecureField("Password", text: $password)

            Button {
                Task {
                    await firebaseService.signIn(
                        email: email.trimmingCharacters(in: .whitespacesAndNewlines),
                        password: password
                    )
                }
            } label: {
                Label("Sign In", systemImage: "person.crop.circle.badge.checkmark")
            }
            .disabled(firebaseService.isBusy)

            Button {
                Task {
                    await firebaseService.signUp(
                        email: email.trimmingCharacters(in: .whitespacesAndNewlines),
                        password: password
                    )
                }
            } label: {
                Label("Create Account", systemImage: "person.crop.circle.badge.plus")
            }
            .disabled(firebaseService.isBusy)

            Button {
                Task {
                    await firebaseService.sendPasswordReset(
                        email: email.trimmingCharacters(in: .whitespacesAndNewlines)
                    )
                }
            } label: {
                Label("Forgot Password", systemImage: "envelope.badge")
            }
            .disabled(firebaseService.isBusy)

            Button {
                Task {
                    await firebaseService.signInAnonymously()
                }
            } label: {
                Label("Continue as Guest", systemImage: "person")
            }
            .disabled(firebaseService.isBusy)

#if os(iOS) && canImport(GoogleSignIn)
            Button {
                handleGoogleSignIn()
            } label: {
                Label("Sign in with Google", systemImage: "globe")
            }
            .disabled(firebaseService.isBusy)
#endif
        }
    }

    private var accountSection: some View {
        Section("Account") {
            Text(firebaseService.signedInEmail ?? "Anonymous account")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack {
                Text("Network")
                Spacer()
                Text(firebaseService.isNetworkReachable ? "Online" : "Offline")
                    .foregroundStyle(firebaseService.isNetworkReachable ? .green : .orange)
            }

            if let lastSyncedAt = firebaseService.lastSyncedAt {
                Text("Last synced: \(lastSyncedAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Text("Sync state")
                Spacer()
                Text(syncStatusText)
                    .foregroundStyle(syncStatusColor)
            }

            if viewModel.isRestoreInProgress {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Restoration Progress")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ProgressView(value: viewModel.restoreProgress)
                    Text("\(Int(viewModel.restoreProgress * 100))%")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } else if let lastRestore = viewModel.lastRestoreCompletedAt {
                Text("Last restore: \(lastRestore.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button("Sign Out", role: .destructive) {
                firebaseService.signOut()
            }
        }
    }

    private var cloudBackupSection: some View {
        Section("Cloud Backup") {
            Button {
                Task {
                    if let backupData = viewModel.exportBackupData() {
                        await firebaseService.uploadBackup(backupData)
                    } else {
                        firebaseService.lastErrorMessage = "No local data to upload."
                    }
                }
            } label: {
                Label("Upload Backup to Firestore", systemImage: "arrow.up.circle")
            }
            .disabled(firebaseService.isBusy)

            Button {
                viewModel.syncNowWithCoordinator()
            } label: {
                Label("Sync Now", systemImage: "arrow.triangle.2.circlepath")
            }
            .disabled(
                firebaseService.isBusy
                || viewModel.isSyncNowInProgress
                || viewModel.syncCoordinator.syncState == .syncing
            )

            if !viewModel.syncCoordinator.pendingConflicts.isEmpty {
                Button {
                    showingConflictReview = true
                } label: {
                    Label("Resolve Conflicts", systemImage: "exclamationmark.arrow.trianglehead.2.clockwise.rotate.90")
                }
            }

            Toggle("Restore schedules", isOn: $restoreSchedulesFromCloud)
            Toggle("Restore settings", isOn: $restoreSettingsFromCloud)

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
                            includeSchedules: restoreSchedulesFromCloud,
                            includeSettings: restoreSettingsFromCloud
                        )
                    }
                }
            } label: {
                Label("Restore Backup from Cloud", systemImage: "arrow.counterclockwise.circle")
            }
            .disabled(firebaseService.isBusy || (!restoreSchedulesFromCloud && !restoreSettingsFromCloud))
        }
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
                if firebaseService.isSignedIn {
                    dismiss()
                }
            } catch {
                firebaseService.lastErrorMessage = error.localizedDescription
            }
        }
#endif
    }

#endif
}
