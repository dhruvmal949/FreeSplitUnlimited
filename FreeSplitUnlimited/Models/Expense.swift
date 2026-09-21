//
//  Expense.swift
//  FreeSplitUnlimited
//

import Foundation
import SwiftData

@Model
final class Expense {
    /// Defaults are required so SwiftData can load older stores without trapping (`brk`).
    var id: UUID = UUID()
    var title: String = ""
    var amount: Decimal = 0
    var date: Date = Date.now
    var splitMethodRaw: String = SplitMethod.equal.rawValue
    /// How the payment was settled (Venmo, cash, etc.). Empty for regular expenses.
    var note: String = ""
    var occasion: Occasion?
    var paidBy: Person?
    var participants: [Person] = []
    @Relationship(deleteRule: .cascade, inverse: \ExpenseShare.expense)
    var shares: [ExpenseShare] = []

    var splitMethod: SplitMethod {
        get { SplitMethod(rawValue: splitMethodRaw) ?? .equal }
        set { splitMethodRaw = newValue.rawValue }
    }

    /// Unique people on this expense (SwiftData relationships can occasionally duplicate).
    var uniqueParticipants: [Person] {
        var seen = Set<UUID>()
        var result: [Person] = []
        for person in participants where seen.insert(person.id).inserted {
            result.append(person)
        }
        return result
    }

    init(
        title: String,
        amount: Decimal,
        date: Date = .now,
        splitMethod: SplitMethod = .equal,
        paidBy: Person? = nil,
        participants: [Person] = [],
        shares: [ExpenseShare] = [],
        note: String = "",
        id: UUID = UUID()
    ) {
        self.id = id
        self.title = title
        self.amount = amount
        self.date = date
        self.splitMethodRaw = splitMethod.rawValue
        self.paidBy = paidBy
        self.participants = Self.deduplicated(participants)
        self.shares = shares
        self.note = note
    }

    /// How much each participant owes for this expense. Shares always add up to `amount`.
    func owedAmounts() -> [UUID: Decimal] {
        let people = uniqueParticipants.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        guard !people.isEmpty else { return [:] }

        var weights: [(id: UUID, weight: Decimal)]
        switch splitMethod {
        case .equal:
            weights = people.map { ($0.id, 1) }
        case .percentage, .parts:
            weights = people.map { person in
                let value = shares.first(where: { $0.person?.id == person.id })?.value ?? 0
                return (person.id, value)
            }
            if weights.allSatisfy({ $0.weight == 0 }) {
                weights = people.map { ($0.id, 1) }
            }
        }
        return MoneySplit.distribute(total: amount, weights: weights)
    }

    var splitSummary: String {
        let people = uniqueParticipants
        let names = people.map(\.name).sorted()
        switch splitMethod {
        case .equal:
            return "Equally · \(names.joined(separator: ", "))"
        case .percentage:
            let bits = people.compactMap { person -> String? in
                guard let value = shares.first(where: { $0.person?.id == person.id })?.value else { return nil }
                return "\(person.name) \(NSDecimalNumber(decimal: value))%"
            }.sorted()
            return "By % · \(bits.joined(separator: ", "))"
        case .parts:
            let bits = people.compactMap { person -> String? in
                guard let value = shares.first(where: { $0.person?.id == person.id })?.value else { return nil }
                let label = value == 1 ? "1 part" : "\(NSDecimalNumber(decimal: value)) parts"
                return "\(person.name) \(label)"
            }.sorted()
            return "By parts · \(bits.joined(separator: ", "))"
        }
    }

    private static func deduplicated(_ people: [Person]) -> [Person] {
        var seen = Set<UUID>()
        return people.filter { seen.insert($0.id).inserted }
    }
}
