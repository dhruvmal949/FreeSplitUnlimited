//
//  CreateAccountView.swift
//  FreeSplitUnlimited
//

import SwiftUI
import UIKit

struct CreateAccountView: View {
    @ObservedObject private var session = AuthSession.shared
    @Environment(\.dismiss) private var dismiss

    @State private var firstName = ""
    @State private var lastName = ""
    @State private var contact = ContactEntryState()
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var errorMessage: String?
    @State private var showingDuplicate = false
    @State private var duplicateKind: AuthSession.ExistingAccountKind = .email

    private var canSave: Bool {
        let first = firstName.trimmingCharacters(in: .whitespacesAndNewlines)
        let last = lastName.trimmingCharacters(in: .whitespacesAndNewlines)
        return !first.isEmpty
            && !last.isEmpty
            && contact.isValid
            && passwordsMatch(password, confirmPassword)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    VStack(spacing: 6) {
                        BrandLogoMark(size: 72)

                        Text("Create an account")
                            .font(.title2.weight(.bold))
                            .foregroundStyle(AppTheme.deepTeal)
                    }
                    .padding(.top, 8)

                    VStack(spacing: 12) {
                        field("First name", text: $firstName, contentType: .givenName, capitalize: .words, identifier: "createFirstNameField")
                        field("Last name", text: $lastName, contentType: .familyName, capitalize: .words, identifier: "createLastNameField")

                        EmailPhonePicker(
                            entry: $contact,
                            fieldIdentifier: "createContactField",
                            pickerIdentifier: "createContactKind",
                            hintIdentifier: "createContactHint",
                            onKindChange: { errorMessage = nil }
                        )

                        PasswordField(title: "Password", text: $password, contentType: .newPassword, fieldIdentifier: "createPasswordField")
                        PasswordField(title: "Confirm password", text: $confirmPassword, contentType: .newPassword, fieldIdentifier: "createConfirmPasswordField")
                        PasswordPairHint(password: password, confirmPassword: confirmPassword, identifier: "createPasswordHint")

                        if let errorMessage {
                            Text(errorMessage)
                                .font(.footnote)
                                .foregroundStyle(.red)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .accessibilityIdentifier("createErrorLabel")
                        }

                        Button(action: saveAccount) {
                            Text("Save")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(AppTheme.teal)
                        .disabled(!canSave)
                        .accessibilityIdentifier("createSaveButton")

                        Button("Already have an account? Sign in") {
                            dismiss()
                        }
                        .font(.subheadline.weight(.semibold))
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 28)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .freeSplitBackground()
            .keyboardDoneButton()
            .navigationTitle("New Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .alert("Account already exists", isPresented: $showingDuplicate) {
                Button("Sign in") { dismiss() }
                Button(duplicateKind == .phone ? "Use a different number" : "Use a different email") {
                    contact.clearCurrent()
                    errorMessage = nil
                }
            } message: {
                Text(
                    duplicateKind == .phone
                        ? "This iPhone already has an account with that phone number. Sign in, or enter a different number."
                        : "This iPhone already has an account with that email. Sign in, or enter a different email."
                )
            }
        }
        .tint(AppTheme.teal)
    }

    private func saveAccount() {
        errorMessage = nil
        if let existing = session.existingAccount(matching: contact.selectedValue) {
            duplicateKind = existing
            showingDuplicate = true
            return
        }
        errorMessage = session.beginRegistration(
            firstName: firstName,
            lastName: lastName,
            contact: contact.selectedValue,
            password: password,
            confirmPassword: confirmPassword
        )
        if errorMessage == nil {
            dismiss()
        }
    }

    private func field(
        _ title: String,
        text: Binding<String>,
        contentType: UITextContentType,
        keyboard: UIKeyboardType = .default,
        capitalize: TextInputAutocapitalization = .never,
        identifier: String
    ) -> some View {
        TextField(title, text: text)
            .textContentType(contentType)
            .keyboardType(keyboard)
            .textInputAutocapitalization(capitalize)
            .autocorrectionDisabled()
            .authInputChrome()
            .accessibilityIdentifier(identifier)
    }
}
