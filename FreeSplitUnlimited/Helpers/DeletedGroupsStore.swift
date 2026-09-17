//
//  DeletedGroupsStore.swift
//  FreeSplitUnlimited
//
//  Remembers groups the user deleted so Home cannot show them again if SwiftData
//  or nearby sync restores a copy.
//

import Foundation

enum DeletedGroupsStore {
    private static var key: String {
        AppLaunchFlags.isAutomatedTesting
            ? "freeSplit.deletedGroups.testing"
            : "freeSplit.deletedGroups"
    }

    static func ids() -> Set<UUID> {
        let raw = UserDefaults.standard.stringArray(forKey: key) ?? []
        return Set(raw.compactMap(UUID.init(uuidString:)))
    }

    static func contains(_ id: UUID) -> Bool {
        ids().contains(id)
    }

    static func remember(_ id: UUID, notify: Bool = true) {
        var next = ids()
        let inserted = next.insert(id).inserted
        if inserted {
            UserDefaults.standard.set(next.map(\.uuidString), forKey: key)
        }
        guard notify, inserted else { return }
        NotificationCenter.default.post(name: .freeSplitDidHideGroups, object: id)
    }

    static func resetForTesting() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}

extension Notification.Name {
    static let freeSplitDidHideGroups = Notification.Name("freeSplitDidHideGroups")
    static let freeSplitJumpToHome = Notification.Name("freeSplitJumpToHome")
    static let freeSplitOpenGroupSettings = Notification.Name("freeSplitOpenGroupSettings")
}
