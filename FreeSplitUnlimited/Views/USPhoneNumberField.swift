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
        field.setContentHuggingPriority(.required, for: .vertical)
        field.setContentCompressionResistancePriority(.required, for: .vertical)
        field.inputAssistantItem.leadingBarButtonGroups = []
        field.inputAssistantItem.trailingBarButtonGroups = []
        return field
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextField, context: Context) -> CGSize? {
        let width = proposal.width ?? uiView.intrinsicContentSize.width
        return CGSize(width: width, height: uiView.intrinsicContentSize.height)
    }

    func updateUIView(_ uiView: UITextField, context: Context) {
        context.coordinator.text = $text
        let formatted = formattedUSPhone(text)
        if uiView.text != formatted {
            uiView.text = formatted
        }
        uiView.isUserInteractionEnabled = isActive
        let nextContent: UITextContentType? = isActive ? .telephoneNumber : nil
        if uiView.textContentType != nextContent {
            uiView.textContentType = nextContent
        }
        if uiView.keyboardType != .numberPad {
            uiView.keyboardType = .numberPad
        }
        syncFocus(uiView, coordinator: context.coordinator)
    }

    private func syncFocus(_ uiView: UITextField, coordinator: Coordinator) {
        coordinator.wantsFocus = isFocused && isActive
        coordinator.isActive = isActive
        let shouldResign = !isActive && uiView.isFirstResponder
        let shouldFocus = coordinator.wantsFocus && !uiView.isFirstResponder
        guard shouldResign || shouldFocus else { return }
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
