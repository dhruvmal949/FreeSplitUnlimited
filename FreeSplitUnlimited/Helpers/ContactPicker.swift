//
//  ContactPicker.swift
//  FreeSplitUnlimited
//
//  One friend picker for New Split: a visible search bar, "Me" already added,
//  then search Contacts (if allowed) or previously saved friends.
//

import Contacts
import SwiftUI
import UIKit

enum ContactAuthorization {
    /// First tap shows Apple's popup: Full Access, Select Contacts (limited), or Don't Allow.
    @MainActor
    static func requestIfNeeded() async {
        guard !AppLaunchFlags.isUITesting else { return }
        let status = CNContactStore.authorizationStatus(for: .contacts)
        guard status == .notDetermined else { return }
        do {
            _ = try await CNContactStore().requestAccess(for: .contacts)
        } catch {
            print("Contacts access request failed: \(error)")
        }
    }

    static var canUseSystemPicker: Bool {
        switch CNContactStore.authorizationStatus(for: .contacts) {
        case .authorized, .limited:
            return true
        default:
            return false
        }
    }
}

struct PickedContact: Identifiable, Hashable {
    let id: String
    let name: String
    let email: String
    let phone: String
    var isMe: Bool = false

    init(id: String = UUID().uuidString, name: String, email: String = "", phone: String = "", isMe: Bool = false) {
        self.id = id
        self.name = name
        self.email = email
        self.phone = phone
        self.isMe = isMe
    }

    init?(contact: CNContact, isMe: Bool = false) {
        var parts: [String] = []
        if contact.isKeyAvailable(CNContactGivenNameKey), !contact.givenName.isEmpty {
            parts.append(contact.givenName)
        }
        if contact.isKeyAvailable(CNContactMiddleNameKey), !contact.middleName.isEmpty {
            parts.append(contact.middleName)
        }
        if contact.isKeyAvailable(CNContactFamilyNameKey), !contact.familyName.isEmpty {
            parts.append(contact.familyName)
        }
        var name = parts.joined(separator: " ")
        if name.isEmpty, contact.isKeyAvailable(CNContactOrganizationNameKey) {
            name = contact.organizationName.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard !name.isEmpty else { return nil }

        self.id = isMe ? "me" : contact.identifier
        self.name = name
        if contact.isKeyAvailable(CNContactEmailAddressesKey) {
            self.email = contact.emailAddresses.first.map { $0.value as String } ?? ""
        } else {
            self.email = ""
        }
        if contact.isKeyAvailable(CNContactPhoneNumbersKey) {
            self.phone = contact.phoneNumbers.first?.value.stringValue ?? ""
        } else {
            self.phone = ""
        }
        self.isMe = isMe
    }
}

enum ContactDirectory {
    private static var keys: [CNKeyDescriptor] {
        [
            CNContactIdentifierKey as CNKeyDescriptor,
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactMiddleNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactOrganizationNameKey as CNKeyDescriptor,
            CNContactEmailAddressesKey as CNKeyDescriptor,
            CNContactPhoneNumbersKey as CNKeyDescriptor,
        ]
    }

    static func me() -> PickedContact {
        PickedContact(id: "me", name: "Me", isMe: true)
    }

    static func searchContacts(matching query: String) -> [PickedContact] {
        guard ContactAuthorization.canUseSystemPicker else { return [] }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 1 else { return [] }
        let store = CNContactStore()
        let predicate = CNContact.predicateForContacts(matchingName: trimmed)
        let contacts = (try? store.unifiedContacts(matching: predicate, keysToFetch: keys)) ?? []
        return contacts.compactMap { PickedContact(contact: $0) }
    }
}

/// Always-visible search field used on both Contacts and saved-friends screens.
struct FriendSearchBar: View {
    @Binding var query: String
    var placeholder: String
    var isFocused: FocusState<Bool>.Binding

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField(placeholder, text: $query)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .focused(isFocused)
                .accessibilityIdentifier("friendSearchField")
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
}

/// Search Contacts (if allowed) or saved friends. "Me" is already added.
struct FriendSearchPicker: View {
    let contactsAllowed: Bool
    let savedFriends: [PickedContact]
    /// `nil` means unlimited extra people. `1` is used when creating a one-to-one split.
    var selectionLimit: Int?
    var onPick: ([PickedContact]) -> Void
    var onContactsAccessGranted: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var query = ""
    @State private var selected: [PickedContact] = [ContactDirectory.me()]
    @State private var usingContacts: Bool
    @FocusState private var searchFocused: Bool

    private var otherSelectedCount: Int {
        selected.filter { !$0.isMe }.count
    }

    private var canAddMore: Bool {
        guard let selectionLimit else { return true }
        return otherSelectedCount < selectionLimit
    }

