//
//  LoginView.swift
//  FreeSplitUnlimited
//

import SwiftUI

struct LoginView: View {
    @ObservedObject private var session = AuthSession.shared
    @State private var contact = ContactEntryState()
    @State private var password = AuthSession.shared.rememberedPassword
    @State private var errorMessage: String?
    @State private var showingCreateAccount = false
    @State private var showingForgotPassword = false
    @State private var didAutoPromptFaceID = false
    @State private var didPrefillContact = false
    @State private var rememberedLoginWhenOpeningSheet = ""
    @State private var prefersManualLogin = false
    @State private var ignoreLoginEdits = true
    @Environment(\.scenePhase) private var scenePhase
    @State private var didFinishFirstAppear = false

    private var canLogIn: Bool {
        contact.isValid && !password.isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    HStack(spacing: 12) {
                        if session.hasUnlockableAccount {
                            Button {
                                Task {
                                    errorMessage = await session.unlockWithFaceID()
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "faceid")
                                    Text("Face ID")
                                }
                            }
                            .buttonStyle(LoginCornerButtonStyle())
                            .accessibilityLabel("Face ID")
                            .accessibilityIdentifier("loginFaceIDButton")
                        }

                        Spacer(minLength: 8)

                        Button("Create an account") {
                            session.lastError = nil
                            rememberedLoginWhenOpeningSheet = session.rememberedLogin
                            showingCreateAccount = true
                        }
                        .buttonStyle(LoginCornerButtonStyle())
                        .accessibilityIdentifier("loginCreateAccount")
                    }
                    .padding(.horizontal, 16)

