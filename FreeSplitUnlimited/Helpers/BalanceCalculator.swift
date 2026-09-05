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
            .map { PersonBalance(id: $0.id, person: $0, net: MoneySplit.cents(netByID[$0.id] ?? 0)) }
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
                results.append(Settlement(from: debtors[i].0, to: creditors[j].0, amount: MoneySplit.cents(pay)))
            }
            debtors[i].1 -= pay
            creditors[j].1 -= pay
            if debtors[i].1 == 0 { i += 1 }
            if creditors[j].1 == 0 { j += 1 }
        }

        return results
    }

    /// 1:1 Splitwise-style balances between Me and each other person, across groups.
    static func friendSummaries(from occasions: [Occasion], myNames: [String] = ["Me"]) -> [FriendSummary] {
        func isMe(_ name: String) -> Bool {
            myNames.contains { $0.localizedCaseInsensitiveCompare(name) == .orderedSame }
        }

        var net: [String: Decimal] = [:]
        var displayName: [String: String] = [:]
        var occasionIDs: [String: [UUID]] = [:]
        var occasionNames: [String: [String]] = [:]

        for occasion in occasions {
            for member in occasion.uniqueMembers where !isMe(member.name) {
                let key = member.name.lowercased()
                displayName[key] = member.name
                net[key, default: 0] += 0
                if occasionIDs[key]?.contains(occasion.id) != true {
                    occasionIDs[key, default: []].append(occasion.id)
                    occasionNames[key, default: []].append(occasion.name)
                }
            }

            for settlement in settlements(for: occasion) {
                if isMe(settlement.from.name), !isMe(settlement.to.name) {
                    let key = settlement.to.name.lowercased()
                    displayName[key] = settlement.to.name
                    net[key, default: 0] -= settlement.amount
                } else if isMe(settlement.to.name), !isMe(settlement.from.name) {
                    let key = settlement.from.name.lowercased()
                    displayName[key] = settlement.from.name
                    net[key, default: 0] += settlement.amount
                }
            }
        }

        return displayName.keys.map { key in
            FriendSummary(
                id: key,
                name: displayName[key] ?? key,
                net: net[key] ?? 0,
                occasionIDs: occasionIDs[key] ?? [],
                occasionNames: occasionNames[key] ?? []
            )
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Positive = others owe you in this group; negative = you owe others.
    static func myNet(in occasion: Occasion, myNames: [String] = ["Me"]) -> Decimal {
        balances(for: occasion).first { balance in
            myNames.contains { $0.localizedCaseInsensitiveCompare(balance.person.name) == .orderedSame }
        }?.net ?? 0
    }

    static func activity(from occasions: [Occasion]) -> [ActivityEvent] {
        var items: [ActivityEvent] = []
        for occasion in occasions {
            items.append(
                ActivityEvent(
                    id: "created-\(occasion.id.uuidString)",
                    date: occasion.createdAt,
                    kind: .splitCreated,
                    title: "Split created",
                    subtitle: occasion.name,
                    occasionID: occasion.id
                )
            )
            var seenExpenseIDs = Set<UUID>()
            for expense in occasion.expenses where seenExpenseIDs.insert(expense.id).inserted {
                let payer = expense.paidBy?.name ?? "Someone"
                items.append(
                    ActivityEvent(
                        id: "paid-\(expense.id.uuidString)",
                        date: expense.date,
                        kind: .amountPaid,
                        title: "\(payer) paid \(CurrencyFormat.string(from: expense.amount))",
                        subtitle: "\(expense.title) · \(occasion.name)",
                        occasionID: occasion.id
                    )
                )
            }
        }
        return items.sorted { $0.date > $1.date }
    }
}

struct FriendSummary: Identifiable {
    let id: String
    let name: String
    /// Positive = they owe you; negative = you owe them.
    let net: Decimal
    let occasionIDs: [UUID]
    let occasionNames: [String]
}

struct ActivityEvent: Identifiable {
    enum Kind {
        case splitCreated
        case amountPaid
    }

    let id: String
    let date: Date
    let kind: Kind
    let title: String
    let subtitle: String
    let occasionID: UUID
}

enum CurrencyFormat {
    static func string(from amount: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = Locale.current.currency?.identifier ?? "USD"
        return formatter.string(from: amount as NSDecimalNumber) ?? "\(amount)"
    }
}
