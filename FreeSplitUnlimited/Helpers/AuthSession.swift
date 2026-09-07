//
//  AuthSession.swift
//  FreeSplitUnlimited
//
//  Username + password accounts on this iPhone, plus Apple / Google / Facebook.
//

import Combine
import CryptoKit
import Foundation
import Security

enum AuthProvider: String {
    case password
    case apple
    case google
    case facebook
    case guest

    var title: String {
        switch self {
        case .password: return "Username"
        case .apple: return "Apple"
        case .google: return "Google"
        case .facebook: return "Facebook"
        case .guest: return "Guest"
        }
    }
}

private struct LocalAccount: Codable {
    var id: UUID
    var username: String
    var passwordSalt: String
    var passwordHash: String
}

private struct PersistedAuth: Codable {
    var provider: String
    var displayName: String
    var email: String
    var isGuest: Bool
}

@MainActor
final class AuthSession: ObservableObject {
    static let shared = AuthSession()

    @Published private(set) var isAuthenticated = false
    @Published private(set) var isGuest = false
    @Published private(set) var provider: AuthProvider = .guest
    @Published private(set) var displayName = ""
    @Published private(set) var pairingNickname = ""
    @Published private(set) var email = ""
    @Published var lastError: String?
    @Published var rememberMe: Bool {
        didSet {
            UserDefaults.standard.set(rememberMe, forKey: Self.rememberMeKey)
            if rememberMe {
                if isAuthenticated { persistSession() }
            } else {
                clearPersistedSession()
            }
        }
    }

    /// Names that count as you when totaling balances (`Me` plus your sign-in name).
    var selfNames: [String] {
        var names = ["Me"]
        for extra in [displayName, pairingNickname] {
            let trimmed = extra.trimmingCharacters(in: .whitespacesAndNewlines)
            guard FriendPairing.isUsableName(trimmed) else { continue }
            if names.contains(where: { FriendPairing.namesMatch($0, trimmed) }) { continue }
            names.append(trimmed)
        }
        return names
    }

    /// Name the other phone should type to connect a 1:1 split with you.
    var pairingName: String {
        let signedIn = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if FriendPairing.isUsableName(signedIn) { return signedIn }
        return pairingNickname.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func setPairingNickname(_ raw: String) {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        pairingNickname = FriendPairing.isUsableName(name) ? name : ""
        UserDefaults.standard.set(pairingNickname, forKey: Self.pairingNameKey)
    }

    private static let keychainService = "pramela.FreeSplitUnlimited.accounts"
    private static let keychainAccount = "localAccounts.v2"
    private static let sessionAccount = "currentSession.v1"
    private static let rememberMeKey = "freeSplit.auth.rememberMe"
    private static let pairingNameKey = "freeSplit.auth.pairingName"

    private init() {
        rememberMe = UserDefaults.standard.object(forKey: Self.rememberMeKey) as? Bool ?? true
        pairingNickname = UserDefaults.standard.string(forKey: Self.pairingNameKey) ?? ""
        restoreSession()
    }

    func logIn(username: String, password: String) -> String? {
        lastError = nil
        let user = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !user.isEmpty else { return "Enter a username." }
        guard !password.isEmpty else { return "Enter a password." }

        let accounts = loadAccounts()
        guard let account = accounts.first(where: { $0.username.caseInsensitiveCompare(user) == .orderedSame }) else {
            return "No account with that username. Create a new account first."
        }
        guard hashPassword(password, salt: account.passwordSalt) == account.passwordHash else {
            return "Wrong password."
        }

        applySession(provider: .password, name: account.username, email: "", guest: false)
        return nil
    }

    func createAccount(username: String, password: String, confirmPassword: String) -> String? {
        lastError = nil
        let user = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard user.count >= 3 else { return "Username needs at least 3 characters." }
        guard password.count >= 6 else { return "Password needs at least 6 characters." }
        guard password == confirmPassword else { return "Passwords don't match." }

        var accounts = loadAccounts()
        if accounts.contains(where: { $0.username.caseInsensitiveCompare(user) == .orderedSame }) {
            return "That username is already taken."
        }

        let salt = UUID().uuidString
        accounts.append(
            LocalAccount(
                id: UUID(),
                username: user,
                passwordSalt: salt,
                passwordHash: hashPassword(password, salt: salt)
            )
        )
        saveAccounts(accounts)

        applySession(provider: .password, name: user, email: "", guest: false)
        return nil
    }

    func resetPassword(username: String, newPassword: String, confirmPassword: String) -> String? {
        lastError = nil
        let user = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !user.isEmpty else { return "Enter your username." }
        guard newPassword.count >= 6 else { return "Password needs at least 6 characters." }
        guard newPassword == confirmPassword else { return "Passwords don't match." }

        var accounts = loadAccounts()
        guard let index = accounts.firstIndex(where: { $0.username.caseInsensitiveCompare(user) == .orderedSame }) else {
            return "No account with that username on this iPhone."
        }

        let salt = UUID().uuidString
        accounts[index].passwordSalt = salt
        accounts[index].passwordHash = hashPassword(newPassword, salt: salt)
        saveAccounts(accounts)
        applySession(provider: .password, name: accounts[index].username, email: "", guest: false)
        return nil
    }

    func continueAsGuest() {
        lastError = nil
        applySession(provider: .guest, name: "Guest", email: "", guest: true)
    }

    func finishSocialLogin(provider: AuthProvider, name: String, email: String?) {
        lastError = nil
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        applySession(
            provider: provider,
            name: trimmed.isEmpty ? provider.title : trimmed,
            email: email?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            guest: false
        )
    }

    func signOut() {
        isAuthenticated = false
        isGuest = false
        provider = .guest
        displayName = ""
        email = ""
        lastError = nil
        clearPersistedSession()
    }

    private func applySession(provider: AuthProvider, name: String, email: String, guest: Bool) {
        self.provider = provider
        displayName = name
        self.email = email
        isGuest = guest
        isAuthenticated = true
        persistSession()
    }

    private func persistSession() {
        guard rememberMe else {
            clearPersistedSession()
            return
        }
        let saved = PersistedAuth(
            provider: provider.rawValue,
            displayName: displayName,
            email: email,
            isGuest: isGuest
        )
        guard let data = try? JSONEncoder().encode(saved) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: Self.sessionAccount
        ]
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }

    private func restoreSession() {
        guard rememberMe else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: Self.sessionAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let saved = try? JSONDecoder().decode(PersistedAuth.self, from: data) else {
            return
        }
        provider = AuthProvider(rawValue: saved.provider) ?? .guest
        displayName = saved.displayName
        email = saved.email
        isGuest = saved.isGuest
        isAuthenticated = true
    }

    private func clearPersistedSession() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: Self.sessionAccount
        ]
        SecItemDelete(query as CFDictionary)
    }

    private func hashPassword(_ password: String, salt: String) -> String {
        let digest = SHA256.hash(data: Data((salt + password).utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func loadAccounts() -> [LocalAccount] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: Self.keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return [] }
        return (try? JSONDecoder().decode([LocalAccount].self, from: data)) ?? []
    }

    private func saveAccounts(_ accounts: [LocalAccount]) {
        guard let data = try? JSONEncoder().encode(accounts) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: Self.keychainAccount
        ]
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }
}
