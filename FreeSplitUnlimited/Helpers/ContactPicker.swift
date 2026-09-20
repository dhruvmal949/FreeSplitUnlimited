//
//  ContactPicker.swift
//  FreeSplitUnlimited
//
//  One friend picker for New Split: a visible search bar, "Me" already added,
//  then search Contacts (if allowed) or previously saved friends.
//

import Contacts
import ContactsUI
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

/// Apple's contact picker. Presented with UIKit so it does not dismiss the Add friends sheet.
struct SystemContactPicker: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    var onPick: (PickedContact) -> Void
    var onCancel: () -> Void = {}

    func makeCoordinator() -> Coordinator {
        Coordinator(isPresented: $isPresented, onPick: onPick, onCancel: onCancel)
    }

    func makeUIViewController(context: Context) -> UIViewController {
        context.coordinator.host
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        context.coordinator.isPresented = $isPresented
        context.coordinator.onPick = onPick
        context.coordinator.onCancel = onCancel
        if isPresented {
            context.coordinator.presentIfNeeded()
        }
    }

    final class Coordinator: NSObject, CNContactPickerDelegate {
        let host = UIViewController()
        var isPresented: Binding<Bool>
        var onPick: (PickedContact) -> Void
        var onCancel: () -> Void
        private var isShowingPicker = false

        init(
            isPresented: Binding<Bool>,
            onPick: @escaping (PickedContact) -> Void,
            onCancel: @escaping () -> Void
        ) {
            self.isPresented = isPresented
            self.onPick = onPick
            self.onCancel = onCancel
        }

        func presentIfNeeded() {
            guard isPresented.wrappedValue, !isShowingPicker else { return }
            guard let presenter = presentationAnchor() else {
                DispatchQueue.main.async { [weak self] in
                    self?.presentIfNeeded()
                }
                return
            }
            let picker = CNContactPickerViewController()
            picker.delegate = self
            picker.displayedPropertyKeys = [
                CNContactGivenNameKey,
                CNContactMiddleNameKey,
                CNContactFamilyNameKey,
                CNContactOrganizationNameKey,
                CNContactEmailAddressesKey,
                CNContactPhoneNumbersKey
            ]
            picker.predicateForEnablingContact = NSPredicate(
                format: "phoneNumbers.@count > 0 OR emailAddresses.@count > 0"
            )
            picker.predicateForSelectionOfProperty = NSPredicate(
                format: "key == %@ OR key == %@",
                CNContactPhoneNumbersKey,
                CNContactEmailAddressesKey
            )
            isShowingPicker = true
            presenter.present(picker, animated: true)
        }

        private func presentationAnchor() -> UIViewController? {
            var current: UIViewController? = host
            while let parent = current?.parent {
                current = parent
            }
            guard let current, current.view.window != nil else { return nil }
            return current
        }

        private func finishPresented() {
            isShowingPicker = false
            DispatchQueue.main.async {
                self.isPresented.wrappedValue = false
            }
        }

        func contactPicker(_ picker: CNContactPickerViewController, didSelect contactProperty: CNContactProperty) {
            finishPresented()
            let picked = Self.pickedContact(from: contactProperty)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                if let picked {
                    self.onPick(picked)
                } else {
                    self.onCancel()
                }
            }
        }

        func contactPickerDidCancel(_ picker: CNContactPickerViewController) {
            finishPresented()
            DispatchQueue.main.async { self.onCancel() }
        }

        private static func pickedContact(from property: CNContactProperty) -> PickedContact? {
            guard let picked = PickedContact(contact: property.contact) else { return nil }
            switch property.key {
            case CNContactPhoneNumbersKey:
                guard let phone = (property.value as? CNPhoneNumber)?.stringValue else { return picked.resolvedContact() ?? picked }
                return picked.selectingPhone(phone)
            case CNContactEmailAddressesKey:
                let email: String
                if let value = property.value as? String {
                    email = value
                } else if let value = property.value as? NSString {
                    email = value as String
                } else {
                    return picked.resolvedContact() ?? picked
                }
                return picked.selectingEmail(email)
            default:
                return picked.resolvedContact() ?? picked
            }
        }
    }
}

struct PickedContact: Identifiable, Hashable {
    let id: String
    var name: String
    var email: String
    var phone: String
    var emails: [String]
    var phones: [String]
    var isMe: Bool = false
    var personID: UUID? = nil
    var didInvite: Bool = false

