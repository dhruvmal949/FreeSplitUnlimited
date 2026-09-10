//
//  FriendReminder.swift
//  FreeSplitUnlimited
//
//  Pre-filled “you owe …” texts, sent via Messages or the share sheet.
//

import MessageUI
import SwiftUI
import UIKit

struct FriendRemindPayload: Identifiable {
    let id = UUID()
    let name: String
    let message: String
    let phone: String
}

enum FriendReminder {
    static func payload(
        name: String,
        amount: Decimal,
        occasions: [Occasion],
        myNames: [String]
    ) -> FriendRemindPayload {
        FriendRemindPayload(
            name: name,
            message: message(name: name, amount: amount, occasions: occasions, myNames: myNames),
            phone: phone(for: name, in: occasions)
        )
    }

    static func payload(
        for summary: FriendSummary,
        occasions: [Occasion],
        myNames: [String]
    ) -> FriendRemindPayload {
        let shared = occasions.filter { summary.occasionIDs.contains($0.id) }
        return payload(name: summary.name, amount: summary.net, occasions: shared, myNames: myNames)
    }

    static func message(
        name: String,
        amount: Decimal,
        occasions: [Occasion],
        myNames: [String]
    ) -> String {
        let money = CurrencyFormat.string(from: amount)
        if let title = highlightTitle(friendName: name, occasions: occasions, myNames: myNames) {
            return "Hey, you owe \(money) for \(title)"
        }
        if occasions.count == 1, let group = occasions.first?.name, !group.isEmpty {
            return "Hey, you owe \(money) for \(group)"
        }
        return "Hey, you owe \(money) total"
    }

    static func phone(for name: String, in occasions: [Occasion]) -> String {
        if let saved = KnownFriendsStore.all().first(where: {
            $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame
        }), !saved.phone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return saved.phone.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        for occasion in occasions {
            if let person = occasion.uniqueMembers.first(where: {
                $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame
            }) {
                let phone = person.phone.trimmingCharacters(in: .whitespacesAndNewlines)
                if !phone.isEmpty { return phone }
            }
        }
        return ""
    }

    /// Use an expense title only when one shared bill clearly explains the reminder.
    private static func highlightTitle(
        friendName: String,
        occasions: [Occasion],
        myNames: [String]
    ) -> String? {
        func isMe(_ name: String) -> Bool {
            myNames.contains { $0.localizedCaseInsensitiveCompare(name) == .orderedSame }
        }

        var hits: [Expense] = []
        for occasion in occasions {
            var seen = Set<UUID>()
            for expense in occasion.expenses where seen.insert(expense.id).inserted {
                let friendIn = expense.uniqueParticipants.contains {
                    $0.name.localizedCaseInsensitiveCompare(friendName) == .orderedSame
                }
                let iPaid = expense.paidBy.map { isMe($0.name) } ?? false
                if friendIn && iPaid {
                    hits.append(expense)
                }
            }
        }
        guard hits.count == 1 else { return nil }
        let title = hits[0].title.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? nil : title
    }
}

struct FriendRemindSheet: View {
    let payload: FriendRemindPayload

    var body: some View {
        if MessageComposeView.canSend, !payload.phone.isEmpty {
            MessageComposeView(recipients: [payload.phone], body: payload.message)
        } else {
            TextActivitySheet(text: payload.message)
        }
    }
}

private struct MessageComposeView: UIViewControllerRepresentable {
    static var canSend: Bool { MFMessageComposeViewController.canSendText() }

    let recipients: [String]
    let body: String

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIViewController(context: Context) -> MFMessageComposeViewController {
        let controller = MFMessageComposeViewController()
        controller.recipients = recipients
        controller.body = body
        controller.messageComposeDelegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: MFMessageComposeViewController, context: Context) {}

    final class Coordinator: NSObject, MFMessageComposeViewControllerDelegate {
        func messageComposeViewController(
            _ controller: MFMessageComposeViewController,
            didFinishWith result: MessageComposeResult
        ) {
            controller.dismiss(animated: true)
        }
    }
}

private struct TextActivitySheet: UIViewControllerRepresentable {
    let text: String

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [text], applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
