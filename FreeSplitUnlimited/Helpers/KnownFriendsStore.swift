//
//  KnownFriendsStore.swift
//  FreeSplitUnlimited
//
//  Remembers friend names added to splits so they can still be picked
//  when the user has denied Contacts access.
//

import Foundation
import SwiftData

struct SavedFriend: Codable, Hashable, Identifiable {
    var id: String { name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
    var name: String
    var email: String
    var phone: String

    var asPickedContact: PickedContact {
        PickedContact(id: id, name: name, email: email, phone: phone)
    }
}

enum KnownFriendsStore {
    private static let key = "freeSplit.knownFriends"

    static func all() -> [SavedFriend] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let friends = try? JSONDecoder().decode([SavedFriend].self, from: data) else {
            return []
        }
        return friends
    }

    static func remember(from context: ModelContext) {
        let people = (try? context.fetch(FetchDescriptor<Person>())) ?? []
        remember(people)
    }

    static func remember(_ people: [Person]) {
        var byKey: [String: SavedFriend] = [:]
        for friend in all() {
            let key = friend.id
            guard !key.isEmpty else { continue }
            byKey[key] = friend
        }
        for person in people {
            let name = person.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }
            let key = name.lowercased()
            var friend = byKey[key] ?? SavedFriend(name: name, email: "", phone: "")
            friend.name = name
            let email = person.email.trimmingCharacters(in: .whitespacesAndNewlines)
            let phone = person.phone.trimmingCharacters(in: .whitespacesAndNewlines)
            if friend.email.isEmpty { friend.email = email }
            if friend.phone.isEmpty { friend.phone = phone }
            byKey[key] = friend
        }
        let merged = byKey.values.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        if let data = try? JSONEncoder().encode(merged) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    /// Unique previously used friends: cache plus people still in local splits.
    static func previouslyUsedFriends(from context: ModelContext) -> [PickedContact] {
        remember(from: context)
        var byKey: [String: PickedContact] = [:]
        for friend in all() {
            let name = friend.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }
            byKey[name.lowercased()] = friend.asPickedContact
        }
        return byKey.values.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }
}
