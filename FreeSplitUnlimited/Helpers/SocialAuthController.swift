//
//  SocialAuthController.swift
//  FreeSplitUnlimited
//
//  Google and Sign in with Apple: tapping a button opens that account
//  and signs into the app.
//

import AuthenticationServices
import Foundation
import GoogleSignIn
import UIKit

final class SocialAuthController: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    static let shared = SocialAuthController()
    private var appleController: ASAuthorizationController?

    func signInWithGoogle() {
        Task { @MainActor in
            await presentGoogleSignIn()
        }
    }

    @MainActor
    func signInWithApple() {
        AuthSession.shared.lastError = nil
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName, .email]
        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        appleController = controller
        controller.performRequests()
    }

    func handleURL(_ url: URL) -> Bool {
        GIDSignIn.sharedInstance.handle(url)
    }

    @MainActor
    private func presentGoogleSignIn() async {
        AuthSession.shared.lastError = nil

        guard let presenter = topPresenter() else {
            AuthSession.shared.lastError = "Couldn’t open Google sign-in."
            return
        }

        let clientID = GoogleOAuth.clientID
        guard GoogleOAuth.isConfigured else {
            AuthSession.shared.lastError = "Google Sign-In needs an iOS OAuth client ID (GIDClientID)."
            return
        }

        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)

        do {
            let result = try await GIDSignIn.sharedInstance.signIn(
                withPresenting: presenter,
                hint: AuthSession.shared.lastGoogleEmail
            )
            let profile = result.user.profile
            let email = profile?.email.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let name = profile?.name.trimmingCharacters(in: .whitespacesAndNewlines)
                ?? email.split(separator: "@").first.map(String.init)
                ?? "Google"
            guard isValidEmail(email) else {
                AuthSession.shared.lastError = "Google didn’t return an email address."
                return
            }
            AuthSession.shared.finishSocialLogin(provider: .google, name: name, email: email)
        } catch {
            let ns = error as NSError
            if ns.domain == kGIDSignInErrorDomain,
               ns.code == GIDSignInError.canceled.rawValue {
                return
            }
            AuthSession.shared.lastError = error.localizedDescription
        }
    }

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        Task { @MainActor in
            self.finishAppleSignIn(authorization)
        }
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        Task { @MainActor in
            self.appleController = nil
            let ns = error as NSError
            if ns.domain == ASAuthorizationError.errorDomain,
               ns.code == ASAuthorizationError.canceled.rawValue
                || ns.code == ASAuthorizationError.unknown.rawValue {
                return
            }
            AuthSession.shared.lastError = error.localizedDescription
        }
    }

    @MainActor
    private func finishAppleSignIn(_ authorization: ASAuthorization) {
        appleController = nil
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            AuthSession.shared.lastError = "Apple didn’t return an account."
            return
        }

        let userID = credential.user
        let sharedEmail = credential.email?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let sharedName = credential.fullName.map {
            PersonNameComponentsFormatter().string(from: $0).trimmingCharacters(in: .whitespacesAndNewlines)
        } ?? ""
        let stored = AppleIdentityStore.load(userID: userID)
        let email = isValidEmail(sharedEmail) ? sharedEmail : (stored?.email ?? "")
        let fallbackName = stored.flatMap { $0.name.isEmpty ? nil : $0.name }
            ?? email.split(separator: "@").first.map(String.init)
            ?? "Apple"
        let name = sharedName.isEmpty ? fallbackName : sharedName

        guard isValidEmail(email) else {
            AuthSession.shared.lastError = "Apple didn’t share an email. Choose Share My Email or Hide My Email, then try again."
            return
        }
        AppleIdentityStore.save(userID: userID, email: email, name: name)
        AuthSession.shared.finishSocialLogin(provider: .apple, name: name, email: email)
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        currentWindow() ?? ASPresentationAnchor()
    }

    private func topPresenter() -> UIViewController? {
        guard let root = currentWindow()?.rootViewController else { return nil }
        var top = root
        while let presented = top.presentedViewController {
            top = presented
        }
        return top
    }

    private func currentWindow() -> UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
    }
}

/// Apple only sends name/email the first time. Remember them for later sign-ins.
enum AppleIdentityStore {
    private struct Identity: Codable {
        var email: String
        var name: String
    }

    private static let key = "freeSplit.appleIdentities"

    static func save(userID: String, email: String, name: String) {
        var all = loadAll()
        all[userID] = Identity(email: email, name: name)
        guard let data = try? JSONEncoder().encode(all) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    static func load(userID: String) -> (email: String, name: String)? {
        guard let identity = loadAll()[userID] else { return nil }
        return (identity.email, identity.name)
    }

    static func remove(email: String) {
        let needle = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return }
        var all = loadAll()
        all = all.filter {
            $0.value.email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() != needle
        }
        guard let data = try? JSONEncoder().encode(all) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    static func resetForTesting() {
        UserDefaults.standard.removeObject(forKey: key)
    }

    private static func loadAll() -> [String: Identity] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let all = try? JSONDecoder().decode([String: Identity].self, from: data) else {
            return [:]
        }
        return all
    }
}