    var contactSummary: String {
        var seen = Set<String>()
        var parts: [String] = []
        for value in [email, phone] + emails + phones {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, seen.insert(trimmed.lowercased()).inserted else { continue }
            parts.append(trimmed)
        }
        return parts.joined(separator: " · ")
    }

    var needsContactChoice: Bool {
        uniquePhones.count > 1 || uniqueEmails.count > 1
    }

    var uniquePhones: [String] {
        var seen = Set<String>()
        var result: [String] = []
        for raw in [phone] + phones {
            guard let key = ContactUniqueness.phoneKey(raw), seen.insert(key).inserted else { continue }
            result.append(raw)
        }
        return result
    }

    var uniqueEmails: [String] {
        var seen = Set<String>()
        var result: [String] = []
        for raw in [email] + emails {
            guard let key = ContactUniqueness.emailKey(raw), seen.insert(key).inserted else { continue }
            result.append(raw)
        }
        return result
    }

    func selectingPhone(_ raw: String) -> PickedContact {
        var next = self
        let keptEmail = uniqueEmails.count == 1 ? uniqueEmails[0] : ""
        next.setEnteredContact(email: keptEmail, phone: raw)
        return next
    }

    func selectingEmail(_ raw: String) -> PickedContact {
        var next = self
        let keptPhone = uniquePhones.count == 1 ? uniquePhones[0] : ""
        next.setEnteredContact(email: raw, phone: keptPhone)
        return next
    }

    /// True when this person already has a usable phone or email, so we should not open the add-phone screen.
    var hasUsableContactInfo: Bool {
        resolvedContact() != nil
    }

    /// Fill in the first usable phone/email from the contact-card lists.
    func resolvedContact() -> PickedContact? {
        var next = self
        if ContactUniqueness.phoneKey(next.phone) == nil {
            next.phone = next.phones.first { ContactUniqueness.phoneKey($0) != nil } ?? ""
        }
        if ContactUniqueness.emailKey(next.email) == nil {
            next.email = next.emails.first { ContactUniqueness.emailKey($0) != nil } ?? ""
        }
        guard ContactUniqueness.phoneKey(next.phone) != nil || ContactUniqueness.emailKey(next.email) != nil else {
            return nil
        }
        return next
    }

    init(
        id: String = UUID().uuidString,
        name: String,
        email: String = "",
        phone: String = "",
        emails: [String] = [],
        phones: [String] = [],
        isMe: Bool = false,
        personID: UUID? = nil,
        didInvite: Bool = false
    ) {
        self.id = id
        self.name = name
        self.email = email
        self.phone = phone
        self.emails = emails
        self.phones = phones
        self.isMe = isMe
        self.personID = personID
        self.didInvite = didInvite
        syncContactLists()
    }

    mutating func setEnteredContact(email: String, phone: String) {
        self.email = email.trimmingCharacters(in: .whitespacesAndNewlines)
        self.phone = phone.trimmingCharacters(in: .whitespacesAndNewlines)
        emails = self.email.isEmpty ? [] : [self.email]
        phones = self.phone.isEmpty ? [] : [self.phone]
    }

    private mutating func syncContactLists() {
        if emails.isEmpty, !email.isEmpty {
            emails = [email]
        } else if !email.isEmpty, !emails.contains(email) {
            emails.insert(email, at: 0)
        }
        if phones.isEmpty, !phone.isEmpty {
            phones = [phone]
        } else if !phone.isEmpty, !phones.contains(phone) {
            phones.insert(phone, at: 0)
        }
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

        let emails: [String]
        if contact.isKeyAvailable(CNContactEmailAddressesKey) {
            emails = contact.emailAddresses.map { $0.value as String }.filter { !$0.isEmpty }
        } else {
            emails = []
        }
        let phones: [String]
        if contact.isKeyAvailable(CNContactPhoneNumbersKey) {
            phones = contact.phoneNumbers.map(\.value.stringValue).filter { !$0.isEmpty }
        } else {
            phones = []
        }
        if name.isEmpty {
            name = emails.first ?? phones.first ?? ""
        }
        guard !name.isEmpty else { return nil }

        self.id = isMe ? "me" : contact.identifier
        self.name = name
        self.email = emails.first ?? ""
        self.phone = phones.first ?? ""
        self.emails = emails
        self.phones = phones
        self.isMe = isMe
        self.personID = nil
        self.didInvite = false
    }
}

enum ContactUniqueness {
    static func phoneKey(_ raw: String) -> String? {
        let digits = usPhoneDigits(raw)
        return digits.count == 10 ? digits : nil
    }

