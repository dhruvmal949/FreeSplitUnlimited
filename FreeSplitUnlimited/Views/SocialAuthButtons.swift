//
//  SocialAuthButtons.swift
//  FreeSplitUnlimited
//

import SwiftUI

struct SocialAuthButtons: View {
    var appleTitle = "Continue with Apple"
    var googleTitle = "Continue with Google"
    var facebookTitle = "Continue with Facebook"

    @ObservedObject private var session = AuthSession.shared

    var body: some View {
        VStack(spacing: 12) {
            Button {
                SocialAuthController.shared.signInWithApple()
            } label: {
                socialLabel(appleTitle, systemImage: "apple.logo")
            }
            .buttonStyle(SocialLoginButtonStyle(background: .black, foreground: .white))

            Button {
                SocialAuthController.shared.signInWithGoogle()
            } label: {
                socialLabel(googleTitle, assetLetter: "G")
            }
            .buttonStyle(SocialLoginButtonStyle(background: .white, foreground: .black.opacity(0.85), border: true))

            Button {
                SocialAuthController.shared.signInWithFacebook()
            } label: {
                socialLabel(facebookTitle, systemImage: "f.circle.fill")
            }
            .buttonStyle(SocialLoginButtonStyle(
                background: Color(red: 24 / 255, green: 119 / 255, blue: 242 / 255),
                foreground: .white
            ))

            if let error = session.lastError {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func socialLabel(_ title: String, systemImage: String? = nil, assetLetter: String? = nil) -> some View {
        HStack(spacing: 10) {
            if let assetLetter {
                Text(assetLetter)
                    .font(.title2.weight(.bold))
                    .frame(width: 22)
            } else if let systemImage {
                Image(systemName: systemImage)
                    .font(.title3.weight(.semibold))
                    .frame(width: 22)
            }
            Text(title)
                .font(.headline)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
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
