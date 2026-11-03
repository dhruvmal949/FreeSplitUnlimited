//
//  ModelContext+Save.swift
//  FreeSplitUnlimited
//

import SwiftData

private enum PersistFollowUp {
    static var generation = 0
}

extension ModelContext {
    /// Persist changes immediately, then back them up and sync after the UI can move on.
    @MainActor
    func persist() {
        do {
            try save()
            KnownFriendsStore.remember(from: self)
            schedulePersistFollowUp()
        } catch {
            print("Failed to save Free Split data: \(error)")
        }
    }

    /// Hides a group on this phone. The object is removed after Home is showing
    /// so SwiftData is not asked to delete a model that is still on screen.
    @MainActor
    func removeGroup(_ occasion: Occasion) {
        DeletedGroupsStore.remember(occasion.id)
        occasion.markDeleted()
        do {
            try save()
            KnownFriendsStore.remember(from: self)
            SplitBackup.save(from: self)
            SyncCoordinator.shared.notifyLocalChange()
        } catch {
            print("Failed to delete group: \(error)")
        }
    }

    private func schedulePersistFollowUp() {
        PersistFollowUp.generation += 1
        let generation = PersistFollowUp.generation
        Task { @MainActor in
            guard generation == PersistFollowUp.generation else { return }
            SplitBackup.save(from: self)
            SyncCoordinator.shared.notifyLocalChange()
        }
    }
}
