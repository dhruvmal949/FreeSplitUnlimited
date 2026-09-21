//
//  RecordPaymentView.swift
//  FreeSplitUnlimited
//

import SwiftUI
import SwiftData

struct RecordPaymentView: View {
    private let payerName: String
    private let receiverName: String
    private let defaultAmount: Decimal
    private let occasions: [Occasion]
    private let myNames: [String]
    private let settledWithName: String
    private let usesFriendSplit: Bool
    private let friendName: String
    private let friendPaidYou: Bool

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var amountText = ""
    @State private var isEditingAmount = false
    @State private var showingConfirm = false
    @State private var comment = ""
    @FocusState private var amountFocused: Bool
    @FocusState private var commentFocused: Bool

    /// Friend profile: settle the overall 1:1 balance across shared groups.
    init(friendName: String, overallNet: Decimal, occasions: [Occasion], myNames: [String]) {
        self.friendName = friendName
        self.friendPaidYou = overallNet > 0
        self.payerName = overallNet > 0 ? friendName : "You"
        self.receiverName = overallNet > 0 ? "You" : friendName
        self.defaultAmount = abs(overallNet)
        self.occasions = occasions
        self.myNames = myNames
        self.settledWithName = friendName
        self.usesFriendSplit = true
    }

    /// Group settle up: record one suggested payment inside that group.
    init(payerName: String, receiverName: String, amount: Decimal, occasions: [Occasion], myNames: [String]) {
        self.payerName = payerName
        self.receiverName = receiverName
        self.defaultAmount = abs(amount)
        self.occasions = occasions
        self.myNames = myNames
        self.usesFriendSplit = false
        let receiverIsMe = myNames.contains { FriendPairing.namesMatch($0, receiverName) }
        self.friendPaidYou = receiverIsMe
        self.settledWithName = receiverIsMe ? payerName : receiverName
        self.friendName = self.settledWithName
    }

    private var amount: Decimal? {
        let allowed = CharacterSet(charactersIn: "0123456789.")
        let cleaned = amountText
            .replacingOccurrences(of: ",", with: "")
            .unicodeScalars
            .filter { allowed.contains($0) }
            .map(String.init)
            .joined()
        guard let value = Decimal(string: cleaned), value > 0 else { return nil }
        return MoneySplit.cents(value)
    }

    private var isAlreadySettled: Bool { defaultAmount == 0 }

    private var canRecord: Bool { !isAlreadySettled && amount != nil }

