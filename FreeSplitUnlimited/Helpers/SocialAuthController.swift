//
//  SocialAuthController.swift
//  FreeSplitUnlimited
//
//  Sign in with Apple (native). Google / Facebook open a browser sign-in sheet
//  when a client/app ID is configured.
//

import AuthenticationServices
import Foundation
import UIKit

final class SocialAuthController: NSObject {
    static let shared = SocialAuthController()

    /// iOS OAuth client ID from Google Cloud Console (type: iOS). Leave empty until you add one.
    static let googleClientID = ""
    /// Facebook App ID from developers.facebook.com. Leave empty until you add one.
    static let facebookAppID = ""

    private var appleController: ASAuthorizationController?
    private var webSession: ASWebAuthenticationSession?

    func signInWithApple() {
        Task { @MainActor in
            AuthSession.shared.lastError = nil
        }
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName, .email]
        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        appleController = controller
        controller.performRequests()
    }

    func signInWithGoogle() {
        Task { @MainActor in
            AuthSession.shared.lastError = nil
        }
        let clientID = Self.googleClientID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clientID.isEmpty else {
            Task { @MainActor in
                AuthSession.shared.lastError = "Google Sign-In needs a Google Cloud iOS OAuth client ID. Use Apple or Guest until that’s added."
            }
            return
        }

        let reversed = clientID.split(separator: ".").reversed().joined(separator: ".")
        guard var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth") else { return }
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: "\(reversed):/oauth2redirect"),
            URLQueryItem(name: "response_type", value: "token"),
            URLQueryItem(name: "scope", value: "email profile"),
        ]
        guard let url = components.url else { return }
        startWebAuth(url: url, callbackScheme: String(reversed.split(separator: ".").first ?? Substring(reversed))) { _ in
            Task { @MainActor in
                AuthSession.shared.finishSocialLogin(provider: .google, name: "Google", email: nil)
            }
        }
    }

    func signInWithFacebook() {
        Task { @MainActor in
            AuthSession.shared.lastError = nil
        }
        let appID = Self.facebookAppID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !appID.isEmpty else {
            Task { @MainActor in
                AuthSession.shared.lastError = "Facebook login needs a Facebook App ID. Use Apple, Google, or Guest until that’s added."
            }
            return
        }

        guard var components = URLComponents(string: "https://www.facebook.com/v21.0/dialog/oauth") else { return }
        components.queryItems = [
            URLQueryItem(name: "client_id", value: appID),
            URLQueryItem(name: "redirect_uri", value: "fb\(appID)://authorize"),
            URLQueryItem(name: "response_type", value: "token"),
            URLQueryItem(name: "scope", value: "public_profile,email"),
        ]
        guard let url = components.url else { return }
        startWebAuth(url: url, callbackScheme: "fb\(appID)") { _ in
            Task { @MainActor in
                AuthSession.shared.finishSocialLogin(provider: .facebook, name: "Facebook", email: nil)
            }
        }
    }

    private func startWebAuth(url: URL, callbackScheme: String, onSuccess: @escaping (URL) -> Void) {
        let session = ASWebAuthenticationSession(url: url, callbackURLScheme: callbackScheme) { callbackURL, error in
            if let error {
                let ns = error as NSError
                if ns.code == ASWebAuthenticationSessionError.canceledLogin.rawValue { return }
                Task { @MainActor in
                    AuthSession.shared.lastError = error.localizedDescription
                }
                return
            }
            guard let callbackURL else {
                Task { @MainActor in
                    AuthSession.shared.lastError = "Sign-in didn’t finish."
                }
                return
            }
            onSuccess(callbackURL)
        }
        session.presentationContextProvider = self
        session.prefersEphemeralWebBrowserSession = true
        webSession = session
        if !session.start() {
            Task { @MainActor in
                AuthSession.shared.lastError = "Couldn’t open the sign-in page."
            }
        }
    }

    private func currentWindow() -> UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
    }
}

extension SocialAuthController: ASAuthorizationControllerDelegate {
    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            Task { @MainActor in
                AuthSession.shared.lastError = "Apple didn’t return a sign-in credential."
            }
            return
        }
        let nameParts = [credential.fullName?.givenName, credential.fullName?.familyName]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
        let name = nameParts.joined(separator: " ")
        Task { @MainActor in
            AuthSession.shared.finishSocialLogin(
                provider: .apple,
                name: name.isEmpty ? "Apple User" : name,
                email: credential.email
            )
        }
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        let ns = error as NSError
        if ns.code == ASAuthorizationError.canceled.rawValue { return }
        Task { @MainActor in
            AuthSession.shared.lastError = "Apple Sign-In needs the Sign in with Apple capability (paid Apple Developer account). Try Google, Facebook, or Guest."
        }
    }
}

extension SocialAuthController: ASAuthorizationControllerPresentationContextProviding {
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        currentWindow() ?? UIWindow()
    }
}

extension SocialAuthController: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        currentWindow() ?? UIWindow()
    }
}
