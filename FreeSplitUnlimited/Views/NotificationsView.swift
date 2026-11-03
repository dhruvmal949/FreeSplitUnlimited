//
//  NotificationsView.swift
//  FreeSplitUnlimited
//

import SwiftUI
import SwiftData

struct NotificationsView: View {
    @Query(sort: \Occasion.createdAt, order: .reverse)
    private var allOccasions: [Occasion]
    @ObservedObject private var session = AuthSession.shared
    @State private var hiddenIDs = DeletedNotificationsStore.ids()

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

    private var feed: OverflowStack.Sections<ActivityEvent> {
        NotificationFeed.sections(
            from: BalanceCalculator.activity(from: occasions),
            hiddenIDs: hiddenIDs
        )
    }

    var body: some View {
        Group {
            if feed.isEmpty {
                NoneState(
                    image: "bell",
                    title: "No notifications"
                )
            } else {
                List {
                    Section {
                        ForEach(feed.recent) { event in
                            notificationLink(event)
                        }
                    }

                    if feed.showsPaidStack {
                        Section("Paid") {
                            ForEach(feed.paid) { event in
                                notificationLink(event)
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .contentMargins(.bottom, 12, for: .scrollContent)
            }
        }
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .homeBackButton()
        .freeSplitBackground()
        .avoidsMainTabBar()
        .onAppear {
            hiddenIDs = DeletedNotificationsStore.ids()
        }
    }

    private func notificationLink(_ event: ActivityEvent) -> some View {
        NavigationLink {
            if let occasion = occasions.first(where: { $0.id == event.occasionID }) {
                OccasionDetailView(occasion: occasion)
            } else {
                NoneState(image: "bell.slash", title: "No notifications")
            }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: event.kind == .splitCreated ? "rectangle.stack.badge.plus" : "dollarsign.circle")
                    .font(.title3)
                    .foregroundStyle(AppTheme.teal)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 4) {
                    Text(event.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(event.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(event.date, format: .dateTime.month(.abbreviated).day().year())
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.vertical, 4)
        }
        .listRowBackground(Color.white.opacity(0.78))
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button("Delete", role: .destructive) {
                delete(event)
            }
        }
    }

    private func delete(_ event: ActivityEvent) {
        DeletedNotificationsStore.remember(event.id)
        hiddenIDs.insert(event.id)
    }
}
