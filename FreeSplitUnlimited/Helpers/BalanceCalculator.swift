//
//  BalanceCalculator.swift
//  FreeSplitUnlimited
//

import Foundation

struct PersonBalance: Identifiable {
    let id: UUID
    let person: Person
    /// Positive = others owe them; negative = they owe others.
    let net: Decimal
}

struct Settlement: Identifiable {
    var id: String { "\(from.id.uuidString)-\(to.id.uuidString)-\(amount)" }
    let from: Person
    let to: Person
    let amount: Decimal
}

enum BalanceCalculator {
    static func balances(for occasion: Occasion) -> [PersonBalance] {
        var netByID: [UUID: Decimal] = [:]
        let members = occasion.uniqueMembers
        for member in members {
            netByID[member.id] = 0
        }

        for expense in occasion.expenses {
            guard let payer = expense.paidBy, !expense.uniqueParticipants.isEmpty else { continue }
            let owed = expense.owedAmounts()
            for (personID, amount) in owed {
                netByID[personID, default: 0] -= amount
            }
            netByID[payer.id, default: 0] += expense.amount
        }

        return members
            .map { PersonBalance(id: $0.id, person: $0, net: netByID[$0.id] ?? 0) }
            .sorted { $0.person.name.localizedCaseInsensitiveCompare($1.person.name) == .orderedAscending }
    }

    /// Minimal list of payments that settle all balances.
    static func settlements(for occasion: Occasion) -> [Settlement] {
        var debtors: [(Person, Decimal)] = []
        var creditors: [(Person, Decimal)] = []

        for balance in balances(for: occasion) {
            if balance.net < 0 {
                debtors.append((balance.person, -balance.net))
            } else if balance.net > 0 {
                creditors.append((balance.person, balance.net))
            }
        }

        debtors.sort { $0.1 > $1.1 }
        creditors.sort { $0.1 > $1.1 }

        var results: [Settlement] = []
        var i = 0
        var j = 0

        while i < debtors.count && j < creditors.count {
            let pay = min(debtors[i].1, creditors[j].1)
            if pay > 0 {
                results.append(Settlement(from: debtors[i].0, to: creditors[j].0, amount: pay))
            }
            debtors[i].1 -= pay
            creditors[j].1 -= pay
            if debtors[i].1 == 0 { i += 1 }
            if creditors[j].1 == 0 { j += 1 }
        }

        return results
    }
}

enum CurrencyFormat {
    static func string(from amount: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = Locale.current.currency?.identifier ?? "USD"
        return formatter.string(from: amount as NSDecimalNumber) ?? "\(amount)"
    }
}
