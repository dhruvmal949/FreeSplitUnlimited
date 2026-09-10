//
//  FriendsView.swift
//  FreeSplitUnlimited
//

import SwiftUI
import SwiftData

struct FriendsView: View {
    @Query(sort: \Occasion.createdAt, order: .reverse)
    private var allOccasions: [Occasion]
    @ObservedObject private var auth = AuthSession.shared
    @State private var showingFilter = false
    @State private var filter: FriendBalanceFilter = .none
    @State private var showingAddOccasion = false
    @State private var pendingOpenGroupID: UUID?
    @State private var openedGroupID: OpenedGroup?
    @State private var remindPayload: FriendRemindPayload?
    @State private var payRequest: PayFriendRequest?

    private struct OpenedGroup: Identifiable, Hashable {
        let id: UUID
    }


    private var occasions: [Occasion] {
        var seen = Set<UUID>()
        return allOccasions.filter { !$0.isDeleted && seen.insert($0.id).inserted }
    }

    private var friends: [FriendSummary] {
        BalanceCalculator.friendSummaries(from: occasions, myNames: auth.selfNames)
    }

    private var visibleFriends: [FriendSummary] {
        friends.filter { filter.matches($0.net) }
    }

    private var overallNet: Decimal {
        friends.reduce(0) { $0 + $1.net }
    }

    var body: some View {
        Group {
            if friends.isEmpty {
                NoneState(
                    image: "person",
                    message: "No one-to-one friends yet. Tap + to start a split with one person."
                )
            } else {
                List {
                    Section {
                        OverallBalanceBanner(net: overallNet) {
                            showingFilter = true
                        }
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 4, trailing: 12))

                    if visibleFriends.isEmpty {
                        Text("No friends match this filter.")
                            .foregroundStyle(.secondary)
                            .listRowBackground(Color.clear)
                    } else {
                        ForEach(visibleFriends) { friend in
                            NavigationLink {
                                FriendDetailView(summary: friend, occasions: occasions)
                            } label: {
                                friendRow(friend)
                            }
                            .listRowBackground(Color.white.opacity(0.78))
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                if friend.net > 0 {
                                    Button {
                                        remindPayload = FriendReminder.payload(
                                            for: friend,
                                            occasions: occasions,
                                            myNames: auth.selfNames
                                        )
                                    } label: {
                                        Label("Remind", systemImage: "bubble.left")
                                    }
                                    .tint(AppTheme.teal)
                                } else if friend.net < 0 {
                                    Button {
                                        payRequest = PaymentTransfer.request(
                                            for: friend,
                                            occasions: occasions
                                        )
                                    } label: {
                                        Label("Pay", systemImage: "dollarsign.circle")
                                    }
                                    .tint(AppTheme.teal)
                                }
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .contentMargins(.bottom, 12, for: .scrollContent)
            }
        }
        .navigationTitle("Friends")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .homeBackButton()
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    guard !showingAddOccasion else { return }
                    showingAddOccasion = true
                } label: {
                    Label("New Split", systemImage: "plus")
                }
                .disabled(showingAddOccasion)
            }
        }
        .confirmationDialog("Set filter", isPresented: $showingFilter, titleVisibility: .visible) {
            ForEach(FriendBalanceFilter.allCases) { option in
                Button((filter == option ? "✓ " : "") + option.title) {
                    filter = option
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: $showingAddOccasion, onDismiss: {
            if let id = pendingOpenGroupID {
                pendingOpenGroupID = nil
                openedGroupID = OpenedGroup(id: id)
            }
        }) {
            CreateFriendSplitView { id in
                pendingOpenGroupID = id
            }
        }
        .navigationDestination(item: $openedGroupID) { token in
            if let occasion = occasions.first(where: { $0.id == token.id }) {
                OccasionDetailView(occasion: occasion)
            } else {
                NoneState(image: "person.3", message: "This group isn’t available.")
                    .homeBackButton()
            }
        }
        .sheet(item: $remindPayload) { payload in
            FriendRemindSheet(payload: payload)
        }
        .sheet(item: $payRequest) { request in
            PayFriendSheet(request: request, occasions: occasions)
        }
        .freeSplitBackground()
        .avoidsMainTabBar()
    }

    private func friendRow(_ friend: FriendSummary) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(friend.name)
                    .font(.headline)
                    .foregroundStyle(.primary)
                if let group = friend.occasionNames.first {
                    Text(friend.occasionNames.count == 1 ? group : "\(group) + \(friend.occasionNames.count - 1) more")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(balanceLabel(for: friend.net))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(balanceColor(for: friend.net))
        }
        .padding(.vertical, 4)
    }

