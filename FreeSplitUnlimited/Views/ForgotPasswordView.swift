//
//  ForgotPasswordView.swift
//  FreeSplitUnlimited
//

import SwiftUI

struct ForgotPasswordView: View {
    @ObservedObject private var session = AuthSession.shared
    @Environment(\.dismiss) private var dismiss

    @State private var username = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var errorMessage: String?

    private var canReset: Bool {
        !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && password.count >= 6
            && password == confirmPassword
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    VStack(spacing: 6) {
                        Image(systemName: "key.fill")
                            .font(.system(size: 32, weight: .semibold))
                            .foregroundStyle(AppTheme.teal)
                        Text("Forgot password")
                            .font(.title2.weight(.bold))
                            .foregroundStyle(AppTheme.deepTeal)
                        Text("Accounts live on this iPhone. Enter your username and pick a new password.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 8)

                    VStack(spacing: 12) {
                        TextField("Username", text: $username)
                            .textContentType(.username)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .padding(14)
                            .background(Color.white.opacity(0.78), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                        PasswordField(title: "New password", text: $password, contentType: .newPassword)
                        PasswordField(title: "Confirm new password", text: $confirmPassword, contentType: .newPassword)

                        if let errorMessage {
                            Text(errorMessage)
                                .font(.footnote)
                                .foregroundStyle(.red)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        Button {
                            errorMessage = session.resetPassword(
                                username: username,
                                newPassword: password,
                                confirmPassword: confirmPassword
                            )
                        } label: {
                            Text("Reset Password")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(AppTheme.teal)
                        .disabled(!canReset)
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 28)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .freeSplitBackground()
            .navigationTitle("Reset Password")
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
