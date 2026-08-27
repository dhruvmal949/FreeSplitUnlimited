//
//  ExpenseShare.swift
//  FreeSplitUnlimited
//

import Foundation
import SwiftData

@Model
final class ExpenseShare {
    var id: UUID
    /// Percentage (0–100) or number of parts, depending on the expense split method.
    var value: Decimal
    var person: Person?
    var expense: Expense?

    init(person: Person? = nil, value: Decimal) {
        self.id = UUID()
        self.person = person
        self.value = value
    }
}
