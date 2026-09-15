//
//  PasswordField.swift
//  FreeSplitUnlimited
//

import SwiftUI
import UIKit

struct PasswordField: View {
    var title: String
    @Binding var text: String
    var contentType: UITextContentType = .password
    var fieldIdentifier: String? = nil

    @State private var isVisible = false

    var body: some View {
        HStack(spacing: 10) {
            Group {
                if isVisible {
                    TextField(title, text: $text)
                } else {
                    SecureField(title, text: $text)
                }
            }
            .textContentType(AppLaunchFlags.isUITesting ? .oneTimeCode : contentType)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .accessibilityIdentifier(fieldIdentifier ?? title)

            Button {
                isVisible.toggle()
            } label: {
                Image(systemName: isVisible ? "eye.slash" : "eye")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isVisible ? "Hide password" : "Show password")
            .accessibilityIdentifier("\(fieldIdentifier ?? title)Visibility")
        }
        .padding(14)
        .background(Color.white.opacity(0.78), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
