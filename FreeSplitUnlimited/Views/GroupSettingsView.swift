//
//  GroupSettingsView.swift
//  FreeSplitUnlimited
//

import SwiftUI
import SwiftData
import UIKit

struct GroupSettingsView: View {
    @Bindable var occasion: Occasion
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    var onDeleted: () -> Void = {}

    @State private var name = ""
    @State private var note = ""
    @State private var kind: GroupKind = .other
    @State private var confirmDelete = false

    private var displayedCode: String {
        let code = JoinCode.normalize(occasion.joinCode)
        return code.isEmpty ? "—" : code
    }

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

                Section {
                    HStack {
                        Text("Join code")
                        Spacer()
                        Text(displayedCode)
                            .font(.body.weight(.semibold).monospaced())
                            .foregroundStyle(AppTheme.deepTeal)
                            .textSelection(.enabled)
                    }
                    Button {
                        UIPasteboard.general.string = displayedCode
                    } label: {
                        Label("Copy code", systemImage: "doc.on.doc")
                    }
                    ShareLink(
                        item: "Join my Free Split group “\(occasion.name)” with code \(displayedCode). Open Free Split → Join with Code, then stand near me with the app open."
                    ) {
                        Label("Share code", systemImage: "square.and.arrow.up")
                    }
                } header: {
                    Text("Invite without AirDrop")
                } footer: {
                    Text("A friend types this code in Free Split. Keep both phones nearby with the app open so the group can sync.")
                }

                Section("People") {
                    ForEach(occasion.sortedMembers(), id: \.id) { person in
                        Text(person.name)
                    }
                    Text("Use Add people on the group page to invite someone.")
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
                let before = occasion.joinCode
                JoinCode.assignIfNeeded(to: occasion, in: modelContext)
                if occasion.joinCode != before {
                    modelContext.persist()
                }
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
        if !occasion.isOneToOne {
            occasion.groupType = kind.rawValue
        }
        occasion.touch()
        modelContext.persist()
        dismiss()
    }
}
