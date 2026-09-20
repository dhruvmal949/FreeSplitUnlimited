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
    @State private var contact: ContactEntryState
    @FocusState private var nameFocused: Bool

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
        var entry = ContactEntryState()
        if !initial.email.isEmpty {
            entry.kind = .email
            entry.email = initial.email
        } else if !initial.phone.isEmpty {
            entry.kind = .phone
            entry.phone = formattedUSPhone(initial.phone)
        } else {
            entry.kind = .email
        }
        _contact = State(initialValue: entry)
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var parsedEmail: String {
        contact.kind == .email ? contact.trimmedEmail : ""
    }

    private var parsedPhone: String {
        contact.kind == .phone ? contact.phoneDigits : ""
    }

    private var canContinue: Bool {
        !trimmedName.isEmpty && contact.isValid && duplicateMessage == nil
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
                    .submitLabel(.done)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.secondary.opacity(0.35), lineWidth: 1)
                    }
                    .focused($nameFocused)
                    .onSubmit { nameFocused = false }
                    .accessibilityIdentifier("addFriendNameField")
            }

            EmailPhonePicker(
                entry: $contact,
                fieldIdentifier: "addFriendContactField",
                pickerIdentifier: "addFriendContactKind",
                hintIdentifier: "addFriendContactHint",
                usesFilledChrome: false
            )

            if let duplicateMessage {
                Text(duplicateMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button {
                nameFocused = false
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

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 22)
        .padding(.top, 20)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .freeSplitBackground()
        .ignoresSafeArea(.keyboard)
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
