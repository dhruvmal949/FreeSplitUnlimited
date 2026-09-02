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
    }

    /// How much each participant owes for this expense.
    func owedAmounts() -> [UUID: Decimal] {
        let people = uniqueParticipants
        guard !people.isEmpty else { return [:] }

        switch splitMethod {
        case .equal:
            let share = amount / Decimal(people.count)
            var result: [UUID: Decimal] = [:]
            for person in people {
                result[person.id] = share
            }
            return result

        case .percentage:
            var result: [UUID: Decimal] = [:]
            for person in people {
                let percent = shares.first(where: { $0.person?.id == person.id })?.value ?? 0
                result[person.id] = amount * percent / 100
            }
            return result

        case .parts:
            let totalParts = shares
                .filter { share in people.contains(where: { $0.id == share.person?.id }) }
                .reduce(into: [UUID: Decimal]()) { partial, share in
                    guard let id = share.person?.id else { return }
                    partial[id] = share.value
                }
                .values
                .reduce(Decimal(0), +)
            guard totalParts > 0 else { return [:] }

            var result: [UUID: Decimal] = [:]
            for person in people {
                let parts = shares.first(where: { $0.person?.id == person.id })?.value ?? 0
                result[person.id] = amount * parts / totalParts
            }
            return result
        }
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
