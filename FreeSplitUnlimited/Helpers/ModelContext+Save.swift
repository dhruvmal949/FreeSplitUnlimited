//
//  ModelContext+Save.swift
//  FreeSplitUnlimited
//

import SwiftData

extension ModelContext {
    /// Persist changes immediately, back them up so splits can survive reinstall,
    /// and propagate the change to other phones via mesh + cloud sync.
    @MainActor
    func persist() {
        do {
            if hasChanges {
                try save()
            }
            SplitBackup.save(from: self)
            SyncCoordinator.shared.notifyLocalChange()
        } catch {
            print("Failed to save Free Split data: \(error)")
        }
    }
}
