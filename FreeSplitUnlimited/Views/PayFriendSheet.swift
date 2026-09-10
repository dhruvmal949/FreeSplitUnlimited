//
//  PayFriendSheet.swift
//  FreeSplitUnlimited
//

import SwiftData
import SwiftUI

struct PayFriendSheet: View {
    let request: PayFriendRequest
    let occasions: [Occasion]

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var auth = AuthSession.shared

    @State private var errorMessage: String?

    private var money: String {
        CurrencyFormat.string(from: request.amount)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    VStack(spacing: 8) {
                        Image(systemName: "dollarsign.circle.fill")
                            .font(.system(size: 36, weight: .semibold))
                            .foregroundStyle(AppTheme.teal)
                        Text("Pay \(request.payeeName)")
                            .font(.title2.weight(.bold))
                            .foregroundStyle(AppTheme.deepTeal)
                        Text(money)
                            .font(.title.weight(.bold))
                            .foregroundStyle(AppTheme.deepTeal)
                        Text("Free Split doesn’t move money itself. Send \(money) in another app, then tap I paid so this balance clears.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 8)

                    VStack(spacing: 12) {
                        payButton("Venmo", systemImage: "v.circle.fill") {
                            if let url = PaymentTransfer.venmoURL(amount: request.amount, note: request.note) {
                                PaymentTransfer.open(url)
                            }
                        }
                        payButton("Cash App", systemImage: "dollarsign.square.fill") {
                            if let url = PaymentTransfer.cashAppURL() {
                                PaymentTransfer.open(url)
                            }
                        }
                        payButton("PayPal", systemImage: "p.circle.fill") {
                            if let url = PaymentTransfer.paypalURL() {
                                PaymentTransfer.open(url)
                            }
                        }
                        if let url = PaymentTransfer.messagesURL(
                            phone: request.phone,
                            body: "I sent you \(money) for \(request.note)."
                        ) {
                            payButton("Messages / Apple Cash", systemImage: "message.fill") {
                                PaymentTransfer.open(url)
                            }
                        }

                        if let errorMessage {
                            Text(errorMessage)
                                .font(.footnote)
                                .foregroundStyle(.red)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        Button {
                            markPaid()
                        } label: {
                            Text("I paid \(request.payeeName)")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(AppTheme.teal)
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 28)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .freeSplitBackground()
            .navigationTitle("Pay")
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

    private func payButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
        }
        .buttonStyle(.bordered)
        .tint(AppTheme.deepTeal)
    }

    private func markPaid() {
        if let error = PaymentTransfer.record(
            request: request,
            occasions: occasions,
            myNames: auth.selfNames,
            context: modelContext
        ) {
            errorMessage = error
            return
        }
        dismiss()
    }
}
