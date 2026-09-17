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
            let people = (try? fetch(FetchDescriptor<Person>())) ?? []
            for person in people where person.hasContactInfo {
                person.setContact(email: person.email, phone: person.phone)
            }
            try save()
            let occasions = (try? fetch(FetchDescriptor<Occasion>())) ?? []
            for occasion in occasions where occasion.isDeleted {
                occasion.isDeleted = true
            }
            if occasions.contains(where: \.isDeleted) {
                try save()
            }
            SplitBackup.save(from: self)
            KnownFriendsStore.remember(from: self)
            SyncCoordinator.shared.notifyLocalChange()
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
            SplitBackup.save(from: self)
            KnownFriendsStore.remember(from: self)
            SyncCoordinator.shared.notifyLocalChange()
        } catch {
            print("Failed to delete group: \(error)")
        }
    }
}
