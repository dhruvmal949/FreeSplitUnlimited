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

        if AppLaunchFlags.isUITesting {
            let memory = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: true,
                cloudKitDatabase: .none
            )
            return try? ModelContainer(for: schema, configurations: [memory])
        }

        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let folder = support.appendingPathComponent("FreeSplitUnlimited", isDirectory: true)
        let storeURL = folder.appendingPathComponent("FreeSplit.v3.store")
        let v2URL = folder.appendingPathComponent("FreeSplit.v2.store")

        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        copyStore(from: v2URL, to: storeURL, overwrite: false)

        let disk = ModelConfiguration(
            "FreeSplitUnlimited",
            schema: schema,
            url: storeURL,
            cloudKitDatabase: .none
        )

        if let container = try? ModelContainer(for: schema, configurations: [disk]) {
            return container
        }

        print("SwiftData store failed. Resetting store once and copying the previous store.")
        deleteStore(at: storeURL)
        copyStore(from: v2URL, to: storeURL, overwrite: true)

        if let container = try? ModelContainer(for: schema, configurations: [disk]) {
            return container
        }

        print("SwiftData store copy failed. Starting a new empty store.")
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

    /// Copies an older on-disk store so a schema bump does not look like an empty app.
    private static func copyStore(from source: URL, to dest: URL, overwrite: Bool) {
        let fm = FileManager.default
        guard fm.fileExists(atPath: source.path) else { return }
        if !overwrite, fm.fileExists(atPath: dest.path) { return }
        if overwrite {
            deleteStore(at: dest)
        }
        for suffix in ["", "-shm", "-wal"] {
            let src = URL(fileURLWithPath: source.path + suffix)
            let dst = URL(fileURLWithPath: dest.path + suffix)
            guard fm.fileExists(atPath: src.path) else { continue }
            try? fm.copyItem(at: src, to: dst)
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
            if !AppLaunchFlags.isUITesting {
                SplitBackup.restoreIfNeeded(into: container.mainContext)
            }
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
            if isAuthenticated, !AppLaunchFlags.isUITesting {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    SyncCoordinator.shared.startNearby()
                }
            } else if !isAuthenticated {
                SyncCoordinator.shared.stopNearby()
            }
        }
    }
}
