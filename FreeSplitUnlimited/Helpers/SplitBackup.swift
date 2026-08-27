//
//  SplitBackup.swift
//  FreeSplitUnlimited
//
//  Saves splits to iCloud Key-Value Store + Keychain so data can return after reinstall.
//

import Foundation
import Security
import SwiftData

// MARK: - Snapshot models

struct SplitsBackupSnapshot: Codable {
    var version: Int = 1
    var savedAt: Date
    var occasions: [BackupOccasion]
}

struct BackupOccasion: Codable {
    var id: UUID
    var name: String
    var note: String
    var createdAt: Date
    /// Defaults keep older backup files (saved before sync existed) loadable.
    var updatedAt: Date = .now
    var isDeleted: Bool = false
    var members: [BackupPerson]
    var expenses: [BackupExpense]
}

struct BackupPerson: Codable {
    var id: UUID
    var name: String
    var email: String
    var phone: String
}

struct BackupExpense: Codable {
    var id: UUID
    var title: String
    var amount: String
    var date: Date
    var splitMethodRaw: String
    var paidByID: UUID?
    var participantIDs: [UUID]
    var shares: [BackupShare]
}

struct BackupShare: Codable {
    var personID: UUID
    var value: String
}

// MARK: - Backup manager

enum SplitBackup {
    private static let keychainService = "pramela.FreeSplitUnlimited.backup"
    private static let keychainAccount = "splitsSnapshot"
    private static let iCloudKey = "freeSplit.splitsBackup.v1"

    static func save(from context: ModelContext) {
        do {
            let occasions = try context.fetch(FetchDescriptor<Occasion>())
            let snapshot = SplitsBackupSnapshot(
                savedAt: .now,
                occasions: occasions.map(export(occasion:))
            )
            let data = try JSONEncoder().encode(snapshot)
            saveToKeychain(data)
            saveToiCloud(data)
        } catch {
            print("Split backup failed: \(error)")
        }
    }

    /// Restores backup only when the local store has no splits.
    @discardableResult
    static func restoreIfNeeded(into context: ModelContext) -> Bool {
        do {
            let existing = try context.fetch(FetchDescriptor<Occasion>())
            guard existing.isEmpty else { return false }

            guard let data = loadFromiCloud() ?? loadFromKeychain(),
                  let snapshot = try? JSONDecoder().decode(SplitsBackupSnapshot.self, from: data),
                  !snapshot.occasions.isEmpty else {
                return false
            }

            for backup in snapshot.occasions {
                importOccasion(backup, into: context)
            }
            try context.save()
            return true
        } catch {
            print("Split restore failed: \(error)")
            return false
        }
    }

    // MARK: Export / Import

    static func exportOccasion(_ occasion: Occasion) -> BackupOccasion {
        BackupOccasion(
            id: occasion.id,
            name: occasion.name,
            note: occasion.note,
            createdAt: occasion.createdAt,
            updatedAt: occasion.updatedAt,
            isDeleted: occasion.isDeleted,
            members: occasion.uniqueMembers.map {
                BackupPerson(id: $0.id, name: $0.name, email: $0.email, phone: $0.phone)
            },
            expenses: occasion.expenses.map { expense in
                BackupExpense(
                    id: expense.id,
                    title: expense.title,
                    amount: NSDecimalNumber(decimal: expense.amount).stringValue,
                    date: expense.date,
                    splitMethodRaw: expense.splitMethodRaw,
                    paidByID: expense.paidBy?.id,
                    participantIDs: expense.uniqueParticipants.map(\.id),
                    shares: expense.shares.compactMap { share in
                        guard let personID = share.person?.id else { return nil }
                        return BackupShare(
                            personID: personID,
                            value: NSDecimalNumber(decimal: share.value).stringValue
                        )
                    }
                )
            }
        )
    }

    private static func export(occasion: Occasion) -> BackupOccasion {
        exportOccasion(occasion)
    }

    /// Inserts a split, or replaces an existing one with the same id — but only if the
    /// incoming copy is newer (last-write-wins). Returns nil if the incoming copy was
    /// ignored because the local copy is already up to date or newer.
    @discardableResult
    static func upsert(_ backup: BackupOccasion, into context: ModelContext) throws -> Occasion? {
        let existing = try context.fetch(FetchDescriptor<Occasion>()).first { $0.id == backup.id }

        if let existing, existing.updatedAt >= backup.updatedAt {
            // Local copy is already current (or newer) — nothing to merge.
            return nil
        }

        if let existing {
            context.delete(existing)
            try context.save()
        }
        let occasion = importOccasion(backup, into: context)
        try context.save()
        SplitBackup.save(from: context)
        return occasion
    }

    @discardableResult
    private static func importOccasion(_ backup: BackupOccasion, into context: ModelContext) -> Occasion {
        let occasion = Occasion(
            name: backup.name,
            note: backup.note,
            createdAt: backup.createdAt,
            updatedAt: backup.updatedAt,
            id: backup.id
        )
        occasion.isDeleted = backup.isDeleted

        var peopleByID: [UUID: Person] = [:]
        for member in backup.members {
            let person = Person(
                name: member.name,
                email: member.email,
                phone: member.phone,
                id: member.id
            )
            person.occasion = occasion
            peopleByID[member.id] = person
            context.insert(person)
        }

        for expenseBackup in backup.expenses {
            let amount = Decimal(string: expenseBackup.amount) ?? 0
            let participants = expenseBackup.participantIDs.compactMap { peopleByID[$0] }
            let expense = Expense(
                title: expenseBackup.title,
                amount: amount,
                date: expenseBackup.date,
                splitMethod: SplitMethod(rawValue: expenseBackup.splitMethodRaw) ?? .equal,
                paidBy: expenseBackup.paidByID.flatMap { peopleByID[$0] },
                participants: participants,
                shares: [],
                id: expenseBackup.id
            )
            expense.occasion = occasion

            for shareBackup in expenseBackup.shares {
                guard let person = peopleByID[shareBackup.personID],
                      let value = Decimal(string: shareBackup.value) else { continue }
                expense.shares.append(ExpenseShare(person: person, value: value))
            }

            context.insert(expense)
        }

        context.insert(occasion)
        return occasion
    }

    // MARK: iCloud KVS (survives reinstall with same Apple ID)

    private static func saveToiCloud(_ data: Data) {
        NSUbiquitousKeyValueStore.default.set(data, forKey: iCloudKey)
        NSUbiquitousKeyValueStore.default.synchronize()
    }

    private static func loadFromiCloud() -> Data? {
        NSUbiquitousKeyValueStore.default.synchronize()
        return NSUbiquitousKeyValueStore.default.data(forKey: iCloudKey)
    }

    // MARK: Keychain (often survives reinstall on the same device)

    private static func saveToKeychain(_ data: Data) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount
        ]
        SecItemDelete(query as CFDictionary)

        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }

    private static func loadFromKeychain() -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess else { return nil }
        return item as? Data
    }
}
