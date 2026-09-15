//
//  EmailAddressField.swift
//  FreeSplitUnlimited
//

import SwiftUI
import UIKit

struct EmailAddressField: UIViewRepresentable {
    @Binding var text: String
    var isFocused: Bool = false
    var accessibilityIdentifier: String

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeUIView(context: Context) -> UITextField {
        let field = UITextField()
        field.placeholder = "Email address"
        field.keyboardType = .emailAddress
        field.textContentType = .username
        field.autocorrectionType = .no
        field.autocapitalizationType = .none
        field.spellCheckingType = .no
        field.smartQuotesType = .no
        field.smartInsertDeleteType = .no
        if #available(iOS 17.0, *) {
            field.inlinePredictionType = .no
        }
        field.borderStyle = .none
        field.font = .preferredFont(forTextStyle: .body)
        field.delegate = context.coordinator
        field.accessibilityIdentifier = accessibilityIdentifier
        field.addTarget(context.coordinator, action: #selector(Coordinator.editingChanged(_:)), for: .editingChanged)
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return field
    }

    func updateUIView(_ uiView: UITextField, context: Context) {
        context.coordinator.text = $text
        let constrained = constrainedEmailInput(text, previous: text)
        if uiView.text != constrained {
            uiView.text = constrained
        }
        if text != constrained {
            DispatchQueue.main.async {
                self.text = constrained
            }
        }
        if isFocused, !uiView.isFirstResponder {
            DispatchQueue.main.async {
                uiView.becomeFirstResponder()
            }
        }
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var text: Binding<String>

        init(text: Binding<String>) {
            self.text = text
        }

        func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
            let current = textField.text ?? ""
            guard let typedRange = Range(range, in: current) else { return false }
            let next = current.replacingCharacters(in: typedRange, with: string)
            let constrained = constrainedEmailInput(next, previous: current)
            textField.text = constrained
            text.wrappedValue = constrained
            return false
        }

        @objc func editingChanged(_ textField: UITextField) {
            let constrained = constrainedEmailInput(textField.text ?? "", previous: text.wrappedValue)
            if textField.text != constrained {
                textField.text = constrained
            }
            if text.wrappedValue != constrained {
                text.wrappedValue = constrained
            }
        }
    }
}

/// TLDs that count as a finished address. `.co` is left off so `gmail.co` can become `gmail.com`.
private let lockedEmailTLDs: Set<String> = [
    "com", "net", "org", "edu", "gov", "mil", "int", "info", "biz", "app", "dev",
    "xyz", "io", "ai", "me", "us", "uk", "in", "ca", "au", "de", "fr", "es", "it",
    "nl", "jp", "kr", "br", "mx", "nz"
]

func constrainedEmailInput(_ raw: String, previous: String) -> String {
    let sanitized = sanitizedEmailInput(raw)
    if sanitized.count < previous.count {
        return sanitized
    }
    if let locked = longestLockedEmailPrefix(sanitized) {
        if sanitized == locked { return locked }
        if sanitized.hasPrefix(locked) {
            let extra = sanitized.dropFirst(locked.count)
            if extra.first == "." { return sanitized }
            return locked
        }
    }
    if isLockedCompleteEmail(previous), sanitized.count > previous.count {
        return previous
    }
    return sanitized
}

func sanitizedEmailInput(_ raw: String) -> String {
    let localAllowed = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._%+-")
    let domainAllowed = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789.-")
    let filtered = raw.filter { localAllowed.contains($0) || $0 == "@" }
    guard let at = filtered.firstIndex(of: "@") else {
        return String(filtered.filter { localAllowed.contains($0) }.prefix(64))
    }
    let local = String(filtered[..<at].prefix(64))
    let domain = String(filtered[filtered.index(after: at)...].filter { domainAllowed.contains($0) }.prefix(190))
    if local.isEmpty { return local }
    return local + "@" + domain
}

func longestLockedEmailPrefix(_ raw: String) -> String? {
    var candidate = raw
    while candidate.count >= 6 {
        if isLockedCompleteEmail(candidate) { return candidate }
        candidate.removeLast()
    }
    return nil
}

func isLockedCompleteEmail(_ email: String) -> Bool {
    guard isValidEmail(email), let tld = emailTLD(email) else { return false }
    return lockedEmailTLDs.contains(tld)
}

func emailTLD(_ email: String) -> String? {
    guard let at = email.lastIndex(of: "@") else { return nil }
    let domain = email[email.index(after: at)...]
    guard let dot = domain.lastIndex(of: ".") else { return nil }
    let tld = domain[domain.index(after: dot)...]
    return tld.isEmpty ? nil : String(tld).lowercased()
}
