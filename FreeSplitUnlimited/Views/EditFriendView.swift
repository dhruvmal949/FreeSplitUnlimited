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
    @State private var workingPerson: Person?
    @State private var originalName = ""
    @State private var createdInSession = false
    @State private var discardOnDismiss = false
    @State private var isHydrating = false
    @State private var autoSaveTask: Task<Void, Never>?

    private var isEditing: Bool { person != nil }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isNameUnique: Bool {
        !occasion.uniqueMembers.contains {
            $0.id != workingPerson?.id
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
                        persistFriend(dismissAfter: true)
                    } label: {
                        Text("Done")
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
                    Button("Cancel") {
                        discardChanges()
                    }
                }
            }
            .onAppear {
                isHydrating = true
                workingPerson = person
                originalName = person?.name ?? ""
                if name.isEmpty {
                    name = originalName
                }
                DispatchQueue.main.async {
                    isHydrating = false
                }
            }
            .onChange(of: name) { _, _ in
                guard !isHydrating else { return }
                scheduleAutoSave()
            }
            .onDisappear {
                autoSaveTask?.cancel()
                if !discardOnDismiss {
                    persistFriend(dismissAfter: false)
                }
            }
        }
    }

    private func scheduleAutoSave() {
        autoSaveTask?.cancel()
        autoSaveTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            persistFriend(dismissAfter: false)
        }
    }

    private func discardChanges() {
        discardOnDismiss = true
        autoSaveTask?.cancel()
        if createdInSession, let workingPerson {
            modelContext.delete(workingPerson)
            occasion.touch()
            modelContext.persist()
        } else if let person, person.name != originalName {
            person.name = originalName
            occasion.touch()
            modelContext.persist()
        }
        dismiss()
    }

    private func persistFriend(dismissAfter: Bool) {
        guard canSave else {
            if dismissAfter { dismiss() }
            return
        }
        if let workingPerson {
            if workingPerson.name != trimmedName {
                workingPerson.name = trimmedName
                occasion.touch()
                modelContext.persist()
            }
        } else {
            let newPerson = Person(name: trimmedName)
            newPerson.occasion = occasion
            modelContext.insert(newPerson)
            workingPerson = newPerson
            createdInSession = true
            occasion.touch()
            modelContext.persist()
        }
        if dismissAfter {
            discardOnDismiss = true
            dismiss()
        }
    }
}
