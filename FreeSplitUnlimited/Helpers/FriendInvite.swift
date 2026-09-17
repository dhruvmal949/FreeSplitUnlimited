//
//  FriendInvite.swift
//  FreeSplitUnlimited
//

import Foundation
import MessageUI
import SwiftUI
import UIKit

enum FriendInvite {
    @MainActor
    static func needsInvite(_ contact: PickedContact) -> Bool {
        guard !contact.isMe else { return false }
        guard FriendPairing.isUsableName(contact.name) else { return false }
        guard !contact.didInvite else { return false }
        if isCurrentUser(contact) { return false }
        return addressedPhone(contact) != nil || addressedEmail(contact) != nil
    }

    @MainActor
    static func payloads(for contacts: [PickedContact], splitName: String) -> [ComposePayload] {
        let invitees = contacts.filter(needsInvite)
        guard !invitees.isEmpty else { return [] }

        var phoneRecipients: [String] = []
        var phoneIDs: [UUID] = []
        var emailRecipients: [String] = []
        var emailIDs: [UUID] = []
        var seenPhones = Set<String>()
        var seenEmails = Set<String>()

        for person in invitees {
            if let phone = addressedPhone(person), seenPhones.insert(phone).inserted {
                phoneRecipients.append(phone)
                if let id = person.personID { phoneIDs.append(id) }
            } else if let email = addressedEmail(person), seenEmails.insert(email.lowercased()).inserted {
                emailRecipients.append(email)
                if let id = person.personID { emailIDs.append(id) }
            }
        }

        let body = groupMessage(splitName: splitName)
        var result: [ComposePayload] = []
        if !phoneRecipients.isEmpty {
            result.append(ComposePayload(recipients: phoneRecipients, body: body, personIDs: phoneIDs))
        }
        if !emailRecipients.isEmpty {
            result.append(ComposePayload(
                recipients: emailRecipients,
                body: body,
                subject: "Join my split on Free Split",
                personIDs: emailIDs
            ))
        }
        return result
    }

    static func smsURL(to phone: String, body: String) -> URL? {
        var components = URLComponents()
        components.scheme = "sms"
        components.path = phone
        components.queryItems = [URLQueryItem(name: "body", value: body)]
        return components.url
    }

    static func mailURL(to email: String, subject: String, body: String) -> URL? {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = email
        components.queryItems = [
            URLQueryItem(name: "subject", value: subject.isEmpty ? "Join my split on Free Split" : subject),
            URLQueryItem(name: "body", value: body)
        ]
        return components.url
    }

    static func canPresentComposer(_ payload: ComposePayload) -> Bool {
        if payload.isPhoneInvite {
            return MFMessageComposeViewController.canSendText()
        }
        return MFMailComposeViewController.canSendMail()
    }

    static func openFallback(_ payload: ComposePayload) {
        if payload.isPhoneInvite {
            let phones = payload.recipients
            if let url = smsURL(to: phones.joined(separator: ","), body: payload.body) {
                UIApplication.shared.open(url)
            }
            return
        }
        if let email = payload.recipients.first,
           let url = mailURL(to: email, subject: payload.subject, body: payload.body) {
            UIApplication.shared.open(url)
        }
    }

    private static func groupMessage(splitName: String) -> String {
        let group = splitName.trimmingCharacters(in: .whitespacesAndNewlines)
        let split = group.isEmpty ? "a new split" : "'\(group)'"
        return [
            "I added you to \(split) on Free Split.",
            "Create a Free Split account to see this split.",
            ShareLink.appStoreURL.absoluteString
        ].joined(separator: "\n")
    }

    private static func addressedPhone(_ contact: PickedContact) -> String? {
        let digits = usPhoneDigits(contact.phone)
        guard digits.count == 10 else { return nil }
        return "+1\(digits)"
    }

    private static func addressedEmail(_ contact: PickedContact) -> String? {
        let email = contact.email.trimmingCharacters(in: .whitespacesAndNewlines)
        return isValidEmail(email) ? email : nil
    }

    @MainActor
    private static func isCurrentUser(_ contact: PickedContact) -> Bool {
        let sessionEmail = AuthSession.shared.email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let contactEmail = contact.email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !sessionEmail.isEmpty, sessionEmail == contactEmail {
            return true
        }
        return false
    }
}

