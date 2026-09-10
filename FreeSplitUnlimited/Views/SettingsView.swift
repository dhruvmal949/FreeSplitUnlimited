//
//  SettingsView.swift
//  FreeSplitUnlimited
//

import Contacts
import SwiftUI

struct SettingsView: View {
    @ObservedObject private var mesh = MeshSyncService.shared
    @Environment(\.openURL) private var openURL
    @State private var contactsAllowed = ContactAuthorization.canUseSystemPicker

    private var contactsStatus: String {
        switch CNContactStore.authorizationStatus(for: .contacts) {
        case .authorized:
            return "Full Access"
        case .limited:
            return "Limited Access"
        case .denied, .restricted:
            return "Off"
        default:
            return "Not allowed"
        }
    }

    private var accountLabel: String {
        if AuthSession.shared.isGuest { return "Guest" }
        let name = AuthSession.shared.displayName
        if !name.isEmpty { return name }
        return AuthSession.shared.provider.title
    }

    var body: some View {
        Form {
                Section("Nearby sync") {
                    NearbySyncBanner(mesh: mesh) {
                        SyncCoordinator.shared.syncNow()
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                    .listRowBackground(Color.clear)
                }

                Section {
                    HStack {
                        Text("Access")
                        Spacer()
                        Text(contactsStatus)
                            .foregroundStyle(.secondary)
                    }
                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            openURL(url)
                        }
                    } label: {
                        Label("Setting", systemImage: "gear")
                    }
                } header: {
                    Text("Contacts")
                } footer: {
                    Text("Allow Full Access or only selected contacts so you can add friends from your phone.")
                }

                Section("Account") {
                    HStack {
                        Text("Signed in as")
                        Spacer()
                        Text(accountLabel)
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Sign-in method")
                        Spacer()
                        Text(AuthSession.shared.provider.title)
                            .foregroundStyle(.secondary)
                    }
                    if !AuthSession.shared.isGuest, !AuthSession.shared.email.isEmpty {
                        HStack {
                            Text("Email")
                            Spacer()
                            Text(AuthSession.shared.email)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Button("Sign Out", role: .destructive) {
                        AuthSession.shared.signOut()
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
                        Text("1.0")
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
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                contactsAllowed = ContactAuthorization.canUseSystemPicker
            }
    }
}
