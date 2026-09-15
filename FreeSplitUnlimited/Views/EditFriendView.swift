//
//  EditFriendView.swift
//  FreeSplitUnlimited
//

import SwiftUI
import SwiftData

struct EditFriendView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let occasion: Occasion
    /// Pass nil to add a new friend; pass an existing person to edit them.
    var person: Person? = nil

    @State private var name = ""

    private var isEditing: Bool { person != nil }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isNameUnique: Bool {
        !occasion.uniqueMembers.contains {
            $0.id != person?.id
                && $0.name.localizedCaseInsensitiveCompare(trimmedName) == .orderedSame
        }
    }

    private var canSave: Bool {
        !trimmedName.isEmpty && isNameUnique
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                        .textContentType(.name)
                        .textInputAutocapitalization(.words)
                } header: {
                    Text("Friend details")
                } footer: {
                    if !trimmedName.isEmpty && !isNameUnique {
                        Text("Someone with this name is already in this split.")
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    Button {
                        save()
                    } label: {
                        Text(isEditing ? "Save" : "Add Friend")
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
                }
            }
        }
    }

    private func save() {
        guard canSave else { return }

        if let person {
            person.name = trimmedName
        } else {
            let newPerson = Person(name: trimmedName)
            newPerson.occasion = occasion
            modelContext.insert(newPerson)
        }
        occasion.touch()
        modelContext.persist()
        dismiss()
    }
}
