//
//  alarmApp.swift
//  alarm
//
//  Created by Lenny Muffler on 06.06.26.
//

import SwiftData
import SwiftUI

@main
struct alarmApp: App {
    var sharedModelContainer: ModelContainer = Self.makeModelContainer()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }

    private static func makeModelContainer() -> ModelContainer {
        let schema = Schema([
            Item.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            resetSwiftDataStore()

            do {
                return try ModelContainer(for: schema, configurations: [modelConfiguration])
            } catch {
                fatalError("Could not create ModelContainer after reset: \(error)")
            }
        }
    }

    private static func resetSwiftDataStore() {
        guard let applicationSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return
        }

        let storeURLs = [
            applicationSupportURL.appending(path: "default.store"),
            applicationSupportURL.appending(path: "default.store-shm"),
            applicationSupportURL.appending(path: "default.store-wal")
        ]

        for storeURL in storeURLs {
            try? FileManager.default.removeItem(at: storeURL)
        }
    }
}
