//
//  NotificationsView.swift
//  FreeSplitUnlimited
//

import SwiftUI
import SwiftData

struct NotificationsView: View {
    @Query(sort: \Occasion.createdAt, order: .reverse)
    private var allOccasions: [Occasion]

    private var occasions: [Occasion] {
        var seen = Set<UUID>()
        return allOccasions.filter { !$0.isDeleted && seen.insert($0.id).inserted }
    }

    private var events: [ActivityEvent] {
        BalanceCalculator.activity(from: occasions)
    }

    var body: some View {
        Group {
            if events.isEmpty {
                NoneState(
                    image: "bell",
                    message: "None. New splits and amounts paid will show up here."
                )
            } else {
                List {
                    ForEach(events) { event in
                        NavigationLink {
                            if let occasion = occasions.first(where: { $0.id == event.occasionID }) {
                                OccasionDetailView(occasion: occasion)
                            } else {
                                NoneState(image: "bell.slash", message: "None")
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
                                    Text(event.date, style: .relative)
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .listRowBackground(Color.white.opacity(0.78))
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
    }
}
