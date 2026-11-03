//
//  KnownFriendsStore.swift
//  FreeSplitUnlimited
//
//  Remembers friends added to splits so they can be picked again later,
//  including after they are removed from a split. Each signed-in account
//  keeps its own list so the next user on this iPhone does not inherit it.
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
    static var accountOverrideForTesting: UUID?
    nonisolated(unsafe) static var signedInAccountID: UUID?

    private static var payloadKey: String {
        AppLaunchFlags.isAutomatedTesting
            ? "freeSplit.knownFriends.byAccount.testing"
            : "freeSplit.knownFriends.byAccount"
    }

    private static var legacyKey: String {
        AppLaunchFlags.isAutomatedTesting
            ? "freeSplit.knownFriends.testing"
            : "freeSplit.knownFriends"
    }

    private static var legacyFileName: String {
        AppLaunchFlags.isAutomatedTesting ? "knownFriends.testing.json" : "knownFriends.json"
    }

    private static var folderURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("FreeSplitUnlimited", isDirectory: true)
    }

    private static var legacyFileURL: URL? {
        folderURL?.appendingPathComponent(legacyFileName)
    }

    private static func fileURL(for scope: String) -> URL? {
        folderURL?.appendingPathComponent("knownFriends.\(scope).json")
    }

    private static var scope: String {
        if let override = accountOverrideForTesting {
            return override.uuidString.lowercased()
        }
        return signedInAccountID?.uuidString.lowercased() ?? "unsigned"
    }

    static func all() -> [SavedFriend] {
        let key = scope
        migrateLegacyIfNeeded(into: key)
        if let friends = loadPayload().byAccount[key] {
            return friends
        }
        if let fileURL = fileURL(for: key),
           let data = try? Data(contentsOf: fileURL),
           let friends = try? JSONDecoder().decode([SavedFriend].self, from: data) {
            return friends
        }
        return []
    }

    static func resetForTesting() {
        accountOverrideForTesting = nil
        signedInAccountID = nil
        UserDefaults.standard.removeObject(forKey: payloadKey)
        UserDefaults.standard.removeObject(forKey: legacyKey)
        guard let folderURL else { return }
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folderURL.path)) ?? []
        for name in names where name.hasPrefix("knownFriends") && name.hasSuffix(".json") {
            try? FileManager.default.removeItem(at: folderURL.appendingPathComponent(name))
        }
    }

    static func removeAccount(_ accountID: UUID) {
        let key = accountID.uuidString.lowercased()
        var payload = loadPayload()
        payload.byAccount.removeValue(forKey: key)
        persistPayload(payload)
        if let fileURL = fileURL(for: key) {
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
        guard let identity = currentIdentity(), identity.accountID != nil else { return }
        let occasions = (try? context.fetch(FetchDescriptor<Occasion>())) ?? []
        rememberPeople(from: occasions, as: identity)
    }

    private static func currentIdentity() -> AccountIdentity? {
        if Thread.isMainThread {
            return MainActor.assumeIsolated { AccountIdentity.current }
        }
        guard signedInAccountID != nil || accountOverrideForTesting != nil else { return nil }
        return AccountIdentity(accountID: signedInAccountID ?? accountOverrideForTesting)
    }

    static func rememberPeople(from occasions: [Occasion], as identity: AccountIdentity) {
        let people = occasions
            .filter { OccasionAccess.canAccess($0, as: identity) }
            .flatMap(\.uniqueMembers)
            .filter { FriendPairing.isUsableName($0.name) }
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
        var payload = loadPayload()
        payload.byAccount[scope] = friends
        persistPayload(payload)
        guard let data = try? JSONEncoder().encode(friends) else { return }
        guard let fileURL = fileURL(for: scope) else { return }
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: fileURL, options: .atomic)
    }

    /// Unique previously used friends. Removing someone from a split does not forget them.
    static func previouslyUsedFriends(from _: ModelContext) -> [PickedContact] {
        all()
            .filter { FriendPairing.isUsableName($0.name) }
            .map(\.asPickedContact)
            .sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
    }

    private struct Payload: Codable {
        var byAccount: [String: [SavedFriend]]
    }

    private static func loadPayload() -> Payload {
        guard let data = UserDefaults.standard.data(forKey: payloadKey),
              let payload = try? JSONDecoder().decode(Payload.self, from: data) else {
            return Payload(byAccount: [:])
        }
        return payload
    }

    private static func persistPayload(_ payload: Payload) {
        guard let data = try? JSONEncoder().encode(payload) else { return }
        UserDefaults.standard.set(data, forKey: payloadKey)
    }

    /// Older builds stored one phone-wide list. Keep it only for the account that
    /// already claimed the leftover groups, not for whoever signs in next.
    private static func migrateLegacyIfNeeded(into key: String) {
        var payload = loadPayload()
        if payload.byAccount[key] != nil { return }

        let legacy = loadLegacyFriends()
        guard !legacy.isEmpty else { return }

        if let claimed = OccasionAccess.claimedOwnerID,
           claimed.uuidString.lowercased() != key {
            return
        }

        payload.byAccount[key] = legacy
        persistPayload(payload)
        UserDefaults.standard.removeObject(forKey: legacyKey)
        if let legacyFileURL {
            try? FileManager.default.removeItem(at: legacyFileURL)
        }
    }

    private static func loadLegacyFriends() -> [SavedFriend] {
        if let data = UserDefaults.standard.data(forKey: legacyKey),
           let friends = try? JSONDecoder().decode([SavedFriend].self, from: data) {
            return friends
        }
        if let legacyFileURL,
           let data = try? Data(contentsOf: legacyFileURL),
           let friends = try? JSONDecoder().decode([SavedFriend].self, from: data) {
            return friends
        }
        return []
    }
}
