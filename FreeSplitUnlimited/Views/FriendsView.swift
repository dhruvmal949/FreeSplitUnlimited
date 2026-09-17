//
//  FriendsView.swift
//  FreeSplitUnlimited
//

import SwiftUI
import SwiftData

struct FriendsView: View {
    @Query(sort: \Occasion.createdAt, order: .reverse)
    private var allOccasions: [Occasion]
    @ObservedObject private var session = AuthSession.shared
    @State private var showingFilter = false
    @State private var filter: FriendBalanceFilter = .none
    @State private var showingAddOccasion = false
    @State private var pendingOpenGroupID: UUID?
    @State private var openedGroupID: OpenedGroup?

    private struct OpenedGroup: Identifiable, Hashable {
        let id: UUID
    }

    private var occasions: [Occasion] {
        let identity = AccountIdentity(
            accountID: session.accountID,
            email: session.email,
            phone: session.accountPhone,
            names: session.selfNames.filter { FriendPairing.isUsableName($0) }
        )
        var seen = Set<UUID>()
        return allOccasions.filter { OccasionAccess.isVisible($0, as: identity) && seen.insert($0.id).inserted }
    }

    private var friends: [FriendSummary] {
        BalanceCalculator.friendSummaries(from: occasions)
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
            return "owes you \(CurrencyFormat.string(from: net))"
        } else {
            return "you owe \(CurrencyFormat.string(from: -net))"
        }
    }

    private func balanceColor(for net: Decimal) -> Color {
        AppTheme.balanceColor(for: net)
    }
}

private struct FriendDetailView: View {
    let summary: FriendSummary
    let occasions: [Occasion]

    private var sharedOccasions: [Occasion] {
        occasions.filter { summary.occasionIDs.contains($0.id) }
    }

    var body: some View {
        List {
            if sharedOccasions.isEmpty {
                Text("None")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(sharedOccasions, id: \.id) { occasion in
                    NavigationLink {
                        OccasionDetailView(occasion: occasion)
                    } label: {
                        OccasionRowView(occasion: occasion)
                    }
                    .listRowBackground(Color.white.opacity(0.78))
                }
            }
        }
        .freeSplitListStyle()
        .freeSplitBackground()
        .navigationTitle(summary.name)
        .navigationBarTitleDisplayMode(.inline)
        .homeBackButton()
        .avoidsMainTabBar()
    }
}