    static func emailKey(_ raw: String) -> String? {
        let email = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return isValidEmail(email) ? email : nil
    }

    static func ownerName(
        usingPhone raw: String,
        in people: [PickedContact],
        excludingID: String? = nil
    ) -> String? {
        guard let key = phoneKey(raw) else { return nil }
        return people.first { person in
            guard !matches(person, excludingID) else { return false }
            return phoneKey(person.phone) == key
                || person.phones.contains { phoneKey($0) == key }
        }?.name
    }

    static func ownerName(
        usingEmail raw: String,
        in people: [PickedContact],
        excludingID: String? = nil
    ) -> String? {
        guard let key = emailKey(raw) else { return nil }
        return people.first { person in
            guard !matches(person, excludingID) else { return false }
            return emailKey(person.email) == key
                || person.emails.contains { emailKey($0) == key }
        }?.name
    }

    static func duplicateMessage(for contact: PickedContact, in people: [PickedContact]) -> String? {
        if let name = ownerName(usingPhone: contact.phone, in: people, excludingID: contact.id) {
            return "\(name) already uses this phone number. Enter a different number."
        }
        if let name = ownerName(usingEmail: contact.email, in: people, excludingID: contact.id) {
            return "\(name) already uses this email. Enter a different email."
        }
        return nil
    }

