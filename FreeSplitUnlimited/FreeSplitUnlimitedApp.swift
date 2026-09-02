//
//  FreeSplitUnlimitedApp.swift
//  FreeSplitUnlimited
//
//  Created by Pramela on 8/5/26.
//

import SwiftUI
import SwiftData
import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        if let url = launchOptions?[.url] as? URL {
            IncomingURLCapture.capture(url)
        }
        return true
    }

    func application(
        _ app: UIApplication,
        open url: URL,
        options: [UIApplication.OpenURLOptionsKey: Any] = [:]
    ) -> Bool {
        IncomingURLCapture.capture(url)
        return true
    }
}

@main
struct FreeSplitUnlimitedApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    private let container: ModelContainer?

    init() {
        container = Self.makeContainer()
    }

    var body: some Scene {
        WindowGroup {
            if let container {
                RootView(container: container)
            } else {
                ContentUnavailableView(
                    "Couldn't Start",
                    systemImage: "exclamationmark.triangle",
                    description: Text("Free Split couldn't open its data store. Delete the app and reinstall.")
                )
            }
        }
        .handlesExternalEvents(matching: [])
    }

    /// Never traps. Disk store → reset disk → in-memory. Nil only if SwiftData is completely unusable.
    private static func makeContainer() -> ModelContainer? {
        let schema = Schema([
            Occasion.self,
            Person.self,
            Expense.self,
            ExpenseShare.self,
        ])

        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let storeURL = support
            .appendingPathComponent("FreeSplitUnlimited", isDirectory: true)
            .appendingPathComponent("FreeSplit.v2.store")

        try? FileManager.default.createDirectory(
            at: storeURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let disk = ModelConfiguration(
            "FreeSplitUnlimited",
            schema: schema,
            url: storeURL,
            cloudKitDatabase: .none
        )

        if let container = try? ModelContainer(for: schema, configurations: [disk]) {
            return container
        }

        print("SwiftData store failed. Resetting store once.")
        deleteStore(at: storeURL)

        if let container = try? ModelContainer(for: schema, configurations: [disk]) {
            return container
        }

        print("SwiftData store reset failed. Using in-memory store.")
        let memory = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        return try? ModelContainer(for: schema, configurations: [memory])
    }

    private static func deleteStore(at url: URL) {
        let fm = FileManager.default
        for suffix in ["", "-shm", "-wal"] {
            try? fm.removeItem(at: URL(fileURLWithPath: url.path + suffix))
        }
    }
}

private struct RootView: View {
    let container: ModelContainer
    @ObservedObject private var session = AuthSession.shared
    @Environment(\.scenePhase) private var scenePhase
    @State private var didFinishFirstAppear = false

    var body: some View {
        Group {
            if session.isAuthenticated {
                ContentView()
            } else {
                LoginView()
            }
        }
        .freeSplitBackground()
        .modelContainer(container)
        .onAppear {
            SplitBackup.restoreIfNeeded(into: container.mainContext)
            IncomingSplitOpener.shared.attach(context: container.mainContext)
            SyncCoordinator.shared.attach(context: container.mainContext)
            DispatchQueue.main.async {
                didFinishFirstAppear = true
            }
        }
        .onOpenURL { url in
            IncomingURLCapture.capture(url)
            IncomingSplitOpener.shared.flushWhenReady()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active, didFinishFirstAppear else { return }
            IncomingSplitOpener.shared.attach(context: container.mainContext)
            if session.isAuthenticated {
                SyncCoordinator.shared.resume()
            }
        }
        .onChange(of: session.isAuthenticated) { _, isAuthenticated in
            if isAuthenticated {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    SyncCoordinator.shared.startNearby()
                }
            } else {
                SyncCoordinator.shared.stopNearby()
            }
        }
    }
}
