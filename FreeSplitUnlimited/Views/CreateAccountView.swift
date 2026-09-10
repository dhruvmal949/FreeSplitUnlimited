//
//  CreateAccountView.swift
//  FreeSplitUnlimited
//

import SwiftUI

struct CreateAccountView: View {
    @ObservedObject private var session = AuthSession.shared
    @Environment(\.dismiss) private var dismiss

    @State private var username = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var errorMessage: String?

    private var canCreate: Bool {
        username.trimmingCharacters(in: .whitespacesAndNewlines).count >= 3
            && password.count >= 6
            && password == confirmPassword
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    VStack(spacing: 6) {
                        BrandLogoMark(size: 72)

                        Text("Create a new account")
                            .font(.title2.weight(.bold))
                            .foregroundStyle(AppTheme.deepTeal)
                        Text("Pick a username and password")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 8)

                    VStack(spacing: 12) {
                        TextField("Username", text: $username)
                            .textContentType(.username)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .padding(14)
                            .background(Color.white.opacity(0.78), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                        PasswordField(title: "Password", text: $password, contentType: .newPassword)
                        PasswordField(title: "Confirm password", text: $confirmPassword, contentType: .newPassword)

                        if let errorMessage {
                            Text(errorMessage)
                                .font(.footnote)
                                .foregroundStyle(.red)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        Button {
                            errorMessage = session.createAccount(
                                username: username,
                                password: password,
                                confirmPassword: confirmPassword
                            )
                        } label: {
                            Text("Create Account")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(AppTheme.teal)
                        .disabled(!canCreate)

                        Button("Already have an account? Sign in") {
                            dismiss()
                        }
                        .font(.subheadline.weight(.semibold))
                    }
                    .padding(.horizontal, 24)

                    VStack(spacing: 12) {
                        HStack {
                            Rectangle().fill(.secondary.opacity(0.25)).frame(height: 1)
                            Text("or sign up with")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Rectangle().fill(.secondary.opacity(0.25)).frame(height: 1)
                        }

                        SocialAuthButtons(
                            appleTitle: "Apple",
                            googleTitle: "Google",
                            facebookTitle: "Facebook"
                        )
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 28)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .freeSplitBackground()
            .navigationTitle("New Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .tint(AppTheme.teal)
    }
}
