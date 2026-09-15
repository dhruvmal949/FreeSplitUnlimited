//
//  ContentView.swift
//  FreeSplitUnlimited
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import UIKit

struct ContentView: View {
    @State private var selectedTab = 1

    var body: some View {
        NavigationStack {
            tabRoot
        }
        .id(selectedTab)
        .environment(\.popToHome, { selectedTab = 1 })
        .tint(AppTheme.teal)
        .safeAreaInset(edge: .bottom) {
            MainTabBar(selectedTab: selectedTab, onSelect: selectTab)
        }
        .onAppear {
            guard !AppLaunchFlags.isUITesting else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                SyncCoordinator.shared.startNearby()
            }
        }
    }

    @ViewBuilder
    private var tabRoot: some View {
        switch selectedTab {
        case 0:
            FriendsView()
        case 2:
            NotificationsView()
        case 3:
            SettingsView()
        default:
            GroupsView()
        }
    }

    private func selectTab(_ tab: Int) {
        guard tab != selectedTab else { return }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            selectedTab = tab
        }
    }
}

private struct MainTabBar: View {
    let selectedTab: Int
    var onSelect: (Int) -> Void

    var body: some View {
        HStack {
            tabButton(0, title: "Friends", image: "person.fill")
            tabButton(1, title: "Groups", image: "person.3.fill")
            tabButton(2, title: "Notifications", image: "bell.fill")
            tabButton(3, title: "Settings", image: "gearshape.fill")
        }
        .padding(.top, 8)
        .padding(.bottom, 4)
        .frame(minHeight: AppTheme.mainTabBarHeight)
        .background(.ultraThinMaterial)
    }

    private func tabButton(_ index: Int, title: String, image: String) -> some View {
        Button {
            guard selectedTab != index else { return }
            onSelect(index)
        } label: {
            VStack(spacing: 4) {
                Image(systemName: image)
                    .font(.system(size: 20, weight: .semibold))
                Text(title)
                    .font(.caption2)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .foregroundStyle(selectedTab == index ? AppTheme.teal : Color.secondary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityIdentifier("tab-\(title)")
    }
}

private struct GroupsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Occasion.createdAt, order: .reverse)
    private var allOccasions: [Occasion]
    @State private var showingAddOccasion = false
    @State private var showingImporter = false
    @State private var statusMessage: StatusMessage?
    @State private var openedGroupID: OpenedGroup?
    @State private var pendingOpenGroupID: UUID?
    @State private var showingFilter = false
    @State private var groupFilter: GroupBalanceFilter = .none

    private struct OpenedGroup: Identifiable, Hashable {
        let id: UUID
    }

    private struct StatusMessage: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }

    /// Filter in Swift — `#Predicate` on SwiftData can trap (`brk`) after schema changes.
    private var occasions: [Occasion] {
        var seen = Set<UUID>()
        return allOccasions.filter { !$0.isDeleted && seen.insert($0.id).inserted }
    }

    /// One-to-one Friends splits stay off Home until a third person is added.
    private var groupOccasions: [Occasion] {
        occasions.filter(\.appearsInGroups)
    }

    private var visibleOccasions: [Occasion] {
        groupOccasions.filter { groupFilter.matches(myNet: BalanceCalculator.myNet(in: $0)) }
    }

    private var overallNet: Decimal {
        groupOccasions.reduce(0) { $0 + BalanceCalculator.myNet(in: $1) }
    }

