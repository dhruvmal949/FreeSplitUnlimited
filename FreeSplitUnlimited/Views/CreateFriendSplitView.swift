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
    @State private var savedSplitID: UUID?
    @State private var createdInSession = false
    @State private var didConnectNearby = false
    @State private var discardOnDismiss = false
    @State private var skipDismissSave = false

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
                        persistSplit(dismissAfter: true)
                    } label: {
                        Text(nearbyMatch == nil ? "Done" : "Connected — Done")
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
                    Button("Cancel") {
                        discardDraft()
                    }
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
            .onChange(of: nearbyMatch) { _, match in
                guard match != nil else { return }
                didConnectNearby = true
                persistSplit(dismissAfter: false)
            }
            .onDisappear {
                if !discardOnDismiss && !skipDismissSave && !showingFriendPicker {
                    persistSplit(dismissAfter: false)
                }
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
                        Text("This split is saved. Both phones share it automatically — no join code needed.")
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

    private func discardDraft() {
        discardOnDismiss = true
        skipDismissSave = true
        if createdInSession,
           !didConnectNearby,
           let savedSplitID,
           let draft = ((try? modelContext.fetch(FetchDescriptor<Occasion>())) ?? [])
            .first(where: { $0.id == savedSplitID && !$0.isDeleted }),
           draft.expenses.isEmpty {
            draft.isDeleted = true
            draft.touch()
            modelContext.persist()
        }
        dismiss()
    }

    private func persistSplit(dismissAfter: Bool) {
        guard canCreate else {
            if dismissAfter {
                skipDismissSave = true
                dismiss()
            }
            return
        }
        if FriendPairing.isUsableName(trimmedMyName) {
            auth.setPairingNickname(trimmedMyName)
        }

        let selfNames = auth.selfNames
        let localName = pairingName
        let meName = FriendPairing.isUsableName(localName) ? localName : "Me"
        let occasions = (try? modelContext.fetch(FetchDescriptor<Occasion>())) ?? []

        let target = FriendPairing.resolveTarget(
            friendName: trimmedFriendName,
            savedID: savedSplitID,
            createdInSession: createdInSession,
            selfNames: selfNames,
            in: occasions
        )
        if let abandon = target.abandon {
            abandon.isDeleted = true
            abandon.touch()
        }
        if let occasion = target.occasion {
            if occasion.id != savedSplitID {
                createdInSession = false
            }
            update(occasion, meName: meName, selfNames: selfNames)
            finish(occasion.id, dismissAfter: dismissAfter)
            return
        }

        let occasionID = FriendPairing.isUsableName(localName)
            ? FriendPairing.occasionID(localName, trimmedFriendName)
            : UUID()
        if let existing = occasions.first(where: { $0.id == occasionID && !$0.isDeleted }) {
            createdInSession = false
            update(existing, meName: meName, selfNames: selfNames)
            finish(existing.id, dismissAfter: dismissAfter)
            return
        }

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
        createdInSession = true
        modelContext.persist()
        finish(occasion.id, dismissAfter: dismissAfter)
    }

    private func update(_ occasion: Occasion, meName: String, selfNames: [String]) {
        occasion.name = trimmedFriendName
        if let me = occasion.uniqueMembers.first(where: {
            FriendPairing.isSelf($0.name, selfNames: selfNames)
        }) {
            me.name = meName
        }
        if let friend = occasion.uniqueMembers.first(where: {
            FriendPairing.namesMatch($0.name, trimmedFriendName)
        }) ?? occasion.uniqueMembers.first(where: {
            !FriendPairing.isSelf($0.name, selfNames: selfNames)
        }) {
            friend.name = trimmedFriendName
            if friend.email.isEmpty {
                friend.email = friendEmail.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if friend.phone.isEmpty {
                friend.phone = friendPhone.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        realignPairingIDs(occasion, meName: meName, selfNames: selfNames)
        occasion.touch()
        modelContext.persist()
    }

    /// Keep the deterministic pair IDs in sync as the typed name grows from "Al" to "Alex".
    private func realignPairingIDs(_ occasion: Occasion, meName: String, selfNames: [String]) {
        let localName = pairingName
        guard FriendPairing.isUsableName(localName), occasion.expenses.isEmpty else { return }
        let nextOccasionID = FriendPairing.occasionID(localName, trimmedFriendName)
        if occasion.id != nextOccasionID {
            occasion.id = nextOccasionID
        }
        if let me = occasion.uniqueMembers.first(where: { FriendPairing.isSelf($0.name, selfNames: selfNames) }) {
            me.id = FriendPairing.personID(localName, trimmedFriendName, person: meName)
        }
        if let friend = occasion.uniqueMembers.first(where: { !FriendPairing.isSelf($0.name, selfNames: selfNames) }) {
            friend.id = FriendPairing.personID(localName, trimmedFriendName, person: trimmedFriendName)
        }
        savedSplitID = occasion.id
    }

    private func finish(_ id: UUID, dismissAfter: Bool) {
        savedSplitID = id
        startConnectingIfNeeded()
        guard dismissAfter else { return }
        skipDismissSave = true
        dismiss()
        onCreated(id)
    }

    private func startConnectingIfNeeded() {
        guard !AppLaunchFlags.isUITesting else { return }
        SyncCoordinator.shared.startNearby()
        MeshSyncService.shared.broadcastLocalChanges()
    }
}
