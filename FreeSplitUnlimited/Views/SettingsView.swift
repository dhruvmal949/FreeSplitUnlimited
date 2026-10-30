//
//  SettingsView.swift
//  FreeSplitUnlimited
//

import SwiftData
import SwiftUI

struct SettingsView: View {
    @ObservedObject private var mesh = MeshSyncService.shared
    @ObservedObject private var session = AuthSession.shared
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Occasion.createdAt, order: .reverse) private var allOccasions: [Occasion]
    @State private var showingDeleteAccount = false

    var body: some View {
        Form {
                if AppLaunchFlags.nearbySyncEnabled {
                    Section("Nearby sync") {
                        NearbySyncBanner(mesh: mesh) {
                            SyncCoordinator.shared.syncNow()
                        }
                        .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                        .listRowBackground(Color.clear)
                    }
                }

                Section("Account") {
                    if session.isGuest {
                        HStack {
                            Text("Username")
                            Spacer()
                            Text("Guest")
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        if !session.displayName.isEmpty,
                           session.displayName.localizedCaseInsensitiveCompare(session.signedInHandle) != .orderedSame {
                            HStack {
                                Text("Name")
                                Spacer()
                                Text(session.displayName)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        HStack {
                            Text("Username")
                            Spacer()
                            Text(session.signedInHandle)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                    Button("Sign Out", role: .destructive) {
                        session.signOut()
                    }
                    if !session.isGuest {
                        Button("Delete Account", role: .destructive) {
                            showingDeleteAccount = true
                        }
                        .accessibilityIdentifier("settingsDeleteAccount")
                    }
                }

                Section("Legal") {
                    NavigationLink("Privacy Policy") {
                        PrivacyPolicyView()
                    }
                    NavigationLink("Support") {
                        SupportView()
                    }
                }

                Section("About") {
                    HStack {
                        Text("App")
                        Spacer()
                        Text("Free Split")
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Version")
                        Spacer()
                        Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .freeSplitListStyle()
            .freeSplitBackground()
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .homeBackButton()
            .avoidsMainTabBar()
            .alert("Delete Account?", isPresented: $showingDeleteAccount) {
                Button("Delete Account", role: .destructive) {
                    deleteAccountAndLocalSplits()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This removes your sign-in and local splits from this iPhone. It cannot be undone.")
            }
    }

    private func deleteAccountAndLocalSplits() {
        let identity = AccountIdentity(
            accountID: session.accountID,
            email: session.email,
            phone: session.accountPhone,
            names: session.selfNames.filter { FriendPairing.isUsableName($0) }
        )
        for occasion in allOccasions where OccasionAccess.isVisible(occasion, as: identity) {
            modelContext.removeGroup(occasion)
        }
        session.deleteCurrentAccount()
    }
}
