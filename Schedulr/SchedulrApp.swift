//
//  SchedulrApp.swift
//  Schedulr
//
//  Created by AMITABH GIRI on 07/02/26.
//

import SwiftUI
import SwiftData
import Foundation
import FirebaseCore

@main
struct SchedulrApp: App {
    private let sharedModelContainer: ModelContainer
    @State private var appSettings = AppSettings.shared

    init() {
        if FirebaseApp.app() == nil,
           Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil {
            FirebaseApp.configure()
        }
        Self.ensureApplicationSupportDirectory()
        self.sharedModelContainer = Self.makeModelContainer()
        _ = NotificationManager.shared
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .id(appSettings.accentColorHex)
                .preferredColorScheme(appSettings.preferredColorScheme)
                .tint(appSettings.accentColor)
        }
        .modelContainer(sharedModelContainer)
    }

    private static func makeModelContainer() -> ModelContainer {
        let schema = Schema([Schedule.self])
        let fileManager = FileManager.default

        if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" {
            do {
                let previewConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
                return try ModelContainer(for: schema, configurations: [previewConfiguration])
            } catch {
                print("Preview in-memory container setup failed. Falling back to standard setup: \(error)")
            }
        }

        let localStoreURL = modelStoreURL(fileManager: fileManager)

        do {
            let localConfiguration = ModelConfiguration(schema: schema, url: localStoreURL)
            return try ModelContainer(for: schema, configurations: [localConfiguration])
        } catch {
            print("Local container setup failed. Attempting store reset: \(error)")
            resetModelStore(fileManager: fileManager, at: localStoreURL)

            do {
                let recoveredLocalConfiguration = ModelConfiguration(schema: schema, url: localStoreURL)
                return try ModelContainer(for: schema, configurations: [recoveredLocalConfiguration])
            } catch {
                print("Recovered local container setup failed. Falling back to in-memory: \(error)")
                do {
                    let inMemoryConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
                    return try ModelContainer(for: schema, configurations: [inMemoryConfiguration])
                } catch {
                    fatalError("Unable to create any model container: \(error)")
                }
            }
        }
    }

    private static func modelStoreURL(fileManager: FileManager) -> URL {
        let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return appSupportURL.appendingPathComponent("Schedulr.store")
    }

    private static func resetModelStore(fileManager: FileManager, at url: URL) {
        let sidecarURLs = [
            url,
            URL(fileURLWithPath: url.path + "-shm"),
            URL(fileURLWithPath: url.path + "-wal")
        ]

        for fileURL in sidecarURLs where fileManager.fileExists(atPath: fileURL.path) {
            do {
                try fileManager.removeItem(at: fileURL)
            } catch {
                print("Failed to remove store file at \(fileURL.path): \(error)")
            }
        }
    }

    private static func ensureApplicationSupportDirectory() {
        let fileManager = FileManager.default
        guard let applicationSupportURL = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            return
        }

        do {
            try fileManager.createDirectory(
                at: applicationSupportURL,
                withIntermediateDirectories: true
            )
        } catch {
            assertionFailure("Unable to create Application Support directory: \(error)")
        }
    }
}
