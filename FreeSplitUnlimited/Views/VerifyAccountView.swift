//
//  VerifyAccountView.swift
//  FreeSplitUnlimited
//

import MessageUI
import SwiftUI
import UIKit

struct VerifyAccountView: View {
    var onVerified: () -> Void = {}

    @ObservedObject private var session = AuthSession.shared
    @State private var code = ""
    @State private var errorMessage: String?
    @State private var mailPayload: ComposePayload?
    @State private var messagePayload: ComposePayload?
    @State private var didOfferSend = false

    private var pending: PendingVerification? {
        session.pendingVerification
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Image(systemName: pending?.channel == .phone ? "iphone.gen3" : "envelope.fill")
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(AppTheme.teal)

                Text(pending?.channel == .phone ? "Confirm your phone" : "Confirm your email")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(AppTheme.deepTeal)

                if let pending {
                    Text("We prepared a confirmation code for \(pending.contact). Send it, then enter the 6-digit code here.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                TextField("6-digit code", text: $code)
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
                    .multilineTextAlignment(.center)
                    .font(.title3.weight(.semibold))
                    .padding(14)
                    .background(Color.white.opacity(0.78), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .accessibilityIdentifier("verifyCodeField")

                if AppLaunchFlags.isUITesting {
                    Text(session.confirmationMessage())
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("uiTestingConfirmationCode")
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Button {
                    errorMessage = session.confirmRegistration(code: code)
                    if errorMessage == nil {
                        onVerified()
                    }
                } label: {
                    Text("Confirm")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.teal)
                .disabled(code.trimmingCharacters(in: .whitespacesAndNewlines).count < 6)
                .accessibilityIdentifier("verifyConfirmButton")

                Button("Resend code") {
                    errorMessage = session.resendConfirmationCode()
                    didOfferSend = false
                    sendCode()
                }
                .font(.subheadline.weight(.semibold))
                .accessibilityIdentifier("verifyResendButton")
            }
            .padding(24)
        }
        .scrollDismissesKeyboard(.interactively)
        .freeSplitBackground()
        .keyboardDoneButton()
        .navigationTitle("Confirmation")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            sendCode()
        }
        .sheet(item: $mailPayload) { payload in
            MailComposeView(payload: payload) { sent in
                if !sent {
                    errorMessage = "Mail couldn’t send. Check that Mail is set up, or tap Resend code."
                }
            }
        }
        .sheet(item: $messagePayload) { payload in
            MessageComposeView(payload: payload) { sent in
                if !sent {
                    errorMessage = "Messages couldn’t send. Check that Messages is set up, or tap Resend code."
                }
            }
        }
    }

    private func sendCode() {
        guard !AppLaunchFlags.isUITesting else { return }
        guard !didOfferSend, let pending else { return }
        didOfferSend = true
        let payload = ComposePayload(
            recipient: pending.contact,
            body: session.confirmationMessage()
        )
        switch pending.channel {
        case .email:
            if MFMailComposeViewController.canSendMail() {
                mailPayload = payload
            } else if let url = mailURL(to: pending.contact, body: payload.body) {
                UIApplication.shared.open(url)
            } else {
                errorMessage = "Set up Mail to send the code, then enter it here."
            }
        case .phone:
            if MFMessageComposeViewController.canSendText() {
                messagePayload = payload
            } else if let url = URL(string: "sms:\(pending.contact)&body=\(payload.body.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")") {
                UIApplication.shared.open(url)
            } else {
                errorMessage = "Set up Messages to send the code, then enter it here."
            }
        }
    }

    private func mailURL(to email: String, body: String) -> URL? {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = email
        components.queryItems = [
            URLQueryItem(name: "subject", value: "Free Split confirmation code"),
            URLQueryItem(name: "body", value: body)
        ]
        return components.url
    }
}

struct ComposePayload: Identifiable {
    let id = UUID()
    let recipient: String
    let body: String
}

private struct MailComposeView: UIViewControllerRepresentable {
    let payload: ComposePayload
    var onFinish: (Bool) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let controller = MFMailComposeViewController()
        controller.mailComposeDelegate = context.coordinator
        controller.setToRecipients([payload.recipient])
        controller.setSubject("Free Split confirmation code")
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

private struct MessageComposeView: UIViewControllerRepresentable {
    let payload: ComposePayload
    var onFinish: (Bool) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    func makeUIViewController(context: Context) -> MFMessageComposeViewController {
        let controller = MFMessageComposeViewController()
        controller.messageComposeDelegate = context.coordinator
        controller.recipients = [payload.recipient]
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
