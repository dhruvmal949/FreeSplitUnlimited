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
    @State private var autoSaveTask: Task<Void, Never>?
    @State private var isHydrating = true

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
                    SwiftUI.ShareLink(
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
                    Button("Done") { saveAndDismiss() }
                }
            }
            .onAppear {
                isHydrating = true
                name = occasion.name
                note = occasion.note
                kind = occasion.kind
                let before = occasion.joinCode
                JoinCode.assignIfNeeded(to: occasion, in: modelContext)
                if occasion.joinCode != before {
                    modelContext.persist()
                }
                DispatchQueue.main.async {
                    isHydrating = false
                }
            }
            .onChange(of: name) { _, _ in scheduleAutoSave() }
            .onChange(of: note) { _, _ in scheduleAutoSave() }
            .onChange(of: kind) { _, _ in scheduleAutoSave() }
            .onDisappear {
                autoSaveTask?.cancel()
                saveIfNeeded()
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

    private func scheduleAutoSave() {
        autoSaveTask?.cancel()
        guard !isHydrating else { return }
        autoSaveTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            saveIfNeeded()
        }
    }

    private func saveAndDismiss() {
        autoSaveTask?.cancel()
        saveIfNeeded()
        dismiss()
    }

    private func saveIfNeeded() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let nextKind = occasion.isOneToOne ? occasion.groupType : kind.rawValue
        let kindChanged = !occasion.isOneToOne && occasion.groupType != kind.rawValue
        guard trimmedName != occasion.name || trimmedNote != occasion.note || kindChanged else { return }
        occasion.name = trimmedName
        occasion.note = trimmedNote
        if !occasion.isOneToOne {
            occasion.groupType = nextKind
        }
        occasion.touch()
        modelContext.persist()
    }

}
