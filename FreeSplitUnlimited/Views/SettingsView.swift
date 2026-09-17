//
//  SettingsView.swift
//  FreeSplitUnlimited
//

import Contacts
import SwiftUI

struct SettingsView: View {
    @ObservedObject private var mesh = MeshSyncService.shared
    @ObservedObject private var session = AuthSession.shared
    @Environment(\.openURL) private var openURL
    @State private var contactsAllowed = ContactAuthorization.canUseSystemPicker

    private var contactsStatus: String {
        switch CNContactStore.authorizationStatus(for: .contacts) {
        case .authorized:
            return "Full Access"
        case .limited:
            return "Selected contacts"
        case .denied, .restricted:
            return "Off"
        default:
            return "Not asked yet"
        }
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
                        Label("Change in Settings", systemImage: "gear")
                    }
                } header: {
                    Text("Contacts")
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
