//
//  FriendsView.swift
//  FreeSplitUnlimited
//

import SwiftUI
import SwiftData

struct FriendsView: View {
    @Query(sort: \Occasion.createdAt, order: .reverse)
    private var allOccasions: [Occasion]
    @State private var showingFilter = false
    @State private var filter: FriendBalanceFilter = .none

    private var occasions: [Occasion] {
        var seen = Set<UUID>()
        return allOccasions.filter { !$0.isDeleted && seen.insert($0.id).inserted }
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
                    message: "No one-to-one friends yet. Add people to a split to see them here."
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
                    showingFilter = true
                } label: {
                    Label("Set filter", systemImage: "plus")
                }
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
        if net > 0 { return .green }
        if net < 0 { return .orange }
        return .secondary
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
