//
//  SocialAuthController.swift
//  FreeSplitUnlimited
//
//  Google opens Google’s own email/password page.
//

import AuthenticationServices
import Foundation
import SafariServices
import UIKit

final class SocialAuthController: NSObject {
    static let shared = SocialAuthController()

    /// iOS OAuth client ID from Google Cloud Console (type: iOS). Leave empty until you add one.
    static let googleClientID = ""

    private var webSession: ASWebAuthenticationSession?
    private var safari: SFSafariViewController?
    private var onSafariDismiss: (() -> Void)?

    func signInWithGoogle() {
        Task { @MainActor in
            AuthSession.shared.lastError = nil
        }
        let clientID = configuredGoogleClientID
        if !clientID.isEmpty {
            startGoogleOAuth(clientID: clientID)
            return
        }
        openGoogleAccountPage()
    }

    private var configuredGoogleClientID: String {
        let fromCode = Self.googleClientID.trimmingCharacters(in: .whitespacesAndNewlines)
        if !fromCode.isEmpty { return fromCode }
        return (Bundle.main.object(forInfoDictionaryKey: "GIDClientID") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private func startGoogleOAuth(clientID: String) {
        let reversed = clientID.split(separator: ".").reversed().joined(separator: ".")
        guard var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth") else { return }
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: "\(reversed):/oauth2redirect"),
            URLQueryItem(name: "response_type", value: "token"),
            URLQueryItem(name: "scope", value: "email profile"),
            URLQueryItem(name: "prompt", value: "select_account"),
        ]
        guard let url = components.url else { return }
        let scheme = String(reversed.split(separator: ".").first ?? Substring(reversed))
        startWebAuth(url: url, callbackScheme: scheme, ephemeral: false) { callback in
            self.handleGoogleOAuthCallback(callback)
        }
    }

    /// Opens Google’s email / password page so they sign in with their Google account, not ours.
    private func openGoogleAccountPage() {
        var components = URLComponents(string: "https://accounts.google.com/signin/v2/identifier")
        var items = [
            URLQueryItem(name: "flowName", value: "GlifWebSignIn"),
            URLQueryItem(name: "flowEntry", value: "ServiceLogin"),
        ]
        Task { @MainActor in
            if let email = AuthSession.shared.lastGoogleEmail {
                items.append(URLQueryItem(name: "login_hint", value: email))
            }
            components?.queryItems = items
            guard let url = components?.url else { return }
            self.presentGoogleSafari(url)
        }
    }

    private func presentGoogleSafari(_ url: URL) {
        DispatchQueue.main.async {
            let safari = SFSafariViewController(url: url)
            safari.dismissButtonStyle = .done
            safari.delegate = self
            self.safari = safari
            self.onSafariDismiss = {
                Task { @MainActor in
                    AuthSession.shared.needsGoogleEmailConfirmation = true
                }
            }
            guard let presenter = self.topPresenter() else {
                Task { @MainActor in
                    AuthSession.shared.lastError = "Couldn’t open Google sign-in."
                }
                return
            }
            presenter.present(safari, animated: true)
        }
    }

    private func handleGoogleOAuthCallback(_ url: URL) {
        guard let token = accessToken(from: url) else {
            Task { @MainActor in
                if AuthSession.shared.restoreLastGoogleAccount() { return }
                AuthSession.shared.needsGoogleEmailConfirmation = true
            }
            return
        }
        fetchGoogleProfile(token: token)
    }

    private func accessToken(from callback: URL) -> String? {
        let raw = callback.fragment ?? callback.query ?? ""
        return raw
            .split(separator: "&")
            .compactMap { part -> (String, String)? in
                let bits = part.split(separator: "=", maxSplits: 1)
                guard bits.count == 2 else { return nil }
                return (String(bits[0]), String(bits[1]))
            }
            .first { $0.0 == "access_token" }?
            .1
            .removingPercentEncoding
    }

    private func fetchGoogleProfile(token: String) {
        guard let url = URL(string: "https://www.googleapis.com/oauth2/v3/userinfo") else { return }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        URLSession.shared.dataTask(with: request) { data, _, _ in
            Task { @MainActor in
                guard let data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    if AuthSession.shared.restoreLastGoogleAccount() { return }
                    AuthSession.shared.needsGoogleEmailConfirmation = true
                    return
                }
                let email = (json["email"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                let name = (json["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                    ?? email?.split(separator: "@").first.map(String.init)
                    ?? "Google"
                AuthSession.shared.finishSocialLogin(provider: .google, name: name, email: email)
            }
        }.resume()
    }

    private func startWebAuth(url: URL, callbackScheme: String, ephemeral: Bool, onSuccess: @escaping (URL) -> Void) {
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
        session.prefersEphemeralWebBrowserSession = ephemeral
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

    private func topPresenter() -> UIViewController? {
        guard let root = currentWindow()?.rootViewController else { return nil }
        var top = root
        while let presented = top.presentedViewController {
            top = presented
        }
        return top
    }
}

extension SocialAuthController: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        currentWindow() ?? UIWindow()
    }
}

extension SocialAuthController: SFSafariViewControllerDelegate {
    func safariViewControllerDidFinish(_ controller: SFSafariViewController) {
        safari = nil
        let completion = onSafariDismiss
        onSafariDismiss = nil
        completion?()
    }
}
