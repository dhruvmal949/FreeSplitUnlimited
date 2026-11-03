//
//  OccasionAccess.swift
//  FreeSplitUnlimited
//
//  A group is visible only to its owner or to people who participate in it.
//  The generic member name "Me" does not count as membership.
//

import Foundation
import SwiftData

struct AccountIdentity: Equatable {
    var accountID: UUID?
    var email: String = ""
    var phone: String = ""
    var names: [String] = []

    @MainActor
    static var current: AccountIdentity {
        AccountIdentity(
            accountID: AuthSession.shared.accountID,
            email: AuthSession.shared.email,
            phone: AuthSession.shared.accountPhone,
            names: AuthSession.shared.selfNames.filter { FriendPairing.isUsableName($0) }
        )
    }

    var emailKey: String? {
        ContactUniqueness.emailKey(email)
    }

    var phoneKey: String? {
        ContactUniqueness.phoneKey(phone)
    }
}

enum OccasionAccess {
    private static var claimedOwnerKey: String {
        AppLaunchFlags.isAutomatedTesting
            ? "freeSplit.privacy.claimedOwner.testing"
            : "freeSplit.privacy.claimedOwner"
    }

    static var claimedOwnerID: UUID? {
        UserDefaults.standard.string(forKey: claimedOwnerKey).flatMap(UUID.init(uuidString:))
    }

    static func resetForTesting() {
        UserDefaults.standard.removeObject(forKey: claimedOwnerKey)
    }

    static func resetClaimIfOwned(by accountID: UUID?) {
        guard let accountID else { return }
        guard UserDefaults.standard.string(forKey: claimedOwnerKey) == accountID.uuidString else { return }
        UserDefaults.standard.removeObject(forKey: claimedOwnerKey)
    }

    /// First signed-in account after this update owns groups that have no owner yet.
    /// Later accounts on the same phone do not inherit those groups.
    @MainActor
    static func claimExistingGroupsIfNeeded(in context: ModelContext) {
        let identity = AccountIdentity.current
        guard let accountID = identity.accountID else { return }
        if UserDefaults.standard.string(forKey: claimedOwnerKey) != nil {
            return
        }
        UserDefaults.standard.set(accountID.uuidString, forKey: claimedOwnerKey)

        let occasions = (try? context.fetch(FetchDescriptor<Occasion>())) ?? []
        var didChange = false
        for occasion in occasions where occasion.ownerAccountID == nil {
            occasion.ownerAccountID = accountID
            occasion.grantAccess(to: accountID)
            didChange = true
        }
        if didChange {
            try? context.save()
        }
    }

    static func isVisible(_ occasion: Occasion, as identity: AccountIdentity) -> Bool {
        occasion.shouldAppearInLists && canAccess(occasion, as: identity)
    }

    @MainActor
    static func isVisible(_ occasion: Occasion) -> Bool {
        isVisible(occasion, as: .current)
    }

    static func canAccess(_ occasion: Occasion, as identity: AccountIdentity) -> Bool {
        canAccess(
            ownerAccountID: occasion.ownerAccountID,
            grantedAccountIDs: occasion.grantedAccountIDs,
            members: occasion.uniqueMembers.map {
                MemberKey(name: $0.name, email: $0.email, phone: $0.phone)
            },
            as: identity
        )
    }

    static func canAccess(_ backup: BackupOccasion, as identity: AccountIdentity) -> Bool {
        canAccess(
            ownerAccountID: backup.ownerAccountID,
            grantedAccountIDs: backup.grantedAccountIDs,
            members: backup.members.map {
                MemberKey(name: $0.name, email: $0.email, phone: $0.phone)
            },
            as: identity
        )
    }

    /// Nearby sync may send a group only if this account can see it and the other phone is in it.
    static func canSend(
        _ occasion: Occasion,
        toPeerNamed peerName: String,
        as identity: AccountIdentity
    ) -> Bool {
        guard canAccess(occasion, as: identity) else { return false }
        return peerIsMember(
            peerName,
            members: occasion.uniqueMembers.map {
                MemberKey(name: $0.name, email: $0.email, phone: $0.phone)
            }
        )
    }

    static func canSend(
        _ backup: BackupOccasion,
        toPeerNamed peerName: String,
        as identity: AccountIdentity
    ) -> Bool {
        guard canAccess(backup, as: identity) else { return false }
        return peerIsMember(
            peerName,
            members: backup.members.map {
                MemberKey(name: $0.name, email: $0.email, phone: $0.phone)
            }
        )
    }

    static func shouldImport(_ backup: BackupOccasion, as identity: AccountIdentity) -> Bool {
        canAccess(backup, as: identity)
    }

    @MainActor
    static func grantCurrentUser(_ backup: BackupOccasion) -> BackupOccasion {
        var next = backup
        if let accountID = AccountIdentity.current.accountID,
           !next.grantedAccountIDs.contains(accountID) {
            next.grantedAccountIDs.append(accountID)
        }
        return next
    }

    private struct MemberKey {
        var name: String
        var email: String
        var phone: String
    }

    private static func canAccess(
        ownerAccountID: UUID?,
        grantedAccountIDs: [UUID],
        members: [MemberKey],
        as identity: AccountIdentity
    ) -> Bool {
        if let accountID = identity.accountID {
            if ownerAccountID == accountID { return true }
            if grantedAccountIDs.contains(accountID) { return true }
        }
        return members.contains { matches($0, identity) }
    }

    private static func matches(_ member: MemberKey, _ identity: AccountIdentity) -> Bool {
        if let memberEmail = ContactUniqueness.emailKey(member.email),
           memberEmail == identity.emailKey {
            return true
        }
        if let memberPhone = ContactUniqueness.phoneKey(member.phone),
           memberPhone == identity.phoneKey {
            return true
        }
        guard FriendPairing.isUsableName(member.name) else { return false }
        return identity.names.contains { FriendPairing.namesMatch($0, member.name) }
    }

    private static func peerIsMember(_ peerName: String, members: [MemberKey]) -> Bool {
        guard FriendPairing.isUsableName(peerName) else { return false }
        return members.contains {
            FriendPairing.isUsableName($0.name) && FriendPairing.namesMatch($0.name, peerName)
        }
    }
}
