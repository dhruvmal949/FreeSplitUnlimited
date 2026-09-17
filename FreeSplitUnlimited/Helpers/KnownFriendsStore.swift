//
//  KnownFriendsStore.swift
//  FreeSplitUnlimited
//
//  Remembers friends added to splits so they can be picked again later,
//  including after they are removed from a split.
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
    private static var key: String {
        AppLaunchFlags.isAutomatedTesting
            ? "freeSplit.knownFriends.testing"
            : "freeSplit.knownFriends"
    }

    private static var fileName: String {
        AppLaunchFlags.isAutomatedTesting ? "knownFriends.testing.json" : "knownFriends.json"
    }

    private static var fileURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("FreeSplitUnlimited", isDirectory: true)
            .appendingPathComponent(fileName)
    }

    static func all() -> [SavedFriend] {
        if let data = UserDefaults.standard.data(forKey: key),
           let friends = try? JSONDecoder().decode([SavedFriend].self, from: data) {
            return friends
        }
        if let fileURL,
           let data = try? Data(contentsOf: fileURL),
           let friends = try? JSONDecoder().decode([SavedFriend].self, from: data) {
            return friends
        }
        return []
    }

    static func resetForTesting() {
        UserDefaults.standard.removeObject(forKey: key)
        if let fileURL {
            try? FileManager.default.removeItem(at: fileURL)
        }
    }

    static func contact(named raw: String) -> PickedContact? {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard FriendPairing.isUsableName(name) else { return nil }
        return all().first {
            $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame
        }?.asPickedContact
    }

    static func remember(from context: ModelContext) {
        let people = (try? context.fetch(FetchDescriptor<Person>())) ?? []
        remember(people)
    }

    static func remember(_ people: [Person]) {
        remember(
            people.map {
                SavedFriend(name: $0.name, email: $0.email, phone: $0.phone)
            }
        )
    }

    static func remember(_ contacts: [PickedContact]) {
        remember(
            contacts.map { contact in
                let resolved = contact.resolvedContact() ?? contact
                return SavedFriend(name: resolved.name, email: resolved.email, phone: resolved.phone)
            }
        )
    }

    static func remember(_ incoming: [SavedFriend]) {
        var byKey: [String: SavedFriend] = [:]
        for friend in all() {
            let key = friend.id
            guard !key.isEmpty else { continue }
            byKey[key] = friend
        }
        for raw in incoming {
            let name = raw.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard FriendPairing.isUsableName(name) else { continue }
            let key = name.lowercased()
            var friend = byKey[key] ?? SavedFriend(name: name, email: "", phone: "")
            friend.name = name
            let email = raw.email.trimmingCharacters(in: .whitespacesAndNewlines)
            let phone = raw.phone.trimmingCharacters(in: .whitespacesAndNewlines)
            if !email.isEmpty { friend.email = email }
            if !phone.isEmpty { friend.phone = phone }
            byKey[key] = friend
        }
        persist(
            byKey.values.sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
        )
    }

    private static func persist(_ friends: [SavedFriend]) {
        guard let data = try? JSONEncoder().encode(friends) else { return }
        UserDefaults.standard.set(data, forKey: key)
        guard let fileURL else { return }
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: fileURL, options: .atomic)
    }

    /// Unique previously used friends. Removing someone from a split does not forget them.
    static func previouslyUsedFriends(from context: ModelContext) -> [PickedContact] {
        remember(from: context)
        return all()
            .filter { FriendPairing.isUsableName($0.name) }
            .map(\.asPickedContact)
            .sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
    }
}
