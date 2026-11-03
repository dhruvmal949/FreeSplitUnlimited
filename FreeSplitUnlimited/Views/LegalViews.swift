//
//  LegalViews.swift
//  FreeSplitUnlimited
//

import SwiftUI

struct PrivacyPolicyView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Last updated: October 30, 2026")
                    .font(.caption)
                    .foregroundStyle(.tertiary)

                Text("Free Split is a shared expense app for friends. Your splits stay on this iPhone. We do not sell your information or use it for ads.")

                section("What we collect") {
                    "Sign in with Apple or Google gives us your name and email so we can open your account on this phone. Apple can hide your email. Groups, people, expenses, and payments you add stay on this device. Contacts are used only when you pick people to add. Photos are used only if you choose a group cover. You can deny those permissions and type names yourself."
                }

                section("What other people see") {
                    "People in a group or friend split can see the expenses and payments in that split. Expenses are not public."
                }

                section("Third parties") {
                    "Apple and Google process sign-in. We do not share your splits with them for ads or marketing."
                }

                section("Where data is stored") {
                    "On this iPhone. If you share a split, the people you share with get a copy on their phone."
                }

                section("How to delete") {
                    "Open Settings and tap Delete Account to remove your sign-in and local splits from this iPhone."
                }

                section("Children") {
                    "Free Split is not intended for children under 13."
                }
            }
            .padding(20)
        }
        .freeSplitBackground()
        .navigationTitle("Privacy Policy")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(false)
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
                Text("Use Sign in with Apple or Continue with Google. Your splits stay with that account on this iPhone.")
            }
            Section("Groups and friends") {
                Text("Groups are shared trips and bills. Friends holds one-to-one splits.")
            }
            Section("Expenses") {
                Text("Open a group or friend split and tap Add expense. Choose who paid and how to split it.")
            }
            Section("Settle up") {
                Text("Use Settle up when someone pays the other back. Balances only lists people who still owe or are owed.")
            }
            Section("Delete") {
                Text("Swipe left on a group, friend, or notification to remove it. To remove your account, open Settings and tap Delete Account.")
            }
        }
        .freeSplitListStyle()
        .freeSplitBackground()
        .navigationTitle("Support")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(false)
        .avoidsMainTabBar()
    }
}