    private static func matches(_ person: PickedContact, _ excludingID: String?) -> Bool {
        guard let excludingID, !excludingID.isEmpty else { return false }
        return person.id == excludingID || person.personID?.uuidString == excludingID
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
        var seen = Set<String>()
        var results: [PickedContact] = []

        func append(_ contacts: [CNContact]) {
            for contact in contacts {
                guard let picked = PickedContact(contact: contact), seen.insert(picked.id).inserted else { continue }
                results.append(picked)
            }
        }

        append((try? store.unifiedContacts(
            matching: CNContact.predicateForContacts(matchingName: trimmed),
            keysToFetch: keys
        )) ?? [])

        if trimmed.contains("@") {
            append((try? store.unifiedContacts(
                matching: CNContact.predicateForContacts(matchingEmailAddress: trimmed),
                keysToFetch: keys
            )) ?? [])
        }

        let digits = trimmed.filter(\.isNumber)
        if digits.count >= 3 {
            let request = CNContactFetchRequest(keysToFetch: keys)
            try? store.enumerateContacts(with: request) { contact, stop in
                let phones = contact.phoneNumbers.map { $0.value.stringValue.filter(\.isNumber) }
                if phones.contains(where: { $0.contains(digits) }) {
                    append([contact])
                }
                if results.count >= 40 { stop.pointee = true }
            }
        }
        return results
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
                .textInputAutocapitalization(.never)
                .keyboardType(.default)
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

struct ContactNumberChoiceView: View {
    let contact: PickedContact
    var onCancel: () -> Void
    var onChoose: (PickedContact) -> Void

    var body: some View {
        NavigationStack {
            List {
                if !contact.uniquePhones.isEmpty {
                    Section("Phone numbers") {
                        ForEach(contact.uniquePhones, id: \.self) { phone in
                            Button {
                                onChoose(contact.selectingPhone(phone))
                            } label: {
                                Text(formattedUSPhone(phone))
                                    .foregroundStyle(.primary)
                            }
                            .accessibilityIdentifier("chooseContactPhone")
                        }
                    }
                }
                if !contact.uniqueEmails.isEmpty {
                    Section("Emails") {
                        ForEach(contact.uniqueEmails, id: \.self) { email in
                            Button {
                                onChoose(contact.selectingEmail(email))
                            } label: {
                                Text(email)
                                    .foregroundStyle(.primary)
                            }
                            .accessibilityIdentifier("chooseContactEmail")
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(contact.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onCancel() }
                }
            }
        }
        .presentationDetents(contact.uniquePhones.count + contact.uniqueEmails.count > 4 ? [.medium, .large] : [.medium])
        .tint(AppTheme.teal)
    }
}

/// Search Contacts (if allowed) or saved friends. "Me" is added to the group in the background, not shown here.
struct FriendSearchPicker: View {
    let contactsAllowed: Bool
    let savedFriends: [PickedContact]
    /// `nil` means unlimited extra people. `1` is used when creating a one-to-one split.
    var selectionLimit: Int?
    var onPick: ([PickedContact]) -> Void
    var onRemoveExisting: (PickedContact) -> Void = { _ in }
    var onContactsAccessGranted: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var query = ""
    @State private var selected: [PickedContact] = []
    @State private var usingContacts: Bool
    @State private var friendToRemove: PickedContact?
    @State private var pendingAdd: PickedContact?
    @State private var detailsContact: PickedContact?
    @State private var numberChoiceContact: PickedContact?
    @State private var duplicateWarning: String?
    @State private var showingSystemPicker = false
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
        existingPeople: [PickedContact] = [],
        selectionLimit: Int? = nil,
        onPick: @escaping ([PickedContact]) -> Void,
        onRemoveExisting: @escaping (PickedContact) -> Void = { _ in },
        onContactsAccessGranted: @escaping () -> Void = {}
    ) {
        self.contactsAllowed = contactsAllowed
        self.savedFriends = savedFriends
        self.selectionLimit = selectionLimit
        self.onPick = onPick
        self.onRemoveExisting = onRemoveExisting
        self.onContactsAccessGranted = onContactsAccessGranted
        let start = existingPeople.filter {
            !$0.isMe && FriendPairing.isUsableName($0.name)
        }
        _selected = State(initialValue: start)
        _usingContacts = State(initialValue: contactsAllowed)
    }

    private var placeholder: String {
        usingContacts ? "Search name, email, or phone" : "Search saved friends"
    }

    private var typedNameToAdd: String? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 1 else { return nil }
        guard FriendPairing.isUsableName(trimmed) else { return nil }
        let alreadySelected = selected.contains {
            $0.name.localizedCaseInsensitiveCompare(trimmed) == .orderedSame
        }
        guard !alreadySelected else { return nil }
        if savedContact(named: trimmed) != nil { return nil }
        return trimmed
    }

    private func savedContact(named name: String) -> PickedContact? {
        savedFriends.first {
            $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame
        } ?? KnownFriendsStore.contact(named: name)
    }

    private func contactForTypedName(_ name: String) -> PickedContact {
        savedContact(named: name) ?? PickedContact(name: name)
    }

    private var currentOtherFriend: PickedContact? {
        selected.first { !$0.isMe }
    }

    private func requestAdd(_ friend: PickedContact) {
        let alreadySelected = selected.contains {
            $0.id == friend.id
                || $0.personID != nil && $0.personID == friend.personID
                || $0.name.localizedCaseInsensitiveCompare(friend.name) == .orderedSame
        }
        guard !alreadySelected else { return }
        if friend.needsContactChoice {
            numberChoiceContact = friend
            return
        }
        if let ready = friend.resolvedContact() {
            commitAdd(ready)
            return
        }
        detailsContact = friend
    }

    private func commitAdd(_ friend: PickedContact) {
        if let message = ContactUniqueness.duplicateMessage(for: friend, in: selected) {
            duplicateWarning = message
            return
        }
        if canAddMore {
            KnownFriendsStore.remember([friend])
            selected.append(friend)
            query = ""
            finishIfSingleSelection()
            return
        }
        if selectionLimit == 1 {
            pendingAdd = friend
        }
    }

    private func confirmReplace() {
        guard let pendingAdd else { return }
        selected.removeAll { !$0.isMe }
        KnownFriendsStore.remember([pendingAdd])
        selected.append(pendingAdd)
        query = ""
        self.pendingAdd = nil
        finishIfSingleSelection()
    }

    private func finishIfSingleSelection() {
        guard selectionLimit == 1, otherSelectedCount >= 1 else { return }
        onPick(selected)
        dismiss()
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
            saved = savedFriends.filter {
                $0.name.localizedStandardContains(trimmed)
                    || $0.email.localizedStandardContains(trimmed)
                    || $0.phone.localizedStandardContains(trimmed)
                    || $0.contactSummary.localizedStandardContains(trimmed)
            }
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
                    if !selected.isEmpty {
                        Section("Added to split") {
                            ForEach(selected) { friend in
                                addedFriendRow(friend)
                            }
                        }
                    }

                    if let typedName = typedNameToAdd {
                        Section {
                            Button {
                                requestAdd(contactForTypedName(typedName))
                            } label: {
                                HStack(spacing: 14) {
                                    Image(systemName: "person.badge.plus")
                                        .font(.title2)
                                        .foregroundStyle(.secondary)
                                        .frame(width: 32)
                                    Text("Add “\(typedName)” to Free Split")
                                        .foregroundStyle(.primary)
                                    Spacer()
                                }
                            }
                            .accessibilityIdentifier("addTypedName")
                        }
                    }

                    Section {
                        Button {
                            showingSystemPicker = true
                        } label: {
                            Label("Choose a contact", systemImage: "person.crop.circle.badge.plus")
                        }
                        .accessibilityIdentifier("chooseOneContact")
                    } footer: {
                        Text("Picks one person from your phone. This works even if Contacts access is Off.")
                    }

                    Section(usingContacts ? "From your contacts" : "Saved friends") {
                        if results.isEmpty {
                            Text(emptyResultsText)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(results) { friend in
                                friendRow(friend, isSelected: false) {
                                    requestAdd(friend)
                                }
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
            .navigationTitle("Add friends")
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
            .background {
                SystemContactPicker(
                    isPresented: $showingSystemPicker,
                    onPick: { contact in
                        requestAdd(contact)
                    },
                    onCancel: {
                        showingSystemPicker = false
                    }
                )
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
            }
            .sheet(item: $numberChoiceContact) { friend in
                ContactNumberChoiceView(
                    contact: friend,
                    onCancel: { numberChoiceContact = nil },
                    onChoose: { chosen in
                        numberChoiceContact = nil
                        commitAdd(chosen)
                    }
                )
            }
            .confirmationDialog(
                confirmationTitle,
                isPresented: Binding(
                    get: { friendToRemove != nil || pendingAdd != nil },
                    set: { if !$0 {
                        friendToRemove = nil
                        pendingAdd = nil
                    } }
                ),
                titleVisibility: .visible
            ) {
                if friendToRemove != nil {
                    Button("Delete", role: .destructive) {
                        removeFriendFromSelection()
                    }
                }
                if pendingAdd != nil {
                    Button("Replace") {
                        confirmReplace()
                    }
                }
                Button("Cancel", role: .cancel) {
                    friendToRemove = nil
                    pendingAdd = nil
                }
            } message: {
                if friendToRemove != nil {
                    Text("They will be removed from this split.")
                } else if let current = currentOtherFriend, let pending = pendingAdd {
                    Text("This split can have one friend. \(pending.name) will replace \(current.name).")
                } else {
                    Text("This split can have one friend. Adding someone new replaces the person already selected.")
                }
            }
            .sheet(item: $detailsContact) { friend in
                NavigationStack {
                    AddFriendDetailsView(
                        initial: friend,
                        occupiedPeople: selected,
                        onCancel: { detailsContact = nil },
                        onNext: { completed in
                            detailsContact = nil
                            commitAdd(completed)
                        }
                    )
                }
                .ignoresSafeArea(.keyboard)
                .tint(AppTheme.teal)
            }
            .alert("Number already used", isPresented: Binding(
                get: { duplicateWarning != nil },
                set: { if !$0 { duplicateWarning = nil } }
            )) {
                Button("OK", role: .cancel) { duplicateWarning = nil }
            } message: {
                Text(duplicateWarning ?? "")
            }
        }
        .tint(AppTheme.teal)
    }

    private var confirmationTitle: String {
        if let friendToRemove {
            return "Delete \(friendToRemove.name)?"
        }
        if pendingAdd != nil {
            return "Replace \(currentOtherFriend?.name ?? "this person")?"
        }
        return "Please confirm"
    }

    private func removeFriendFromSelection() {
        guard let friendToRemove else { return }
        selected.removeAll { $0.id == friendToRemove.id || $0.personID == friendToRemove.personID }
        if friendToRemove.personID != nil {
            onRemoveExisting(friendToRemove)
        }
        self.friendToRemove = nil
    }

    private var emptyResultsText: String {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return usingContacts
                ? "Search to add other friends, or choose one contact."
                : "No other saved friends yet. Choose a contact, or allow Contacts in Settings to search."
        }
        return "No matches for “\(trimmed)”."
    }

    private func addedFriendRow(_ friend: PickedContact) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(friend.name)
                    if friend.isMe {
                        Text("You")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(AppTheme.teal.opacity(0.18), in: Capsule())
                            .foregroundStyle(AppTheme.teal)
                    }
                }
                if !friend.contactSummary.isEmpty {
                    Text(friend.contactSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if friend.isMe {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(AppTheme.teal)
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            if !friend.isMe {
                Button("Delete", role: .destructive) {
                    friendToRemove = friend
                }
            }
        }
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
                    if !friend.contactSummary.isEmpty {
                        Text(friend.contactSummary)
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
