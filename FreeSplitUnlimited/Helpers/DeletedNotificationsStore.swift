//
//  DeletedNotificationsStore.swift
//  FreeSplitUnlimited
//
//  Remembers notifications the user swiped away so they stay gone after relaunch.
//

import Foundation

enum DeletedNotificationsStore {
    private static var key: String {
        AppLaunchFlags.isAutomatedTesting
            ? "freeSplit.deletedNotifications.testing"
            : "freeSplit.deletedNotifications"
    }

    static func ids() -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: key) ?? [])
    }

    static func contains(_ id: String) -> Bool {
        ids().contains(id)
    }

    static func remember(_ id: String) {
        remember([id])
    }

    static func remember(_ incoming: [String]) {
        var next = ids()
        var inserted = false
        for id in incoming {
            inserted = next.insert(id).inserted || inserted
        }
        guard inserted else { return }
        UserDefaults.standard.set(Array(next), forKey: key)
    }

    static func resetForTesting() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
