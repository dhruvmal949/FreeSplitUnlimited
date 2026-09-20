//
//  FriendInvite.swift
//  FreeSplitUnlimited
//

import Foundation
import MessageUI
import SwiftData
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
    static func payloads(for contacts: [PickedContact], splitName: String, joinURL: URL? = nil) -> [ComposePayload] {
        let invitees = contacts.filter(needsInvite)
        guard !invitees.isEmpty else { return [] }

        var seenPhones = Set<String>()
        var seenEmails = Set<String>()
        var phoneRecipients: [String] = []
        var phoneIDs: [UUID] = []
        let textBody = groupMessage(splitName: splitName, joinURL: joinURL)
        var result: [ComposePayload] = []

        for person in invitees {
            if let phone = addressedPhone(person), seenPhones.insert(phone).inserted {
                phoneRecipients.append(phone)
                if let id = person.personID { phoneIDs.append(id) }
            }
        }
        if !phoneRecipients.isEmpty {
            result.append(ComposePayload(
                recipients: phoneRecipients,
                body: textBody,
                personIDs: phoneIDs
            ))
        }
        for person in invitees {
            if let email = addressedEmail(person), seenEmails.insert(email.lowercased()).inserted {
                result.append(ComposePayload(
                    recipients: [email],
                    body: groupMessage(splitName: splitName, joinURL: joinURL, emails: [email]),
                    subject: "Join my split on Free Split",
                    personIDs: person.personID.map { [$0] } ?? []
                ))
            }
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
        mailURL(to: [email], subject: subject, body: body)
    }

    static func mailURL(to emails: [String], subject: String, body: String) -> URL? {
        let addresses = emails
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !addresses.isEmpty else { return nil }

        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: "subject", value: subject.isEmpty ? "Join my split on Free Split" : subject),
            URLQueryItem(name: "body", value: body)
        ]
        let encodedAddresses = addresses
            .map { $0.addingPercentEncoding(withAllowedCharacters: Self.mailtoAddressAllowed) ?? $0 }
            .joined(separator: ",")
        let query = components.percentEncodedQuery.map { "?\($0)" } ?? ""
        return URL(string: "mailto:\(encodedAddresses)\(query)")
    }

    private static let mailtoAddressAllowed: CharacterSet = {
        var allowed = CharacterSet.urlPathAllowed
        allowed.insert(charactersIn: "@+")
        allowed.remove(charactersIn: "?&")
        return allowed
    }()

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
        Task {
            _ = await openEmailFallback(payload)
        }
    }

    static func openEmailFallback(_ payload: ComposePayload) async -> Bool {
        for url in emailFallbackURLs(for: payload) {
            if await openURL(url) {
                return true
            }
        }
        return false
    }

    static func emailFallbackURLs(for payload: ComposePayload) -> [URL] {
        let subject = payload.subject.isEmpty ? "Join my split on Free Split" : payload.subject
        var urls: [URL] = []
        if let mail = mailURL(to: payload.recipients, subject: subject, body: payload.body) {
            urls.append(mail)
        }
        if let gmail = gmailURL(to: payload.recipients, subject: subject, body: payload.body) {
            urls.append(gmail)
        }
        return urls
    }

    static func openMail(_ payload: ComposePayload) async -> Bool {
        let subject = payload.subject.isEmpty ? "Join my split on Free Split" : payload.subject
        guard let url = mailURL(to: payload.recipients, subject: subject, body: payload.body) else {
            return false
        }
        return await openURL(url)
    }

    static func openGmail(_ payload: ComposePayload) async -> Bool {
        let subject = payload.subject.isEmpty ? "Join my split on Free Split" : payload.subject
        guard let url = gmailURL(to: payload.recipients, subject: subject, body: payload.body) else {
            return false
        }
        return await openURL(url)
    }

    static func openMessages(_ payload: ComposePayload) async -> Bool {
        let phones = payload.recipients.joined(separator: ",")
        guard let url = smsURL(to: phones, body: payload.body) else { return false }
        return await openURL(url)
    }

    @MainActor
    static var prefersGmailApp: Bool {
        AuthSession.shared.provider == .google
    }

    static func gmailURL(to emails: [String], subject: String, body: String) -> URL? {
        let to = emails.joined(separator: ",")
        guard !to.isEmpty else { return nil }
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&")
        let encodedTo = to.addingPercentEncoding(withAllowedCharacters: allowed) ?? to
        let encodedSubject = subject.addingPercentEncoding(withAllowedCharacters: allowed) ?? subject
        let encodedBody = body.addingPercentEncoding(withAllowedCharacters: allowed) ?? body
        return URL(string: "googlegmail://co?to=\(encodedTo)&subject=\(encodedSubject)&body=\(encodedBody)")
    }

    private static func openURL(_ url: URL) async -> Bool {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                UIApplication.shared.open(url, options: [:]) { success in
                    continuation.resume(returning: success)
                }
            }
        }
    }

    static func joinURL(for occasion: Occasion?, splitName: String) -> URL? {
        ShareLink.appStoreURL
    }

    /// Short https page other apps can tap. Never put the huge `freesplit://i/…` token in Mail/Gmail.
    static func publishedJoinURL(for occasion: Occasion?, splitName: String) async -> URL? {
        guard let occasion else { return ShareLink.appStoreURL }
        let name = splitName.trimmingCharacters(in: .whitespacesAndNewlines)
        let groupName = name.isEmpty ? occasion.name : name
        if let package = try? SplitShare.makePackage(from: occasion),
           let published = try? await ShareLink.publish(package, groupName: groupName) {
            return published
        }
        return ShareLink.appStoreURL
    }

    private static func groupMessage(
        splitName: String,
        joinURL: URL? = nil,
        emails: [String] = []
    ) -> String {
        let group = splitName.trimmingCharacters(in: .whitespacesAndNewlines)
        let split = group.isEmpty ? "a new split" : "'\(group)'"
        var lines = ["I added you to \(split) on Free Split."]
        if !emails.isEmpty {
            lines.append("Email: \(emails.joined(separator: ", "))")
        }
        if let joinURL, joinURL.host?.contains("apps.apple.com") != true {
            lines.append("Tap this link to open the split. If Free Split is on your phone it opens the app; if not, get it from the App Store:")
            lines.append(joinURL.absoluteString)
        } else {
            lines.append("Need Free Split? \(ShareLink.appStoreURL.absoluteString)")
        }
        return lines.joined(separator: "\n")
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
        guard contact.isMe || FriendPairing.isPlaceholderSelf(contact.name) else { return false }
        return true
    }
}

