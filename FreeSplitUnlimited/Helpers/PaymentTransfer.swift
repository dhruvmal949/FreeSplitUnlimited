//
//  PaymentTransfer.swift
//  FreeSplitUnlimited
//
//  Opens Venmo / Cash App / PayPal / Messages so you can pay a friend,
//  then records a settlement so Free Split balances update.
//

import Foundation
import SwiftData
import UIKit

struct PaymentLeg: Hashable {
    let occasionID: UUID
    let amount: Decimal
}

struct PayFriendRequest: Identifiable {
    let id = UUID()
    let payeeName: String
    let amount: Decimal
    let note: String
    let phone: String
    let legs: [PaymentLeg]
}

enum PaymentTransfer {
    static func request(
        payeeName: String,
        amount: Decimal,
        occasions: [Occasion],
        note: String,
        legs: [PaymentLeg]
    ) -> PayFriendRequest {
        PayFriendRequest(
            payeeName: payeeName,
            amount: amount,
            note: note,
            phone: FriendReminder.phone(for: payeeName, in: occasions),
            legs: legs
        )
    }

    static func request(
        for summary: FriendSummary,
        occasions: [Occasion]
    ) -> PayFriendRequest? {
        let owed = summary.groupBalances.filter { $0.net < 0 }
        guard !owed.isEmpty else { return nil }
        let shared = occasions.filter { summary.occasionIDs.contains($0.id) }
        let total = owed.reduce(Decimal(0)) { $0 + -$1.net }
        let names = owed.map(\.occasionName)
        let note: String
        if names.count == 1 {
            note = "Free Split · \(names[0])"
        } else {
            note = "Free Split"
        }
        return request(
            payeeName: summary.name,
            amount: total,
            occasions: shared,
            note: note,
            legs: owed.map { PaymentLeg(occasionID: $0.occasionID, amount: -$0.net) }
        )
    }

    @discardableResult
    static func record(
        payeeName: String,
        amount: Decimal,
        in occasion: Occasion,
        myNames: [String],
        context: ModelContext
    ) -> String? {
        guard amount > 0 else { return "Nothing to pay." }
        guard let payer = person(namedIn: myNames, occasion: occasion) else {
            return "Add yourself to this group before recording a payment."
        }
        guard let payee = person(named: payeeName, occasion: occasion) else {
            return "\(payeeName) isn’t in this group."
        }
        guard payer.id != payee.id else { return "You can’t pay yourself." }

        let expense = Expense(
            title: "Paid \(payee.name)",
            amount: amount,
            date: .now,
            splitMethod: .equal,
            paidBy: payer,
            participants: [payee],
            shares: []
        )
        expense.occasion = occasion
        context.insert(expense)
        occasion.touch()
        return nil
    }

    @MainActor
    static func record(
        request: PayFriendRequest,
        occasions: [Occasion],
        myNames: [String],
        context: ModelContext
    ) -> String? {
        for leg in request.legs {
            guard let occasion = occasions.first(where: { $0.id == leg.occasionID }) else {
                return "Couldn’t find that group."
            }
            if let error = record(
                payeeName: request.payeeName,
                amount: leg.amount,
                in: occasion,
                myNames: myNames,
                context: context
            ) {
                return error
            }
        }
        context.persist()
        return nil
    }

    @MainActor
    static func open(_ url: URL) {
        UIApplication.shared.open(url)
    }

    static func venmoURL(amount: Decimal, note: String) -> URL? {
        var components = URLComponents(string: "venmo://paycharge")
        components?.queryItems = [
            URLQueryItem(name: "txn", value: "pay"),
            URLQueryItem(name: "amount", value: amountString(amount)),
            URLQueryItem(name: "note", value: note)
        ]
        if let url = components?.url, UIApplication.shared.canOpenURL(url) {
            return url
        }
        return URL(string: "https://venmo.com/")
    }

    static func cashAppURL() -> URL? {
        if let url = URL(string: "cashme://"), UIApplication.shared.canOpenURL(url) {
            return url
        }
        return URL(string: "https://cash.app/")
    }

    static func paypalURL() -> URL? {
        if let url = URL(string: "paypal://"), UIApplication.shared.canOpenURL(url) {
            return url
        }
        return URL(string: "https://www.paypal.com/paypalme")
    }

    static func messagesURL(phone: String, body: String) -> URL? {
        let digits = phone.filter(\.isNumber)
        guard !digits.isEmpty else { return nil }
        var components = URLComponents(string: "sms:\(digits)")
        components?.queryItems = [URLQueryItem(name: "body", value: body)]
        return components?.url
    }

    static func amountString(_ amount: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: amount as NSDecimalNumber) ?? "\(amount)"
    }

    private static func person(named name: String, occasion: Occasion) -> Person? {
        occasion.uniqueMembers.first {
            $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame
        }
    }

    private static func person(namedIn names: [String], occasion: Occasion) -> Person? {
        occasion.uniqueMembers.first { member in
            names.contains { $0.localizedCaseInsensitiveCompare(member.name) == .orderedSame }
        }
    }
}
