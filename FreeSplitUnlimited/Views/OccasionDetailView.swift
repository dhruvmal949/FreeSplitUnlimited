//
//  OccasionDetailView.swift
//  FreeSplitUnlimited
//

import SwiftUI
import SwiftData
import UIKit

struct OccasionDetailView: View {
    @Bindable var occasion: Occasion
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var showingAddExpense = false
    @State private var showingAddMember = false
    @State private var editingExpenseID: UUID?
    @State private var selectedTab = 0
    @State private var sharePayload: ActivitySharePayload?
    @State private var shareAlert: String?
    @State private var contactsAllowed = ContactAuthorization.canUseSystemPicker
    @State private var isEditingName = false
    @State private var draftName = ""
    @State private var showingRenameGroup = false
    @State private var inviteContacts: [PickedContact] = []
    @State private var pendingInviteContacts: [PickedContact] = []
    @State private var personToRemove: Person?
    @FocusState private var nameFieldFocused: Bool

    private var sortedExpenses: [Expense] {
        var seen = Set<UUID>()
        return occasion.expenses
            .filter { seen.insert($0.id).inserted }
            .sorted { $0.date > $1.date }
    }

    private var balances: [PersonBalance] {
        BalanceCalculator.balances(for: occasion)
    }

    private var settlements: [Settlement] {
        BalanceCalculator.settlements(for: occasion)
    }

    private var isAlone: Bool {
        occasion.uniqueMembers.count < 2
    }

