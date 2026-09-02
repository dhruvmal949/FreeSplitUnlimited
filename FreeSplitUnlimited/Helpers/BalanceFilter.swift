//
//  BalanceFilter.swift
//  FreeSplitUnlimited
//

import SwiftUI

enum FriendBalanceFilter: String, CaseIterable, Identifiable {
    case none
    case outstanding
    case youOwe
    case owedToYou

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: return "None"
        case .outstanding: return "Friends with outstanding balances"
        case .youOwe: return "Friends you owe"
        case .owedToYou: return "Friends who owe you"
        }
    }

    func matches(_ net: Decimal) -> Bool {
        switch self {
        case .none: return true
        case .outstanding: return net != 0
        case .youOwe: return net < 0
        case .owedToYou: return net > 0
        }
    }
}

enum GroupBalanceFilter: String, CaseIterable, Identifiable {
    case none
    case outstanding
    case youOwe
    case owedToYou

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: return "None"
        case .outstanding: return "Groups with outstanding balances"
        case .youOwe: return "Group balances you owe"
        case .owedToYou: return "Group balances you are owed"
        }
    }

    func matches(myNet: Decimal) -> Bool {
        switch self {
        case .none: return true
        case .outstanding: return myNet != 0
        case .youOwe: return myNet < 0
        case .owedToYou: return myNet > 0
        }
    }
}

struct OverallBalanceBanner: View {
    let net: Decimal
    var onFilter: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            overallText
            Spacer(minLength: 8)
            Button(action: onFilter) {
                Image(systemName: "line.3.horizontal.decrease")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Set filter")
        }
        .padding(.vertical, 4)
    }

    private var overallText: Text {
        if net == 0 {
            return Text("Overall, you are settled")
                .foregroundColor(.secondary)
        }
        if net > 0 {
            return Text("Overall, you are owed ")
                .foregroundColor(.secondary)
            + Text(CurrencyFormat.string(from: net))
                .foregroundColor(.green)
                .fontWeight(.semibold)
        }
        return Text("Overall, you owe ")
            .foregroundColor(.secondary)
        + Text(CurrencyFormat.string(from: -net))
            .foregroundColor(.orange)
            .fontWeight(.semibold)
    }
}
