//
//  GoogleOAuth.swift
//  FreeSplitUnlimited
//
//  Google OAuth 2.0 (OpenID) with PKCE. Tapping Google opens Google’s login page.
//

import CryptoKit
import Foundation

enum GoogleOAuth {
    static let authorizationEndpoint = "https://accounts.google.com/o/oauth2/v2/auth"
    static let tokenEndpoint = "https://oauth2.googleapis.com/token"
    static let userInfoEndpoint = "https://www.googleapis.com/oauth2/v3/userinfo"
    static let fallbackCallbackScheme = "com.pramela.freesplitunlimited"
    static let scopes = "openid email profile"

    static var clientID: String {
        let fromInfo = (Bundle.main.object(forInfoDictionaryKey: "GIDClientID") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if fromInfo.hasSuffix(".apps.googleusercontent.com") { return fromInfo }
        if let url = Bundle.main.url(forResource: "GoogleService-Info", withExtension: "plist"),
           let dict = NSDictionary(contentsOf: url),
           let id = (dict["CLIENT_ID"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
           id.hasSuffix(".apps.googleusercontent.com") {
            return id
        }
        return fromInfo
    }

    static var isConfigured: Bool {
        clientID.hasSuffix(".apps.googleusercontent.com")
    }

    static var reversedClientID: String {
        clientID.split(separator: ".").reversed().joined(separator: ".")
    }

    static var callbackScheme: String {
        isConfigured ? reversedClientID : fallbackCallbackScheme
    }

    static var redirectURI: String {
        "\(callbackScheme):/oauth2redirect"
    }

    static func makePKCE() -> (verifier: String, challenge: String) {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        let verifier = base64URL(Data(bytes))
        let challenge = base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
        return (verifier, challenge)
    }

    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func authorizationURL(
        clientID: String = clientID,
        redirectURI: String = redirectURI,
        challenge: String,
        loginHint: String? = nil
    ) -> URL? {
        var components = URLComponents(string: authorizationEndpoint)
        var items = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: scopes),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "prompt", value: "select_account"),
        ]
        if let loginHint, !loginHint.isEmpty {
            items.append(URLQueryItem(name: "login_hint", value: loginHint))
        }
        components?.queryItems = items
        return components?.url
    }

    static func authCode(from callback: URL) -> String? {
        let query = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems
            ?? URLComponents(string: "https://host?\(callback.fragment ?? "")")?.queryItems
            ?? []
        if let error = query.first(where: { $0.name == "error" })?.value, !error.isEmpty {
            return nil
        }
        return query.first(where: { $0.name == "code" })?.value?
            .removingPercentEncoding
    }

    static func tokenRequest(code: String, verifier: String, clientID: String = clientID, redirectURI: String = redirectURI) -> URLRequest? {
        guard let url = URL(string: tokenEndpoint) else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let body = [
            "code": code,
            "client_id": clientID,
            "redirect_uri": redirectURI,
            "grant_type": "authorization_code",
            "code_verifier": verifier,
        ]
        .map { key, value in
            let encoded = value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
            return "\(key)=\(encoded)"
        }
        .joined(separator: "&")
        request.httpBody = Data(body.utf8)
        return request
    }
}
