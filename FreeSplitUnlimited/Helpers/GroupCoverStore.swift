//
//  GroupCoverStore.swift
//  FreeSplitUnlimited
//
//  Group photos stay out of SwiftData. Optional `Data` on a `@Model` can trap
//  with EXC_BREAKPOINT (`typeID does not match`) when the store is loaded.
//

import Foundation

enum GroupCoverStore {
    private static func key(_ id: UUID) -> String {
        "freeSplit.groupCover.\(id.uuidString)"
    }

    static func data(for id: UUID) -> Data? {
        guard let data = UserDefaults.standard.data(forKey: key(id)), !data.isEmpty else {
            return nil
        }
        return data
    }

    static func save(_ data: Data?, for id: UUID) {
        if let data, !data.isEmpty {
            UserDefaults.standard.set(data, forKey: key(id))
        } else {
            UserDefaults.standard.removeObject(forKey: key(id))
        }
    }
}
