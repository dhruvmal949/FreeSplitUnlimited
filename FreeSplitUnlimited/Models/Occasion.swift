//
//  Occasion.swift
//  FreeSplitUnlimited
//

import Foundation
import SwiftData

@Model
final class Occasion {
    /// Defaults are required so SwiftData can load older stores without trapping (`brk`).
    var id: UUID = UUID()
    var name: String = ""
    var note: String = ""
    var createdAt: Date = Date.now
    /// Bumped on every local change; used to resolve conflicts when merging data from other phones.
    var updatedAt: Date = Date.now
    /// Soft-delete flag so deletions propagate to other phones instead of being silently resurrected.
    var isDeleted: Bool = false
    /// Stored as a string so older SwiftData stores can load without trapping.
    var groupType: String = GroupKind.other.rawValue
    /// Account that created this group. Nil on older stores until claimed or stamped.
    var ownerAccountID: UUID? = nil
    /// Comma-separated account UUIDs that opened a share link or were granted this group.
    var grantedAccountIDsRaw: String = ""
    @Relationship(deleteRule: .cascade, inverse: \Person.occasion)
    var members: [Person] = []
    @Relationship(deleteRule: .cascade, inverse: \Expense.occasion)
    var expenses: [Expense] = []

    init(
        name: String,
        note: String = "",
        createdAt: Date = .now,
        updatedAt: Date? = nil,
        id: UUID = UUID(),
        groupType: String = GroupKind.other.rawValue
    ) {
        self.id = id
        self.name = name
        self.note = note
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
        self.isDeleted = false
        self.groupType = groupType
        self.ownerAccountID = nil
        self.grantedAccountIDsRaw = ""
        self.members = []
        self.expenses = []
    }

    var grantedAccountIDs: [UUID] {
        get {
            grantedAccountIDsRaw
                .split(separator: ",")
                .compactMap { UUID(uuidString: $0.trimmingCharacters(in: .whitespacesAndNewlines)) }
        }
        set {
            var seen = Set<UUID>()
            grantedAccountIDsRaw = newValue
                .filter { seen.insert($0).inserted }
                .map(\.uuidString)
                .joined(separator: ",")
        }
    }

    func grantAccess(to accountID: UUID) {
        var ids = grantedAccountIDs
        guard !ids.contains(accountID) else { return }
        ids.append(accountID)
        grantedAccountIDs = ids
    }

    @MainActor
    func assignCurrentOwner() {
        guard let accountID = AuthSession.shared.accountID else { return }
        if ownerAccountID == nil {
            ownerAccountID = accountID
        }
        grantAccess(to: accountID)
    }

    var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled group" : trimmed
    }

    var kind: GroupKind {
        GroupKind.resolve(groupType)
    }

    /// Friends-tab splits start as one-to-one until a third person is added.
    var isOneToOne: Bool {
        groupType == SplitKind.oneToOne
    }

    /// Home lists named groups. A Friends split becomes a group at 3+ people.
    var appearsInGroups: Bool {
        !isOneToOne || uniqueMembers.count > 2
    }

    /// Hidden after the user deletes the group, even if a copy is restored locally.
    var shouldAppearInLists: Bool {
        !isDeleted && !DeletedGroupsStore.contains(id)
    }

    /// Marks this split as changed so sync (mesh + cloud) knows to propagate it.
    func touch() {
        updatedAt = .now
    }

    /// Soft-delete so Home hides the group and nearby phones receive the removal.
    func markDeleted() {
        isDeleted = true
        DeletedGroupsStore.remember(id)
        touch()
    }

    /// When a one-to-one split grows past two people, save it as a group.
    func promoteToGroupIfNeeded() {
        guard isOneToOne, uniqueMembers.count > 2 else { return }
        groupType = GroupKind.other.rawValue
        touch()
    }

    var totalSpent: Decimal {
        expenses.reduce(0) { $0 + $1.amount }
    }

    /// Unique members (guards against SwiftData relationship duplicates).
    var uniqueMembers: [Person] {
        var seen = Set<UUID>()
        var result: [Person] = []
        for person in members where seen.insert(person.id).inserted {
            result.append(person)
        }
        return result
    }

    func sortedMembers() -> [Person] {
        uniqueMembers.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    /// Removes duplicate relationship entries that can crash ForEach / Dictionary lookups.
    func deduplicateRelationships() {
        members = uniqueMembers

        var seenExpenseIDs = Set<UUID>()
        var uniqueExpenses: [Expense] = []
        for expense in expenses where seenExpenseIDs.insert(expense.id).inserted {
            expense.participants = expense.uniqueParticipants
            uniqueExpenses.append(expense)
        }
        expenses = uniqueExpenses
    }
}

enum SplitKind {
    /// Stored `groupType` for a Friends-created 1:1 split. Not a `GroupKind` case
    /// so it does not show in the Create Group kind picker.
    static let oneToOne = "oneToOne"
}

enum GroupKind: String, CaseIterable, Identifiable {
    case trip
    case home
    case party
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .trip: return "Trip"
        case .home: return "Home"
        case .party: return "Party"
        case .other: return "Other"
        }
    }

    var symbol: String {
        switch self {
        case .trip: return "suitcase.fill"
        case .home: return "house.fill"
        case .party: return "party.popper.fill"
        case .other: return "square.grid.2x2.fill"
        }
    }

    static func resolve(_ raw: String) -> GroupKind {
        GroupKind(rawValue: raw) ?? .other
    }
}
