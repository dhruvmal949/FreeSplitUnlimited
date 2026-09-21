//
//  FriendsView.swift
//  FreeSplitUnlimited
//

import SwiftUI
import SwiftData
import UIKit

struct FriendsView: View {
    @Query(sort: \Occasion.createdAt, order: .reverse)
    private var allOccasions: [Occasion]
    @ObservedObject private var session = AuthSession.shared
    @State private var showingFilter = false
    @State private var filter: FriendBalanceFilter = .none
    @State private var showingAddOccasion = false
    @State private var pendingOpenGroupID: UUID?
    @State private var openedGroupID: OpenedGroup?
    @State private var hiddenSplitIDs = DeletedGroupsStore.ids()
    @Environment(\.modelContext) private var modelContext

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
        return allOccasions.filter {
            OccasionAccess.isVisible($0, as: identity)
                && !hiddenSplitIDs.contains($0.id)
                && seen.insert($0.id).inserted
        }
    }

    private var friends: [FriendSummary] {
        BalanceCalculator.friendSummaries(from: occasions, myNames: session.selfNames)
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
        .onAppear {
            hiddenSplitIDs = DeletedGroupsStore.ids()
            DispatchQueue.main.async {
                persistHiddenSplits()
            }
            openImportedSplitIfNeeded()
        }
        .onReceive(NotificationCenter.default.publisher(for: .freeSplitDidHideGroups)) { _ in
            hiddenSplitIDs = DeletedGroupsStore.ids()
        }
        .onReceive(NotificationCenter.default.publisher(for: .freeSplitDidImport)) { _ in
            openImportedSplitIfNeeded()
        }
        .freeSplitBackground()
        .avoidsMainTabBar()
    }

    private func openImportedSplitIfNeeded() {
        guard let id = IncomingSplitOpener.shared.pendingOpenID else { return }
        guard let occasion = occasions.first(where: { $0.id == id }), !occasion.appearsInGroups else { return }
        IncomingSplitOpener.shared.consumePendingOpen()
        openedGroupID = OpenedGroup(id: id)
    }

    private func persistHiddenSplits() {
        let stale = allOccasions.filter { hiddenSplitIDs.contains($0.id) || !$0.shouldAppearInLists }
        guard !stale.isEmpty else { return }
        for occasion in stale {
            modelContext.removeGroup(occasion)
        }
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

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var session = AuthSession.shared
    @State private var showingBreakdown = true
    @State private var selectedAction: FriendAction = .request
    @State private var openedSplit: OpenedSplit?
    @State private var showingRecordPayment = false
    @State private var inviteContacts: [PickedContact] = []

    private enum FriendAction {
        case request, settle, remind
    }

    private struct OpenedSplit: Identifiable, Hashable {
        let id: UUID
    }

    private var myNames: [String] {
        session.selfNames
    }

    private var sharedOccasions: [Occasion] {
        occasions
            .filter { summary.occasionIDs.contains($0.id) }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    private var overallNet: Decimal {
        sharedOccasions.reduce(0) { $0 + net(in: $1) }
    }

    private var primaryOccasion: Occasion? {
        sharedOccasions.first { net(in: $0) != 0 } ?? sharedOccasions.first
    }

    private var friendContact: PickedContact? {
        for occasion in sharedOccasions {
            if let person = occasion.uniqueMembers.first(where: {
                FriendPairing.namesMatch($0.name, summary.name)
            }) {
                return person.asPickedContact
            }
        }
        return nil
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 0) {
                    hero
                    profileHeader
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }

            Section {
                if sharedOccasions.isEmpty {
                    Text("No shared splits yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(sharedOccasions, id: \.id) { occasion in
                        Button {
                            openedSplit = OpenedSplit(id: occasion.id)
                        } label: {
                            friendGroupRow(occasion)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("friendSharedGroup")
                        .listRowBackground(Color.white.opacity(0.78))
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .freeSplitBackground()
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
        .toolbarBackground(.hidden, for: .navigationBar)
        .avoidsMainTabBar()
        .navigationDestination(item: $openedSplit) { token in
            if let occasion = sharedOccasions.first(where: { $0.id == token.id }) {
                OccasionDetailView(occasion: occasion)
            }
        }
        .fullScreenCover(isPresented: $showingRecordPayment, onDismiss: {
            selectedAction = .request
        }) {
            RecordPaymentView(
                friendName: summary.name,
                overallNet: overallNet,
                occasions: sharedOccasions,
                myNames: myNames
            )
        }
        .friendInvite(
            contacts: $inviteContacts,
            splitName: summary.name,
            occasion: primaryOccasion
        )
    }

    private var hero: some View {
        ZStack(alignment: .bottomLeading) {
            ZStack {
                LinearGradient(
                    colors: [AppTheme.deepTeal, AppTheme.teal, AppTheme.brightTeal],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                FriendHeaderPattern()
                    .fill(Color.white.opacity(0.14))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 148)
            .ignoresSafeArea(edges: .top)

            VStack {
                HStack {
                    headerCircleButton(systemImage: "chevron.left", label: "Back to friends") {
                        dismiss()
                    }
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            friendAvatar
                .offset(x: 20, y: 28)
        }
        .frame(height: 148)
    }

    private var friendAvatar: some View {
        ZStack {
            Circle()
                .fill(avatarColor)
            Text(avatarLetter)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
        .frame(width: 72, height: 72)
        .overlay {
            Circle().stroke(Color.white, lineWidth: 3)
        }
        .accessibilityHidden(true)
    }

    private var avatarLetter: String {
        String(summary.name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(1)).uppercased()
    }

    private var avatarColor: Color {
        let palette: [Color] = [
            Color(red: 1, green: 0.48, blue: 0.37),
            AppTheme.teal,
            Color(red: 0.45, green: 0.55, blue: 0.95),
            Color(red: 0.95, green: 0.62, blue: 0.2)
        ]
        let index = abs(summary.name.lowercased().hashValue) % palette.count
        return palette[index]
    }

    private var profileHeader: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(summary.name)
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                .foregroundStyle(.primary)
                .padding(.top, 36)
            overallHeader
            if showingBreakdown {
                breakdown
            }
            actionPills
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
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

    private var overallHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                overallText
                Spacer(minLength: 8)
                Button {
                    showingBreakdown.toggle()
                } label: {
                    Image(systemName: showingBreakdown ? "chevron.up" : "chevron.down")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(showingBreakdown ? "Hide group balances" : "Show group balances")
            }
        }
    }

    private var overallText: Text {
        if overallNet == 0 {
            return Text("You are settled up overall")
                .foregroundColor(.secondary)
        }
        if overallNet > 0 {
            return Text("You are owed \(CurrencyFormat.string(from: overallNet)) overall")
                .foregroundColor(AppTheme.youAreOwed)
                .fontWeight(.semibold)
        }
        return Text("You owe \(CurrencyFormat.string(from: -overallNet)) overall")
            .foregroundColor(AppTheme.youOwe)
            .fontWeight(.semibold)
    }

    private var breakdown: some View {
        let lines = sharedOccasions.compactMap { occasion -> (UUID, Decimal, String)? in
            let amount = net(in: occasion)
            guard amount != 0 else { return nil }
            return (occasion.id, amount, occasion.displayName)
        }
        return Group {
            if !lines.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(lines, id: \.0) { _, amount, group in
                        breakdownLine(amount: amount, group: group)
                            .font(.subheadline)
                    }
                }
                .padding(.leading, 8)
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.35))
                        .frame(width: 2)
                }
            }
        }
    }

    private func breakdownLine(amount: Decimal, group: String) -> Text {
        let money = CurrencyFormat.string(from: abs(amount))
        let moneyColor = amount > 0 ? AppTheme.youAreOwed : AppTheme.youOwe
        if amount > 0 {
            return Text("\(summary.name) owes you ")
                .foregroundColor(.secondary)
            + Text(money)
                .foregroundColor(moneyColor)
                .fontWeight(.semibold)
            + Text(" in “\(group)”")
                .foregroundColor(.secondary)
        }
        return Text("You owe \(summary.name) ")
            .foregroundColor(.secondary)
        + Text(money)
            .foregroundColor(moneyColor)
            .fontWeight(.semibold)
        + Text(" in “\(group)”")
            .foregroundColor(.secondary)
    }

    private var actionPills: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                if primaryOccasion != nil {
                    pill("Request", selected: selectedAction == .request) {
                        selectedAction = .request
                    }
                }
                pill("Settle up", selected: selectedAction == .settle) {
                    selectedAction = .settle
                    showingRecordPayment = true
                }
                if let contact = friendContact, contact.hasUsableContactInfo {
                    pill("Remind", selected: selectedAction == .remind) {
                        selectedAction = .remind
                        inviteContacts = [contact]
                    }
                }
            }
        }
    }

    private func pill(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .foregroundStyle(selected ? Color.white : Color.primary)
                .background(selected ? AppTheme.teal : Color.clear, in: Capsule())
                .overlay {
                    Capsule()
                        .stroke(Color.secondary.opacity(0.28), lineWidth: selected ? 0 : 1)
                }
        }
        .buttonStyle(.plain)
    }

    private func friendGroupRow(_ occasion: Occasion) -> some View {
        HStack(spacing: 12) {
            groupDate(occasion.updatedAt)
            groupArtwork(occasion)
            VStack(alignment: .leading, spacing: 4) {
                Text(occasion.displayName)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(occasion.appearsInGroups ? "Shared group" : "Friend split")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(groupBalanceLabel(net(in: occasion)))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.balanceColor(for: net(in: occasion)))
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private func groupDate(_ date: Date) -> some View {
        VStack(spacing: 2) {
            Text(date, format: .dateTime.month(.abbreviated))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(date, format: .dateTime.day())
                .font(.headline)
                .foregroundStyle(.primary)
        }
        .frame(width: 36)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func groupArtwork(_ occasion: Occasion) -> some View {
        if let data = GroupCoverStore.data(for: occasion.id), let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        } else {
            Image(systemName: occasion.kind.symbol)
                .font(.body.weight(.semibold))
                .foregroundStyle(AppTheme.teal)
                .frame(width: 44, height: 44)
                .background(AppTheme.lightAqua, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private func net(in occasion: Occasion) -> Decimal {
        BalanceCalculator.net(withFriend: summary.name, in: occasion, myNames: myNames)
    }

    private func groupBalanceLabel(_ net: Decimal) -> String {
        if net == 0 { return "settled up" }
        if net > 0 { return "you are owed\n\(CurrencyFormat.string(from: net))" }
        return "you owe\n\(CurrencyFormat.string(from: -net))"
    }
}

private struct FriendHeaderPattern: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let cols = 5
        let rows = 3
        let width = rect.width / CGFloat(cols)
        let height = rect.height / CGFloat(rows)
        for row in 0..<rows {
            for col in 0..<cols {
                let origin = CGPoint(x: CGFloat(col) * width, y: CGFloat(row) * height)
                var triangle = Path()
                if (row + col).isMultiple(of: 2) {
                    triangle.move(to: origin)
                    triangle.addLine(to: CGPoint(x: origin.x + width, y: origin.y))
                    triangle.addLine(to: CGPoint(x: origin.x, y: origin.y + height))
                } else {
                    triangle.move(to: CGPoint(x: origin.x + width, y: origin.y))
                    triangle.addLine(to: CGPoint(x: origin.x + width, y: origin.y + height))
                    triangle.addLine(to: CGPoint(x: origin.x, y: origin.y + height))
                }
                triangle.closeSubpath()
                path.addPath(triangle)
            }
        }
        return path
    }
}
