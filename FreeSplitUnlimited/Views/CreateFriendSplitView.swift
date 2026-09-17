//
//  CreateFriendSplitView.swift
//  FreeSplitUnlimited
//

import SwiftData
import SwiftUI

struct CreateFriendSplitView: View {
    var onCreated: (UUID) -> Void = { _ in }

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var friendName = ""
    @State private var friendEmail = ""
    @State private var friendPhone = ""
    @State private var showingFriendPicker = false
    @State private var contactsAllowed = ContactAuthorization.canUseSystemPicker
    @State private var inviteContacts: [PickedContact] = []
    @State private var pendingCreatedID: UUID?
    @State private var createdOccasion: Occasion?

    private var trimmedFriendName: String {
        friendName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canCreate: Bool {
        !trimmedFriendName.isEmpty
            && trimmedFriendName.localizedCaseInsensitiveCompare("Me") != .orderedSame
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Split with")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)

                        TextField("Friend’s name", text: $friendName)
                            .textContentType(.name)
                            .textInputAutocapitalization(.words)
                            .font(.headline)
                            .accessibilityIdentifier("friendNameField")
                            .padding(.horizontal, 12)
                            .padding(.vertical, 12)
                            .background(Color.white.opacity(0.9), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                        Button {
                            Task { await presentFriendPicker() }
                        } label: {
                            Label("Choose from contacts", systemImage: "person.crop.circle.badge.plus")
                                .font(.subheadline.weight(.semibold))
                        }
                        .disabled(showingFriendPicker)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))

                    Text("Start with one friend. Add people later to turn this into a group.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    Button {
                        createSplit()
                    } label: {
                        Text("Create Split")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.teal)
                    .disabled(!canCreate)
                    .accessibilityIdentifier("createSplitButton")
                    .padding(.top, 4)
                    .padding(.bottom, 12)
                }
                .padding(20)
            }
            .scrollDismissesKeyboard(.interactively)
            .freeSplitBackground()
            .navigationTitle("New Split")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .sheet(isPresented: $showingFriendPicker) {
                FriendSearchPicker(
                    contactsAllowed: contactsAllowed,
                    savedFriends: KnownFriendsStore.previouslyUsedFriends(from: modelContext),
                    selectionLimit: 1,
                    onPick: { contacts in
                        apply(contacts)
                    },
                    onContactsAccessGranted: {
                        contactsAllowed = true
                    }
                )
            }
        }
        .tint(AppTheme.teal)
        .friendInvite(
            contacts: $inviteContacts,
            splitName: trimmedFriendName,
            onSent: markInviteSent,
            onFinished: finishCreateIfNeeded
        )
    }

    @MainActor
    private func presentFriendPicker() async {
        guard !showingFriendPicker else { return }
        await ContactAuthorization.requestIfNeeded()
        try? await Task.sleep(for: .milliseconds(250))
        guard !showingFriendPicker else { return }
        contactsAllowed = ContactAuthorization.canUseSystemPicker
        showingFriendPicker = true
    }

    private func apply(_ contacts: [PickedContact]) {
        guard let contact = contacts.first(where: { !$0.isMe }) else { return }
        friendName = contact.name
        friendEmail = contact.email
        friendPhone = contact.phone
    }

    private func createSplit() {
        guard canCreate else { return }

        let occasion = Occasion(
            name: trimmedFriendName,
            groupType: SplitKind.oneToOne
        )
        let friendPerson = Person(
            name: trimmedFriendName,
            email: friendEmail.trimmingCharacters(in: .whitespacesAndNewlines),
            phone: friendPhone.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        occasion.members = [
            Person(name: "Me"),
            friendPerson
        ]
        occasion.assignCurrentOwner()
        modelContext.insert(occasion)
        friendPerson.setContact(email: friendEmail, phone: friendPhone)
        modelContext.persist()
        createdOccasion = occasion
        pendingCreatedID = occasion.id
        let friend = occasion.members.first { FriendPairing.isUsableName($0.name) }
        let inviteContact = PickedContact(
            id: friend?.id.uuidString ?? UUID().uuidString,
            name: trimmedFriendName,
            email: friendEmail.trimmingCharacters(in: .whitespacesAndNewlines),
            phone: friendPhone.trimmingCharacters(in: .whitespacesAndNewlines),
            personID: friend?.id
        )
        if FriendInvite.needsInvite(inviteContact) {
            inviteContacts = [inviteContact]
        } else {
            finishCreateIfNeeded()
        }
    }

    private func finishCreateIfNeeded() {
        guard let id = pendingCreatedID else { return }
        pendingCreatedID = nil
        createdOccasion = nil
        dismiss()
        onCreated(id)
    }

    private func markInviteSent(_ id: UUID) {
        guard let person = createdOccasion?.uniqueMembers.first(where: { $0.id == id }) else { return }
        person.didInvite = true
        createdOccasion?.touch()
        modelContext.persist()
    }
}
