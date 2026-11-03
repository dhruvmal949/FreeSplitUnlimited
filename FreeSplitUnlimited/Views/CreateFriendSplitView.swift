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
    @Query(sort: \Occasion.createdAt, order: .reverse)
    private var allOccasions: [Occasion]

    @State private var friendName = ""
    @State private var friendEmail = ""
    @State private var friendPhone = ""
    @State private var showingFriendPicker = false
    @State private var contactsAllowed = ContactAuthorization.canUseSystemPicker
    @State private var inviteContacts: [PickedContact] = []
    @State private var pendingCreatedID: UUID?
    @State private var createdOccasion: Occasion?
    @State private var isCreating = false

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
                        if !trimmedFriendName.isEmpty {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Image(systemName: "person.crop.circle")
                                        .foregroundStyle(AppTheme.teal)
                                    Text(trimmedFriendName)
                                        .accessibilityIdentifier("friendNameField")
                                    Spacer()
                                }
                                if !friendEmail.isEmpty || !friendPhone.isEmpty {
                                    Text([friendEmail, friendPhone].filter { !$0.isEmpty }.joined(separator: " · "))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .padding(.leading, 28)
                                }
                            }
                            .padding(.vertical, 4)
                        }

                        Button {
                            presentFriendPicker()
                        } label: {
                            Label("Add people", systemImage: "person.badge.plus")
                                .font(.subheadline.weight(.semibold))
                        }
                        .disabled(showingFriendPicker)
                        .accessibilityIdentifier("addFriendToSplit")
                        .padding(.top, 4)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))

                    Text("Start with one friend.")
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
                    .disabled(!canCreate || isCreating)
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
                    existingPeople: trimmedFriendName.isEmpty
                        ? []
                        : [
                            PickedContact(
                                name: trimmedFriendName,
                                email: friendEmail,
                                phone: friendPhone
                            )
                        ],
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
            occasion: createdOccasion,
            onSent: markInviteSent,
            onFinished: finishCreateIfNeeded
        )
    }

    private func presentFriendPicker() {
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
        guard canCreate, !isCreating else { return }
        isCreating = true

        let selfNames = AuthSession.shared.selfNames
        let live = allOccasions.filter { $0.shouldAppearInLists }
        DeletedFriendsStore.forget(trimmedFriendName.lowercased())

        if let existing = FriendPairing.existingOccasion(
            friendName: trimmedFriendName,
            selfNames: selfNames,
            in: live
        ) {
            pendingCreatedID = existing.id
            createdOccasion = existing
            finishCreateIfNeeded()
            return
        }

        let pairingName = AuthSession.shared.pairingName
        var occasionID = FriendPairing.isUsableName(pairingName)
            ? FriendPairing.occasionID(pairingName, trimmedFriendName)
            : UUID()
        if DeletedGroupsStore.contains(occasionID) {
            occasionID = UUID()
        }

        let occasion = Occasion(
            name: trimmedFriendName,
            id: occasionID,
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
            DispatchQueue.main.async {
                inviteContacts = [inviteContact]
            }
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
