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
    static func payloads(
        for contacts: [PickedContact],
        splitName: String,
        joinURL: URL? = nil,
        senderEmail: String? = nil
    ) -> [ComposePayload] {
        let invitees = contacts.filter(needsInvite)
        guard !invitees.isEmpty else { return [] }

        let fromEmail = resolvedSenderEmail(senderEmail)
        var seenPhones = Set<String>()
        var seenEmails = Set<String>()
        var phoneRecipients: [String] = []
        var phoneIDs: [UUID] = []
        var emailRecipients: [String] = []
        var emailIDs: [UUID] = []
        var result: [ComposePayload] = []

        for person in invitees {
            if let email = addressedEmail(person), seenEmails.insert(email.lowercased()).inserted {
                emailRecipients.append(email)
                if let id = person.personID { emailIDs.append(id) }
            }
            if let phone = addressedPhone(person), seenPhones.insert(phone).inserted {
                phoneRecipients.append(phone)
                if let id = person.personID { phoneIDs.append(id) }
            }
        }
        if !phoneRecipients.isEmpty {
            result.append(ComposePayload(
                recipients: phoneRecipients,
                body: groupMessage(splitName: splitName, joinURL: joinURL),
                personIDs: phoneIDs
            ))
        }
        if !emailRecipients.isEmpty {
            result.append(ComposePayload(
                recipients: emailRecipients,
                body: groupMessage(splitName: splitName, joinURL: joinURL, senderEmail: fromEmail),
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
        mailURL(to: [email], subject: subject, body: body)
    }

    static func mailURL(to emails: [String], subject: String, body: String) -> URL? {
        let addresses = emails
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !addresses.isEmpty else { return nil }

        var queryAllowed = CharacterSet.urlQueryAllowed
        queryAllowed.remove(charactersIn: "&+")
        let encodedTo = addresses
            .map { $0.addingPercentEncoding(withAllowedCharacters: Self.mailtoAddressAllowed) ?? $0 }
            .joined(separator: ",")
        let encodedSubject = (subject.isEmpty ? "Join my split on Free Split" : subject)
            .addingPercentEncoding(withAllowedCharacters: queryAllowed) ?? subject
        let encodedBody = body.addingPercentEncoding(withAllowedCharacters: queryAllowed) ?? body
        return URL(string: "mailto:\(encodedTo)?subject=\(encodedSubject)&body=\(encodedBody)")
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
        let body = compactMailBody(payload.body)
        var urls: [URL] = []
        urls.append(contentsOf: gmailComposeURLs(to: payload.recipients, subject: subject, body: body))
        if let mail = mailURL(to: payload.recipients, subject: subject, body: body) {
            urls.append(mail)
        }
        return urls
    }

    static func openMail(_ payload: ComposePayload) async -> Bool {
        let subject = payload.subject.isEmpty ? "Join my split on Free Split" : payload.subject
        guard let url = mailURL(to: payload.recipients, subject: subject, body: compactMailBody(payload.body)) else {
            return false
        }
        return await openURL(url)
    }

    static func openGmail(_ payload: ComposePayload) async -> Bool {
        let subject = payload.subject.isEmpty ? "Join my split on Free Split" : payload.subject
        let body = compactMailBody(payload.body)
        for url in gmailComposeURLs(to: payload.recipients, subject: subject, body: body) {
            if await openURL(url) {
                return true
            }
        }
        return false
    }

    /// Long join URLs make Gmail/mailto open a blank draft. Keep the compose short.
    static func compactMailBody(_ body: String) -> String {
        if body.count <= 280 { return body }
        return String(body.prefix(280))
    }

    static func openMessages(_ payload: ComposePayload) async -> Bool {
        let phones = payload.recipients.joined(separator: ",")
        guard let url = smsURL(to: phones, body: payload.body) else { return false }
        return await openURL(url)
    }

    static func gmailURL(to emails: [String], subject: String, body: String) -> URL? {
        gmailComposeURLs(to: emails, subject: subject, body: body).first
    }

    static func gmailComposeURLs(to emails: [String], subject: String, body: String) -> [URL] {
        let to = emails
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: ",")
        guard !to.isEmpty else { return [] }
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&+")
        let encodedTo = to.addingPercentEncoding(withAllowedCharacters: allowed) ?? to
        let encodedSubject = subject.addingPercentEncoding(withAllowedCharacters: allowed) ?? subject
        let encodedBody = body.addingPercentEncoding(withAllowedCharacters: allowed) ?? body
        return [
            "googlegmail:///co?to=\(encodedTo)&subject=\(encodedSubject)&body=\(encodedBody)",
            "googlegmail://co?to=\(encodedTo)&subject=\(encodedSubject)&body=\(encodedBody)"
        ].compactMap(URL.init(string:))
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
        senderEmail: String? = nil
    ) -> String {
        let group = splitName.trimmingCharacters(in: .whitespacesAndNewlines)
        let split = group.isEmpty ? "a new split" : "'\(group)'"
        var parts = ["I added you to \(split) on Free Split."]
        if let senderEmail, isValidEmail(senderEmail) {
            parts.append("Email: \(senderEmail)")
        }
        if let joinURL, joinURL.host?.contains("apps.apple.com") != true {
            parts.append("Tap this link to open the split \(joinURL.absoluteString) in Free Split.")
        } else {
            parts.append("Need Free Split? \(ShareLink.appStoreURL.absoluteString)")
        }
        return parts.joined(separator: " ")
    }

    @MainActor
    private static func resolvedSenderEmail(_ override: String?) -> String? {
        let raw = (override ?? AuthSession.shared.email)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return isValidEmail(raw) ? raw : nil
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

    @Environment(\.scenePhase) private var scenePhase
    @State private var queue: [ComposePayload] = []
    @State private var current: ComposePayload?
    @State private var isRunning = false
    @State private var isPublishing = false
    @State private var isPresentingComposer = false
    @State private var systemPayload: ComposePayload?
    @State private var pendingEmailReturn: ComposePayload?
    @State private var leftForExternalEmail = false

    func body(content: Content) -> some View {
        content
            .onChange(of: contacts) { _, newValue in
                guard !newValue.isEmpty else { return }
                let pending = newValue
                let split = occasion
                contacts = []
                start(pending, occasion: split)
            }
            .sheet(item: $current, onDismiss: advanceAfterSheet) { payload in
                TextInviteSheet(payload: payload, onDone: finishCurrent)
            }
            .onChange(of: scenePhase) { _, phase in
                guard pendingEmailReturn != nil else { return }
                if phase != .active {
                    leftForExternalEmail = true
                    return
                }
                if leftForExternalEmail {
                    completeExternalEmailIfNeeded()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .freeSplitInviteComposerDidFinish)) { note in
                guard let payload = systemPayload else { return }
                systemPayload = nil
                finishPayload(payload, sent: note.object as? Bool ?? false)
            }
    }

    private func start(_ contacts: [PickedContact], occasion: Occasion?) {
        guard !AppLaunchFlags.isUITesting else {
            if !isRunning { onFinished() }
            return
        }
        guard !isPublishing else { return }
        isPublishing = true
        Task { @MainActor in
            defer { isPublishing = false }
            let joinURL = await FriendInvite.publishedJoinURL(for: occasion, splitName: splitName)
            let payloads = FriendInvite.payloads(for: contacts, splitName: splitName, joinURL: joinURL)
            guard !payloads.isEmpty else {
                if !isRunning { onFinished() }
                return
            }
            for payload in payloads where !alreadyQueued(payload) {
                queue.append(payload)
            }
            guard !isRunning else { return }
            isRunning = true
            presentNext()
        }
    }

    private func alreadyQueued(_ payload: ComposePayload) -> Bool {
        let sameRecipientsAndBody = { (item: ComposePayload) in
            item.recipients == payload.recipients && item.body == payload.body
        }
        if let current, sameRecipientsAndBody(current) { return true }
        return queue.contains(where: sameRecipientsAndBody)
    }

    private func presentNext() {
        guard isRunning, current == nil, !isPresentingComposer else { return }
        guard !queue.isEmpty else {
            isRunning = false
            onFinished()
            return
        }
        let payload = queue.removeFirst()
        if !payload.isPhoneInvite {
            presentExternalEmail(payload)
            return
        }
        if MFMessageComposeViewController.canSendText() {
            presentSystemComposer(payload)
            return
        }
        current = payload
    }

    private func presentExternalEmail(_ payload: ComposePayload) {
        isPresentingComposer = true
        leftForExternalEmail = false
        Task {
            var opened = await FriendInvite.openGmail(payload)
            if !opened {
                opened = await FriendInvite.openMail(payload)
            }
            await MainActor.run {
                guard opened else {
                    finishPayload(payload, sent: false)
                    return
                }
                pendingEmailReturn = payload
            }
        }
    }

    private func completeExternalEmailIfNeeded() {
        guard let payload = pendingEmailReturn else { return }
        pendingEmailReturn = nil
        leftForExternalEmail = false
        finishPayload(payload, sent: true)
    }

    private func presentSystemComposer(_ payload: ComposePayload) {
        isPresentingComposer = true
        systemPayload = payload
        InviteComposerHost.shared.present(payload) { sent in
            NotificationCenter.default.post(name: .freeSplitInviteComposerDidFinish, object: sent)
        }
    }

    private func finishPayload(_ payload: ComposePayload, sent: Bool) {
        if sent {
            payload.personIDs.forEach(onSent)
        }
        isPresentingComposer = false
        current = nil
        let delay: TimeInterval = payload.isPhoneInvite ? 0.8 : 0.4
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            presentNext()
        }
    }

    private func finishCurrent(_ sent: Bool) {
        if sent, let current {
            current.personIDs.forEach(onSent)
        }
        current = nil
    }

    private func advanceAfterSheet() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
            presentNext()
        }
    }
}

struct TextInviteSheet: View {
    let payload: ComposePayload
    var onDone: (Bool) -> Void

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
