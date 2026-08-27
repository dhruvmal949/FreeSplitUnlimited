//
//  Occasion.swift
//  FreeSplitUnlimited
//

import Foundation
import SwiftData

@Model
final class Occasion {
    var id: UUID
    var name: String
    var note: String
    var createdAt: Date
    /// Bumped on every local change; used to resolve conflicts when merging data from other phones.
    var updatedAt: Date = Date.now
    /// Soft-delete flag so deletions propagate to other phones instead of being silently resurrected.
    var isDeleted: Bool = false
    @Relationship(deleteRule: .cascade, inverse: \Person.occasion)
    var members: [Person]
    @Relationship(deleteRule: .cascade, inverse: \Expense.occasion)
    var expenses: [Expense]

    init(name: String, note: String = "", createdAt: Date = .now, updatedAt: Date? = nil, id: UUID = UUID()) {
        self.id = id
        self.name = name
        self.note = note
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
        self.isDeleted = false
        self.members = []
        self.expenses = []
    }

    /// Marks this split as changed so sync (mesh + cloud) knows to propagate it.
    func touch() {
        updatedAt = .now
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
