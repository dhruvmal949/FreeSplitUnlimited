//
//  ContactActions.swift
//  FreeSplitUnlimited
//

import MessageUI
import SwiftUI
import UIKit

enum ContactActions {
    static func inviteSubject(splitName: String) -> String {
        "You're invited to \"\(splitName)\" on Free Split"
    }

    static func inviteBody(friendName: String, splitName: String) -> String {
        """
        Hi \(friendName),

        I added you to "\(splitName)" in Free Split so we can share expenses together.

        To get the split on your phone without internet:
        1. Install Free Split
        2. Ask me to AirDrop the split (Share Offline), then open the file
        or keep both phones nearby with Free Split open (Bluetooth + Wi‑Fi on)

        Thanks!
        """
    }

    static func mailtoURL(for email: String, subject: String = "", body: String = "") -> URL? {
        let cleaned = FriendContactValidation.normalizedEmail(email)
        guard FriendContactValidation.isValidEmail(cleaned) else { return nil }

        var components = URLComponents()
        components.scheme = "mailto"
        components.path = cleaned

        var items: [URLQueryItem] = []
        if !subject.isEmpty {
            items.append(URLQueryItem(name: "subject", value: subject))
        }
        if !body.isEmpty {
            items.append(URLQueryItem(name: "body", value: body))
        }
        if !items.isEmpty {
            components.queryItems = items
        }
        return components.url
    }

    static func telURL(for phone: String) -> URL? {
        let digits = phone.filter(\.isNumber)
        guard digits.count >= 7 else { return nil }
        return URL(string: "tel:\(digits)")
    }

    static func smsURL(for phone: String, body: String = "") -> URL? {
        let digits = phone.filter(\.isNumber)
        guard digits.count >= 7 else { return nil }
        if body.isEmpty {
            return URL(string: "sms:\(digits)")
        }
        var components = URLComponents()
        components.scheme = "sms"
        components.path = digits
        components.queryItems = [URLQueryItem(name: "body", value: body)]
        return components.url
    }

    static var canComposeMail: Bool {
        MFMailComposeViewController.canSendMail()
    }

    static var canComposeText: Bool {
        MFMessageComposeViewController.canSendText()
    }

    static func open(_ url: URL?, completion: ((Bool) -> Void)? = nil) {
        guard let url else {
            completion?(false)
            return
        }
        UIApplication.shared.open(url, options: [:], completionHandler: completion)
    }

    /// Keeps phone text fields formatted with dashes while typing.
    static func phoneBinding(_ text: Binding<String>) -> Binding<String> {
        Binding(
            get: { FriendContactValidation.formatPhone(text.wrappedValue) },
            set: { newValue in
                text.wrappedValue = FriendContactValidation.formatPhone(newValue)
            }
        )
    }
}

/// In-app Mail compose sheet.
struct MailComposerView: UIViewControllerRepresentable {
    let recipients: [String]
    var subject: String = ""
    var body: String = ""
    var onFinish: (MFMailComposeResult) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onFinish: onFinish)
    }

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let controller = MFMailComposeViewController()
        controller.mailComposeDelegate = context.coordinator
        controller.setToRecipients(recipients)
        if !subject.isEmpty {
            controller.setSubject(subject)
        }
        if !body.isEmpty {
            controller.setMessageBody(body, isHTML: false)
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: MFMailComposeViewController, context: Context) {}

    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        let onFinish: (MFMailComposeResult) -> Void

        init(onFinish: @escaping (MFMailComposeResult) -> Void) {
            self.onFinish = onFinish
        }

        func mailComposeController(
            _ controller: MFMailComposeViewController,
            didFinishWith result: MFMailComposeResult,
            error: Error?
        ) {
            controller.dismiss(animated: true) {
                self.onFinish(result)
            }
        }
    }
}

/// In-app Messages compose sheet.
struct MessageComposerView: UIViewControllerRepresentable {
    let recipients: [String]
    var body: String = ""
    var onFinish: (MessageComposeResult) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onFinish: onFinish)
    }

    func makeUIViewController(context: Context) -> MFMessageComposeViewController {
        let controller = MFMessageComposeViewController()
        controller.messageComposeDelegate = context.coordinator
        controller.recipients = recipients
        controller.body = body
        return controller
    }

    func updateUIViewController(_ uiViewController: MFMessageComposeViewController, context: Context) {}

    final class Coordinator: NSObject, MFMessageComposeViewControllerDelegate {
        let onFinish: (MessageComposeResult) -> Void

        init(onFinish: @escaping (MessageComposeResult) -> Void) {
            self.onFinish = onFinish
        }

        func messageComposeViewController(
            _ controller: MFMessageComposeViewController,
            didFinishWith result: MessageComposeResult
        ) {
            controller.dismiss(animated: true) {
                self.onFinish(result)
            }
        }
    }
}

/// Tappable email / call / text / invite actions for a friend.
struct FriendContactActionsView: View {
    let person: Person
    var splitName: String = "this split"

    @State private var showingMailComposer = false
    @State private var showingMessageComposer = false
    @State private var contactAlert: ContactAlert?

    private let linkBlue = Color(red: 0 / 255, green: 122 / 255, blue: 255 / 255)

