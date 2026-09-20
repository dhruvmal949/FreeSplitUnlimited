//
//  AuthContactEntry.swift
//  FreeSplitUnlimited
//

import SwiftUI

enum ContactKind: String, CaseIterable, Identifiable {
    case email = "Email"
    case phone = "Phone"
    var id: String { rawValue }
}

struct ContactEntryState {
    var kind: ContactKind = .email
    var email = ""
    var phone = ""

    var trimmedEmail: String {
        email.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var phoneDigits: String {
        usPhoneDigits(phone)
    }

    var isValid: Bool {
        kind == .email ? isValidEmail(trimmedEmail) : phoneDigits.count == 10
    }

    var selectedValue: String {
        kind == .phone ? phoneDigits : trimmedEmail
    }

    var hint: String? {
        switch kind {
        case .email:
            guard !trimmedEmail.isEmpty, !isValidEmail(trimmedEmail) else { return nil }
            return "Enter a valid email address."
        case .phone:
            guard !phoneDigits.isEmpty, phoneDigits.count != 10 else { return nil }
            return "Enter a 10-digit phone number."
        }
    }

    mutating func applyRemembered(_ raw: String, switchingKind: Bool = true) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if trimmed.contains("@") {
            email = trimmed
            if switchingKind { kind = .email }
        } else {
            phone = formattedUSPhone(trimmed)
            if switchingKind { kind = .phone }
        }
    }

    mutating func clearCurrent() {
        if kind == .phone {
            phone = ""
        } else {
            email = ""
        }
    }
}

struct EmailPhonePicker: View {
    @Binding var entry: ContactEntryState
    var fieldIdentifier: String
    var pickerIdentifier: String
    var hintIdentifier: String? = nil
    var usesFilledChrome: Bool = true
    var onKindChange: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Email or phone", selection: $entry.kind) {
                ForEach(ContactKind.allCases) { kind in
                    Text(kind.rawValue).tag(kind)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier(pickerIdentifier)

            contactField

            if let hint = entry.hint {
                Text(hint)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier(hintIdentifier ?? "\(fieldIdentifier)Hint")
            }
        }
        .onChange(of: entry.kind) { _, _ in
            onKindChange?()
        }
    }

    @ViewBuilder
    private var contactField: some View {
        let field = Group {
            if entry.kind == .email {
                EmailAddressField(
                    text: $entry.email,
                    isActive: true,
                    accessibilityIdentifier: fieldIdentifier
                )
            } else {
                USPhoneNumberField(
                    text: $entry.phone,
                    isActive: true,
                    accessibilityIdentifier: fieldIdentifier
                )
            }
        }
        .frame(maxWidth: .infinity, minHeight: 24, maxHeight: 24, alignment: .leading)

        if usesFilledChrome {
            field.authInputChrome()
        } else {
            field
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.secondary.opacity(0.35), lineWidth: 1)
                }
        }
    }
}

struct PasswordPairHint: View {
    var password: String
    var confirmPassword: String
    var identifier: String? = nil

    var body: some View {
        if password.isEmpty, confirmPassword.isEmpty {
            Text("Use at least 6 characters.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else if let message = errorMessage {
            Text(message)
                .font(.footnote)
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier(identifier ?? "passwordHint")
        }
    }

    private var errorMessage: String? {
        if !password.isEmpty, password.count < 6 {
            return "Password needs at least 6 characters."
        }
        if !confirmPassword.isEmpty, password != confirmPassword {
            return "Passwords don't match."
        }
        return nil
    }
}

extension View {
    func authInputChrome() -> some View {
        padding(14)
            .background(Color.white.opacity(0.78), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

func passwordsMatch(_ password: String, _ confirmPassword: String) -> Bool {
    password.count >= 6 && password == confirmPassword
}

func isValidEmail(_ email: String) -> Bool {
    let emailRegex = /[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/
    return email.trimmingCharacters(in: .whitespacesAndNewlines).wholeMatch(of: emailRegex) != nil
}

func looksLikePhoneTyping(_ raw: String) -> Bool {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return false }
    if trimmed.contains("@") { return false }
    if trimmed.contains(where: \.isLetter) { return false }
    return trimmed.contains(where: \.isNumber)
}

func formattedUSPhone(_ raw: String) -> String {
    let digits = usPhoneDigits(raw)
    guard !digits.isEmpty else { return "" }
    let area = String(digits.prefix(3))
    if digits.count <= 3 {
        return "(\(area)"
    }
    let prefix = String(digits.dropFirst(3).prefix(3))
    if digits.count <= 6 {
        return "(\(area)) \(prefix)"
    }
    let line = String(digits.dropFirst(6))
    return "(\(area)) \(prefix)-\(line)"
}

func usPhoneDigits(_ raw: String) -> String {
    var digits = raw.filter(\.isNumber)
    if digits.count == 11, digits.hasPrefix("1") {
        digits.removeFirst()
    }
    return String(digits.prefix(10))
}
