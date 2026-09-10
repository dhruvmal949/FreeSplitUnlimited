//
//  LoginView.swift
//  FreeSplitUnlimited
//

import SwiftUI

struct LoginView: View {
    @ObservedObject private var session = AuthSession.shared
    @State private var username = ""
    @State private var password = ""
    @State private var errorMessage: String?
    @State private var showingCreateAccount = false
    @State private var showingForgotPassword = false

    private var canLogIn: Bool {
        !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !password.isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    Spacer(minLength: 12)

                    VStack(spacing: 6) {
                        BrandLogoMark(size: 88)

                        Text("Free Split")
                            .font(.largeTitle.weight(.bold))
                            .foregroundStyle(AppTheme.deepTeal)
                        Text("Sign in to your account")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    VStack(spacing: 12) {
                        TextField("Username", text: $username)
                            .textContentType(.username)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .padding(14)
                            .background(Color.white.opacity(0.78), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                        PasswordField(title: "Password", text: $password, contentType: .password)

                        HStack {
                            Toggle("Remember me", isOn: $session.rememberMe)
                                .tint(AppTheme.teal)
                            Spacer(minLength: 8)
                        }
                        .font(.subheadline)

                        Button("Forgot password?") {
                            session.lastError = nil
                            showingForgotPassword = true
                        }
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, alignment: .trailing)

                        if let errorMessage {
                            Text(errorMessage)
                                .font(.footnote)
                                .foregroundStyle(.red)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        Button {
                            errorMessage = session.logIn(username: username, password: password)
                        } label: {
                            Text("Sign In")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(AppTheme.teal)
                        .disabled(!canLogIn)

                        Button {
                            session.lastError = nil
                            showingCreateAccount = true
                        } label: {
                            Text("Create a new account")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(AppTheme.deepTeal)

                        Button {
                            session.continueAsGuest()
                        } label: {
                            Text("Continue as Guest")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                        }
                        .buttonStyle(.bordered)
                        .tint(AppTheme.teal)
                    }
                    .padding(.horizontal, 24)

                    VStack(spacing: 12) {
                        HStack {
                            Rectangle().fill(.secondary.opacity(0.25)).frame(height: 1)
                            Text("or sign in with")
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
                    .padding(.top, 8)
                    .padding(.bottom, 28)

                    Spacer(minLength: 8)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .freeSplitBackground()
            .navigationTitle("Sign In")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .sheet(isPresented: $showingCreateAccount) {
                CreateAccountView()
            }
            .sheet(isPresented: $showingForgotPassword) {
                ForgotPasswordView()
            }
        }
        .tint(AppTheme.teal)
    }
}
