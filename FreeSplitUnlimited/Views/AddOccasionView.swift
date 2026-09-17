//
//  AddOccasionView.swift
//  FreeSplitUnlimited
//

import SwiftUI
import SwiftData

struct FriendDraft: Identifiable {
    let id = UUID()
    var name = ""
    var email = ""
    var phone = ""

    var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isComplete: Bool {
        !trimmedName.isEmpty
    }

    var isSelf: Bool {
        FriendPairing.isPlaceholderSelf(trimmedName)
    }

    init(name: String = "", email: String = "", phone: String = "") {
        self.name = name
        self.email = email
        self.phone = phone
    }

    init(contact: PickedContact) {
        self.name = contact.name
        self.email = contact.email
        self.phone = contact.phone
    }
}

struct AddOccasionView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var note = ""
    @State private var friends: [FriendDraft]
    @State private var showingFriendPicker = false
    @State private var contactsAllowed = ContactAuthorization.canUseSystemPicker

    init(initialFriends: [FriendDraft] = []) {
        var drafts = initialFriends.filter { $0.isComplete && !$0.isSelf }
        while drafts.count < 2 {
            drafts.append(FriendDraft())
        }
        _friends = State(initialValue: drafts)
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && friends.filter(\.isComplete).count >= 2
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Split") {
                    TextField("Name (e.g. Beach Trip)", text: $name)
                    TextField("Note (optional)", text: $note)
                }

                ForEach($friends) { $friend in
                    Section {
                        TextField("Name", text: $friend.name)
                            .textContentType(.name)
                            .textInputAutocapitalization(.words)

                        if friends.count > 2 {
                            Button("Remove Friend", role: .destructive) {
                                friends.removeAll { $0.id == friend.id }
                            }
                        }
                    } header: {
                        Text("Friend \((friends.firstIndex(where: { $0.id == friend.id }) ?? 0) + 1)")
                    }
                }

                Section {
                    Button {
                        Task { await presentFriendPicker() }
                    } label: {
                        Label("Add Friends", systemImage: "magnifyingglass")
                    }
                    .disabled(showingFriendPicker)

                    Button {
                        friends.append(FriendDraft())
                    } label: {
                        Label("Add Another Friend", systemImage: "plus.circle")
                    }
                }

                Section {
                    Button {
                        save()
                    } label: {
                        Text("Create Split")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .disabled(!canSave)
                    .listRowBackground(
                        canSave ? AppTheme.teal : Color.gray.opacity(0.35)
                    )
                    .foregroundStyle(.white)
                }
            }
            .freeSplitListStyle()
            .freeSplitBackground()
            .scrollDismissesKeyboard(.interactively)
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
                    onPick: { contacts in
                        add(contacts)
                    },
                    onContactsAccessGranted: {
                        contactsAllowed = true
                    }
                )
            }
        }
    }

    @MainActor
    private func presentFriendPicker() async {
        guard !showingFriendPicker else { return }
        await ContactAuthorization.requestIfNeeded()
        try? await Task.sleep(for: .milliseconds(250))
        guard !showingFriendPicker else { return }
        let allowed = ContactAuthorization.canUseSystemPicker
        contactsAllowed = allowed
        showingFriendPicker = true
    }

    private func add(_ contacts: [PickedContact]) {
        var next: [FriendDraft] = []
        for contact in contacts where !contact.isMe {
            let draft = FriendDraft(contact: contact)
            guard !draft.isSelf else { continue }
            let alreadyAdded = next.contains {
                $0.trimmedName.localizedCaseInsensitiveCompare(draft.trimmedName) == .orderedSame
            }
            if !alreadyAdded {
                next.append(draft)
            }
        }
        for existing in friends where existing.isComplete {
            let alreadyAdded = next.contains {
                $0.trimmedName.localizedCaseInsensitiveCompare(existing.trimmedName) == .orderedSame
            }
            if !alreadyAdded {
                next.append(existing)
            }
        }
        while next.count < 2 {
            next.append(FriendDraft())
        }
        friends = next
    }

    private func save() {
        let occasion = Occasion(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            note: note.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        var people = friends
            .filter { $0.isComplete && !$0.isSelf }
            .map { draft -> Person in
                let person = Person(
                    name: draft.trimmedName,
                    email: draft.email.trimmingCharacters(in: .whitespacesAndNewlines),
                    phone: draft.phone.trimmingCharacters(in: .whitespacesAndNewlines)
                )
                person.setContact(email: draft.email, phone: draft.phone)
                return person
            }
        if !people.contains(where: { FriendPairing.isPlaceholderSelf($0.name) }) {
            people.insert(Person(name: "Me"), at: 0)
        }

        occasion.members = people
        modelContext.insert(occasion)
        for person in occasion.members {
            person.setContact(email: person.email, phone: person.phone)
        }
        modelContext.persist()
        dismiss()
    }
}

#Preview {
    AddOccasionView()
        .modelContainer(for: [Occasion.self, Person.self, Expense.self, ExpenseShare.self], inMemory: true)
}
