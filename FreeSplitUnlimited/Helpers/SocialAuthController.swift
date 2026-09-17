//
//  SocialAuthController.swift
//  FreeSplitUnlimited
//
//  Google Sign-In: tapping Google presents Google Auth and signs into the app
//  with that Google account.
//

import AuthenticationServices
import Foundation
import GoogleSignIn
import UIKit

final class SocialAuthController: NSObject {
    static let shared = SocialAuthController()

    func signInWithGoogle() {
        Task { @MainActor in
            await presentGoogleSignIn()
        }
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
