//
//  AddOccasionView.swift
//  FreeSplitUnlimited
//

import SwiftUI
import SwiftData

private struct FriendDraft: Identifiable {
    let id = UUID()
    var name = ""
    var email = ""
    var phone = ""

    var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var normalizedEmail: String {
        FriendContactValidation.normalizedEmail(email)
    }

    var trimmedPhone: String {
        FriendContactValidation.formatPhone(phone)
    }

    var isComplete: Bool {
        !trimmedName.isEmpty
            && FriendContactValidation.isValidEmail(normalizedEmail)
            && FriendContactValidation.isValidPhone(trimmedPhone)
    }
}

struct AddOccasionView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var note = ""
    @State private var friends: [FriendDraft] = [FriendDraft(), FriendDraft()]

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

                ForEach(friends.indices, id: \.self) { index in
                    Section {
                        TextField("Name", text: $friends[index].name)
                            .textContentType(.name)
                            .textInputAutocapitalization(.words)

                        TextField("Email", text: $friends[index].email)
                            .keyboardType(.emailAddress)
                            .textContentType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()

                        TextField("555-123-4567", text: ContactActions.phoneBinding($friends[index].phone))
                            .keyboardType(.phonePad)
                            .textContentType(.telephoneNumber)

                        if friends.count > 2 {
                            Button("Remove Friend", role: .destructive) {
                                friends.remove(at: index)
                            }
                        }
                    } header: {
                        Text("Friend \(index + 1)")
                    } footer: {
                        if index == friends.count - 1 {
                            Text("Type an email like name@email.com for each friend.")
                        }
                    }
                }

                Section {
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
            .navigationTitle("New Split")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func save() {
        let occasion = Occasion(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            note: note.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        let people = friends
            .filter(\.isComplete)
            .map {
                Person(
                    name: $0.trimmedName,
                    email: $0.normalizedEmail,
                    phone: $0.trimmedPhone
                )
            }

        occasion.members = people
        modelContext.insert(occasion)
        modelContext.persist()
        dismiss()
    }
}

#Preview {
    AddOccasionView()
        .modelContainer(for: [Occasion.self, Person.self, Expense.self, ExpenseShare.self], inMemory: true)
}
