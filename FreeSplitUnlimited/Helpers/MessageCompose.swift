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
        controller.setSubject(payload.subject.isEmpty ? "Join my split on Free Split" : payload.subject)
        controller.setMessageBody(payload.body, isHTML: false)
        controller.setToRecipients(payload.recipients)
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
            controller.dismiss(animated: true) {
                self.onFinish(result == .sent)
            }
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

/// Presents Mail/Messages on the top UIKit screen so they still appear after
/// Create Group (a SwiftUI sheet). Nested SwiftUI sheets often swallow Mail.
final class InviteComposerHost: NSObject, MFMailComposeViewControllerDelegate, MFMessageComposeViewControllerDelegate {
    static let shared = InviteComposerHost()
    private var onFinish: ((Bool) -> Void)?

    @MainActor
    func present(_ payload: ComposePayload, completion: @escaping (Bool) -> Void) {
        present(payload, triesLeft: 4, completion: completion)
    }

    @MainActor
    private func present(_ payload: ComposePayload, triesLeft: Int, completion: @escaping (Bool) -> Void) {
        onFinish = completion
        guard let host = Self.topViewController() else {
            completion(false)
            return
        }
        if Self.isComposer(host), triesLeft > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                self?.present(payload, triesLeft: triesLeft - 1, completion: completion)
            }
            return
        }
        if payload.isPhoneInvite {
            let controller = MFMessageComposeViewController()
            controller.messageComposeDelegate = self
            controller.recipients = payload.recipients
            controller.body = payload.body
            host.present(controller, animated: true)
            return
        }
        let recipients = payload.recipients
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.contains("@") }
        let controller = MFMailComposeViewController()
        controller.mailComposeDelegate = self
        controller.setSubject(payload.subject.isEmpty ? "Join my split on Free Split" : payload.subject)
        controller.setMessageBody(payload.body, isHTML: false)
        controller.setToRecipients(recipients)
        host.present(controller, animated: true)
    }

    nonisolated func mailComposeController(
        _ controller: MFMailComposeViewController,
        didFinishWith result: MFMailComposeResult,
        error: Error?
    ) {
        DispatchQueue.main.async {
            controller.dismiss(animated: true) { [weak self] in
                let finish = self?.onFinish
                self?.onFinish = nil
                finish?(result == .sent)
            }
        }
    }

    nonisolated func messageComposeViewController(
        _ controller: MFMessageComposeViewController,
        didFinishWith result: MessageComposeResult
    ) {
        DispatchQueue.main.async {
            controller.dismiss(animated: true) { [weak self] in
                let finish = self?.onFinish
                self?.onFinish = nil
                finish?(result == .sent)
            }
        }
    }

    private static func isComposer(_ controller: UIViewController) -> Bool {
        controller is MFMailComposeViewController || controller is MFMessageComposeViewController
    }

    private static func topViewController() -> UIViewController? {
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
        let window = windows.first(where: \.isKeyWindow) ?? windows.first
        var controller = window?.rootViewController
        while let presented = controller?.presentedViewController {
            controller = presented
        }
        return controller
    }
}

extension Notification.Name {
    static let freeSplitInviteComposerDidFinish = Notification.Name("freeSplitInviteComposerDidFinish")
}