    var body: some View {
        VStack(spacing: 0) {
            heroHeader
            pillBar

            Group {
                if isAlone, selectedTab == 0 {
                    aloneInviteCard
                } else {
                    switch selectedTab {
                    case 1:
                        balancesTab
                    case 2:
                        whoIsOwedTab
                    case 3:
                        totalTab
                    default:
                        expensesTab
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(.systemBackground))
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
        .toolbarBackground(.hidden, for: .navigationBar)
        .sheet(item: $sharePayload) { payload in
            ActivityShareSheet(payload: payload)
        }
        .alert("Couldn't Share", isPresented: Binding(
            get: { shareAlert != nil },
            set: { if !$0 { shareAlert = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(shareAlert ?? "")
        }
        .safeAreaInset(edge: .bottom) {
            HStack {
                Spacer()
                Button {
                    showingAddExpense = true
                } label: {
                    Label("Add expense", systemImage: "list.bullet.rectangle")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.teal)
                .disabled(isAlone)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
        .avoidsMainTabBar()
        .sheet(isPresented: $showingAddExpense) {
            AddExpenseView(occasion: occasion)
        }
        .sheet(isPresented: Binding(
            get: { editingExpenseID != nil },
            set: { if !$0 { editingExpenseID = nil } }
        )) {
            if let editingExpenseID,
               let expense = occasion.expenses.first(where: { $0.id == editingExpenseID }) {
                AddExpenseView(occasion: occasion, expenseToEdit: expense)
            }
        }
        .sheet(isPresented: $showingAddMember, onDismiss: {
            if showingRenameGroup { return }
            presentPendingInvite()
        }) {
            FriendSearchPicker(
                contactsAllowed: contactsAllowed,
                savedFriends: KnownFriendsStore.previouslyUsedFriends(from: modelContext),
                existingPeople: occasion.uniqueMembers
                    .filter { FriendPairing.isUsableName($0.name) }
                    .map(\.asPickedContact),
                onPick: { contacts in
                    addMembers(contacts)
                },
                onRemoveExisting: { contact in
                    removeExistingMember(contact)
                },
                onContactsAccessGranted: {
                    contactsAllowed = true
                }
            )
        }
        .friendInvite(
            contacts: $inviteContacts,
            splitName: occasion.displayName,
            onSent: markInviteSent
        )
        .alert("Name this group", isPresented: $showingRenameGroup) {
            TextField("Group name", text: $draftName)
            Button("Save") {
                saveEditedName()
                presentPendingInvite()
            }
            Button("Later", role: .cancel) {
                presentPendingInvite()
            }
        } message: {
            Text("You can name this group now, or tap the title anytime to rename it.")
        }
        .confirmationDialog(
            "Remove \(personToRemove?.name ?? "this person")?",
            isPresented: Binding(
                get: { personToRemove != nil },
                set: { if !$0 { personToRemove = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let personToRemove {
                    modelContext.delete(personToRemove)
                    occasion.touch()
                    modelContext.persist()
                }
                personToRemove = nil
            }
            Button("Cancel", role: .cancel) {
                personToRemove = nil
            }
        } message: {
            Text("They will be removed from this split.")
        }
        .onChange(of: nameFieldFocused) { _, focused in
            if !focused, isEditingName {
                saveEditedName()
            }
        }
    }

    private var heroHeader: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                headerCircleButton(systemImage: "chevron.left", label: "Back to groups") {
                    dismiss()
                }
                Spacer()
                headerCircleButton(systemImage: "person.badge.plus", label: "Add people") {
                    Task { await presentMemberPicker() }
                }
                headerCircleButton(systemImage: "square.and.arrow.up", label: "Share group") {
                    shareSplit()
                }
                headerCircleButton(systemImage: "gearshape.fill", label: "Group settings") {
                    NotificationCenter.default.post(name: .freeSplitOpenGroupSettings, object: occasion.id)
                }
            }

            if isEditingName {
                TextField("Group name", text: $draftName)
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .foregroundStyle(.white)
                    .tint(.white)
                    .focused($nameFieldFocused)
                    .submitLabel(.done)
                    .onSubmit { saveEditedName() }
                    .accessibilityIdentifier("groupNameTitleField")
            } else {
                Button {
                    beginEditingName()
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(occasion.displayName)
                            .font(.system(.largeTitle, design: .rounded, weight: .bold))
                            .foregroundStyle(.white)
                            .lineLimit(2)
                        Image(systemName: "pencil")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.85))
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Edit group name")
                .accessibilityIdentifier("editGroupName")
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            ZStack {
                LinearGradient(
                    colors: [AppTheme.deepTeal, AppTheme.teal, AppTheme.brightTeal],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                WaveShape()
                    .fill(Color.white.opacity(0.08))
                    .frame(height: 90)
                    .frame(maxHeight: .infinity, alignment: .bottom)
            }
            .ignoresSafeArea(edges: .top)
        }
    }

    private func headerCircleButton(systemImage: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(AppTheme.deepTeal)
                .frame(width: 36, height: 36)
                .background(.white, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityIdentifier(label)
    }

    private var pillBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                pill("Expenses", tag: 0)
                pill("Settle up", tag: 1)
                pill("Balances", tag: 2)
                pill("Total", tag: 3)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Color(.systemBackground))
    }

    private func pill(_ title: String, tag: Int) -> some View {
        Button {
            selectedTab = tag
        } label: {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .foregroundStyle(selectedTab == tag ? Color.white : Color.primary)
                .background(
                    selectedTab == tag ? AppTheme.teal : Color.clear,
                    in: Capsule()
                )
                .overlay {
                    Capsule()
                        .stroke(Color.secondary.opacity(0.28), lineWidth: selectedTab == tag ? 0 : 1)
                }
        }
        .buttonStyle(.plain)
    }

    private var aloneInviteCard: some View {
        VStack {
            VStack(spacing: 16) {
                Text("You're the only one here!")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Button {
                    Task { await presentMemberPicker() }
                } label: {
                    Label("Add people", systemImage: "person.badge.plus")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.teal)

                Button {
                    shareSplit()
                } label: {
                    Text("Share a link")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.bordered)
                .tint(AppTheme.teal)
            }
            .padding(20)
            .frame(maxWidth: .infinity)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .padding(.horizontal, 20)
            .padding(.top, 8)

            Spacer()
        }
    }

    private var expensesTab: some View {
        Group {
            if sortedExpenses.isEmpty, !occasion.isOneToOne {
                ContentUnavailableView(
                    "No Expenses",
                    systemImage: "cart",
                    description: Text("Tap Add expense to log something someone paid for.")
                )
            } else {
                List {
                    if occasion.isOneToOne {
                        Section {
                            Button {
                                Task { await presentMemberPicker() }
                            } label: {
                                Label("Add people", systemImage: "person.badge.plus")
                                    .font(.headline)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                            }
                            .listRowBackground(AppTheme.teal)
                            .foregroundStyle(.white)
                        } footer: {
                            Text("This split is just the two of you. Adding more people saves it as a group.")
                        }
                    }

                    if sortedExpenses.isEmpty {
                        Text("Tap Add expense to log something someone paid for.")
                            .foregroundStyle(.secondary)
                            .listRowBackground(Color.clear)
                    } else {
                        ForEach(sortedExpenses, id: \.id) { expense in
                            Button {
                                editingExpenseID = expense.id
                            } label: {
                                ExpenseRowView(expense: expense)
                            }
                            .buttonStyle(.plain)
                            .listRowBackground(Color.white.opacity(0.78))
                        }
                        .onDelete(perform: deleteExpenses)
                    }
                }
                .freeSplitListStyle()
            }
        }
    }

    private var balancesTab: some View {
        List {
            Section("Who is owed") {
                ForEach(balances) { balance in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(balance.person.name)
                            if balance.person.hasContactInfo {
                                Text([balance.person.email, balance.person.phone].filter { !$0.isEmpty }.joined(separator: " · "))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Text(balanceLabel(for: balance.net))
                            .foregroundStyle(balanceColor(for: balance.net))
                            .fontWeight(.semibold)
                    }
                    .listRowBackground(Color.white.opacity(0.78))
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        if FriendPairing.isUsableName(balance.person.name) {
                            Button("Delete", role: .destructive) {
                                personToRemove = balance.person
                            }
                        }
                    }
                }
            }

            Section {
                if settlements.isEmpty {
                    Text("Everyone is settled up.")
                        .foregroundStyle(.secondary)
                        .listRowBackground(Color.white.opacity(0.78))
                } else {
                    ForEach(settlements) { settlement in
                        HStack(alignment: .firstTextBaseline) {
                            Text("\(settlement.from.name) → \(settlement.to.name)")
                            Spacer()
                            Text(CurrencyFormat.string(from: settlement.amount))
                                .fontWeight(.semibold)
                        }
                        .listRowBackground(Color.white.opacity(0.78))
                    }
                }
            } header: {
                Text("Settle up")
            } footer: {
                Text("Suggested payments so everyone is even.")
            }
        }
        .freeSplitListStyle()
    }

    private var whoIsOwedTab: some View {
        List {
            Section("Who is owed") {
                ForEach(balances) { balance in
                    HStack {
                        Text(balance.person.name)
                        Spacer()
                        Text(balanceLabel(for: balance.net))
                            .foregroundStyle(balanceColor(for: balance.net))
                            .fontWeight(.semibold)
                    }
                    .listRowBackground(Color.white.opacity(0.78))
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        if FriendPairing.isUsableName(balance.person.name) {
                            Button("Delete", role: .destructive) {
                                personToRemove = balance.person
                            }
                        }
                    }
                }
            }
        }
        .freeSplitListStyle()
    }

    private var totalTab: some View {
        VStack(spacing: 8) {
            Text(CurrencyFormat.string(from: occasion.totalSpent))
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
            Text("\(occasion.kind.title) · \(occasion.expenses.count) expense\(occasion.expenses.count == 1 ? "" : "s")")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if !occasion.note.isEmpty {
                Text(occasion.note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.top, 28)
        .frame(maxWidth: .infinity)
    }

    @MainActor
    private func presentMemberPicker() async {
        await ContactAuthorization.requestIfNeeded()
        contactsAllowed = ContactAuthorization.canUseSystemPicker
        showingAddMember = true
    }

    private func addMembers(_ contacts: [PickedContact]) {
        let existing = Set(occasion.uniqueMembers.map { $0.name.lowercased() })
        var addedContacts: [PickedContact] = []
        let wasOneToOne = occasion.isOneToOne
        for contact in contacts where !contact.isMe {
            let name = contact.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, !existing.contains(name.lowercased()) else { continue }
            let occupied = occasion.uniqueMembers.map(\.asPickedContact) + addedContacts
            if ContactUniqueness.duplicateMessage(for: contact, in: occupied) != nil {
                continue
            }
            let resolved = contact.resolvedContact() ?? contact
            let person = Person(name: name, email: resolved.email, phone: resolved.phone)
            person.occasion = occasion
            modelContext.insert(person)
            person.setContact(email: resolved.email, phone: resolved.phone)
            if !occasion.members.contains(where: { $0.id == person.id }) {
                occasion.members.append(person)
            }
            addedContacts.append(person.asPickedContact)
        }
        guard !addedContacts.isEmpty else { return }
        occasion.touch()
        occasion.promoteToGroupIfNeeded()
        modelContext.persist()
        pendingInviteContacts = occasion.uniqueMembers
            .map(\.asPickedContact)
            .filter { FriendInvite.needsInvite($0) }
        if wasOneToOne, !occasion.isOneToOne {
            draftName = occasion.name
            showingRenameGroup = true
        }
    }

    private func presentPendingInvite() {
        let contacts = pendingInviteContacts
        pendingInviteContacts = []
        guard !contacts.isEmpty else { return }
        inviteContacts = contacts
    }

    private func beginEditingName() {
        draftName = occasion.name
        isEditingName = true
        nameFieldFocused = true
    }

    private func saveEditedName() {
        let trimmed = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        if occasion.name != trimmed {
            occasion.name = trimmed
            occasion.touch()
            modelContext.persist()
        }
        isEditingName = false
        nameFieldFocused = false
    }

    private func markInviteSent(_ id: UUID) {
        guard let person = occasion.uniqueMembers.first(where: { $0.id == id }) else { return }
        person.didInvite = true
        occasion.touch()
        modelContext.persist()
    }

    private func removeExistingMember(_ contact: PickedContact) {
        let target = occasion.uniqueMembers.first { person in
            if let id = contact.personID { return person.id == id }
            return person.name.localizedCaseInsensitiveCompare(contact.name) == .orderedSame
                && FriendPairing.isUsableName(person.name)
        }
        guard let target else { return }
        modelContext.delete(target)
        occasion.touch()
        modelContext.persist()
    }

    private func balanceLabel(for net: Decimal) -> String {
        if net == 0 {
            return "Settled"
        } else if net > 0 {
            return "gets \(CurrencyFormat.string(from: net))"
        } else {
            return "owes \(CurrencyFormat.string(from: -net))"
        }
    }

    private func balanceColor(for net: Decimal) -> Color {
        AppTheme.balanceColor(for: net)
    }

    private func deleteExpenses(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(sortedExpenses[index])
        }
        occasion.touch()
        modelContext.persist()
    }

    private func deleteMembers(at offsets: IndexSet) {
        let sorted = occasion.sortedMembers()
        for index in offsets {
            modelContext.delete(sorted[index])
        }
        occasion.touch()
        modelContext.persist()
    }

    private func shareSplit() {
        Task {
            let payload = await SplitShare.activityPayload(for: occasion)
            if payload.link == nil, payload.fileURL == nil {
                shareAlert = "Couldn't create a share link for this group."
                return
            }
            sharePayload = payload
        }
    }
}

private struct WaveShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let midY = rect.height * 0.45
        path.move(to: CGPoint(x: 0, y: midY))
        path.addCurve(
            to: CGPoint(x: rect.width, y: midY * 0.7),
            control1: CGPoint(x: rect.width * 0.3, y: midY - 18),
            control2: CGPoint(x: rect.width * 0.7, y: midY + 22)
        )
        path.addLine(to: CGPoint(x: rect.width, y: rect.height))
        path.addLine(to: CGPoint(x: 0, y: rect.height))
        path.closeSubpath()
        return path
    }
}

private struct ExpenseRowView: View {
    let expense: Expense

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(expense.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Spacer()
                    Text(CurrencyFormat.string(from: expense.amount))
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                }

                Text("Paid by \(expense.paidBy?.name ?? "Unknown")")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if !expense.uniqueParticipants.isEmpty {
                    Text(expense.splitSummary)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
                .padding(.top, 4)
        }
        .padding(.vertical, 2)
    }
}