    private var caption: String {
        if defaultAmount == 0, amountText.isEmpty || amount == nil {
            return "Everyone here is settled up"
        }
        let payer = displayName(payerName)
        let receiver = displayName(receiverName)
        if payer == "you" { return "You paid \(receiver)" }
        if receiver == "you" { return "\(payer) paid you" }
        return "\(payer) paid \(receiver)"
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 0) {
                        Spacer(minLength: 24)
                        avatars
                            .padding(.bottom, 16)
                        Text(caption)
                            .font(.body)
                            .foregroundStyle(.primary)
                            .padding(.bottom, 8)
                        amountRow
                            .padding(.bottom, 20)
                        commentField
                            .padding(.horizontal, 24)
                            .padding(.bottom, 16)
                    }
                    .frame(maxWidth: .infinity)
                }
                .scrollDismissesKeyboard(.interactively)
                Spacer(minLength: 0)
                Button {
                    amountFocused = false
                    commentFocused = false
                    showingConfirm = true
                } label: {
                    Text("Record payment")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                }
                .buttonStyle(.borderedProminent)
                .tint(canRecord ? AppTheme.teal : Color(.systemGray3))
                .clipShape(Capsule())
                .disabled(!canRecord)
                .accessibilityIdentifier("recordPaymentButton")
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
            .background(Color(.systemBackground))
            .navigationTitle("Record a payment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.primary)
                            .frame(width: 36, height: 36)
                            .background(Color(.systemGray6), in: Circle())
                    }
                    .accessibilityLabel("Close")
                }
            }
            .alert("Settle up?", isPresented: $showingConfirm) {
                Button("No", role: .cancel) {}
                Button("Yes") { recordPayment() }
            } message: {
                Text("You have settled the amount to \(settledWithName).")
            }
            .onAppear {
                if amountText.isEmpty {
                    amountText = formatted(defaultAmount)
                }
            }
            .keyboardDoneButton()
        }
    }

    private var avatars: some View {
        HStack(spacing: 16) {
            PaymentAvatar(name: avatarLabel(payerName))
            Image(systemName: "arrow.right")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.secondary)
            PaymentAvatar(name: avatarLabel(receiverName))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(caption)
    }

    private var amountRow: some View {
        HStack(spacing: 10) {
            Text(currencySymbol)
                .font(.system(size: 40, weight: .regular, design: .rounded))
                .foregroundStyle(.secondary)
            if isEditingAmount {
                TextField("0.00", text: $amountText)
                    .keyboardType(.decimalPad)
                    .font(.system(size: 40, weight: .regular, design: .rounded))
                    .multilineTextAlignment(.leading)
                    .focused($amountFocused)
                    .frame(minWidth: 80)
                    .accessibilityIdentifier("paymentAmountField")
                    .onSubmit { isEditingAmount = false }
            } else {
                Text(displayAmount)
                    .font(.system(size: 40, weight: .regular, design: .rounded))
                    .foregroundStyle(.primary)
            }
            Button {
                isEditingAmount.toggle()
                if isEditingAmount {
                    amountFocused = true
                }
            } label: {
                Image(systemName: "pencil")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Edit amount")
        }
    }

    private var commentField: some View {
        TextField("Enter how you settle the payment(optional)", text: $comment, axis: .vertical)
            .lineLimit(2...4)
            .textInputAutocapitalization(.sentences)
            .padding(12)
            .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .focused($commentFocused)
            .accessibilityIdentifier("paymentCommentField")
    }

    private var displayAmount: String {
        if let amount {
            return formatted(amount)
        }
        return amountText.isEmpty ? formatted(defaultAmount) : amountText
    }

    private var currencySymbol: String {
        Locale.current.currencySymbol ?? "$"
    }

    private func isMe(_ name: String) -> Bool {
        name == "You" || myNames.contains { FriendPairing.namesMatch($0, name) }
    }

    private func displayName(_ name: String) -> String {
        isMe(name) ? "you" : name
    }

    private func avatarLabel(_ name: String) -> String {
        isMe(name) ? "You" : name
    }

    private func formatted(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: value as NSDecimalNumber) ?? "\(value)"
    }

    private func recordPayment() {
        guard let amount else { return }
        let note = comment.trimmingCharacters(in: .whitespacesAndNewlines)
        let expenses: [Expense]
        if usesFriendSplit {
            expenses = BalanceCalculator.recordFriendPayment(
                amount: amount,
                friendPaidYou: friendPaidYou,
                friendName: friendName,
                myNames: myNames,
                occasions: occasions,
                note: note
            )
        } else {
            expenses = occasions.compactMap {
                BalanceCalculator.recordDirectedPayment(
                    amount: amount,
                    payerName: payerName,
                    receiverName: receiverName,
                    in: $0,
                    note: note
                )
            }
        }
        for expense in expenses {
            modelContext.insert(expense)
        }
        modelContext.persist()
        SyncCoordinator.shared.syncNow()
        dismiss()
    }
}

private struct PaymentAvatar: View {
    let name: String

    var body: some View {
        ZStack {
            Circle().fill(color)
            Text(letter)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
        .frame(width: 72, height: 72)
    }

    private var letter: String {
        String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(1)).uppercased()
    }

    private var color: Color {
        let palette: [Color] = [
            Color(red: 1, green: 0.48, blue: 0.37),
            Color(red: 0.72, green: 0.18, blue: 0.38),
            AppTheme.teal,
            Color(red: 0.45, green: 0.55, blue: 0.95)
        ]
        let index = abs(name.lowercased().hashValue) % palette.count
        return palette[index]
    }
}
