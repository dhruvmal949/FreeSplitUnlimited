//
//  AuthSession.swift
//  FreeSplitUnlimited
//
//  Username + password accounts on this iPhone, plus Google.
//

import Combine
import CryptoKit
import Foundation
import LocalAuthentication
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

enum VerificationChannel: String, Codable {
    case email
    case phone
}

struct PendingVerification: Equatable, Identifiable {
    var id: UUID { accountID }
    var accountID: UUID
    var contact: String
    var channel: VerificationChannel
    var expiresAt: Date
}

private struct LocalAccount: Codable {
    var id: UUID
    var username: String
    var firstName: String
    var lastName: String
    var email: String
    var phone: String
    var passwordSalt: String
    var passwordHash: String
    var isVerified: Bool

    enum CodingKeys: String, CodingKey {
        case id, username, firstName, lastName, email, phone
        case passwordSalt, passwordHash, isVerified
    }

    init(
        id: UUID,
        username: String,
        firstName: String,
        lastName: String,
        email: String,
        phone: String,
        passwordSalt: String,
        passwordHash: String,
        isVerified: Bool
    ) {
        self.id = id
        self.username = username
        self.firstName = firstName
        self.lastName = lastName
        self.email = email
        self.phone = phone
        self.passwordSalt = passwordSalt
        self.passwordHash = passwordHash
        self.isVerified = isVerified
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        username = try container.decode(String.self, forKey: .username)
        firstName = try container.decodeIfPresent(String.self, forKey: .firstName) ?? ""
        lastName = try container.decodeIfPresent(String.self, forKey: .lastName) ?? ""
        email = try container.decodeIfPresent(String.self, forKey: .email) ?? ""
        phone = try container.decodeIfPresent(String.self, forKey: .phone) ?? ""
        passwordSalt = try container.decode(String.self, forKey: .passwordSalt)
        passwordHash = try container.decode(String.self, forKey: .passwordHash)
        isVerified = try container.decodeIfPresent(Bool.self, forKey: .isVerified) ?? true
    }
}

private struct PersistedAuth: Codable {
    var provider: String
    var displayName: String
    var email: String
    var isGuest: Bool
    var login: String?
    var accountID: UUID?
}

