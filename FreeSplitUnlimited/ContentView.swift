//
//  ContentView.swift
//  FreeSplitUnlimited
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(
        filter: #Predicate<Occasion> { !$0.isDeleted },
        sort: \Occasion.createdAt,
        order: .reverse
    ) private var occasions: [Occasion]
    @State private var showingAddOccasion = false
    @State private var showingImporter = false
    @State private var selectedOccasionID: UUID?
    @State private var statusMessage: StatusMessage?
    @ObservedObject private var sync = SyncCoordinator.shared.mesh

    private struct StatusMessage: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }

    private var selectedOccasion: Occasion? {
        guard let selectedOccasionID else { return nil }
        return occasions.first(where: { $0.id == selectedOccasionID })
    }

    var body: some View {
        NavigationSplitView {
            sidebarContent
                .navigationTitle("Free Split")
                .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Label(
                            sync.connectedPeerCount > 0
                                ? "\(sync.connectedPeerCount) Nearby"
                                : "Offline Sync Ready",
                            systemImage: sync.connectedPeerCount > 0
                                ? "dot.radiowaves.left.and.right"
                                : "wifi.slash"
                        )
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.teal)
                        .accessibilityHint("Nearby mesh works without internet. Keep Wi‑Fi and Bluetooth on.")
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showingImporter = true
                        } label: {
                            Label("Import Split", systemImage: "square.and.arrow.down")
                        }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            showingAddOccasion = true
                        } label: {
                            Label("New Split", systemImage: "plus")
                        }
                    }
                }
                .safeAreaInset(edge: .bottom) {
                    VStack(spacing: 8) {
                        Button {
                            showingAddOccasion = true
                        } label: {
                            Text("New Split")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(AppTheme.teal)

                        Button {
                            showingImporter = true
                        } label: {
                            Text("Import Split (AirDrop / Files)")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                        }
                        .buttonStyle(.bordered)
                        .tint(AppTheme.teal)
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                    .background(.ultraThinMaterial)
                }
                .freeSplitBackground()
        } detail: {
            NavigationStack {
                if let occasion = selectedOccasion {
                    OccasionDetailView(occasion: occasion)
                } else {
                    ContentUnavailableView {
                        Label("Select a Split", systemImage: "person.3")
                    } description: {
                        Text("Choose a split from the sidebar to see expenses and balances.")
                    }
                    .freeSplitBackground()
                }
            }
        }
        .tint(AppTheme.teal)
        .sheet(isPresented: $showingAddOccasion) {
            AddOccasionView()
        }
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [.freeSplit, .json],
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
        .onChange(of: occasions.count) { _, _ in
            if let selectedOccasionID,
               !occasions.contains(where: { $0.id == selectedOccasionID }) {
                self.selectedOccasionID = nil
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .freeSplitDidImport)) { note in
            if let id = note.object as? UUID {
                selectedOccasionID = id
            }
        }
    }

    private func importSharedSplit(from url: URL) {
        do {
            let occasion = try SplitShare.importFile(at: url, into: modelContext)
            selectedOccasionID = occasion.id
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

    @ViewBuilder
    private var sidebarContent: some View {
        if occasions.isEmpty {
            emptyState
        } else {
            List(selection: $selectedOccasionID) {
                ForEach(occasions, id: \.id) { occasion in
                    OccasionRowView(occasion: occasion)
                        .tag(occasion.id)
                        .listRowBackground(Color.white.opacity(0.78))
                }
                .onDelete(perform: deleteOccasions)
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            VStack(spacing: 16) {
                Image("AppLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 96, height: 96)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .shadow(color: .black.opacity(0.12), radius: 8, y: 4)

                Text("No Splits Yet")
                    .font(.title2.weight(.semibold))
            }
        } description: {
            Text("Create a split like a trip, dinner, or roommate month to start splitting expenses.")
        } actions: {
            Button("New Split") {
                showingAddOccasion = true
            }
            .buttonStyle(.borderedProminent)
            .tint(AppTheme.teal)

            Button("Import Split") {
                showingImporter = true
            }
            .buttonStyle(.bordered)
            .tint(AppTheme.teal)
        }
    }

    private func deleteOccasions(at offsets: IndexSet) {
        for index in offsets {
            let occasion = occasions[index]
            if occasion.id == selectedOccasionID {
                selectedOccasionID = nil
            }
            // Soft-delete (tombstone) instead of a hard delete so the deletion
            // propagates to other phones via mesh/cloud sync instead of the
            // split silently reappearing next time they sync.
            occasion.isDeleted = true
            occasion.touch()
        }
        modelContext.persist()
    }
}

extension Notification.Name {
    static let freeSplitDidImport = Notification.Name("freeSplitDidImport")
}

private struct OccasionRowView: View {
    let occasion: Occasion

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(occasion.name)
                .font(.headline)
                .foregroundStyle(.primary)

            HStack(spacing: 12) {
                Label("\(occasion.uniqueMembers.count)", systemImage: "person.2")
                Label(CurrencyFormat.string(from: occasion.totalSpent), systemImage: "dollarsign.circle")
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)

            if !occasion.note.isEmpty {
                Text(occasion.note)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Occasion.self, Person.self, Expense.self, ExpenseShare.self], inMemory: true)
}
