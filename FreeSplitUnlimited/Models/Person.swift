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
    /// Invite SMS/email is sent once; the Notify toggle locks after a successful send.
    var didInvite: Bool = false

    init(name: String, email: String = "", phone: String = "", id: UUID = UUID()) {
        self.id = id
        self.name = name
        self.email = email
        self.phone = phone
        self.expensesPaid = []
        self.expensesShared = []
        self.expenseShares = []
        self.didInvite = false
    }

    var hasContactInfo: Bool {
        !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !phone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// SwiftData can drop `email`/`phone` when they are only set in `init` (they have defaults).
    /// Assign them again after the person is in a model context, then remember the contact.
    func setContact(email: String, phone: String) {
        self.email = email.trimmingCharacters(in: .whitespacesAndNewlines)
        self.phone = phone.trimmingCharacters(in: .whitespacesAndNewlines)
        KnownFriendsStore.remember([self])
    }

    var asPickedContact: PickedContact {
        PickedContact(
            id: id.uuidString,
            name: name,
            email: email,
            phone: phone,
            isMe: FriendPairing.isPlaceholderSelf(name),
            personID: id,
            didInvite: didInvite
        )
    }
}
