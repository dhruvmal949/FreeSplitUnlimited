//
//  FreeSplitUnlimitedApp.swift
//  FreeSplitUnlimited
//
//  Created by Pramela on 8/5/26.
//

import SwiftUI
import SwiftData

@main
struct FreeSplitUnlimitedApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Occasion.self,
            Person.self,
            Expense.self,
            ExpenseShare.self,
        ])

        let storeURL = URL.applicationSupportDirectory
            .appending(path: "FreeSplitUnlimited")
            .appending(path: "FreeSplit.store")

        try? FileManager.default.createDirectory(
            at: storeURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let modelConfiguration = ModelConfiguration(
            "FreeSplitUnlimited",
            schema: schema,
            url: storeURL,
            cloudKitDatabase: .none
        )

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            print("SwiftData store failed (\(error)). Resetting store once.")
            Self.deleteStore(at: storeURL)
            do {
                return try ModelContainer(for: schema, configurations: [modelConfiguration])
            } catch {
                fatalError("Could not create ModelContainer: \(error)")
            }
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .freeSplitBackground()
                .onAppear {
                    NSUbiquitousKeyValueStore.default.synchronize()
                    // After reinstall, local DB is empty — restore from iCloud/Keychain backup.
                    SplitBackup.restoreIfNeeded(into: sharedModelContainer.mainContext)
                    // Start nearby mesh sync + CloudKit fallback so splits stay in sync across phones.
                    SyncCoordinator.shared.start(context: sharedModelContainer.mainContext)
                }
                .onReceive(NotificationCenter.default.publisher(for: NSUbiquitousKeyValueStore.didChangeExternallyNotification)) { _ in
                    SplitBackup.restoreIfNeeded(into: sharedModelContainer.mainContext)
                }
                .onOpenURL { url in
                    importSharedFile(url)
                }
        }
        .modelContainer(sharedModelContainer)
        .handlesExternalEvents(matching: Set(arrayLiteral: "*"))
    }

    private func importSharedFile(_ url: URL) {
        // Accept .freesplit / .json files shared via AirDrop / Files / Messages.
        let ext = url.pathExtension.lowercased()
        guard ext == "freesplit" || ext == "json" || ext.isEmpty else { return }

        do {
            let occasion = try SplitShare.importFile(at: url, into: sharedModelContainer.mainContext)
            NotificationCenter.default.post(name: .freeSplitDidImport, object: occasion.id)
        } catch {
            print("Shared split import failed: \(error)")
        }
    }

    private static func deleteStore(at url: URL) {
        let fm = FileManager.default
        for suffix in ["", "-shm", "-wal"] {
            try? fm.removeItem(at: URL(fileURLWithPath: url.path + suffix))
        }
    }
}
