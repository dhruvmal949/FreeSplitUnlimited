//
//  Person.swift
//  FreeSplitUnlimited
//

import Foundation
import SwiftData

@Model
final class Person {
    /// Defaults are required so SwiftData can load older stores without trapping (`brk`).
    var id: UUID = UUID()
    var name: String = ""
    var email: String = ""
    var phone: String = ""
    var occasion: Occasion?
    @Relationship(inverse: \Expense.paidBy)
    var expensesPaid: [Expense] = []
    @Relationship(inverse: \Expense.participants)
    var expensesShared: [Expense] = []
    @Relationship(inverse: \ExpenseShare.person)
    var expenseShares: [ExpenseShare] = []

    init(name: String, email: String = "", phone: String = "", id: UUID = UUID()) {
        self.id = id
        self.name = name
        self.email = email
        self.phone = phone
        self.expensesPaid = []
        self.expensesShared = []
        self.expenseShares = []
    }
}
