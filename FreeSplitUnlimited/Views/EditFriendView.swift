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
    @State private var email = ""
    @State private var phone = ""

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
                    TextField("Email", text: $email)
                        .keyboardType(.emailAddress)
                        .textContentType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Phone", text: $phone)
                        .keyboardType(.phonePad)
                        .textContentType(.telephoneNumber)
                } header: {
                    Text("Friend details")
                } footer: {
                    if !trimmedName.isEmpty && !isNameUnique {
                        Text("Someone with this name is already in this split.")
                            .foregroundStyle(.red)
                    } else {
                        Text("Email or phone is used to reach this person. If both are empty, you’ll be asked before saving an expense.")
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
                    email = person.email
                    phone = person.phone
                }
            }
        }
    }

    private func save() {
        guard canSave else { return }

        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPhone = phone.trimmingCharacters(in: .whitespacesAndNewlines)

        if let person {
            person.name = trimmedName
            person.setContact(email: trimmedEmail, phone: trimmedPhone)
        } else {
            let newPerson = Person(name: trimmedName, email: trimmedEmail, phone: trimmedPhone)
            newPerson.occasion = occasion
            modelContext.insert(newPerson)
            newPerson.setContact(email: trimmedEmail, phone: trimmedPhone)
        }
        occasion.touch()
        modelContext.persist()
        dismiss()
    }
}
