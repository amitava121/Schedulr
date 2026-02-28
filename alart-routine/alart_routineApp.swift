//
//  alart_routineApp.swift
//  alart-routine
//
//  Created by AMITABH GIRI on 07/02/26.
//

import SwiftUI
import SwiftData

@main
struct alart_routineApp: App {
    init() {
        Self.ensureApplicationSupportDirectory()
        _ = NotificationManager.shared
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: Schedule.self)
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