    private func balanceLabel(for net: Decimal) -> String {
        if net == 0 {
            return "Settled"
        } else if net > 0 {
            return "owes you \(CurrencyFormat.string(from: net)) total"
        } else {
            return "you owe \(CurrencyFormat.string(from: -net)) total"
        }
    }

    private func balanceColor(for net: Decimal) -> Color {
        AppTheme.balanceColor(for: net)
    }
}

private struct FriendDetailView: View {
    let summary: FriendSummary
    let occasions: [Occasion]

    @ObservedObject private var auth = AuthSession.shared
    @State private var remindPayload: FriendRemindPayload?
    @State private var payRequest: PayFriendRequest?

    private var sharedOccasions: [Occasion] {
        occasions.filter { summary.occasionIDs.contains($0.id) }
    }

    private var headline: String {
        if summary.net > 0 {
            return "\(summary.name) owes you \(CurrencyFormat.string(from: summary.net)) total"
        }
        if summary.net < 0 {
            return "You owe \(summary.name) \(CurrencyFormat.string(from: -summary.net)) total"
        }
        return "You and \(summary.name) are settled"
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 14) {
                    Text(headline)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(AppTheme.deepTeal)
                        .fixedSize(horizontal: false, vertical: true)

                    if summary.net > 0 {
                        Button {
                            remindPayload = FriendReminder.payload(
                                for: summary,
                                occasions: occasions,
                                myNames: auth.selfNames
                            )
                        } label: {
                            Label("Remind \(summary.name)", systemImage: "bubble.left")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(AppTheme.teal)
                    } else if summary.net < 0 {
                        Button {
                            payRequest = PaymentTransfer.request(
                                for: summary,
                                occasions: occasions
                            )
                        } label: {
                            Label("Pay \(summary.name)", systemImage: "dollarsign.circle")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(AppTheme.teal)
                    }
                }
                .padding(.vertical, 4)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }

            Section {
                if summary.groupBalances.isEmpty {
                    Text("None")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(summary.groupBalances) { group in
                        if let occasion = sharedOccasions.first(where: { $0.id == group.occasionID }) {
                            NavigationLink {
                                OccasionDetailView(occasion: occasion)
                            } label: {
                                groupRow(group)
                            }
                            .listRowBackground(Color.white.opacity(0.78))
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                if group.net > 0 {
                                    Button {
                                        remindPayload = FriendReminder.payload(
                                            name: summary.name,
                                            amount: group.net,
                                            occasions: [occasion],
                                            myNames: auth.selfNames
                                        )
                                    } label: {
                                        Label("Remind", systemImage: "bubble.left")
                                    }
                                    .tint(AppTheme.teal)
                                } else if group.net < 0 {
                                    Button {
                                        payRequest = PaymentTransfer.request(
                                            payeeName: summary.name,
                                            amount: -group.net,
                                            occasions: [occasion],
                                            note: "Free Split · \(occasion.name)",
                                            legs: [PaymentLeg(occasionID: occasion.id, amount: -group.net)]
                                        )
                                    } label: {
                                        Label("Pay", systemImage: "dollarsign.circle")
                                    }
                                    .tint(AppTheme.teal)
                                }
                            }
                        } else {
                            groupRow(group)
                                .listRowBackground(Color.white.opacity(0.78))
                        }
                    }
                }
            } header: {
                Text("Across groups")
            } footer: {
                Text("Totals combine every group you share with \(summary.name).")
            }
        }
        .freeSplitListStyle()
        .freeSplitBackground()
        .navigationTitle(summary.name)
        .navigationBarTitleDisplayMode(.inline)
        .homeBackButton()
        .avoidsMainTabBar()
        .sheet(item: $remindPayload) { payload in
            FriendRemindSheet(payload: payload)
        }
        .sheet(item: $payRequest) { request in
            PayFriendSheet(request: request, occasions: occasions)
        }
    }

    private func groupRow(_ group: FriendGroupBalance) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(group.occasionName)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(groupLabel(for: group.net))
                    .font(.caption)
                    .foregroundStyle(balanceColor(for: group.net))
            }
            Spacer()
            if group.net != 0 {
                Text(CurrencyFormat.string(from: abs(group.net)))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(balanceColor(for: group.net))
            }
        }
        .padding(.vertical, 4)
    }

    private func groupLabel(for net: Decimal) -> String {
        if net == 0 { return "Settled in this group" }
        if net > 0 { return "Owes you in this group" }
        return "You owe in this group"
    }

    private func balanceColor(for net: Decimal) -> Color {
        if net > 0 { return .green }
        if net < 0 { return .orange }
        return .secondary
    }
}