    init(
        contactsAllowed: Bool,
        savedFriends: [PickedContact],
        selectionLimit: Int? = nil,
        onPick: @escaping ([PickedContact]) -> Void,
        onContactsAccessGranted: @escaping () -> Void = {}
    ) {
        self.contactsAllowed = contactsAllowed
        self.savedFriends = savedFriends
        self.selectionLimit = selectionLimit
        self.onPick = onPick
        self.onContactsAccessGranted = onContactsAccessGranted
        _usingContacts = State(initialValue: contactsAllowed)
    }

    private var placeholder: String {
        usingContacts ? "Search contacts" : "Search saved friends"
    }

    private var typedNameToAdd: String? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 1 else { return nil }
        guard trimmed.localizedCaseInsensitiveCompare("Me") != .orderedSame else { return nil }
        let alreadySelected = selected.contains {
            $0.name.localizedCaseInsensitiveCompare(trimmed) == .orderedSame
        }
        return alreadySelected ? nil : trimmed
    }

    private func addTypedName(_ name: String) {
        guard canAddMore else { return }
        if selectionLimit == 1 {
            selected.removeAll { !$0.isMe }
        }
        selected.append(PickedContact(name: name))
        query = ""
    }

    private var results: [PickedContact] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        var matches: [PickedContact] = []

        if usingContacts, trimmed.count >= 1 {
            matches.append(contentsOf: ContactDirectory.searchContacts(matching: trimmed))
        }

        let saved: [PickedContact]
        if trimmed.isEmpty {
            saved = savedFriends
        } else {
            saved = savedFriends.filter { $0.name.localizedStandardContains(trimmed) }
        }
        matches.append(contentsOf: saved)

        var seen = Set<String>()
        let selectedKeys = Set(selected.map { $0.name.lowercased() })
        return matches.filter { candidate in
            let key = candidate.name.lowercased()
            guard seen.insert(key).inserted else { return false }
            if candidate.isMe { return false }
            return !selectedKeys.contains(key)
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                FriendSearchBar(
                    query: $query,
                    placeholder: placeholder,
                    isFocused: $searchFocused
                )

                List {
                    Section("Added to split") {
                        ForEach(selected) { friend in
                            friendRow(friend, isSelected: true) {
                                guard !friend.isMe else { return }
                                selected.removeAll { $0.id == friend.id }
                            }
                        }
                    }

                    if let typedName = typedNameToAdd {
                        Section {
                            Button {
                                addTypedName(typedName)
                            } label: {
                                Label("Add \(typedName)", systemImage: "plus.circle.fill")
                            }
                            .disabled(!canAddMore)
                            .accessibilityIdentifier("addTypedName")
                        }
                    }

                    Section(usingContacts ? "Contacts" : "Saved friends") {
                        if results.isEmpty {
                            Text(emptyResultsText)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(results) { friend in
                                friendRow(friend, isSelected: false) {
                                    guard canAddMore else { return }
                                    if selectionLimit == 1 {
                                        selected.removeAll { !$0.isMe }
                                    }
                                    selected.append(friend)
                                    query = ""
                                }
                                .disabled(!canAddMore)
                            }
                        }
                    }

                    if !usingContacts {
                        Section {
                            Button {
                                openAppSettings()
                            } label: {
                                Label("Open Settings", systemImage: "gear")
                                    .font(.headline)
                                    .frame(maxWidth: .infinity)
                            }
                            .listRowBackground(AppTheme.teal)
                            .foregroundStyle(.white)
                        } footer: {
                            Text("To add someone who isn’t listed, open Settings and allow Contacts for Free Split.")
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
                .contentMargins(.bottom, 12, for: .scrollContent)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .freeSplitBackground()
            .navigationTitle(selectionLimit == 1 ? "Add Friend" : "Add Friends")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        onPick(selected)
                        dismiss()
                    }
                    .disabled(otherSelectedCount == 0)
                    .accessibilityIdentifier("confirmAddFriends")
                }
            }
            .onAppear {
                searchFocused = true
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                guard ContactAuthorization.canUseSystemPicker else { return }
                usingContacts = true
                onContactsAccessGranted()
            }
        }
        .tint(AppTheme.teal)
    }

    private var emptyResultsText: String {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return usingContacts
                ? "Search to add other friends."
                : "No other saved friends yet. Search or open Settings to use Contacts."
        }
        return "No matches for “\(trimmed)”."
    }

    private func friendRow(_ friend: PickedContact, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(friend.name)
                            .foregroundStyle(.primary)
                        if friend.isMe {
                            Text("You")
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(AppTheme.teal.opacity(0.18), in: Capsule())
                                .foregroundStyle(AppTheme.teal)
                        }
                    }
                    if !friend.email.isEmpty || !friend.phone.isEmpty {
                        Text([friend.email, friend.phone].filter { !$0.isEmpty }.joined(separator: " · "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "plus.circle")
                    .foregroundStyle(AppTheme.teal)
            }
        }
        .disabled(isSelected && friend.isMe)
    }

    private func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        openURL(url)
    }
}