private struct RememberedCredentials: Codable {
    var login: String
    var password: String
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
    @Published private(set) var pendingVerification: PendingVerification?
    @Published var needsGoogleEmailConfirmation = false
    @Published var needsFaceIDOptIn = false
    @Published private(set) var prefersFaceIDLogin: Bool
    @Published var rememberMe: Bool {
        didSet {
            UserDefaults.standard.set(rememberMe, forKey: Self.rememberMeKey)
            if rememberMe {
                if isAuthenticated { persistSession() }
            } else {
                clearPersistedSession()
                clearRememberedCredentials()
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

    private static var keychainService: String {
        AppLaunchFlags.isAutomatedTesting
            ? "pramela.FreeSplitUnlimited.accounts.testing"
            : "pramela.FreeSplitUnlimited.accounts"
    }
    private static let keychainAccount = "localAccounts.v2"
    private static let sessionAccount = "currentSession.v1"
    private static let unlockAccount = "faceIDUnlock.v1"
    private static let credentialsAccount = "rememberedCredentials.v1"
    private static var rememberMeKey: String {
        AppLaunchFlags.isAutomatedTesting ? "freeSplit.auth.rememberMe.testing" : "freeSplit.auth.rememberMe"
    }
    private static var pairingNameKey: String {
        AppLaunchFlags.isAutomatedTesting ? "freeSplit.auth.pairingName.testing" : "freeSplit.auth.pairingName"
    }
    private static var lastLoginKey: String {
        AppLaunchFlags.isAutomatedTesting ? "freeSplit.auth.lastLogin.testing" : "freeSplit.auth.lastLogin"
    }
    private static var prefersFaceIDKey: String {
        AppLaunchFlags.isAutomatedTesting ? "freeSplit.auth.prefersFaceID.testing" : "freeSplit.auth.prefersFaceID"
    }
    private static var answeredFaceIDKey: String {
        AppLaunchFlags.isAutomatedTesting ? "freeSplit.auth.answeredFaceID.testing" : "freeSplit.auth.answeredFaceID"
    }

    private var pendingCode = ""
    private var stagedPasswordLogin: (account: LocalAccount, login: String, password: String)?
    private var currentLogin = ""
    private var currentAccountID: UUID?
    private var suppressFaceIDUntilRelaunch = false
    private var faceIDUnlockGeneration = 0
    var testingAsksFaceIDOptIn = false

    var testingConfirmationCode: String {
        pendingCode
    }

    private init() {
        rememberMe = UserDefaults.standard.object(forKey: Self.rememberMeKey) as? Bool ?? false
        prefersFaceIDLogin = UserDefaults.standard.bool(forKey: Self.prefersFaceIDKey)
        pairingNickname = UserDefaults.standard.string(forKey: Self.pairingNameKey) ?? ""
        isAuthenticated = false
        isGuest = false
        if AppLaunchFlags.isUITesting {
            wipeTestingAuthStore()
        }
    }

    func resetForTesting() {
        isAuthenticated = false
        isGuest = false
        provider = .guest
        displayName = ""
        email = ""
        lastError = nil
        needsGoogleEmailConfirmation = false
        needsFaceIDOptIn = false
        pendingVerification = nil
        pendingCode = ""
        stagedPasswordLogin = nil
        currentLogin = ""
        currentAccountID = nil
        suppressFaceIDUntilRelaunch = false
        faceIDUnlockGeneration = 0
        testingAsksFaceIDOptIn = false
        rememberMe = false
        prefersFaceIDLogin = false
        pairingNickname = ""
        wipeTestingAuthStore()
        BiometricAuth.resetOverrides()
    }

    var rememberedLogin: String {
        loadRememberedCredentials()?.login
            ?? UserDefaults.standard.string(forKey: Self.lastLoginKey)
            ?? ""
    }

    var rememberedPassword: String {
        loadRememberedCredentials()?.password ?? ""
    }

    var lastUnlockProvider: AuthProvider? {
        guard let saved = loadUnlockSession(), !saved.isGuest else { return nil }
        return AuthProvider(rawValue: saved.provider)
    }

    var unlockAccountHint: String {
        if let account = verifiedPasswordAccountForUnlock() {
            if !account.email.isEmpty { return account.email }
            if !account.phone.isEmpty { return account.phone }
            return displayName(for: account)
        }
        return ""
    }

    var shouldOpenGoogleSignIn: Bool {
        lastUnlockProvider == .google
    }

    var hasUnlockableAccount: Bool {
        verifiedPasswordAccountForUnlock() != nil
    }

    var canOfferFaceID: Bool {
        guard hasUnlockableAccount else { return false }
        return BiometricAuth.canEvaluate().0
    }

    var faceIDButtonTitle: String {
        if AppLaunchFlags.stubBiometrics || BiometricAuth.canEvaluateOverride == true {
            return "Open with Face ID"
        }
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch context.biometryType {
        case .touchID: return "Open with Touch ID"
        default: return "Open with Face ID"
        }
    }

    var lastGoogleEmail: String? {
        guard let saved = loadUnlockSession(), saved.provider == AuthProvider.google.rawValue else { return nil }
        let mail = saved.email.trimmingCharacters(in: .whitespacesAndNewlines)
        return mail.isEmpty ? nil : mail
    }

    func cancelPendingFaceIDUnlock() {
        faceIDUnlockGeneration += 1
        BiometricAuth.cancel()
    }

    func unlockWithFaceID() async -> String? {
        lastError = nil
        let generation = faceIDUnlockGeneration
        guard verifiedPasswordAccountForUnlock() != nil else {
            return "Create an account and sign in first, then you can use Face ID."
        }
        let availability = BiometricAuth.canEvaluate()
        guard availability.0 else {
            return availability.1 ?? "Face ID isn’t available on this iPhone."
        }
        do {
            let matched = try await BiometricAuth.evaluate(reason: "Open your Free Split account")
            guard generation == faceIDUnlockGeneration else { return nil }
            guard matched else { return "Face ID didn’t match." }
            guard restoreVerifiedPasswordSession() else { return "We couldn’t restore your account. Sign in again." }
            return nil
        } catch {
            let ns = error as NSError
            if ns.code == LAError.userCancel.rawValue
                || ns.code == LAError.appCancel.rawValue
                || ns.code == LAError.systemCancel.rawValue {
                return nil
            }
            return error.localizedDescription
        }
    }

    func confirmGoogleEmail(_ raw: String) -> String? {
        let mail = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isValidEmail(mail) else { return "Enter the Google email you just signed in with." }
        let name = mail.split(separator: "@").first.map(String.init) ?? "Google"
        needsGoogleEmailConfirmation = false
        finishSocialLogin(provider: .google, name: name, email: mail)
        return nil
    }

    func logIn(username: String, password: String) -> String? {
        lastError = nil
        let user = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !user.isEmpty else { return "Enter your email or phone number." }
        guard !password.isEmpty else { return "Enter a password." }

        let accounts = loadAccounts()
        guard let index = accounts.firstIndex(where: { matchesLogin($0, user) }) else {
            return "No account with that email or phone. Create an account first."
        }
        guard hashPassword(password, salt: accounts[index].passwordSalt) == accounts[index].passwordHash else {
            return "Wrong password."
        }
        guard accounts[index].isVerified else {
            startVerification(for: accounts[index])
            return "Confirm your email or phone number first. We sent a new code."
        }

        if shouldAskFaceIDOptIn {
            stagedPasswordLogin = (accounts[index], user, password)
            needsFaceIDOptIn = true
            return nil
        }

        finishPasswordLogin(account: accounts[index], login: user, password: password)
        return nil
    }

    func answerFaceIDOptIn(_ enabled: Bool) {
        prefersFaceIDLogin = enabled
        UserDefaults.standard.set(enabled, forKey: Self.prefersFaceIDKey)
        UserDefaults.standard.set(true, forKey: Self.answeredFaceIDKey)
        needsFaceIDOptIn = false
        guard let staged = stagedPasswordLogin else { return }
        stagedPasswordLogin = nil
        finishPasswordLogin(account: staged.account, login: staged.login, password: staged.password)
    }

    var shouldAutoPromptFaceID: Bool {
        prefersFaceIDLogin && canOfferFaceID && !suppressFaceIDUntilRelaunch && !AppLaunchFlags.isUITesting
    }

    func beginRegistration(
        firstName: String,
        lastName: String,
        contact: String,
        password: String,
        confirmPassword: String
    ) -> String? {
        let parsed = parseContact(contact)
        if let error = parsed.error { return error }
        return beginRegistration(
            firstName: firstName,
            lastName: lastName,
            email: parsed.email,
            phone: parsed.phone,
            password: password,
            confirmPassword: confirmPassword
        )
    }

    func beginRegistration(
        firstName: String,
        lastName: String,
        email: String,
        phone: String,
        password: String,
        confirmPassword: String
    ) -> String? {
        lastError = nil
        let first = firstName.trimmingCharacters(in: .whitespacesAndNewlines)
        let last = lastName.trimmingCharacters(in: .whitespacesAndNewlines)
        let mail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let number = normalizedPhone(phone)
        guard !first.isEmpty else { return "Enter your first name." }
        guard !last.isEmpty else { return "Enter your last name." }
        guard !mail.isEmpty || !number.isEmpty else { return "Enter an email or a 10-digit US phone number." }
        if !mail.isEmpty, !isValidEmail(mail) { return "Enter a valid email address." }
        if !number.isEmpty, number.count != 10 { return "Enter a 10-digit US phone number." }
        guard password.count >= 6 else { return "Password needs at least 6 characters." }
        guard password == confirmPassword else { return "Passwords don't match." }

        let login = mail.isEmpty ? number : mail
        var accounts = loadAccounts()
        if !mail.isEmpty, accounts.contains(where: { matchesLogin($0, mail) }) {
            return "An account with that email already exists. Sign in, or use a different phone or email."
        }
        if !number.isEmpty, accounts.contains(where: { matchesLogin($0, number) }) {
            return "An account with that phone number already exists. Sign in, or use a different phone or email."
        }

        let salt = UUID().uuidString
        let account = LocalAccount(
            id: UUID(),
            username: login,
            firstName: first,
            lastName: last,
            email: mail,
            phone: number,
            passwordSalt: salt,
            passwordHash: hashPassword(password, salt: salt),
            isVerified: true
        )
        accounts.append(account)
        saveAccounts(accounts)
        pendingVerification = nil
        pendingCode = ""
        UserDefaults.standard.set(login, forKey: Self.lastLoginKey)
        pointUnlockSession(at: account)
        return nil
    }

    enum ExistingAccountKind {
        case email
        case phone
    }

    func existingAccount(matching contact: String) -> ExistingAccountKind? {
        let parsed = parseContact(contact)
        guard parsed.error == nil else { return nil }
        let accounts = loadAccounts()
        if !parsed.email.isEmpty, accounts.contains(where: { matchesLogin($0, parsed.email) }) {
            return .email
        }
        if !parsed.phone.isEmpty, accounts.contains(where: { matchesLogin($0, parsed.phone) }) {
            return .phone
        }
        return nil
    }

    func confirmRegistration(code: String) -> String? {
        lastError = nil
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let pending = pendingVerification else { return "Start creating an account first." }
        guard Date() < pending.expiresAt else { return "That code expired. Tap Resend code." }
        guard trimmed == pendingCode else { return "That code doesn’t match. Try again." }

        var accounts = loadAccounts()
        guard let index = accounts.firstIndex(where: { $0.id == pending.accountID }) else {
            return "We couldn't find that account."
        }
        accounts[index].isVerified = true
        saveAccounts(accounts)
        pendingVerification = nil
        pendingCode = ""
        UserDefaults.standard.set(accounts[index].username, forKey: Self.lastLoginKey)
        applySession(
            provider: .password,
            name: displayName(for: accounts[index]),
            email: accounts[index].email,
            guest: false,
            login: accounts[index].username,
            accountID: accounts[index].id
        )
        return nil
    }

    func resendConfirmationCode() -> String? {
        guard let pending = pendingVerification else { return "Start creating an account first." }
        let accounts = loadAccounts()
        guard let account = accounts.first(where: { $0.id == pending.accountID }) else {
            return "We couldn't find that account."
        }
        startVerification(for: account)
        return nil
    }

    func confirmationMessage() -> String {
        "Your Free Split confirmation code is \(pendingCode). It expires in 10 minutes."
    }

    func createAccount(username: String, password: String, confirmPassword: String) -> String? {
        beginRegistration(
            firstName: username,
            lastName: "User",
            email: username.contains("@") ? username : "",
            phone: username.contains("@") ? "" : username,
            password: password,
            confirmPassword: confirmPassword
        )
    }

    func resetPassword(username: String, newPassword: String, confirmPassword: String) -> String? {
        lastError = nil
        let user = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !user.isEmpty else { return "Enter your email or phone number." }
        if user.contains("@") {
            guard isValidEmail(user) else { return "Enter a valid email address." }
        } else {
            guard usPhoneDigits(user).count == 10 else { return "Enter a 10-digit phone number." }
        }
        guard newPassword.count >= 6 else { return "Password needs at least 6 characters." }
        guard newPassword == confirmPassword else { return "Passwords don't match." }

        var accounts = loadAccounts()
        guard let index = accounts.firstIndex(where: { matchesLogin($0, user) }) else {
            return "No account with that email or phone on this iPhone."
        }

        let salt = UUID().uuidString
        accounts[index].passwordSalt = salt
        accounts[index].passwordHash = hashPassword(newPassword, salt: salt)
        saveAccounts(accounts)
        UserDefaults.standard.set(accounts[index].username, forKey: Self.lastLoginKey)
        rememberCredentialsIfNeeded(login: accounts[index].username, password: newPassword)
        pointUnlockSession(at: accounts[index])
        if isAuthenticated {
            signOut()
        }
        return nil
    }

    func continueAsGuest() {
        lastError = nil
        applySession(provider: .guest, name: "Guest", email: "", guest: true)
    }

    func finishSocialLogin(provider: AuthProvider, name: String, email: String?) {
        lastError = nil
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let mail = email?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        applySession(
            provider: provider,
            name: trimmed.isEmpty ? provider.title : trimmed,
            email: mail,
            guest: false,
            login: mail
        )
    }

    private func startVerification(for account: LocalAccount) {
        let channel: VerificationChannel = account.email.isEmpty ? .phone : .email
        let contact = channel == .email ? account.email : account.phone
        pendingCode = String(format: "%06d", Int.random(in: 0...999_999))
        pendingVerification = PendingVerification(
            accountID: account.id,
            contact: contact,
            channel: channel,
            expiresAt: Date().addingTimeInterval(10 * 60)
        )
    }

    private func displayName(for account: LocalAccount) -> String {
        let full = "\(account.firstName) \(account.lastName)".trimmingCharacters(in: .whitespacesAndNewlines)
        return full.isEmpty ? account.username : full
    }

    private func matchesLogin(_ account: LocalAccount, _ raw: String) -> Bool {
        let login = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if account.username.caseInsensitiveCompare(login) == .orderedSame { return true }
        if !account.email.isEmpty, account.email.caseInsensitiveCompare(login) == .orderedSame { return true }
        let phone = normalizedPhone(login)
        let stored = normalizedPhone(account.phone)
        return phone.count == 10 && stored.count == 10 && stored == phone
    }

    private func normalizedPhone(_ raw: String) -> String {
        var digits = raw.filter(\.isNumber)
        if digits.hasPrefix("1"), digits.count != 10 {
            digits.removeFirst()
        }
        return digits
    }

    func signOut() {
        isAuthenticated = false
        isGuest = false
        provider = .guest
        displayName = ""
        email = ""
        lastError = nil
        needsGoogleEmailConfirmation = false
        needsFaceIDOptIn = false
        stagedPasswordLogin = nil
        currentLogin = ""
        currentAccountID = nil
        suppressFaceIDUntilRelaunch = true
        clearPersistedSession()
    }

    private var shouldAskFaceIDOptIn: Bool {
        if AppLaunchFlags.isUITesting { return false }
        if AppLaunchFlags.isUnitTesting && !testingAsksFaceIDOptIn { return false }
        guard !UserDefaults.standard.bool(forKey: Self.answeredFaceIDKey) else { return false }
        return BiometricAuth.canEvaluate().0
    }

    private func finishPasswordLogin(account: LocalAccount, login: String, password: String) {
        UserDefaults.standard.set(account.username, forKey: Self.lastLoginKey)
        rememberCredentialsIfNeeded(login: login, password: password)
        applySession(
            provider: .password,
            name: displayName(for: account),
            email: account.email,
            guest: false,
            login: account.username,
            accountID: account.id
        )
    }

    private func parseContact(_ raw: String) -> (email: String, phone: String, error: String?) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return ("", "", "Enter an email or a 10-digit US phone number.")
        }
        if trimmed.contains("@") {
            if isValidEmail(trimmed) { return (trimmed, "", nil) }
            return ("", "", "Enter a valid email address.")
        }
        let digits = normalizedPhone(trimmed)
        if digits.count != 10 {
            return ("", "", "Enter a 10-digit US phone number.")
        }
        return ("", digits, nil)
    }

    private func applySession(
        provider: AuthProvider,
        name: String,
        email: String,
        guest: Bool,
        login: String = "",
        accountID: UUID? = nil
    ) {
        self.provider = provider
        displayName = name
        self.email = email
        isGuest = guest
        isAuthenticated = true
        currentLogin = login.isEmpty ? email : login
        currentAccountID = accountID
        persistSession()
        if guest {
            currentLogin = ""
            currentAccountID = nil
            clearUnlockSession()
        } else {
            saveUnlockSession()
        }
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
            isGuest: isGuest,
            login: currentLogin.isEmpty ? nil : currentLogin,
            accountID: currentAccountID
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
        currentLogin = saved.login ?? saved.email
        currentAccountID = saved.accountID
    }

    private func clearPersistedSession() {
        deleteKeychain(account: Self.sessionAccount)
    }

    private func saveUnlockSession() {
        let saved = PersistedAuth(
            provider: provider.rawValue,
            displayName: displayName,
            email: email,
            isGuest: false,
            login: currentLogin.isEmpty ? nil : currentLogin,
            accountID: currentAccountID
        )
        guard let data = try? JSONEncoder().encode(saved) else { return }
        writeKeychain(account: Self.unlockAccount, data: data)
    }

    private func pointUnlockSession(at account: LocalAccount) {
        let saved = PersistedAuth(
            provider: AuthProvider.password.rawValue,
            displayName: displayName(for: account),
            email: account.email,
            isGuest: false,
            login: account.username,
            accountID: account.id
        )
        guard let data = try? JSONEncoder().encode(saved) else { return }
        writeKeychain(account: Self.unlockAccount, data: data)
    }

    private func loadUnlockSession() -> PersistedAuth? {
        guard let data = readKeychain(account: Self.unlockAccount) else { return nil }
        return try? JSONDecoder().decode(PersistedAuth.self, from: data)
    }

    func restoreLastGoogleAccount() -> Bool {
        guard let saved = loadUnlockSession(),
              !saved.isGuest,
              saved.provider == AuthProvider.google.rawValue,
              !saved.email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        provider = .google
        displayName = saved.displayName
        email = saved.email
        isGuest = false
        isAuthenticated = true
        currentLogin = saved.login ?? saved.email
        currentAccountID = saved.accountID
        persistSession()
        return true
    }

    @discardableResult
    private func restoreVerifiedPasswordSession() -> Bool {
        guard let account = verifiedPasswordAccountForUnlock() else { return false }
        applySession(
            provider: .password,
            name: displayName(for: account),
            email: account.email,
            guest: false,
            login: account.username,
            accountID: account.id
        )
        return true
    }

    private func verifiedPasswordAccountForUnlock() -> LocalAccount? {
        let accounts = loadAccounts().filter(\.isVerified)
        guard !accounts.isEmpty else { return nil }

        if let saved = loadUnlockSession(),
           !saved.isGuest,
           saved.provider == AuthProvider.password.rawValue {
            if let id = saved.accountID, let match = accounts.first(where: { $0.id == id }) {
                return match
            }
            if let login = saved.login, !login.isEmpty, let match = accounts.first(where: { matchesLogin($0, login) }) {
                return match
            }
            if !saved.email.isEmpty, let match = accounts.first(where: { matchesLogin($0, saved.email) }) {
                return match
            }
        }
        let remembered = rememberedLogin
        if !remembered.isEmpty, let match = accounts.first(where: { matchesLogin($0, remembered) }) {
            return match
        }
        if accounts.count == 1 { return accounts[0] }
        return nil
    }

    private func wipeTestingAuthStore() {
        deleteKeychain(account: Self.keychainAccount)
        deleteKeychain(account: Self.sessionAccount)
        deleteKeychain(account: Self.unlockAccount)
        deleteKeychain(account: Self.credentialsAccount)
        UserDefaults.standard.removeObject(forKey: Self.lastLoginKey)
        UserDefaults.standard.removeObject(forKey: Self.rememberMeKey)
        UserDefaults.standard.removeObject(forKey: Self.pairingNameKey)
        UserDefaults.standard.removeObject(forKey: Self.prefersFaceIDKey)
        UserDefaults.standard.removeObject(forKey: Self.answeredFaceIDKey)
    }

    func saveRememberedCredentials(login: String, password: String) {
        rememberCredentialsIfNeeded(login: login, password: password)
    }

    private func rememberCredentialsIfNeeded(login: String, password: String) {
        guard rememberMe else {
            clearRememberedCredentials()
            return
        }
        let user = login.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !user.isEmpty, !password.isEmpty else { return }
        let saved = RememberedCredentials(login: user, password: password)
        guard let data = try? JSONEncoder().encode(saved) else { return }
        writeKeychain(account: Self.credentialsAccount, data: data)
        UserDefaults.standard.set(user, forKey: Self.lastLoginKey)
    }

    private func loadRememberedCredentials() -> RememberedCredentials? {
        guard rememberMe, let data = readKeychain(account: Self.credentialsAccount) else { return nil }
        return try? JSONDecoder().decode(RememberedCredentials.self, from: data)
    }

    private func clearRememberedCredentials() {
        deleteKeychain(account: Self.credentialsAccount)
    }

    private func clearUnlockSession() {
        deleteKeychain(account: Self.unlockAccount)
    }

    private func writeKeychain(account: String, data: Data) {
        deleteKeychain(account: account)
        let add: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        SecItemAdd(add as CFDictionary, nil)
    }

    private func readKeychain(account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess else { return nil }
        return item as? Data
    }

    private func deleteKeychain(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: account
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
