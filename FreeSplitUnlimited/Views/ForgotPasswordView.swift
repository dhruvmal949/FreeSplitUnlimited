//
//  ForgotPasswordView.swift
//  FreeSplitUnlimited
//

import SwiftUI

struct ForgotPasswordView: View {
    @ObservedObject private var session = AuthSession.shared
    @Environment(\.dismiss) private var dismiss

    @State private var contact = ContactEntryState()
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var errorMessage: String?

    private var canReset: Bool {
        contact.isValid && passwordsMatch(password, confirmPassword)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    VStack(spacing: 12) {
                        EmailPhonePicker(
                            entry: $contact,
                            fieldIdentifier: "forgotEmailField",
                            pickerIdentifier: "forgotContactKind",
                            onKindChange: { errorMessage = nil }
                        )

                        PasswordField(title: "New password", text: $password, contentType: .newPassword, fieldIdentifier: "forgotNewPasswordField")
                        PasswordField(title: "Confirm new password", text: $confirmPassword, contentType: .newPassword, fieldIdentifier: "forgotConfirmPasswordField")
                        PasswordPairHint(password: password, confirmPassword: confirmPassword)

                        if let errorMessage {
                            Text(errorMessage)
                                .font(.footnote)
                                .foregroundStyle(.red)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .accessibilityIdentifier("forgotErrorLabel")
                        }

                        Button {
                            errorMessage = session.resetPassword(
                                username: contact.selectedValue,
                                newPassword: password,
                                confirmPassword: confirmPassword
                            )
                            if errorMessage == nil {
                                dismiss()
                            }
                        } label: {
                            Text("Reset Password")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(AppTheme.teal)
                        .disabled(!canReset)
                        .accessibilityIdentifier("forgotResetButton")
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 8)
                    .padding(.bottom, 28)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .freeSplitBackground()
            .keyboardDoneButton()
            .navigationTitle("")
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
