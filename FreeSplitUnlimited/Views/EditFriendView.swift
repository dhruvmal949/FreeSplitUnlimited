//
//  EditFriendView.swift
//  FreeSplitUnlimited
//

import MessageUI
import SwiftUI
import SwiftData

struct EditFriendView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let occasion: Occasion
    /// Pass nil to add a new friend; pass an existing person to edit them.
    var person: Person? = nil

    @State private var name = ""
    @State private var email = ""
    @State private var phone = ""
    @State private var showingMailComposer = false
    @State private var showingMessageComposer = false
    @State private var pendingInviteAlert = false
    @State private var infoAlert: InfoAlert?

    private struct InfoAlert: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }

    private var isEditing: Bool { person != nil }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var normalizedEmail: String {
        FriendContactValidation.normalizedEmail(email)
    }

    private var trimmedPhone: String {
        FriendContactValidation.formatPhone(phone)
    }

    private var isNameUnique: Bool {
        !occasion.uniqueMembers.contains {
            $0.id != person?.id
                && $0.name.localizedCaseInsensitiveCompare(trimmedName) == .orderedSame
        }
    }

    private var canSave: Bool {
        !trimmedName.isEmpty
            && isNameUnique
            && FriendContactValidation.isValidEmail(normalizedEmail)
            && FriendContactValidation.isValidPhone(trimmedPhone)
    }

    private var inviteSubject: String {
        ContactActions.inviteSubject(splitName: occasion.name)
    }

    private var inviteBody: String {
        ContactActions.inviteBody(friendName: trimmedName, splitName: occasion.name)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                        .textContentType(.name)
                        .textInputAutocapitalization(.words)

                    TextField("Email", text: $email)
                        .keyboardType(.emailAddress)
                        .textContentType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    TextField("555-123-4567", text: ContactActions.phoneBinding($phone))
                        .keyboardType(.phonePad)
                        .textContentType(.telephoneNumber)
                } header: {
                    Text("Friend details")
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("After saving, you can send an invite email or text. iOS requires you to tap Send.")
                        if !trimmedName.isEmpty && !isNameUnique {
                            Text("Someone with this name is already in this split.")
                                .foregroundStyle(.red)
                        }
                        if !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            && !FriendContactValidation.isValidEmail(normalizedEmail) {
                            Text("Enter a valid email (example: alex@email.com).")
                                .foregroundStyle(.red)
                        }
                        if !trimmedPhone.isEmpty && !FriendContactValidation.isValidPhone(trimmedPhone) {
                            Text("Enter a valid phone number (at least 7 digits).")
                                .foregroundStyle(.red)
                        }
                    }
                }

                Section {
                    Button {
                        save(offerInvite: true)
                    } label: {
                        Text(isEditing ? "Save & Invite" : "Add Friend & Invite")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .disabled(!canSave)
                    .listRowBackground(
                        canSave ? AppTheme.teal : Color.gray.opacity(0.35)
                    )
                    .foregroundStyle(.white)

                    Button {
                        save(offerInvite: false)
                    } label: {
                        Text(isEditing ? "Save Without Invite" : "Add Without Invite")
                            .frame(maxWidth: .infinity)
                    }
                    .disabled(!canSave)
                }
            }
            .freeSplitListStyle()
            .freeSplitBackground()
            .navigationTitle(isEditing ? "Edit Friend" : "Add Friend")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear {
                if let person {
                    name = person.name
                    email = person.email
                    phone = FriendContactValidation.formatPhone(person.phone)
                }
            }
            .confirmationDialog(
                "Send invite to \(trimmedName)?",
                isPresented: $pendingInviteAlert,
                titleVisibility: .visible
            ) {
                if FriendContactValidation.isValidPhone(trimmedPhone) {
                    Button("Text Invite") {
                        if ContactActions.canComposeText {
                            showingMessageComposer = true
                        } else if let url = ContactActions.smsURL(for: trimmedPhone, body: inviteBody) {
                            ContactActions.open(url) { success in
                                if !success {
                                    infoAlert = InfoAlert(
                                        title: "Messages Not Available",
                                        message: "Simulator can't send texts. Try on a real iPhone."
                                    )
                                } else {
                                    dismiss()
                                }
                            }
                        }
                    }
                }
                if FriendContactValidation.isValidEmail(normalizedEmail) {
                    Button("Email Invite") {
                        if ContactActions.canComposeMail {
                            showingMailComposer = true
                        } else if let url = ContactActions.mailtoURL(
                            for: normalizedEmail,
                            subject: inviteSubject,
                            body: inviteBody
                        ) {
                            ContactActions.open(url) { success in
                                if !success {
                                    infoAlert = InfoAlert(
                                        title: "Mail Not Available",
                                        message: "No Mail account is set up, or you're on Simulator. Try a real iPhone with Mail signed in."
                                    )
                                } else {
                                    dismiss()
                                }
                            }
                        }
                    }
                }
                Button("Skip", role: .cancel) { dismiss() }
            } message: {
                Text("Apple does not allow apps to auto-send messages. Choose Text or Email, then tap Send.")
            }
            .sheet(isPresented: $showingMailComposer, onDismiss: { dismiss() }) {
                MailComposerView(
                    recipients: [normalizedEmail],
                    subject: inviteSubject,
                    body: inviteBody
                ) { _ in
                    showingMailComposer = false
                }
                .ignoresSafeArea()
            }
            .sheet(isPresented: $showingMessageComposer, onDismiss: { dismiss() }) {
                MessageComposerView(
                    recipients: [trimmedPhone.filter(\.isNumber)],
                    body: inviteBody
                ) { _ in
                    showingMessageComposer = false
                }
                .ignoresSafeArea()
            }
            .alert(item: $infoAlert) { alert in
                Alert(
                    title: Text(alert.title),
                    message: Text(alert.message),
                    dismissButton: .default(Text("OK")) { dismiss() }
                )
            }
        }
    }

    private func save(offerInvite: Bool) {
        guard canSave else { return }

        if let person {
            person.name = trimmedName
            person.email = normalizedEmail
            person.phone = trimmedPhone
        } else {
            let newPerson = Person(
                name: trimmedName,
                email: normalizedEmail,
                phone: trimmedPhone
            )
            newPerson.occasion = occasion
            modelContext.insert(newPerson)
        }
        occasion.touch()
        modelContext.persist()

        if offerInvite {
            pendingInviteAlert = true
        } else {
            dismiss()
        }
    }
}
