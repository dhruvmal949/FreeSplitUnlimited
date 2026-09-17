//
//  AddFriendDetailsView.swift
//  FreeSplitUnlimited
//

import SwiftUI

struct AddFriendDetailsView: View {
    let initial: PickedContact
    var occupiedPeople: [PickedContact] = []
    var onCancel: () -> Void
    var onNext: (PickedContact) -> Void

    @State private var name: String
    @State private var contact: String
    @FocusState private var focusedField: Field?

    private enum Field {
        case name
        case contact
    }

    init(
        initial: PickedContact,
        occupiedPeople: [PickedContact] = [],
        onCancel: @escaping () -> Void,
        onNext: @escaping (PickedContact) -> Void
    ) {
        self.initial = initial
        self.occupiedPeople = occupiedPeople
        self.onCancel = onCancel
        self.onNext = onNext
        _name = State(initialValue: initial.name)
        let prefill = initial.email.isEmpty ? initial.phone : initial.email
        _contact = State(initialValue: prefill.contains("@") ? prefill : formattedUSPhone(prefill))
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedContact: String {
        contact.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var usesEmail: Bool {
        trimmedContact.contains("@")
    }

    private var parsedEmail: String {
        usesEmail ? trimmedContact : ""
    }

    private var parsedPhone: String {
        usesEmail ? "" : usPhoneDigits(contact)
    }

    private var isContactValid: Bool {
        if usesEmail {
            return isValidEmail(parsedEmail)
        }
        return parsedPhone.count == 10
    }

    private var canContinue: Bool {
        !trimmedName.isEmpty && isContactValid && duplicateMessage == nil
    }

    private var duplicateMessage: String? {
        if !parsedPhone.isEmpty,
           let name = ContactUniqueness.ownerName(usingPhone: parsedPhone, in: occupiedPeople, excludingID: initial.id) {
            return "\(name) already uses this phone number. Enter a different number."
        }
        if !parsedEmail.isEmpty,
           let name = ContactUniqueness.ownerName(usingEmail: parsedEmail, in: occupiedPeople, excludingID: initial.id) {
            return "\(name) already uses this email. Enter a different email."
        }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Name")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                TextField("Name", text: $name)
                    .textContentType(.name)
                    .textInputAutocapitalization(.words)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.secondary.opacity(0.35), lineWidth: 1)
                    }
                    .focused($focusedField, equals: .name)
                    .accessibilityIdentifier("addFriendNameField")
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Phone number or email address")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                TextField("", text: $contact)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textContentType(.username)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.secondary.opacity(0.35), lineWidth: 1)
                    }
                    .focused($focusedField, equals: .contact)
                    .accessibilityIdentifier("addFriendContactField")
                    .onChange(of: contact) { _, newValue in
                        guard !newValue.contains("@") else { return }
                        let formatted = formattedUSPhone(newValue)
                        if formatted != newValue, usPhoneDigits(newValue).count <= 10 {
                            contact = formatted
                        }
                    }
            }

            if let duplicateMessage {
                Text(duplicateMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Spacer()

            Button {
                submit()
            } label: {
                Text("Next")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .tint(canContinue ? AppTheme.teal : Color.gray.opacity(0.35))
            .disabled(!canContinue)
            .accessibilityIdentifier("addFriendNextButton")
        }
        .padding(.horizontal, 22)
        .padding(.top, 20)
        .padding(.bottom, 16)
        .freeSplitBackground()
        .navigationTitle("Add friend")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(action: onCancel) {
                    Image(systemName: "xmark")
                        .font(.body.weight(.semibold))
                }
                .accessibilityLabel("Close")
            }
        }
        .onAppear {
            focusedField = .contact
        }
    }

    private func submit() {
        guard canContinue else { return }
        var next = initial
        next.name = trimmedName
        next.setEnteredContact(
            email: parsedEmail,
            phone: parsedPhone.isEmpty ? "" : formattedUSPhone(parsedPhone)
        )
        KnownFriendsStore.remember([next])
        onNext(next)
    }
}