                    VStack(spacing: 6) {
                        BrandLogoMark(size: 88)

                        Text("Free Split")
                            .font(.largeTitle.weight(.bold))
                            .foregroundStyle(AppTheme.deepTeal)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        EmailPhonePicker(
                            entry: $contact,
                            fieldIdentifier: "loginEmailField",
                            pickerIdentifier: "loginContactKind",
                            hintIdentifier: "loginContactHint",
                            onKindChange: {
                                errorMessage = nil
                                beginManualLogin()
                            }
                        )

                        PasswordField(title: "Password", text: $password, contentType: .password, fieldIdentifier: "loginPasswordField")

                        HStack(alignment: .center) {
                            Button {
                                session.rememberMe.toggle()
                                if session.rememberMe {
                                    session.saveRememberedCredentials(login: contact.selectedValue, password: password)
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: session.rememberMe ? "checkmark.square.fill" : "square")
                                        .font(.body)
                                        .foregroundStyle(AppTheme.teal)
                                    Text("Remember me")
                                        .font(.subheadline)
                                        .foregroundStyle(.primary)
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("loginRememberMe")
                            .accessibilityLabel("Remember me")
                            .accessibilityAddTraits(session.rememberMe ? [.isSelected] : [])

                            Spacer(minLength: 8)

                            Button("Forget Password") {
                                session.lastError = nil
                                rememberedLoginWhenOpeningSheet = session.rememberedLogin
                                showingForgotPassword = true
                            }
                            .font(.subheadline.weight(.semibold))
                            .accessibilityIdentifier("loginForgotPassword")
                        }

                        if let errorMessage {
                            Text(errorMessage)
                                .font(.footnote)
                                .foregroundStyle(.red)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .accessibilityIdentifier("loginErrorLabel")
                        }

                        Button {
                            errorMessage = session.logIn(username: contact.selectedValue, password: password)
                        } label: {
                            Text("Sign In")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(AppTheme.teal)
                        .disabled(!canLogIn)
                        .padding(.top, 4)
                        .accessibilityIdentifier("loginSignInButton")
                    }
                    .padding(.horizontal, 24)
                    .onChange(of: contact.email) { _, _ in
                        beginManualLogin()
                        saveRememberedIfNeeded()
                    }
                    .onChange(of: contact.phone) { _, _ in
                        beginManualLogin()
                        saveRememberedIfNeeded()
                    }
                    .onChange(of: password) { _, _ in
                        beginManualLogin()
                        saveRememberedIfNeeded()
                    }

                    VStack(spacing: 14) {
                        HStack {
                            Rectangle().fill(.secondary.opacity(0.25)).frame(height: 1)
                            Text("or sign in with")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Rectangle().fill(.secondary.opacity(0.25)).frame(height: 1)
                        }

                        SocialAuthButtons(googleTitle: "Google")
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 4)
                    .padding(.bottom, 32)

                    Spacer(minLength: 8)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .freeSplitBackground()
            .keyboardDoneButton()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showingCreateAccount, onDismiss: {
                applyRememberedIfChanged()
            }) {
                CreateAccountView()
            }
            .sheet(isPresented: $showingForgotPassword, onDismiss: {
                if applyRememberedIfChanged() {
                    password = ""
                }
                errorMessage = nil
            }) {
                ForgotPasswordView()
            }
            .sheet(isPresented: $session.needsGoogleEmailConfirmation) {
                GoogleEmailConfirmView()
            }
            .alert("Use Face ID?", isPresented: $session.needsFaceIDOptIn) {
                Button("Yes") {
                    session.answerFaceIDOptIn(true)
                }
                Button("No", role: .cancel) {
                    session.answerFaceIDOptIn(false)
                }
            } message: {
                Text("Use Face ID to open Free Split next time instead of signing in with your email or phone?")
            }
            .onAppear {
                if !didPrefillContact {
                    contact.applyRemembered(session.rememberedLogin)
                    didPrefillContact = true
                }
                scheduleFaceIDPrompt()
                DispatchQueue.main.async {
                    ignoreLoginEdits = false
                    didFinishFirstAppear = true
                }
            }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active, didFinishFirstAppear else { return }
                guard !prefersManualLogin, !session.isAuthenticated else { return }
                didAutoPromptFaceID = false
                scheduleFaceIDPrompt()
            }
        }
        .tint(AppTheme.teal)
    }

    @discardableResult
    private func applyRememberedIfChanged() -> Bool {
        let login = session.rememberedLogin
        guard login != rememberedLoginWhenOpeningSheet else { return false }
        contact.applyRemembered(login)
        return true
    }

    private func beginManualLogin() {
        guard !ignoreLoginEdits else { return }
        prefersManualLogin = true
        session.cancelPendingFaceIDUnlock()
    }

    private func saveRememberedIfNeeded() {
        guard session.rememberMe else { return }
        session.saveRememberedCredentials(login: contact.selectedValue, password: password)
    }

    private func scheduleFaceIDPrompt() {
        guard !didAutoPromptFaceID, !prefersManualLogin else { return }
        guard session.prefersFaceIDLogin, session.canOfferFaceID, !AppLaunchFlags.isUITesting else { return }
        didAutoPromptFaceID = true
        let delay = session.autoPromptDelayRemaining > 0
            ? session.autoPromptDelayRemaining
            : 0.35
        Task {
            try? await Task.sleep(for: .seconds(delay))
            guard !prefersManualLogin, !session.isAuthenticated else { return }
            guard session.shouldAutoPromptFaceID else { return }
            errorMessage = await session.unlockWithFaceID()
        }
    }
}

private struct GoogleEmailConfirmView: View {
    @ObservedObject private var session = AuthSession.shared
    @State private var email: String
    @State private var errorMessage: String?

    init() {
        _email = State(initialValue: AuthSession.shared.lastGoogleEmail ?? "")
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Enter the Google email you just signed in with.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                EmailAddressField(
                    text: $email,
                    isFocused: true,
                    accessibilityIdentifier: "googleEmailField"
                )
                .authInputChrome()

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }

                Button {
                    errorMessage = session.confirmGoogleEmail(email)
                } label: {
                    Text("Continue")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.teal)
                .disabled(!isValidEmail(email))

                Spacer()
            }
            .padding(24)
            .freeSplitBackground()
            .navigationTitle("Google account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        session.needsGoogleEmailConfirmation = false
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

private struct LoginCornerButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(AppTheme.deepTeal)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(
                Color.white.opacity(configuration.isPressed ? 0.7 : 0.88),
                in: Capsule()
            )
            .overlay {
                Capsule().stroke(Color.white.opacity(0.95), lineWidth: 0.8)
            }
            .shadow(color: AppTheme.deepTeal.opacity(0.12), radius: 8, y: 2)
    }
}
