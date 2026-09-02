//
//  AddExpenseView.swift
//  FreeSplitUnlimited
//

import SwiftUI
import SwiftData

struct AddExpenseView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let occasion: Occasion
    /// Pass an existing expense to edit it; omit to create a new one.
    var expenseToEdit: Expense? = nil

    @State private var title = ""
    @State private var amountText = ""
    @State private var paidByID: UUID?
    @State private var selectedParticipantIDs: Set<UUID> = []
    @State private var shareValues: [UUID: String] = [:]
    @State private var splitMethod: SplitMethod = .equal
    @State private var date = Date()
    @State private var didLoadExisting = false
    @State private var isUpdatingSplitMethod = false

    private var isEditing: Bool { expenseToEdit != nil }

    private var sortedMembers: [Person] {
        occasion.sortedMembers()
    }

    private var selectedMembers: [Person] {
        sortedMembers.filter { selectedParticipantIDs.contains($0.id) }
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
        return value
    }

    private var parsedShareTotal: Decimal {
        selectedMembers.reduce(0) { partial, person in
            partial + (decimalValue(for: person.id) ?? 0)
        }
    }

    private var isPercentageValid: Bool {
        let diff = parsedShareTotal - 100
        return diff >= -0.01 && diff <= 0.01
    }

    private var formattedShareTotal: String {
        let number = NSDecimalNumber(decimal: parsedShareTotal)
        let formatter = NumberFormatter()
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        return formatter.string(from: number) ?? "\(number)"
    }

    private var canSave: Bool {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              amount != nil,
              paidByID != nil,
              !selectedParticipantIDs.isEmpty else { return false }

        switch splitMethod {
        case .equal:
            return true
        case .percentage:
            guard selectedMembers.allSatisfy({ (decimalValue(for: $0.id) ?? 0) > 0 }) else { return false }
            return isPercentageValid
        case .parts:
            return selectedMembers.allSatisfy { (decimalValue(for: $0.id) ?? 0) > 0 }
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text("Group")
                        Spacer()
                        Text(occasion.name)
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.trailing)
                    }
                }

                Section("Expense") {
                    TextField("What was it? (e.g. Dinner)", text: $title)
                    TextField("Amount (e.g. 55 or $55)", text: $amountText)
                        .keyboardType(.decimalPad)
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                }

                Section("Paid by") {
                    ForEach(sortedMembers, id: \.id) { person in
                        Button {
                            paidByID = person.id
                        } label: {
                            HStack {
                                Text(person.name)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if paidByID == person.id {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.tint)
                                }
                            }
                        }
                    }
                }

                Section {
                    Picker("Split method", selection: $splitMethod) {
                        ForEach(SplitMethod.allCases) { method in
                            Text(method.title).tag(method)
                        }
                    }
                    .pickerStyle(.segmented)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                } footer: {
                    Text(splitMethod.detail)
                }

                Section {
                    ForEach(sortedMembers, id: \.id) { person in
                        participantRow(for: person)
                    }

                    Button("Select everyone") {
                        selectedParticipantIDs = Set(sortedMembers.map(\.id))
                        ensureDefaultShares(for: sortedMembers.map(\.id))
                    }

                    if splitMethod == .percentage {
                        HStack {
                            Text("Total")
                            Spacer()
                            Text("\(formattedShareTotal)%")
                                .foregroundStyle(isPercentageValid ? Color.secondary : Color.red)
                                .fontWeight(.semibold)
                        }
                    }
                } header: {
                    Text("Split between")
                } footer: {
                    footerText
                }

                Section {
                    Button {
                        save()
                    } label: {
                        Text(isEditing ? "Save Changes" : "Save Expense")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .disabled(!canSave)
                    .listRowBackground(
                        canSave ? AppTheme.teal : Color.gray.opacity(0.35)
                    )
                    .foregroundStyle(.white)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 1) {
                        Text(isEditing ? "Edit Expense" : "Add Expense")
                            .font(.headline)
                        Text(occasion.name)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .freeSplitListStyle()
            .freeSplitBackground()
            .scrollDismissesKeyboard(.interactively)
            .onAppear {
                loadExistingIfNeeded()
            }
            .onChange(of: splitMethod) { _, newMethod in
                guard !isUpdatingSplitMethod else { return }
                shareValues = [:]
                ensureDefaultShares(for: Array(selectedParticipantIDs), method: newMethod)
            }
        }
    }

    @ViewBuilder
    private func participantRow(for person: Person) -> some View {
        let isSelected = selectedParticipantIDs.contains(person.id)

        VStack(alignment: .leading, spacing: 8) {
            Button {
                toggleParticipant(person.id)
            } label: {
                HStack {
                    Text(person.name)
                        .foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                        .foregroundStyle(.tint)
                }
            }

            if isSelected && splitMethod != .equal {
                HStack {
                    Text(splitMethod == .percentage ? "Percent" : "Parts")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    TextField(
                        splitMethod == .percentage ? "0" : "1",
                        text: binding(for: person.id)
                    )
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 72)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(Color(.tertiarySystemFill))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                    Text(splitMethod == .percentage ? "%" : "parts")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var footerText: Text {
        switch splitMethod {
        case .equal:
            return Text("Each selected person owes an equal share.")
        case .percentage:
            return Text("Enter each person's percent. Total must equal 100%.")
        case .parts:
            return Text("Enter parts for each person. Example: Mom 2, Dad 1 → Mom pays 2/3.")
        }
    }

    private func binding(for id: UUID) -> Binding<String> {
        Binding(
            get: { shareValues[id] ?? "" },
            set: { shareValues[id] = $0 }
        )
    }

    private func decimalValue(for id: UUID) -> Decimal? {
        guard let raw = shareValues[id]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else { return nil }
        let cleaned = raw.replacingOccurrences(of: ",", with: "")
        guard let value = Decimal(string: cleaned), value > 0 else { return nil }
        return value
    }

    private func toggleParticipant(_ id: UUID) {
        if selectedParticipantIDs.contains(id) {
            selectedParticipantIDs.remove(id)
            shareValues[id] = nil
        } else {
            selectedParticipantIDs.insert(id)
            ensureDefaultShares(for: [id])
        }
    }

    private func ensureDefaultShares(for ids: [UUID], method: SplitMethod? = nil) {
        let method = method ?? splitMethod
        guard method != .equal else { return }

        let selected = ids.filter { selectedParticipantIDs.contains($0) }
        guard !selected.isEmpty else { return }

        if method == .percentage {
            let even = (100 / selected.count)
            let remainder = 100 - (even * selected.count)
            for (index, id) in selected.enumerated() {
                if shareValues[id] == nil || shareValues[id]?.isEmpty == true {
                    let value = index == 0 ? even + remainder : even
                    shareValues[id] = "\(value)"
                }
            }
        } else if method == .parts {
            for id in selected where shareValues[id] == nil || shareValues[id]?.isEmpty == true {
                shareValues[id] = "1"
            }
        }
    }

    private func loadExistingIfNeeded() {
        guard !didLoadExisting else { return }
        didLoadExisting = true

        if let expense = expenseToEdit {
            isUpdatingSplitMethod = true
            title = expense.title
            amountText = NSDecimalNumber(decimal: expense.amount).stringValue
            date = expense.date
            splitMethod = expense.splitMethod
            paidByID = expense.paidBy?.id
            selectedParticipantIDs = Set(expense.uniqueParticipants.map(\.id))

            var loadedShares: [UUID: String] = [:]
            for share in expense.shares {
                guard let personID = share.person?.id else { continue }
                loadedShares[personID] = NSDecimalNumber(decimal: share.value).stringValue
            }
            shareValues = loadedShares
            isUpdatingSplitMethod = false
        } else {
            if paidByID == nil {
                paidByID = sortedMembers.first?.id
            }
            if selectedParticipantIDs.isEmpty {
                selectedParticipantIDs = Set(sortedMembers.map(\.id))
            }
            ensureDefaultShares(for: Array(selectedParticipantIDs))
        }
    }

    private func save() {
        guard canSave,
              let amount,
              let paidByID,
              let payer = sortedMembers.first(where: { $0.id == paidByID }) else { return }

        let participants = selectedMembers

        if let expense = expenseToEdit {
            expense.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
            expense.amount = amount
            expense.date = date
            expense.splitMethod = splitMethod
            expense.paidBy = payer
            expense.participants = participants
            replaceShares(on: expense, participants: participants)
        } else {
            let expense = Expense(
                title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                amount: amount,
                date: date,
                splitMethod: splitMethod,
                paidBy: payer,
                participants: participants,
                shares: []
            )
            applyShares(to: expense, participants: participants)
            expense.occasion = occasion
            modelContext.insert(expense)
        }

        occasion.touch()
        modelContext.persist()
        dismiss()
    }

    private func replaceShares(on expense: Expense, participants: [Person]) {
        for share in expense.shares {
            modelContext.delete(share)
        }
        expense.shares = []
        applyShares(to: expense, participants: participants)
    }

    private func applyShares(to expense: Expense, participants: [Person]) {
        guard splitMethod != .equal else { return }
        for person in participants {
            guard let value = decimalValue(for: person.id) else { continue }
            expense.shares.append(ExpenseShare(person: person, value: value))
        }
    }
}
