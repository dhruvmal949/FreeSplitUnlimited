//
//  DeletedFriendsStore.swift
//  FreeSplitUnlimited
//
//  Remembers friends the user swiped away on Friends so the row stays gone
//  even if they still share a group. A new 1:1 with that person brings them back.
//

import Foundation

enum DeletedFriendsStore {
    private static var key: String {
        AppLaunchFlags.isAutomatedTesting
            ? "freeSplit.deletedFriends.testing"
            : "freeSplit.deletedFriends"
    }

    static func ids() -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: key) ?? [])
    }

    static func contains(_ id: String) -> Bool {
        ids().contains(id)
    }

    static func remember(_ id: String) {
        var next = ids()
        guard next.insert(id).inserted else { return }
        UserDefaults.standard.set(Array(next), forKey: key)
    }

    static func forget(_ id: String) {
        var next = ids()
        guard next.remove(id) != nil else { return }
        UserDefaults.standard.set(Array(next), forKey: key)
    }

    static func resetForTesting() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
