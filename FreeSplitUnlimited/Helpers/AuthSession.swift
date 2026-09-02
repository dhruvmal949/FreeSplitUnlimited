//
//  AuthSession.swift
//  FreeSplitUnlimited
//

import Foundation
import Combine

@MainActor
final class AuthSession: ObservableObject {
    static let shared = AuthSession()

    @Published private(set) var isAuthenticated = false
    @Published private(set) var isGuest = false
    @Published private(set) var username = ""

    private init() {
        // Always start on the login screen. Previous Guest/Login skips are cleared.
        UserDefaults.standard.removeObject(forKey: "freeSplit.auth.isAuthenticated")
        UserDefaults.standard.removeObject(forKey: "freeSplit.auth.isGuest")
        UserDefaults.standard.removeObject(forKey: "freeSplit.auth.username")
    }

    func logIn(username: String, password: String) -> String? {
        let name = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let pass = password.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return "Enter a username." }
        guard !pass.isEmpty else { return "Enter a password." }

        isGuest = false
        self.username = name
        isAuthenticated = true
        return nil
    }

    func continueAsGuest() {
        isGuest = true
        username = "Guest"
        isAuthenticated = true
    }

    func signOut() {
        isAuthenticated = false
        isGuest = false
        username = ""
    }
}
