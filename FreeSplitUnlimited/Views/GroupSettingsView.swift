//
//  GroupSettingsView.swift
//  FreeSplitUnlimited
//

import SwiftUI
import SwiftData

struct GroupSettingsView: View {
    @Bindable var occasion: Occasion
    @Environment(\.modelContext) private var modelContext

    var onClose: () -> Void = {}

    @State private var name = ""
    @State private var note = ""
    @State private var kind: GroupKind = .other
    @State private var confirmDelete = false
    @State private var personToRemove: Person?
    @State private var inviteContacts: [PickedContact] = []

    var body: some View {
        NavigationStack {
            Form {
                Section(occasion.isOneToOne ? "Split" : "Group") {
                    TextField("Name", text: $name)
                        .textInputAutocapitalization(.words)
                    TextField("Note", text: $note)
                    if !occasion.isOneToOne {
                        Picker("Kind", selection: $kind) {
                            ForEach(GroupKind.allCases) { option in
                                Label(option.title, systemImage: option.symbol).tag(option)
                            }
                        }
                    }
                }

                Section("People") {
                    ForEach(occasion.sortedMembers().filter { FriendPairing.isUsableName($0.name) }, id: \.id) { person in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(person.name)
                                if person.hasContactInfo {
                                    Text([person.email, person.phone].filter { !$0.isEmpty }.joined(separator: " · "))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                } else if FriendPairing.isUsableName(person.name) {
                                    Text("No email or phone")
                                        .font(.caption)
                                        .foregroundStyle(.orange)
                                }
                            }
                            Spacer()
                            if FriendPairing.isUsableName(person.name), person.hasContactInfo {
                                VStack(spacing: 4) {
                                    Toggle("Notify", isOn: notifyBinding(for: person))
                                        .labelsHidden()
                                        .tint(AppTheme.teal)
                                        .disabled(person.didInvite)
                                        .accessibilityLabel(person.didInvite ? "Invite sent" : "Send invite")
                                    Text(person.didInvite ? "Sent" : "Notify")
                                        .font(.caption2)
                                        .foregroundStyle(person.didInvite ? AppTheme.teal : .secondary)
                                }
                            }
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            if FriendPairing.isUsableName(person.name) {
                                Button("Delete", role: .destructive) {
                                    personToRemove = person
                                }
                            }
                        }
                    }
                    Text("Contact info is locked after someone is added. Swipe left to delete a person added by mistake. Notify sends one text or email.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section {
                    if confirmDelete {
                        Text("This removes the group from this phone. Nearby phones will get the deletion the next time they sync.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Button("Delete Group", role: .destructive) {
                            deleteGroup()
                        }
                        .accessibilityIdentifier("deleteGroupButton")
                        Button("Cancel") {
                            confirmDelete = false
                        }
                    } else {
                        Button("Delete Group", role: .destructive) {
                            confirmDelete = true
                        }
                        .accessibilityIdentifier("deleteGroupButton")
                    }
                }
            }
            .freeSplitListStyle()
            .freeSplitBackground()
            .navigationTitle("Group Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { onClose() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                }
            }
            .onAppear {
                name = occasion.name
                note = occasion.note
                kind = occasion.kind
            }
            .friendInvite(
                contacts: $inviteContacts,
                splitName: occasion.displayName,
                onSent: markInviteSent
            )
            .confirmationDialog(
                "Remove \(personToRemove?.name ?? "this person")?",
                isPresented: Binding(
                    get: { personToRemove != nil },
                    set: { if !$0 { personToRemove = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Remove", role: .destructive) {
                    if let personToRemove {
                        modelContext.delete(personToRemove)
                        occasion.touch()
                        modelContext.persist()
                    }
                    personToRemove = nil
                }
                Button("Cancel", role: .cancel) {
                    personToRemove = nil
                }
            } message: {
                Text("They will be removed from this split.")
            }
        }
        .tint(AppTheme.teal)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }

    private func save() {
        occasion.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        occasion.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        if !occasion.isOneToOne {
            occasion.groupType = kind.rawValue
        }
        occasion.touch()
        modelContext.persist()
        onClose()
    }

    private func deleteGroup() {
        DeletedGroupsStore.remember(occasion.id, notify: false)
        NotificationCenter.default.post(name: .freeSplitJumpToHome, object: nil)
    }

    private func notifyBinding(for person: Person) -> Binding<Bool> {
        Binding(
            get: { person.didInvite },
            set: { isOn in
                guard isOn, !person.didInvite else { return }
                inviteContacts = [
                    PickedContact(
                        id: person.id.uuidString,
                        name: person.name,
                        email: person.email,
                        phone: person.phone,
                        personID: person.id,
                        didInvite: false
                    )
                ]
            }
        )
    }

    private func markInviteSent(_ id: UUID) {
        guard let person = occasion.uniqueMembers.first(where: { $0.id == id }) else { return }
        person.didInvite = true
        occasion.touch()
        modelContext.persist()
    }
}
