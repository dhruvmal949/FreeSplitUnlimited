//
//  Person.swift
//  FreeSplitUnlimited
//

import Foundation
import SwiftData

@Model
final class Person {
    var id: UUID
    var name: String
    /// Defaults help SwiftData migrate older installs without wiping data.
    var email: String = ""
    var phone: String = ""
    var occasion: Occasion?
    @Relationship(inverse: \Expense.paidBy)
    var expensesPaid: [Expense]
    @Relationship(inverse: \Expense.participants)
    var expensesShared: [Expense]
    @Relationship(inverse: \ExpenseShare.person)
    var expenseShares: [ExpenseShare]

    init(name: String, email: String = "", phone: String = "", id: UUID = UUID()) {
        self.id = id
        self.name = name
        self.email = email
        self.phone = phone
        self.expensesPaid = []
        self.expensesShared = []
        self.expenseShares = []
    }

    var formattedPhone: String {
        FriendContactValidation.formatPhone(phone)
    }
}

enum FriendContactValidation {
    /// Accepts common emails like name@email.com
    static func isValidEmail(_ email: String) -> Bool {
        let trimmed = email
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !trimmed.isEmpty else { return false }

        // Simple, practical email check: local@domain.tld
        let pattern = #"^[A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,}$"#
        return trimmed.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    static func normalizedEmail(_ email: String) -> String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    static func isValidPhone(_ phone: String) -> Bool {
        let digits = phone.filter(\.isNumber)
        return digits.count >= 7
    }

    /// Formats digits with dashes, e.g. 555-123-4567
    static func formatPhone(_ phone: String) -> String {
        let digits = String(phone.filter(\.isNumber).prefix(11))
        guard !digits.isEmpty else { return "" }

        if digits.count <= 3 {
            return digits
        }

        // 11-digit numbers starting with 1 → 1-555-123-4567
        if digits.count == 11, digits.first == "1" {
            let area = digits.dropFirst().prefix(3)
            let mid = digits.dropFirst(4).prefix(3)
            let last = digits.dropFirst(7)
            var result = "1-\(area)"
            if !mid.isEmpty { result += "-\(mid)" }
            if !last.isEmpty { result += "-\(last)" }
            return result
        }

        // 7-digit local → 555-1234
        if digits.count <= 7 {
            let first = digits.prefix(3)
            let rest = digits.dropFirst(3)
            return "\(first)-\(rest)"
        }

        // 10-digit → 555-123-4567 (also formats while typing 8–10 digits)
        let area = digits.prefix(3)
        let mid = digits.dropFirst(3).prefix(3)
        let last = digits.dropFirst(6)
        var result = "\(area)-\(mid)"
        if !last.isEmpty {
            result += "-\(last)"
        }
        return result
    }
}
