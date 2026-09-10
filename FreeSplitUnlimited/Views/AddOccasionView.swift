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
    @State private var discardOnDismiss = false
    @State private var skipDismissSave = false
    @State private var savedOccasionID: UUID?

    init(initialFriends: [FriendDraft] = []) {
        let me = FriendDraft(contact: ContactDirectory.me())
        var drafts = initialFriends.filter(\.isComplete)
        if drafts.isEmpty {
            drafts = [me]
        } else if !drafts.contains(where: {
            $0.trimmedName.localizedCaseInsensitiveCompare(me.trimmedName) == .orderedSame
        }) {
            drafts.insert(me, at: 0)
        }
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
                        save(dismissAfter: true)
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
                    Button("Cancel") {
                        discardOnDismiss = true
                        if let savedOccasionID,
                           let existing = (try? modelContext.fetch(FetchDescriptor<Occasion>()))?.first(where: { $0.id == savedOccasionID && !$0.isDeleted }) {
                            existing.isDeleted = true
                            existing.touch()
                            modelContext.persist()
                        }
                        dismiss()
                    }
                }
            }
            .onDisappear {
                if !discardOnDismiss && !skipDismissSave && !showingFriendPicker {
                    save(dismissAfter: false)
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
        for contact in contacts {
            let draft = FriendDraft(contact: contact)
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

    private func save(dismissAfter: Bool = true) {
        guard canSave else {
            if dismissAfter { dismiss() }
            return
        }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let people = friends
            .filter(\.isComplete)
            .map {
                Person(
                    name: $0.trimmedName,
                    email: $0.email.trimmingCharacters(in: .whitespacesAndNewlines),
                    phone: $0.phone.trimmingCharacters(in: .whitespacesAndNewlines)
                )
            }

        if let savedOccasionID,
           let existing = (try? modelContext.fetch(FetchDescriptor<Occasion>()))?.first(where: { $0.id == savedOccasionID && !$0.isDeleted }) {
            existing.name = trimmedName
            existing.note = trimmedNote
            existing.touch()
            modelContext.persist()
        } else {
            let occasion = Occasion(
                name: trimmedName,
                note: trimmedNote
            )
            occasion.members = people
            modelContext.insert(occasion)
            modelContext.persist()
            savedOccasionID = occasion.id
        }
        if dismissAfter {
            skipDismissSave = true
            dismiss()
        }
    }
}

#Preview {
    AddOccasionView()
        .modelContainer(for: [Occasion.self, Person.self, Expense.self, ExpenseShare.self], inMemory: true)
}
