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

    @State private var showingAddExpense = false
    @State private var showingAddMember = false
    @State private var editingFriendID: UUID?
    @State private var editingExpenseID: UUID?
    @State private var selectedTab = 0
    @State private var sharePayload: SharePayload?
    @State private var shareAlert: String?

    private struct SharePayload: Identifiable {
        let id = UUID()
        let url: URL
    }

    private var sortedExpenses: [Expense] {
        occasion.expenses.sorted { $0.date > $1.date }
    }

    private var balances: [PersonBalance] {
        BalanceCalculator.balances(for: occasion)
    }

    private var settlements: [Settlement] {
        BalanceCalculator.settlements(for: occasion)
    }

    var body: some View {
        VStack(spacing: 0) {
            summaryHeader

            Picker("Section", selection: $selectedTab) {
                Text("Expenses").tag(0)
                Text("Balances").tag(1)
                Text("Friends").tag(2)
            }
            .pickerStyle(.segmented)
            .padding()

            Group {
                switch selectedTab {
                case 0:
                    expensesTab
                case 1:
                    balancesTab
                default:
                    friendsTab
                }
            }
        }
        .navigationTitle(occasion.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    shareSplit()
                } label: {
                    Label("Share Split", systemImage: "square.and.arrow.up")
                }
            }
        }
        .freeSplitBackground()
        .sheet(item: $sharePayload) { payload in
            ShareSheet(items: [payload.url])
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
            Button {
                showingAddExpense = true
            } label: {
                Text("Add Expense")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .tint(AppTheme.teal)
            .disabled(occasion.uniqueMembers.count < 2)
            .padding(.horizontal)
            .padding(.bottom, 8)
            .background(.ultraThinMaterial)
        }
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
        .sheet(isPresented: $showingAddMember) {
            EditFriendView(occasion: occasion)
        }
        .sheet(isPresented: Binding(
            get: { editingFriendID != nil },
            set: { if !$0 { editingFriendID = nil } }
        )) {
            if let editingFriendID,
               let person = occasion.uniqueMembers.first(where: { $0.id == editingFriendID }) {
                EditFriendView(occasion: occasion, person: person)
            }
        }
        .onAppear {
            occasion.deduplicateRelationships()
        }
    }

    private var summaryHeader: some View {
        VStack(spacing: 4) {
            Text(CurrencyFormat.string(from: occasion.totalSpent))
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
            Text("total across \(occasion.expenses.count) expense\(occasion.expenses.count == 1 ? "" : "s")")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if !occasion.note.isEmpty {
                Text(occasion.note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
            }

            Button {
                shareSplit()
            } label: {
                Label("Share Offline (AirDrop)", systemImage: "wifi.slash")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.bordered)
            .tint(AppTheme.teal)
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(AppTheme.heroCardGradient)
    }

    private var expensesTab: some View {
        Group {
            if sortedExpenses.isEmpty {
                ContentUnavailableView(
                    "No Expenses",
                    systemImage: "cart",
                    description: Text("Tap Add Expense below to log something someone paid for. Tap an expense later to edit it.")
                )
            } else {
                List {
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
                .freeSplitListStyle()
            }
        }
    }

    private var balancesTab: some View {
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

    private var friendsTab: some View {
        List {
            Section {
                ForEach(occasion.sortedMembers(), id: \.id) { person in
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(person.name)
                                .font(.headline)
                                .foregroundStyle(.primary)

                            FriendContactActionsView(person: person, splitName: occasion.name)
                        }

                        Spacer(minLength: 8)

                        Button("Edit") {
                            editingFriendID = person.id
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.teal)
                    }
                    .padding(.vertical, 4)
                    .listRowBackground(Color.white.opacity(0.78))
                }
                .onDelete(perform: deleteMembers)
            } footer: {
                Text("Tap Send Invite, Email, or Text — then tap Send in Mail/Messages. Saving a friend's contact does not auto-send.")
            }

            Section {
                Button {
                    showingAddMember = true
                } label: {
                    Text("Add Friend")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .listRowBackground(AppTheme.teal)
                .foregroundStyle(.white)
            }
        }
        .freeSplitListStyle()
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
        if net > 0 { return .green }
        if net < 0 { return .orange }
        return .secondary
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

    /// AirDrop / Files / Messages — works without internet (AirDrop uses Bluetooth + peer Wi‑Fi).
    private func shareSplit() {
        do {
            let url = try SplitShare.temporaryFileURL(for: occasion)
            sharePayload = SharePayload(url: url)
        } catch {
            shareAlert = error.localizedDescription
        }
    }
}

private struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
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
