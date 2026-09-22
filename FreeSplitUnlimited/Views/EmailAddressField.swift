//
//  EmailAddressField.swift
//  FreeSplitUnlimited
//

import SwiftUI
import UIKit

struct EmailAddressField: UIViewRepresentable {
    @Binding var text: String
    var isFocused: Bool = false
    var isActive: Bool = true
    var accessibilityIdentifier: String

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeUIView(context: Context) -> UITextField {
        let field = UITextField()
        field.placeholder = "Email address"
        field.keyboardType = .emailAddress
        field.textContentType = .emailAddress
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
        field.setContentHuggingPriority(.required, for: .vertical)
        field.setContentCompressionResistancePriority(.required, for: .vertical)
        field.inputAssistantItem.leadingBarButtonGroups = []
        field.inputAssistantItem.trailingBarButtonGroups = []
        return field
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextField, context: Context) -> CGSize? {
        let width = proposal.width ?? uiView.intrinsicContentSize.width
        return CGSize(width: width, height: uiView.intrinsicContentSize.height)
    }

    func updateUIView(_ uiView: UITextField, context: Context) {
        context.coordinator.text = $text
        if !uiView.isFirstResponder {
            let constrained = constrainedEmailInput(text, previous: text)
            if uiView.text != constrained {
                uiView.text = constrained
            }
            if text != constrained {
                DispatchQueue.main.async {
                    self.text = constrained
                }
            }
        }
        uiView.isUserInteractionEnabled = isActive
        let nextContent: UITextContentType? = isActive ? .emailAddress : nil
        if uiView.textContentType != nextContent {
            uiView.textContentType = nextContent
        }
        if uiView.keyboardType != .emailAddress {
            uiView.keyboardType = .emailAddress
        }
        syncFocus(uiView, coordinator: context.coordinator)
    }

    private func syncFocus(_ uiView: UITextField, coordinator: Coordinator) {
        coordinator.wantsFocus = isFocused && isActive
        coordinator.isActive = isActive
        let shouldResign = !isActive && uiView.isFirstResponder
        let shouldFocus = coordinator.wantsFocus && !uiView.isFirstResponder
        guard shouldResign || shouldFocus else { return }
        DispatchQueue.main.async {
            if !coordinator.isActive {
                if uiView.isFirstResponder {
                    uiView.resignFirstResponder()
                }
                return
            }
            if coordinator.wantsFocus, !uiView.isFirstResponder {
                uiView.becomeFirstResponder()
            }
        }
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var text: Binding<String>
        var wantsFocus = false
        var isActive = true
        private var isApplyingText = false

        init(text: Binding<String>) {
            self.text = text
        }

        func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
            let current = textField.text ?? ""
            let change = resolvedEmailFieldChange(current: current, replacement: string, range: range)
            apply(change.text, to: textField, cursorOffset: change.cursorUTF16Offset)
            return false
        }

        @objc func editingChanged(_ textField: UITextField) {
            guard !isApplyingText else { return }
            let current = textField.text ?? ""
            let constrained = constrainedEmailInput(current, previous: text.wrappedValue)
            let cursor = textField.selectedTextRange.flatMap { range in
                textField.offset(from: textField.beginningOfDocument, to: range.start)
            } ?? (constrained as NSString).length
            apply(constrained, to: textField, cursorOffset: cursor)
        }

        private func apply(_ newText: String, to textField: UITextField, cursorOffset: Int) {
            isApplyingText = true
            if textField.text != newText {
                textField.text = newText
            }
            let clamped = max(0, min(cursorOffset, (newText as NSString).length))
            if let position = textField.position(from: textField.beginningOfDocument, offset: clamped) {
                textField.selectedTextRange = textField.textRange(from: position, to: position)
            }
            if text.wrappedValue != newText {
                text.wrappedValue = newText
            }
            isApplyingText = false
        }
    }
}

/// TLDs that count as a finished address. `.co` is left off so `gmail.co` can become `gmail.com`.
private let lockedEmailTLDs: Set<String> = [
    "com", "net", "org", "edu", "gov", "mil", "int", "info", "biz", "app", "dev",
    "xyz", "io", "ai", "me", "us", "uk", "in", "ca", "au", "de", "fr", "es", "it",
    "nl", "jp", "kr", "br", "mx", "nz"
]

func resolvedEmailFieldChange(current: String, replacement: String, range: NSRange) -> (text: String, cursorUTF16Offset: Int) {
    let trimmedReplacement = replacement.trimmingCharacters(in: .whitespacesAndNewlines)
    let replaceAll = isValidEmail(trimmedReplacement)
    let nextRaw: String
    if replaceAll {
        nextRaw = trimmedReplacement
    } else {
        nextRaw = (current as NSString).replacingCharacters(in: range, with: replacement)
    }
    let constrained = constrainedEmailInput(nextRaw, previous: current)
    let cursor: Int
    if replaceAll {
        cursor = (constrained as NSString).length
    } else if replacement.isEmpty {
        cursor = min(range.location, (constrained as NSString).length)
    } else {
        cursor = min(range.location + (replacement as NSString).length, (constrained as NSString).length)
    }
    return (constrained, cursor)
}

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
