//
//  SyncCoordinator.swift
//  FreeSplitUnlimited
//
//  Single entry point for "real-time-ish" sync between phones with no backend:
//  - Nearby phones sync instantly over Bluetooth/Wi-Fi mesh (MeshSyncService).
//  - Phones that aren't nearby could fall back to CloudKit's public database
//    (CloudSyncService) — but that's currently disabled, see `cloudKitEnabled` below.
//  Local SwiftData storage is always the source of truth for the current device.
//

import Foundation
import SwiftData

@MainActor
final class SyncCoordinator: ObservableObject {
    static let shared = SyncCoordinator()

    /// CloudKit is fully stubbed out. Do not import CloudKit or construct CKContainer.
    private let cloudKitEnabled = false

    private var context: ModelContext?
    private var pollTask: Task<Void, Never>?
    private var didStart = false

    private init() {}

    /// Stores the SwiftData context without touching Multipeer radios.
    /// Starting `MCPeerID` / `MCSession` during launch or a document-open can `brk`.
    func attach(context: ModelContext) {
        self.context = context
    }

    func start(context: ModelContext) {
        attach(context: context)
        startNearby()
    }

    /// Turns on nearby discovery. Safe to call more than once.
    func startNearby() {
        guard AppLaunchFlags.nearbySyncEnabled else { return }
        guard let context else { return }
        didStart = true
        MeshSyncService.shared.start(context: context)
        startCloudIfNeeded()
    }

    /// Re-start nearby discovery when the app comes back to the foreground.
    func resume() {
        guard AppLaunchFlags.nearbySyncEnabled, didStart else { return }
        MeshSyncService.shared.resume()
        startCloudIfNeeded()
    }

    /// Call right after any local edit is saved. Broadcasts to nearby peers immediately;
    /// pushes to CloudKit too, but only if that's enabled (see `cloudKitEnabled`).
    func notifyLocalChange() {
        guard AppLaunchFlags.nearbySyncEnabled, didStart else { return }
        MeshSyncService.shared.broadcastLocalChanges()
        guard cloudKitEnabled, let context else { return }
        let occasions = (try? context.fetch(FetchDescriptor<Occasion>())) ?? []
        guard !occasions.isEmpty else { return }
        Task {
            await CloudSyncService.shared.pushAll(occasions)
        }
    }

    /// Manual nearby sync: start radios if needed, rediscover peers, push current splits.
    func syncNow() {
        guard AppLaunchFlags.nearbySyncEnabled else { return }
        startNearby()
        MeshSyncService.shared.restartDiscovery()
        guard cloudKitEnabled else { return }
        Task {
            await pullFromCloud()
        }
    }

    func stopNearby() {
        didStart = false
        MeshSyncService.shared.stop()
    }

    private func startCloudIfNeeded() {
        guard cloudKitEnabled else { return }
        guard pollTask == nil else { return }
        pollTask = Task {
            await CloudSyncService.shared.refreshAvailability()
            await pullFromCloud()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(20))
                await pullFromCloud()
            }
        }
    }

    private func pullFromCloud() async {
        guard let context else { return }
        let ids = ((try? context.fetch(FetchDescriptor<Occasion>())) ?? []).map(\.id)
        await CloudSyncService.shared.pull(ids: ids, into: context)
    }
}