    private struct ContactAlert: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }

    private var inviteSubject: String {
        ContactActions.inviteSubject(splitName: splitName)
    }

    private var inviteBody: String {
        ContactActions.inviteBody(friendName: person.name, splitName: splitName)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !person.email.isEmpty {
                HStack(spacing: 10) {
                    Button(action: openEmail) {
                        HStack(spacing: 6) {
                            Image(systemName: "link")
                                .font(.caption.weight(.bold))
                            Text(person.email)
                                .underline()
                                .lineLimit(1)
                        }
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(linkBlue)
                    }
                    .buttonStyle(.plain)

                    Spacer(minLength: 0)

                    Button(action: openEmail) {
                        Label("Email", systemImage: "envelope.fill")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(linkBlue.opacity(0.14))
                            .foregroundStyle(linkBlue)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }

            if !person.phone.isEmpty {
                HStack(spacing: 10) {
                    Button(action: openCall) {
                        HStack(spacing: 6) {
                            Image(systemName: "link")
                                .font(.caption.weight(.bold))
                            Text(person.formattedPhone)
                                .underline()
                        }
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(linkBlue)
                    }
                    .buttonStyle(.plain)

                    Spacer(minLength: 0)

                    Button(action: openCall) {
                        Label("Call", systemImage: "phone.fill")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(AppTheme.teal.opacity(0.15))
                            .foregroundStyle(AppTheme.teal)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)

                    Button(action: openText) {
                        Label("Text", systemImage: "message.fill")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(AppTheme.teal.opacity(0.15))
                            .foregroundStyle(AppTheme.teal)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }

            if !person.email.isEmpty || !person.phone.isEmpty {
                Button(action: sendInvite) {
                    Label("Send Invite", systemImage: "paperplane.fill")
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(AppTheme.teal.opacity(0.16))
                        .foregroundStyle(AppTheme.deepTeal)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .sheet(isPresented: $showingMailComposer) {
            MailComposerView(
                recipients: [FriendContactValidation.normalizedEmail(person.email)],
                subject: inviteSubject,
                body: inviteBody
            ) { result in
                showingMailComposer = false
                handleMailResult(result)
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showingMessageComposer) {
            MessageComposerView(
                recipients: [person.phone.filter(\.isNumber)],
                body: inviteBody
            ) { result in
                showingMessageComposer = false
                handleMessageResult(result)
            }
            .ignoresSafeArea()
        }
        .alert(item: $contactAlert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    private func sendInvite() {
        // Prefer text if available; otherwise email.
        if !person.phone.isEmpty, FriendContactValidation.isValidPhone(person.phone) {
            openText()
        } else {
            openEmail()
        }
    }

    private func openEmail() {
        let cleaned = FriendContactValidation.normalizedEmail(person.email)
        guard FriendContactValidation.isValidEmail(cleaned) else {
            contactAlert = ContactAlert(
                title: "Invalid Email",
                message: "Edit this friend and enter a valid email like name@email.com."
            )
            return
        }

        if ContactActions.canComposeMail {
            showingMailComposer = true
            return
        }

        guard let url = ContactActions.mailtoURL(
            for: cleaned,
            subject: inviteSubject,
            body: inviteBody
        ) else {
            contactAlert = ContactAlert(
                title: "Can't Open Email",
                message: "This email address couldn't be opened."
            )
            return
        }

        ContactActions.open(url) { success in
            if !success {
                contactAlert = ContactAlert(
                    title: "Mail Not Available",
                    message: "No email account is set up. Add one in Settings → Mail, or try on a real iPhone. Simulator usually can't send email."
                )
            }
        }
    }

    private func openCall() {
        guard let url = ContactActions.telURL(for: person.phone) else {
            contactAlert = ContactAlert(
                title: "Invalid Phone",
                message: "Edit this friend and enter a valid phone number."
            )
            return
        }
        ContactActions.open(url) { success in
            if !success {
                contactAlert = ContactAlert(
                    title: "Can't Place Call",
                    message: "Calling isn't available here. Try on a real iPhone."
                )
            }
        }
    }

    private func openText() {
        guard FriendContactValidation.isValidPhone(person.phone) else {
            contactAlert = ContactAlert(
                title: "Invalid Phone",
                message: "Edit this friend and enter a valid phone number."
            )
            return
        }

        if ContactActions.canComposeText {
            showingMessageComposer = true
            return
        }

        guard let url = ContactActions.smsURL(for: person.phone, body: inviteBody) else {
            contactAlert = ContactAlert(
                title: "Can't Open Messages",
                message: "This phone number couldn't be opened."
            )
            return
        }

        ContactActions.open(url) { success in
            if !success {
                contactAlert = ContactAlert(
                    title: "Messages Not Available",
                    message: "Texting isn't available here. Try on a real iPhone — Simulator can't send SMS."
                )
            }
        }
    }

    private func handleMailResult(_ result: MFMailComposeResult) {
        switch result {
        case .sent:
            contactAlert = ContactAlert(
                title: "Email Sent",
                message: "Your invite email to \(person.name) was sent."
            )
        case .failed:
            contactAlert = ContactAlert(
                title: "Email Failed",
                message: "Mail couldn't send. Check your internet connection and Mail account, then try again."
            )
        case .cancelled, .saved:
            break
        @unknown default:
            break
        }
    }

    private func handleMessageResult(_ result: MessageComposeResult) {
        switch result {
        case .sent:
            contactAlert = ContactAlert(
                title: "Text Sent",
                message: "Your invite text to \(person.name) was sent."
            )
        case .failed:
            contactAlert = ContactAlert(
                title: "Text Failed",
                message: "Messages couldn't send. Check your signal/Wi‑Fi and try again on a real iPhone."
            )
        case .cancelled:
            break
        @unknown default:
            break
        }
    }
}
