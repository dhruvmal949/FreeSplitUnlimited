//
//  GroupSettingsView.swift
//  FreeSplitUnlimited
//

import SwiftUI
import SwiftData

struct GroupSettingsView: View {
    @Bindable var occasion: Occasion
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    var onDeleted: () -> Void = {}

    @State private var name = ""
    @State private var note = ""
    @State private var kind: GroupKind = .other
    @State private var confirmDelete = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Group") {
                    TextField("Name", text: $name)
                        .textInputAutocapitalization(.words)
                    TextField("Note", text: $note)
                    Picker("Kind", selection: $kind) {
                        ForEach(GroupKind.allCases) { option in
                            Label(option.title, systemImage: option.symbol).tag(option)
                        }
                    }
                }

                Section("People") {
                    ForEach(occasion.sortedMembers(), id: \.id) { person in
                        Text(person.name)
                    }
                    Text("Use Add members on the group page to invite someone.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Button("Delete Group", role: .destructive) {
                        confirmDelete = true
                    }
                }
            }
            .freeSplitListStyle()
            .freeSplitBackground()
            .navigationTitle("Group Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear {
                name = occasion.name
                note = occasion.note
                kind = occasion.kind
            }
            .confirmationDialog("Delete this group?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete Group", role: .destructive) {
                    occasion.isDeleted = true
                    occasion.touch()
                    modelContext.persist()
                    dismiss()
                    onDeleted()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This removes the group from this phone. Nearby phones will get the deletion the next time they sync.")
            }
        }
        .tint(AppTheme.teal)
    }

    private func save() {
        occasion.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        occasion.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        occasion.groupType = kind.rawValue
        occasion.touch()
        modelContext.persist()
        dismiss()
    }
}
