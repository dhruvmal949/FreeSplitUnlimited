//
//  LegalViews.swift
//  FreeSplitUnlimited
//

import SwiftUI

enum AppLegal {
    static let privacyURL = URL(string: "https://dhruvmal949.github.io/FreeSplitUnlimited/privacy.html")
    static let supportURL = URL(string: "https://dhruvmal949.github.io/FreeSplitUnlimited/support.html")
}

struct PrivacyPolicyView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Free Split keeps your data on this iPhone. We do not sell data or use it for advertising.")

                section("Sign in") {
                    "You can sign in with Apple or Google. We only use your name and email to open your account on this phone. Sign in with Apple lets you hide your email. Google Sign-In is not used for ads."
                }

                section("Optional access") {
                    "Contacts, photos, Bluetooth, and local network are used only when you add friends, pick a group photo, or sync a split with a nearby phone. You can deny those permissions."
                }

                section("Splits") {
                    "Groups, expenses, and payments stay on this device. If you sync with a friend nearby or share a file, that copy lives on their phone too."
                }

                section("Delete your account") {
                    "Settings → Delete Account removes your sign-in and local splits from this iPhone."
                }
            }
            .padding(20)
        }
        .freeSplitBackground()
        .navigationTitle("Privacy Policy")
        .navigationBarTitleDisplayMode(.inline)
        .homeBackButton()
        .avoidsMainTabBar()
    }

    private func section(_ title: String, _ body: () -> String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.headline)
            Text(body())
                .font(.body)
                .foregroundStyle(.secondary)
        }
    }
}

struct SupportView: View {
    var body: some View {
        List {
            Section("Sign in") {
                Text("Use Sign in with Apple or Continue with Google. Email and password sign-in is not offered yet.")
            }
            Section("Try the app") {
                Text("After you sign in, open Groups and tap Create Group. Add people, an expense, and a payment to see the full split flow. Friends holds one-to-one splits.")
            }
            Section("Help") {
                if let url = AppLegal.supportURL {
                    Link("Open support page", destination: url)
                }
                if let privacy = AppLegal.privacyURL {
                    Link("Open privacy policy", destination: privacy)
                }
            }
        }
        .freeSplitListStyle()
        .freeSplitBackground()
        .navigationTitle("Support")
        .navigationBarTitleDisplayMode(.inline)
        .homeBackButton()
        .avoidsMainTabBar()
    }
}
