//
//  MoneySplit.swift
//  FreeSplitUnlimited
//
//  Splits a dollar amount so the pieces always add up to the original total.
//

import Foundation

enum MoneySplit {
    /// Rounds money to cents.
    static func cents(_ value: Decimal) -> Decimal {
        var input = value
        var output = Decimal()
        NSDecimalRound(&output, &input, 2, .plain)
        return output
    }

    /// Splits `total` by `weights`. The last person with a weight gets any leftover cent
    /// so $10 among 3 people is $3.33, $3.33, $3.34 — never $9.99.
    static func distribute(total: Decimal, weights: [(id: UUID, weight: Decimal)]) -> [UUID: Decimal] {
        let bill = cents(total)
        guard bill > 0, !weights.isEmpty else { return [:] }

        var unique: [(id: UUID, weight: Decimal)] = []
        var seen = Set<UUID>()
        for item in weights where seen.insert(item.id).inserted {
            unique.append((item.id, max(item.weight, 0)))
        }

        let weightTotal = unique.reduce(Decimal(0)) { $0 + $1.weight }
        guard weightTotal > 0 else { return [:] }

        let lastIndex = unique.lastIndex(where: { $0.weight > 0 }) ?? unique.indices.last!
        var result: [UUID: Decimal] = [:]
        var allocated = Decimal(0)

        for (index, item) in unique.enumerated() {
            if index == lastIndex {
                result[item.id] = cents(bill - allocated)
            } else if item.weight == 0 {
                result[item.id] = 0
            } else {
                let share = cents(bill * item.weight / weightTotal)
                result[item.id] = share
                allocated += share
            }
        }
        return result
    }

    /// Percents that add up to exactly 100 (e.g. 33.33, 33.33, 33.34).
    static func evenPercents(count: Int) -> [Decimal] {
        guard count > 0 else { return [] }
        let even = cents(Decimal(100) / Decimal(count))
        var values = Array(repeating: even, count: count)
        let allocated = even * Decimal(count - 1)
        values[count - 1] = Decimal(100) - allocated
        return values
    }
}
