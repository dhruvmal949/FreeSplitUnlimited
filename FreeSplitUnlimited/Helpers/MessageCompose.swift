//
//  MessageCompose.swift
//  FreeSplitUnlimited
//

import MessageUI
import SwiftUI
import UIKit

struct ComposePayload: Identifiable {
    let id = UUID()
    let recipients: [String]
    let body: String
    var subject: String = ""
    var personIDs: [UUID] = []

    var recipient: String { recipients.first ?? "" }
    var personID: UUID? { personIDs.first }

    init(recipient: String, body: String, subject: String = "", personID: UUID? = nil) {
        self.recipients = [recipient]
        self.body = body
        self.subject = subject
        self.personIDs = personID.map { [$0] } ?? []
    }

    init(recipients: [String], body: String, subject: String = "", personID: UUID? = nil, personIDs: [UUID] = []) {
        self.recipients = recipients
        self.body = body
        self.subject = subject
        if !personIDs.isEmpty {
            self.personIDs = personIDs
        } else if let personID {
            self.personIDs = [personID]
        } else {
            self.personIDs = []
        }
    }

    var isPhoneInvite: Bool {
        recipients.contains { !$0.contains("@") }
    }
}

struct MailComposeView: UIViewControllerRepresentable {
    let payload: ComposePayload
    var onFinish: (Bool) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let controller = MFMailComposeViewController()
        controller.mailComposeDelegate = context.coordinator
        controller.setToRecipients(payload.recipients)
        controller.setSubject(payload.subject.isEmpty ? "Free Split" : payload.subject)
        controller.setMessageBody(payload.body, isHTML: false)
        return controller
    }

    func updateUIViewController(_ uiViewController: MFMailComposeViewController, context: Context) {}

    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        let onFinish: (Bool) -> Void
        init(onFinish: @escaping (Bool) -> Void) { self.onFinish = onFinish }

        func mailComposeController(
            _ controller: MFMailComposeViewController,
            didFinishWith result: MFMailComposeResult,
            error: Error?
        ) {
            controller.dismiss(animated: true)
            onFinish(result == .sent)
        }
    }
}

struct MessageComposeView: UIViewControllerRepresentable {
    let payload: ComposePayload
    var onFinish: (Bool) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    func makeUIViewController(context: Context) -> MFMessageComposeViewController {
        let controller = MFMessageComposeViewController()
        controller.messageComposeDelegate = context.coordinator
        controller.recipients = payload.recipients
        controller.body = payload.body
        return controller
    }

    func updateUIViewController(_ uiViewController: MFMessageComposeViewController, context: Context) {}

    final class Coordinator: NSObject, MFMessageComposeViewControllerDelegate {
        let onFinish: (Bool) -> Void
        init(onFinish: @escaping (Bool) -> Void) { self.onFinish = onFinish }

        func messageComposeViewController(
            _ controller: MFMessageComposeViewController,
            didFinishWith result: MessageComposeResult
        ) {
            controller.dismiss(animated: true)
            onFinish(result == .sent)
        }
    }
}
