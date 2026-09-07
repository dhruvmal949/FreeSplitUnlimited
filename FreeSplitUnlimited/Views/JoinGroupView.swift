//
//  JoinGroupView.swift
//  FreeSplitUnlimited
//

import SwiftData
import SwiftUI

struct JoinGroupView: View {
    var onJoined: (UUID) -> Void = { _ in }

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var mesh = MeshSyncService.shared

    @State private var code = ""
    @State private var isWorking = false
    @State private var errorMessage: String?

    private var normalized: String {
        JoinCode.normalize(code)
    }

    private var canJoin: Bool {
        normalized.contains("-") && normalized.count >= 6 && !isWorking
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    VStack(spacing: 8) {
                        Image(systemName: "person.badge.plus")
                            .font(.system(size: 36, weight: .semibold))
                            .foregroundStyle(AppTheme.teal)
                        Text("Join with a code")
                            .font(.title2.weight(.bold))
                            .foregroundStyle(AppTheme.deepTeal)
                        Text("Ask a friend in the group for their code (like TRIP-4K). Keep both phones nearby with Free Split open — no AirDrop needed.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 8)

                    TextField("TRIP-4K", text: $code)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .font(.title3.weight(.semibold).monospaced())
                        .multilineTextAlignment(.center)
                        .padding(16)
                        .background(Color.white.opacity(0.86), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .onChange(of: code) { _, newValue in
                            let cleaned = JoinCode.normalize(newValue)
                            if cleaned != newValue {
                                code = cleaned
                            }
                        }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Button {
                        Task { await join() }
                    } label: {
                        if isWorking {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                        } else {
                            Text("Join Group")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.teal)
                    .disabled(!canJoin)

                    Text(mesh.connectedPeerCount > 0
                         ? mesh.statusTitle
                         : "Looking for a nearby phone that already has this group…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(24)
            }
            .freeSplitBackground()
            .navigationTitle("Join Group")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear {
                SyncCoordinator.shared.startNearby()
            }
        }
        .tint(AppTheme.teal)
    }

    private func join() async {
        let code = normalized
        guard !code.isEmpty else { return }
        errorMessage = nil
        isWorking = true
        defer { isWorking = false }

        if let existing = JoinCode.find(code: code, in: modelContext) {
            addLocalUser(to: existing)
            modelContext.persist()
            let id = existing.id
            dismiss()
            onJoined(id)
            return
        }

        SyncCoordinator.shared.startNearby()
        if mesh.connectedPeerCount == 0 {
            try? await Task.sleep(for: .seconds(2))
        }

        if let backup = await MeshSyncService.shared.fetchByJoinCode(code),
           let occasion = try? SplitBackup.upsert(backup, into: modelContext, force: true) {
            addLocalUser(to: occasion)
            modelContext.persist()
            let id = occasion.id
            dismiss()
            onJoined(id)
            return
        }

        if let existing = JoinCode.find(code: code, in: modelContext) {
            addLocalUser(to: existing)
            modelContext.persist()
            let id = existing.id
            dismiss()
            onJoined(id)
            return
        }

        errorMessage = mesh.connectedPeerCount == 0
            ? "No nearby phone found. Open Free Split on a friend’s phone that already has this group, stay close, then try again."
            : "No nearby group uses that code. Check the code, or ask your friend to open Free Split."
    }

    private func addLocalUser(to occasion: Occasion) {
        let name = AuthSession.shared.pairingName.isEmpty ? "Me" : AuthSession.shared.pairingName
        if occasion.uniqueMembers.contains(where: {
            $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame
        }) {
            return
        }
        let person = Person(name: name)
        person.occasion = occasion
        modelContext.insert(person)
        occasion.touch()
    }
}