struct FriendInvitePresenter: ViewModifier {
    @Binding var contacts: [PickedContact]
    var splitName: String
    var occasion: Occasion? = nil
    var onSent: (UUID) -> Void = { _ in }
    var onFinished: () -> Void = {}

    @State private var queue: [ComposePayload] = []
    @State private var current: ComposePayload?
    @State private var isRunning = false

    func body(content: Content) -> some View {
        content
            .onChange(of: contacts) { _, newValue in
                guard !newValue.isEmpty else { return }
                let pending = newValue
                let split = occasion
                contacts = []
                start(pending, occasion: split)
            }
            .sheet(item: $current, onDismiss: presentNext) { payload in
                inviteSheet(for: payload)
            }
    }

    @ViewBuilder
    private func inviteSheet(for payload: ComposePayload) -> some View {
        if payload.isPhoneInvite {
            if MFMessageComposeViewController.canSendText() {
                MessageComposeView(payload: payload, onFinish: finishCurrent)
                    .ignoresSafeArea()
            } else {
                TextInviteSheet(payload: payload, onDone: finishCurrent)
            }
        } else {
            EmailInviteSheet(payload: payload, onDone: finishCurrent)
        }
    }

    private func start(_ contacts: [PickedContact], occasion: Occasion?) {
        guard !AppLaunchFlags.isUITesting else {
            if !isRunning { onFinished() }
            return
        }
        Task { @MainActor in
            let joinURL = await FriendInvite.publishedJoinURL(for: occasion, splitName: splitName)
            let payloads = FriendInvite.payloads(for: contacts, splitName: splitName, joinURL: joinURL)
            guard !payloads.isEmpty else {
                if !isRunning { onFinished() }
                return
            }
            queue.append(contentsOf: payloads)
            guard !isRunning else { return }
            isRunning = true
            presentNext()
        }
    }

