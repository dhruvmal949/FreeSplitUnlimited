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

    /// CloudKit requires a paid Apple Developer Program membership + iCloud
    /// entitlements. This project's signing team is a free/personal team, which
    /// Apple blocks from using iCloud entirely — `CKContainer.default()` crashes
    /// immediately (uncatchable) if the app has no iCloud entitlement at all.
    /// Keep this false (and never touch `cloud`) until entitlements are restored.
    private let cloudKitEnabled = false

    let mesh = MeshSyncService.shared
    /// `lazy` so this is only ever constructed — and only ever calls into
    /// CloudKit — if `cloudKitEnabled` is flipped back on.
    private lazy var cloud = CloudSyncService.shared

    private var context: ModelContext?
    private var pollTask: Task<Void, Never>?

    private init() {}

    func start(context: ModelContext) {
        self.context = context
        mesh.start(context: context)

        guard cloudKitEnabled else { return }
        pollTask?.cancel()
        pollTask = Task {
            await cloud.refreshAvailability()
            await pullFromCloud()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(20))
                await pullFromCloud()
            }
        }
    }

    /// Call right after any local edit is saved. Broadcasts to nearby peers immediately;
    /// pushes to CloudKit too, but only if that's enabled (see `cloudKitEnabled`).
    func notifyLocalChange() {
        mesh.broadcastLocalChanges()
        guard cloudKitEnabled, let context else { return }
        let occasions = (try? context.fetch(FetchDescriptor<Occasion>())) ?? []
        guard !occasions.isEmpty else { return }
        Task {
            await cloud.pushAll(occasions)
        }
    }

    /// Manual "pull to refresh"-style trigger, e.g. from a toolbar button.
    func syncNow() {
        mesh.broadcastLocalChanges()
        guard cloudKitEnabled else { return }
        Task {
            await pullFromCloud()
        }
    }

    private func pullFromCloud() async {
        guard let context else { return }
        let ids = ((try? context.fetch(FetchDescriptor<Occasion>())) ?? []).map(\.id)
        await cloud.pull(ids: ids, into: context)
    }
}