    var body: some View {
        Group {
            if groupOccasions.isEmpty {
                emptyState
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

                    if visibleOccasions.isEmpty {
                        Text("No groups match this filter.")
                            .foregroundStyle(.secondary)
                            .listRowBackground(Color.clear)
                    } else {
                        ForEach(visibleOccasions, id: \.id) { occasion in
                            NavigationLink {
                                OccasionDetailView(occasion: occasion)
                            } label: {
                                OccasionRowView(occasion: occasion)
                            }
                            .listRowBackground(Color.white.opacity(0.78))
                        }
                        .onDelete(perform: deleteOccasions)
                    }

                    Section {
                        createGroupBar
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 16, leading: 16, bottom: 24, trailing: 16))
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .contentMargins(.bottom, 12, for: .scrollContent)
            }
        }
        .navigationTitle("Home")
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingImporter = true
                } label: {
                    Label("Import from File", systemImage: "square.and.arrow.down")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    openNewSplit()
                } label: {
                    Label("Create Group", systemImage: "plus")
                }
                .disabled(showingAddOccasion)
            }
        }
        .confirmationDialog("Set filter", isPresented: $showingFilter, titleVisibility: .visible) {
            ForEach(GroupBalanceFilter.allCases) { option in
                Button((groupFilter == option ? "✓ " : "") + option.title) {
                    groupFilter = option
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .freeSplitBackground()
        .navigationDestination(item: $openedGroupID) { token in
            if let occasion = occasions.first(where: { $0.id == token.id }) {
                OccasionDetailView(occasion: occasion)
            } else {
                NoneState(image: "person.3", message: "This group isn’t available.")
                    .homeBackButton()
            }
        }
        .sheet(isPresented: $showingAddOccasion, onDismiss: {
            if let id = pendingOpenGroupID {
                pendingOpenGroupID = nil
                openedGroupID = OpenedGroup(id: id)
            }
        }) {
            CreateGroupView { id in
                pendingOpenGroupID = id
            }
        }
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [.json, .data, .item],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                importSharedSplit(from: url)
            case .failure(let error):
                statusMessage = StatusMessage(
                    title: "Import Failed",
                    message: error.localizedDescription
                )
            }
        }
        .alert(item: $statusMessage) { item in
            Alert(
                title: Text(item.title),
                message: Text(item.message),
                dismissButton: .default(Text("OK"))
            )
        }
        .onReceive(NotificationCenter.default.publisher(for: .freeSplitDidImport)) { note in
            if let id = note.object as? UUID,
               let name = occasions.first(where: { $0.id == id })?.name {
                statusMessage = StatusMessage(
                    title: "Split Imported",
                    message: "\"\(name)\" is ready on this phone."
                )
            } else {
                statusMessage = StatusMessage(
                    title: "Split Imported",
                    message: "The split is ready on this phone."
                )
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .freeSplitImportFailed)) { note in
            let message = (note.userInfo?["message"] as? String)
                ?? "Couldn't open this split file."
            statusMessage = StatusMessage(title: "Import Failed", message: message)
        }
    }

    private func openNewSplit() {
        guard !showingAddOccasion else { return }
        showingAddOccasion = true
    }

    private func importSharedSplit(from url: URL) {
        do {
            let occasion = try SplitShare.importFile(at: url, into: modelContext)
            statusMessage = StatusMessage(
                title: "Split Imported",
                message: "\"\(occasion.name)\" is ready on this phone. No internet was required."
            )
        } catch {
            statusMessage = StatusMessage(
                title: "Import Failed",
                message: error.localizedDescription
            )
        }
    }

    private var emptyState: some View {
        ScrollView {
            VStack(spacing: 24) {
                NoneState(
                    image: "person.3",
                    message: "No groups yet. Create a group to start sharing expenses."
                )
                .frame(minHeight: 280)

                createGroupBar
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 28)
        }
    }

    private var createGroupBar: some View {
        VStack(spacing: 8) {
            Button {
                openNewSplit()
            } label: {
                Text("Create Group")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .tint(AppTheme.teal)
            .disabled(showingAddOccasion)

            if groupOccasions.isEmpty {
                Button {
                    showingImporter = true
                } label: {
                    Text("Import from File")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.bordered)
                .tint(AppTheme.teal)
            }
        }
    }

    private func deleteOccasions(at offsets: IndexSet) {
        for index in offsets {
            let occasion = visibleOccasions[index]
            occasion.isDeleted = true
            occasion.touch()
        }
        modelContext.persist()
    }
}

extension Notification.Name {
    static let freeSplitDidImport = Notification.Name("freeSplitDidImport")
    static let freeSplitImportFailed = Notification.Name("freeSplitImportFailed")
}

struct OccasionRowView: View {
    let occasion: Occasion

    var body: some View {
        HStack(spacing: 12) {
            groupArtwork

            VStack(alignment: .leading, spacing: 6) {
                Text(occasion.name)
                    .font(.headline)
                    .foregroundStyle(.primary)

                HStack(spacing: 12) {
                    Label(occasion.kind.title, systemImage: occasion.kind.symbol)
                    Label("\(occasion.uniqueMembers.count)", systemImage: "person.2")
                    Label(CurrencyFormat.string(from: occasion.totalSpent), systemImage: "dollarsign.circle")
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)

                let net = BalanceCalculator.myNet(in: occasion)
                if net != 0 {
                    Text(net > 0
                         ? "You are owed \(CurrencyFormat.string(from: net))"
                         : "You owe \(CurrencyFormat.string(from: -net))")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.balanceColor(for: net))
                }

                if !occasion.note.isEmpty {
                    Text(occasion.note)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var groupArtwork: some View {
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
}

#Preview {
    ContentView()
        .modelContainer(for: [Occasion.self, Person.self, Expense.self, ExpenseShare.self], inMemory: true)
}
