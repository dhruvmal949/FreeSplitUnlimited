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

        var totals: [String: Decimal] = [:]
        var displayName: [String: String] = [:]
        var occasionIDs: [String: [UUID]] = [:]
        var occasionNames: [String: [String]] = [:]

        for occasion in occasions {
            for member in occasion.uniqueMembers where !isMe(member.name) {
                let key = member.name.lowercased()
                displayName[key] = member.name
                if occasionIDs[key]?.contains(occasion.id) != true {
                    occasionIDs[key, default: []].append(occasion.id)
                    occasionNames[key, default: []].append(occasion.name)
                }
                totals[key, default: 0] += net(withFriend: member.name, in: occasion, myNames: myNames)
            }
        }

        return displayName.keys.map { key in
            FriendSummary(
                id: key,
                name: displayName[key] ?? key,
                net: totals[key] ?? 0,
                occasionIDs: occasionIDs[key] ?? [],
                occasionNames: occasionNames[key] ?? []
            )
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Positive = this friend owes you in the group; negative = you owe them.
    static func net(
        withFriend friendName: String,
        in occasion: Occasion,
        myNames: [String] = ["Me"]
    ) -> Decimal {
        func isMe(_ name: String) -> Bool {
            myNames.contains { FriendPairing.namesMatch($0, name) }
        }

        var total: Decimal = 0
        for expense in occasion.expenses {
            guard let payer = expense.paidBy else { continue }
            let owed = expense.owedAmounts()
            let friendShare = occasion.uniqueMembers
                .filter { FriendPairing.namesMatch($0.name, friendName) }
                .reduce(Decimal.zero) { $0 + (owed[$1.id] ?? 0) }
            let myShare = occasion.uniqueMembers
                .filter { isMe($0.name) }
                .reduce(Decimal.zero) { $0 + (owed[$1.id] ?? 0) }

            if isMe(payer.name), friendShare > 0 {
                total += friendShare
            } else if FriendPairing.namesMatch(payer.name, friendName), myShare > 0 {
                total -= myShare
            }
        }
        return MoneySplit.cents(total)
    }

    /// Records a 1:1 cash payment between you and a friend. `friendPaidYou` means they paid you.
    @discardableResult
    static func recordFriendPayment(
        amount: Decimal,
        friendPaidYou: Bool,
        friendName: String,
        myNames: [String] = ["Me"],
        occasions: [Occasion],
        note: String = ""
    ) -> [Expense] {
        var remaining = MoneySplit.cents(amount)
        guard remaining > 0 else { return [] }

        func me(in occasion: Occasion) -> Person? {
            occasion.uniqueMembers.first { member in
                myNames.contains { FriendPairing.namesMatch($0, member.name) }
            }
        }
        func friend(in occasion: Occasion) -> Person? {
            occasion.uniqueMembers.first { FriendPairing.namesMatch($0.name, friendName) }
        }

        let ranked = occasions.compactMap { occasion -> (Occasion, Decimal)? in
            let groupNet = net(withFriend: friendName, in: occasion, myNames: myNames)
            if friendPaidYou, groupNet > 0 { return (occasion, groupNet) }
            if !friendPaidYou, groupNet < 0 { return (occasion, groupNet) }
            return nil
        }
        .sorted { abs($0.1) > abs($1.1) }

        var created: [Expense] = []

        func addPayment(to occasion: Occasion, amount: Decimal) {
            let bill = MoneySplit.cents(amount)
            guard bill > 0, let me = me(in: occasion), let friend = friend(in: occasion) else { return }
            let payer = friendPaidYou ? friend : me
            let receiver = friendPaidYou ? me : friend
            let expense = Expense(
                title: "Payment",
                amount: bill,
                splitMethod: .equal,
                paidBy: payer,
                participants: [receiver],
                note: note
            )
            expense.occasion = occasion
            occasion.expenses.append(expense)
            occasion.touch()
            created.append(expense)
        }

        for (occasion, groupNet) in ranked {
            guard remaining > 0 else { break }
            let slice = min(remaining, abs(groupNet))
            addPayment(to: occasion, amount: slice)
            remaining -= slice
        }

        if remaining > 0, let occasion = occasions.first(where: { me(in: $0) != nil && friend(in: $0) != nil }) {
            addPayment(to: occasion, amount: remaining)
        }
        return created
    }

    /// Records that `payerName` paid `receiverName` inside one group.
    @discardableResult
    static func recordDirectedPayment(
        amount: Decimal,
        payerName: String,
        receiverName: String,
        in occasion: Occasion,
        note: String = ""
    ) -> Expense? {
        let bill = MoneySplit.cents(amount)
        guard bill > 0,
              let payer = occasion.uniqueMembers.first(where: { FriendPairing.namesMatch($0.name, payerName) }),
              let receiver = occasion.uniqueMembers.first(where: { FriendPairing.namesMatch($0.name, receiverName) }),
              payer.id != receiver.id
        else { return nil }
        let expense = Expense(
            title: "Payment",
            amount: bill,
            splitMethod: .equal,
            paidBy: payer,
            participants: [receiver],
            note: note
        )
        expense.occasion = occasion
        occasion.expenses.append(expense)
        occasion.touch()
        return expense
    }
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
                let isPayment = expense.isSettlementPayment
                let counterpart = expense.uniqueParticipants.first(where: { $0.name != payer })?.name
                    ?? occasion.name
                let subtitle: String
                if isPayment {
                    if expense.note.isEmpty {
                        subtitle = occasion.displayName
                    } else {
                        subtitle = "\(expense.note) · \(occasion.displayName)"
                    }
                } else {
                    subtitle = "\(expense.title) · \(occasion.name)"
                }
                items.append(
                    ActivityEvent(
                        id: "paid-\(expense.id.uuidString)",
                        date: expense.date,
                        kind: .amountPaid,
                        title: isPayment
                            ? "\(payer) settled \(CurrencyFormat.string(from: expense.amount)) with \(counterpart)"
                            : "\(payer) paid \(CurrencyFormat.string(from: expense.amount))",
                        subtitle: subtitle,
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

enum OverflowStack {
    static let recentLimit = 15

    struct Sections<Item> {
        var recent: [Item]
        var paid: [Item]
        var isEmpty: Bool { recent.isEmpty && paid.isEmpty }
        var showsPaidStack: Bool { !paid.isEmpty }
    }

    /// Keeps the first 15 items in the main list. Extra paid cells go into a
    /// separate Paid stack on the same screen.
    static func sections<Item>(from items: [Item], isPaid: (Item) -> Bool) -> Sections<Item> {
        guard items.count > recentLimit else {
            return Sections(recent: items, paid: [])
        }
        var recent: [Item] = []
        var paid: [Item] = []
        for (index, item) in items.enumerated() {
            if index >= recentLimit, isPaid(item) {
                paid.append(item)
            } else {
                recent.append(item)
            }
        }
        return Sections(recent: recent, paid: paid)
    }
}

enum NotificationFeed {
    static func sections(from events: [ActivityEvent], hiddenIDs: Set<String> = []) -> OverflowStack.Sections<ActivityEvent> {
        OverflowStack.sections(
            from: events.filter { !hiddenIDs.contains($0.id) },
            isPaid: { $0.kind == .amountPaid }
        )
    }
}

enum FriendFeed {
    static func sections(from friends: [FriendSummary], hiddenIDs: Set<String> = []) -> OverflowStack.Sections<FriendSummary> {
        OverflowStack.sections(
            from: friends.filter { !hiddenIDs.contains($0.id) },
            isPaid: { $0.net == 0 }
        )
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
