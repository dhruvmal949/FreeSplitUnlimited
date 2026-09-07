//
//  FriendPairing.swift
//  FreeSplitUnlimited
//
//  Two phones that each start a 1:1 with the other person’s name should
//  become the same split once they are nearby — no join code required.
//

import CryptoKit
import Foundation
import SwiftData

enum FriendPairing {
    static func namesMatch(_ a: String, _ b: String) -> Bool {
        let left = a.trimmingCharacters(in: .whitespacesAndNewlines)
        let right = b.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !left.isEmpty, !right.isEmpty else { return false }
        return left.localizedCaseInsensitiveCompare(right) == .orderedSame
    }

    static func isUsableName(_ raw: String) -> Bool {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return false }
        return !namesMatch(name, "Me") && !namesMatch(name, "Guest")
    }

    static func isPlaceholderSelf(_ name: String) -> Bool {
        namesMatch(name, "Me") || namesMatch(name, "Guest")
    }

    static func isSelf(_ name: String, selfNames: [String]) -> Bool {
        selfNames.contains { namesMatch($0, name) }
    }

    static func normalize(_ name: String) -> String {
        name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .lowercased()
    }

    /// Same pair of people always gets the same occasion id, no matter who creates it first.
    static func occasionID(_ nameA: String, _ nameB: String) -> UUID {
        uuid5("freesplit.1to1.\([normalize(nameA), normalize(nameB)].sorted().joined(separator: "|"))")
    }

    static func personID(_ nameA: String, _ nameB: String, person: String) -> UUID {
        uuid5(
            "freesplit.1to1.person.\([normalize(nameA), normalize(nameB)].sorted().joined(separator: "|")).\(normalize(person))"
        )
    }

    static func existingOccasion(
        friendName: String,
        selfNames: [String],
        in occasions: [Occasion]
    ) -> Occasion? {
        occasions.first { occasion in
            guard !occasion.isDeleted, occasion.isOneToOne else { return false }
            let members = occasion.uniqueMembers
            let hasFriend = members.contains { namesMatch($0.name, friendName) }
            let hasSelf = members.contains { isSelf($0.name, selfNames: selfNames) }
            return hasFriend && hasSelf
        }
    }

    /// Incoming 1:1 from a nearby phone: rewrite "Me" to their name, and fold
    /// it into a local 1:1 with that friend so both phones share one split.
    static func prepareIncoming(
        _ backup: BackupOccasion,
        peerName: String,
        selfNames: [String],
        localOccasions: [Occasion]
    ) -> BackupOccasion {
        guard backup.groupType == SplitKind.oneToOne, !backup.isDeleted else {
            return backup
        }

        let incoming = rewriteIncoming(backup, peerName: peerName, selfNames: selfNames)
        let local = localOccasions.first { $0.id == incoming.id && !$0.isDeleted }
            ?? complementaryOccasion(peerName: peerName, selfNames: selfNames, in: localOccasions)
        guard let local, local.isOneToOne else {
            return incoming
        }
        return merge(local: local, incoming: incoming, peerName: peerName, selfNames: selfNames)
    }

    private static func rewriteIncoming(
        _ backup: BackupOccasion,
        peerName: String,
        selfNames: [String]
    ) -> BackupOccasion {
        var incoming = backup
        if isUsableName(peerName) {
            incoming.members = backup.members.map { member in
                var next = member
                if isPlaceholderSelf(member.name) {
                    next.name = peerName
                }
                return next
            }
            if selfNames.contains(where: { namesMatch($0, incoming.name) }) || isPlaceholderSelf(incoming.name) {
                incoming.name = peerName
            }
        }
        return incoming
    }

    private static func complementaryOccasion(
        peerName: String,
        selfNames: [String],
        in occasions: [Occasion]
    ) -> Occasion? {
        guard isUsableName(peerName) else { return nil }
        return existingOccasion(friendName: peerName, selfNames: selfNames, in: occasions)
    }

    private static func merge(
        local: Occasion,
        incoming: BackupOccasion,
        peerName: String,
        selfNames: [String]
    ) -> BackupOccasion {
        var merged = SplitBackup.exportOccasion(local)
        var idMap: [UUID: UUID] = [:]
        for member in incoming.members {
            if let localID = localPersonID(
                forIncoming: member.name,
                local: local,
                peerName: peerName,
                selfNames: selfNames
            ) {
                idMap[member.id] = localID
            }
        }

        var expensesByID: [UUID: BackupExpense] = [:]
        for expense in merged.expenses {
            expensesByID[expense.id] = expense
        }
        var addedRemote = false
        for expense in incoming.expenses {
            var next = expense
            next.paidByID = next.paidByID.flatMap { idMap[$0] ?? $0 }
            next.participantIDs = next.participantIDs.map { idMap[$0] ?? $0 }
            next.shares = next.shares.map { share in
                BackupShare(personID: idMap[share.personID] ?? share.personID, value: share.value)
            }
            if expensesByID[next.id] == nil {
                addedRemote = true
            }
            expensesByID[next.id] = expensesByID[next.id] ?? next
        }
        merged.expenses = Array(expensesByID.values)

        for member in incoming.members {
            guard let localID = idMap[member.id],
                  let index = merged.members.firstIndex(where: { $0.id == localID }) else { continue }
            if merged.members[index].email.isEmpty {
                merged.members[index].email = member.email
            }
            if merged.members[index].phone.isEmpty {
                merged.members[index].phone = member.phone
            }
        }

        if merged.joinCode.isEmpty {
            merged.joinCode = incoming.joinCode
        }
        merged.updatedAt = max(merged.updatedAt, incoming.updatedAt)
        if addedRemote {
            merged.updatedAt = max(merged.updatedAt, Date.now)
        }
        return merged
    }

    private static func localPersonID(
        forIncoming name: String,
        local: Occasion,
        peerName: String,
        selfNames: [String]
    ) -> UUID? {
        let members = local.uniqueMembers
        if isIncomingPeer(name, peerName: peerName) {
            return members.first { namesMatch($0.name, peerName) }?.id
                ?? members.first { !isSelf($0.name, selfNames: selfNames) }?.id
        }
        if isIncomingUs(name, selfNames: selfNames, peerName: peerName) {
            return members.first { isSelf($0.name, selfNames: selfNames) }?.id
        }
        return members.first { namesMatch($0.name, name) }?.id
    }

    private static func isIncomingPeer(_ name: String, peerName: String) -> Bool {
        if isPlaceholderSelf(name) { return true }
        return isUsableName(peerName) && namesMatch(name, peerName)
    }

    private static func isIncomingUs(_ name: String, selfNames: [String], peerName: String) -> Bool {
        if isIncomingPeer(name, peerName: peerName) { return false }
        return selfNames.contains { namesMatch($0, name) }
    }

    private static func uuid5(_ string: String) -> UUID {
        let digest = SHA256.hash(data: Data(string.utf8))
        var bytes = Array(digest.prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}