    private func presentNext() {
        guard isRunning, current == nil else { return }
        guard !queue.isEmpty else {
            isRunning = false
            onFinished()
            return
        }
        current = queue.removeFirst()
    }

    private func finishCurrent(_ sent: Bool) {
        if sent, let current {
            current.personIDs.forEach(onSent)
        }
        current = nil
    }
}

struct EmailInviteSheet: View {
    let payload: ComposePayload
    var onDone: (Bool) -> Void

    @Environment(\.scenePhase) private var scenePhase
    @State private var openedComposer = false
    @State private var didFinish = false

    private var gmailFirst: Bool { FriendInvite.prefersGmailApp }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Open Mail or Gmail, tap Send, then come back so the next person can be invited.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                labeled("To", payload.recipients.joined(separator: ", "))
                labeled("Subject", payload.subject.isEmpty ? "Join my split on Free Split" : payload.subject)

                Text(payload.body)
                    .font(.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(Color.white.opacity(0.78), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                if gmailFirst {
                    gmailButton
                    mailButton
                } else {
                    mailButton
                    gmailButton
                }

                if openedComposer {
                    Button("I sent it") { finish(true) }
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("sentEmailInviteButton")
                }

                Spacer()
            }
            .padding(22)
            .freeSplitBackground()
            .navigationTitle("Email invite")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Skip") { finish(false) }
                }
            }
        }
        .presentationDetents([.large])
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, openedComposer {
                finish(true)
            }
        }
    }

    private var mailButton: some View {
        inviteOpenButton("Open Mail", identifier: "openMailInviteButton") {
            await FriendInvite.openMail(payload)
        }
    }

    private var gmailButton: some View {
        inviteOpenButton("Open Gmail", identifier: "openGmailInviteButton") {
            await FriendInvite.openGmail(payload)
        }
    }

    private func inviteOpenButton(_ title: String, identifier: String, open: @escaping () async -> Bool) -> some View {
        Button {
            Task {
                if await open() {
                    openedComposer = true
                }
            }
        } label: {
            Text(title)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
        }
        .buttonStyle(.borderedProminent)
        .tint(AppTheme.teal)
        .accessibilityIdentifier(identifier)
    }

    private func finish(_ sent: Bool) {
        guard !didFinish else { return }
        didFinish = true
        onDone(sent)
    }

    private func labeled(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.body.weight(.semibold))
        }
    }
}

struct TextInviteSheet: View {
    let payload: ComposePayload
    var onDone: (Bool) -> Void

    @Environment(\.scenePhase) private var scenePhase
    @State private var openedComposer = false
    @State private var didFinish = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Open Messages, tap Send, then come back so the next person can be invited.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                labeled("To", payload.recipients.joined(separator: ", "))

                Text(payload.body)
                    .font(.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(Color.white.opacity(0.78), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                Button {
                    Task {
                        if await FriendInvite.openMessages(payload) {
                            openedComposer = true
                        }
                    }
                } label: {
                    Text("Open Messages")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.teal)
                .accessibilityIdentifier("openMessagesInviteButton")

                if openedComposer {
                    Button("I sent it") { finish(true) }
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("sentTextInviteButton")
                }

                Spacer()
            }
            .padding(22)
            .freeSplitBackground()
            .navigationTitle("Text invite")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Skip") { finish(false) }
                }
            }
        }
        .presentationDetents([.large])
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, openedComposer {
                finish(true)
            }
        }
    }

    private func finish(_ sent: Bool) {
        guard !didFinish else { return }
        didFinish = true
        onDone(sent)
    }

    private func labeled(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.body.weight(.semibold))
        }
    }
}

extension View {
    func friendInvite(
        contacts: Binding<[PickedContact]>,
        splitName: String,
        occasion: Occasion? = nil,
        onSent: @escaping (UUID) -> Void = { _ in },
        onFinished: @escaping () -> Void = {}
    ) -> some View {
        modifier(FriendInvitePresenter(
            contacts: contacts,
            splitName: splitName,
            occasion: occasion,
            onSent: onSent,
            onFinished: onFinished
        ))
    }
}
