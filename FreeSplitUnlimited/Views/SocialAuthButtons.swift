//
//  SocialAuthButtons.swift
//  FreeSplitUnlimited
//

import SwiftUI

struct SocialAuthButtons: View {
    var appleTitle = "Sign in with Apple"
    var googleTitle = "Continue with Google"

    @ObservedObject private var session = AuthSession.shared

    var body: some View {
        VStack(spacing: 12) {
            Button {
                SocialAuthController.shared.signInWithApple()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "apple.logo")
                        .font(.title3.weight(.semibold))
                        .frame(width: 22)
                    Text(appleTitle)
                        .font(.headline)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
            }
            .buttonStyle(SocialLoginButtonStyle(background: .black, foreground: .white))
            .accessibilityIdentifier("loginAppleButton")

            Button {
                SocialAuthController.shared.signInWithGoogle()
            } label: {
                HStack(spacing: 10) {
                    Text("G")
                        .font(.title2.weight(.bold))
                        .frame(width: 22)
                    Text(googleTitle)
                        .font(.headline)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
            }
            .buttonStyle(SocialLoginButtonStyle(background: .white, foreground: .black.opacity(0.85), border: true))
            .accessibilityIdentifier("loginGoogleButton")

            if let error = session.lastError {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

struct SocialLoginButtonStyle: ButtonStyle {
    var background: Color
    var foreground: Color
    var border: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(foreground)
            .background(background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                if border {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.black.opacity(0.12), lineWidth: 1)
                }
            }
            .shadow(color: .black.opacity(configuration.isPressed ? 0.04 : 0.1), radius: 6, y: 3)
            .opacity(configuration.isPressed ? 0.88 : 1)
    }
}
