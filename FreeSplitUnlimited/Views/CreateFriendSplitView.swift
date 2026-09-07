//
//  CreateFriendSplitView.swift
//  FreeSplitUnlimited
//

import SwiftData
import SwiftUI

struct CreateFriendSplitView: View {
    var onCreated: (UUID) -> Void = { _ in }

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var auth = AuthSession.shared
    @ObservedObject private var mesh = MeshSyncService.shared

    @State private var myName = ""
    @State private var friendName = ""
    @State private var friendEmail = ""
    @State private var friendPhone = ""
    @State private var showingFriendPicker = false
    @State private var contactsAllowed = ContactAuthorization.canUseSystemPicker
    @State private var showMyNameField = false

    private var trimmedMyName: String {
        myName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedFriendName: String {
        friendName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var pairingName: String {
        FriendPairing.isUsableName(auth.pairingName) ? auth.pairingName : trimmedMyName
    }

    private var needsMyName: Bool {
        showMyNameField
    }

    private var canCreate: Bool {
        !trimmedFriendName.isEmpty
            && FriendPairing.isUsableName(trimmedFriendName)
            && (!needsMyName || FriendPairing.isUsableName(trimmedMyName))
            && !FriendPairing.namesMatch(trimmedFriendName, pairingName)
    }

    private var nearbyMatch: String? {
        mesh.nearbyUserNames.first { FriendPairing.namesMatch($0, trimmedFriendName) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 12) {
                        if needsMyName {
                            Text("Your name")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                            TextField("So they can find you", text: $myName)
                                .textContentType(.name)
                                .textInputAutocapitalization(.words)
                                .font(.headline)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 12)
                                .background(Color.white.opacity(0.9), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }

                        Text("Split with")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)

                        TextField("Friend’s name", text: $friendName)
                            .textContentType(.name)
                            .textInputAutocapitalization(.words)
                            .font(.headline)
                            .accessibilityIdentifier("friendNameField")
                            .padding(.horizontal, 12)
                            .padding(.vertical, 12)
                            .background(Color.white.opacity(0.9), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                        Button {
                            Task { await presentFriendPicker() }
                        } label: {
                            Label("Choose from contacts", systemImage: "person.crop.circle.badge.plus")
                                .font(.subheadline.weight(.semibold))
                        }
                        .disabled(showingFriendPicker)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))

                    connectStatus

                    Text("Start with one friend. If they open Free Split nearby and type your name too, both phones share this split.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    Button {
                        createSplit()
                    } label: {
                        Text(nearbyMatch == nil ? "Create Split" : "Connect Split")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.teal)
                    .disabled(!canCreate)
                    .accessibilityIdentifier("createSplitButton")
                    .padding(.top, 4)
                    .padding(.bottom, 12)
                }
                .padding(20)
            }
            .scrollDismissesKeyboard(.interactively)
            .freeSplitBackground()
            .navigationTitle("New Split")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .sheet(isPresented: $showingFriendPicker) {
                FriendSearchPicker(
                    contactsAllowed: contactsAllowed,
                    savedFriends: KnownFriendsStore.previouslyUsedFriends(from: modelContext),
                    selectionLimit: 1,
                    onPick: { contacts in
                        apply(contacts)
                    },
                    onContactsAccessGranted: {
                        contactsAllowed = true
                    }
                )
            }
            .onAppear {
                if myName.isEmpty {
                    myName = auth.pairingName
                }
                showMyNameField = !FriendPairing.isUsableName(auth.pairingName)
                if !AppLaunchFlags.isUITesting {
                    SyncCoordinator.shared.startNearby()
                }
            }
            .onChange(of: trimmedMyName) { _, name in
                guard FriendPairing.isUsableName(name) else { return }
                auth.setPairingNickname(name)
            }
        }
        .tint(AppTheme.teal)
    }

    @ViewBuilder
    private var connectStatus: some View {
        if !trimmedFriendName.isEmpty {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: nearbyMatch == nil
                      ? "dot.radiowaves.left.and.right"
                      : "checkmark.circle.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(AppTheme.teal)
                    .symbolEffect(
                        .variableColor.iterative,
                        isActive: nearbyMatch == nil && mesh.isRunning
                    )
                VStack(alignment: .leading, spacing: 4) {
                    if let nearbyMatch {
                        Text("\(nearbyMatch) is nearby")
                            .font(.subheadline.weight(.semibold))
                        Text("Create this split to connect both phones. No join code needed.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Looking for \(trimmedFriendName) nearby")
                            .font(.subheadline.weight(.semibold))
                        Text("They should open Free Split and start a split with \(pairingName.isEmpty ? "your name" : pairingName). Keep both phones close with the app open.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    @MainActor
    private func presentFriendPicker() async {
        guard !showingFriendPicker else { return }
        await ContactAuthorization.requestIfNeeded()
        try? await Task.sleep(for: .milliseconds(250))
        guard !showingFriendPicker else { return }
        contactsAllowed = ContactAuthorization.canUseSystemPicker
        showingFriendPicker = true
    }

    private func apply(_ contacts: [PickedContact]) {
        guard let contact = contacts.first(where: { !$0.isMe }) else { return }
        friendName = contact.name
        friendEmail = contact.email
        friendPhone = contact.phone
    }

    private func createSplit() {
        guard canCreate else { return }
        if FriendPairing.isUsableName(trimmedMyName) {
            auth.setPairingNickname(trimmedMyName)
        }

        let selfNames = auth.selfNames
        let localName = pairingName
        let meName = FriendPairing.isUsableName(localName) ? localName : "Me"
        let existing = FriendPairing.existingOccasion(
            friendName: trimmedFriendName,
            selfNames: selfNames,
            in: ((try? modelContext.fetch(FetchDescriptor<Occasion>())) ?? [])
        )
        if let existing {
            if let friend = existing.uniqueMembers.first(where: {
                FriendPairing.namesMatch($0.name, trimmedFriendName)
            }) {
                if friend.email.isEmpty { friend.email = friendEmail.trimmingCharacters(in: .whitespacesAndNewlines) }
                if friend.phone.isEmpty { friend.phone = friendPhone.trimmingCharacters(in: .whitespacesAndNewlines) }
            }
            existing.touch()
            modelContext.persist()
            let id = existing.id
            startConnecting()
            dismiss()
            onCreated(id)
            return
        }

        let occasionID = FriendPairing.isUsableName(localName)
            ? FriendPairing.occasionID(localName, trimmedFriendName)
            : UUID()
        let meID = FriendPairing.isUsableName(localName)
            ? FriendPairing.personID(localName, trimmedFriendName, person: meName)
            : UUID()
        let friendID = FriendPairing.isUsableName(localName)
            ? FriendPairing.personID(localName, trimmedFriendName, person: trimmedFriendName)
            : UUID()

        let occasion = Occasion(
            name: trimmedFriendName,
            id: occasionID,
            groupType: SplitKind.oneToOne
        )
        occasion.members = [
            Person(name: meName, id: meID),
            Person(
                name: trimmedFriendName,
                email: friendEmail.trimmingCharacters(in: .whitespacesAndNewlines),
                phone: friendPhone.trimmingCharacters(in: .whitespacesAndNewlines),
                id: friendID
            )
        ]
        modelContext.insert(occasion)
        modelContext.persist()
        let id = occasion.id
        startConnecting()
        dismiss()
        onCreated(id)
    }

    private func startConnecting() {
        guard !AppLaunchFlags.isUITesting else { return }
        SyncCoordinator.shared.startNearby()
        MeshSyncService.shared.restartDiscovery()
    }
}