/// Presents the system Messages/Mail composers on the top view controller.
/// SwiftUI `.sheet` wrapping `MFMessageComposeViewController` often fails when the
/// friend picker is still dismissing, so texts never appear.
@MainActor
final class FriendInviteComposer: NSObject, ObservableObject, MFMessageComposeViewControllerDelegate, MFMailComposeViewControllerDelegate {
    private var queue: [ComposePayload] = []
    private var active: ComposePayload?
    private var isRunning = false
    private var onSent: (UUID) -> Void = { _ in }
    private var onFinished: () -> Void = {}

    func enqueue(
        _ contacts: [PickedContact],
        splitName: String,
        onSent: @escaping (UUID) -> Void,
        onFinished: @escaping () -> Void
    ) {
        self.onSent = onSent
        self.onFinished = onFinished
        guard !AppLaunchFlags.isUITesting else {
            if !isRunning { onFinished() }
            return
        }
        let payloads = FriendInvite.payloads(for: contacts, splitName: splitName)
        guard !payloads.isEmpty else {
            if !isRunning { onFinished() }
            return
        }
        queue.append(contentsOf: payloads)
        guard !isRunning else { return }
        isRunning = true
        presentNextAfterPickerSettles()
    }

    private func presentNextAfterPickerSettles() {
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(550))
            self?.presentNext()
        }
    }

    private func presentNext() {
        guard isRunning else { return }
        guard active == nil else { return }
        guard !queue.isEmpty else {
            isRunning = false
            onFinished()
            return
        }
        let next = queue.removeFirst()
        if FriendInvite.canPresentComposer(next), let presenter = topViewController() {
            active = next
            presenter.present(viewController(for: next), animated: true)
            return
        }
        FriendInvite.openFallback(next)
        presentNextAfterPickerSettles()
    }

    private func viewController(for payload: ComposePayload) -> UIViewController {
        if payload.isPhoneInvite {
            let controller = MFMessageComposeViewController()
            controller.messageComposeDelegate = self
            controller.recipients = payload.recipients
            controller.body = payload.body
            return controller
        }
        let controller = MFMailComposeViewController()
        controller.mailComposeDelegate = self
        controller.setToRecipients(payload.recipients)
        controller.setSubject(payload.subject.isEmpty ? "Join my split on Free Split" : payload.subject)
        controller.setMessageBody(payload.body, isHTML: false)
        return controller
    }

    private func finishActive(sent: Bool, controller: UIViewController) {
        let payload = active
        active = nil
        if sent, let payload {
            payload.personIDs.forEach(onSent)
        }
        controller.dismiss(animated: true) { [weak self] in
            self?.presentNextAfterPickerSettles()
        }
    }

    private func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes.flatMap(\.windows).first(where: \.isKeyWindow) ?? scenes.first?.windows.first
        var controller = window?.rootViewController
        while let presented = controller?.presentedViewController {
            controller = presented
        }
        return controller
    }

    nonisolated func messageComposeViewController(
        _ controller: MFMessageComposeViewController,
        didFinishWith result: MessageComposeResult
    ) {
        Task { @MainActor in
            finishActive(sent: result == .sent, controller: controller)
        }
    }

    nonisolated func mailComposeController(
        _ controller: MFMailComposeViewController,
        didFinishWith result: MFMailComposeResult,
        error: Error?
    ) {
        Task { @MainActor in
            finishActive(sent: result == .sent, controller: controller)
        }
    }
}

struct FriendInvitePresenter: ViewModifier {
    @Binding var contacts: [PickedContact]
    var splitName: String
    var onSent: (UUID) -> Void = { _ in }
    var onFinished: () -> Void = {}

    @StateObject private var composer = FriendInviteComposer()

    func body(content: Content) -> some View {
        content
            .onChange(of: contacts) { _, newValue in
                guard !newValue.isEmpty else { return }
                let pending = newValue
                DispatchQueue.main.async {
                    contacts = []
                    composer.enqueue(
                        pending,
                        splitName: splitName,
                        onSent: onSent,
                        onFinished: onFinished
                    )
                }
            }
    }
}

extension View {
    func friendInvite(
        contacts: Binding<[PickedContact]>,
        splitName: String,
        onSent: @escaping (UUID) -> Void = { _ in },
        onFinished: @escaping () -> Void = {}
    ) -> some View {
        modifier(FriendInvitePresenter(
            contacts: contacts,
            splitName: splitName,
            onSent: onSent,
            onFinished: onFinished
        ))
    }
}
