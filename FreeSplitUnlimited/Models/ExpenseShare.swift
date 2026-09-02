//
//  ExpenseShare.swift
//  FreeSplitUnlimited
//

import Foundation
import SwiftData

@Model
final class ExpenseShare {
    /// Defaults are required so SwiftData can load older stores without trapping (`brk`).
    var id: UUID = UUID()
    /// Percentage (0–100) or number of parts, depending on the expense split method.
    var value: Decimal = 0
    var person: Person?
    var expense: Expense?

    init(person: Person? = nil, value: Decimal) {
        self.id = UUID()
        self.person = person
        self.value = value
    }
}
