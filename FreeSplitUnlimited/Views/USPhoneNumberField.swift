//
//  USPhoneNumberField.swift
//  FreeSplitUnlimited
//

import SwiftUI
import UIKit

struct USPhoneNumberField: UIViewRepresentable {
    @Binding var text: String
    var isFocused: Bool = false
    var isActive: Bool = true
    var accessibilityIdentifier: String

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeUIView(context: Context) -> UITextField {
        let field = UITextField()
        field.placeholder = "(xxx) xxx-xxxx"
        field.keyboardType = .numberPad
        field.textContentType = .telephoneNumber
        field.autocorrectionType = .no
        field.spellCheckingType = .no
        field.borderStyle = .none
        field.font = .preferredFont(forTextStyle: .body)
        field.delegate = context.coordinator
        field.accessibilityIdentifier = accessibilityIdentifier
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return field
    }

    func updateUIView(_ uiView: UITextField, context: Context) {
        context.coordinator.text = $text
        let formatted = formattedUSPhone(text)
        if uiView.text != formatted {
            uiView.text = formatted
        }
        uiView.isUserInteractionEnabled = isActive
        uiView.textContentType = isActive ? .telephoneNumber : nil
        uiView.keyboardType = .numberPad
        syncFocus(uiView, coordinator: context.coordinator)
    }

    private func syncFocus(_ uiView: UITextField, coordinator: Coordinator) {
        coordinator.wantsFocus = isFocused && isActive
        coordinator.isActive = isActive
        DispatchQueue.main.async {
            if !coordinator.isActive {
                if uiView.isFirstResponder {
                    uiView.resignFirstResponder()
                }
                return
            }
            if coordinator.wantsFocus, !uiView.isFirstResponder {
                uiView.becomeFirstResponder()
            }
        }
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var text: Binding<String>
        var wantsFocus = false
        var isActive = true

        init(text: Binding<String>) {
            self.text = text
        }

        func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
            let current = textField.text ?? ""
            guard let typedRange = Range(range, in: current) else { return false }
            let next = current.replacingCharacters(in: typedRange, with: string)
            let formatted = formattedUSPhone(next)
            textField.text = formatted
            text.wrappedValue = formatted
            return false
        }
    }
}
