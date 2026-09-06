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
    var groupType: String = GroupKind.other.rawValue
    var joinCode: String = ""
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

    static func save(from context: ModelContext) {
        do {
            let occasions = try context.fetch(FetchDescriptor<Occasion>())
            let snapshot = SplitsBackupSnapshot(
                savedAt: .now,
                occasions: occasions.map(export(occasion:))
            )
            let data = try JSONEncoder().encode(snapshot)
            saveToKeychain(data)
            // iCloud KVS is skipped: this target has no ubiquity entitlements.
            // NSUbiquitousKeyValueStore.default traps with brk #0x1 without them.
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

            if restoreFromKeychain(into: context) { return true }
            if restoreFromLegacyStores(into: context) { return true }
            return false
        } catch {
            print("Split restore failed: \(error)")
            return false
        }
    }

    private static func restoreFromKeychain(into context: ModelContext) -> Bool {
        guard let data = loadFromKeychain(),
              let snapshot = try? JSONDecoder().decode(SplitsBackupSnapshot.self, from: data),
              !snapshot.occasions.isEmpty else {
            return false
        }

        var seenIDs = Set<UUID>()
        for backup in snapshot.occasions {
            guard seenIDs.insert(backup.id).inserted else { continue }
            importOccasion(backup, into: context)
        }
        do {
            try context.save()
            KnownFriendsStore.remember(from: context)
            return true
        } catch {
            print("Split keychain restore failed: \(error)")
            return false
        }
    }

    /// Pulls groups out of FreeSplit.v2 (and earlier) when the current store is empty.
    private static func restoreFromLegacyStores(into context: ModelContext) -> Bool {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let folder = support.appendingPathComponent("FreeSplitUnlimited", isDirectory: true)
        let schema = Schema([Occasion.self, Person.self, Expense.self, ExpenseShare.self])

        for name in ["FreeSplit.v2.store", "FreeSplit.v1.store"] {
            let url = folder.appendingPathComponent(name)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            if importOccasions(fromStore: url, schema: schema, into: context) {
                return true
            }
        }
        return false
    }

    private static func importOccasions(fromStore url: URL, schema: Schema, into context: ModelContext) -> Bool {
        let temp = url.deletingLastPathComponent()
            .appendingPathComponent("LegacyImport-\(UUID().uuidString).store")
        copyStore(from: url, to: temp)
        defer { deleteStore(at: temp) }

        let config = ModelConfiguration(
            "FreeSplitLegacyImport-\(temp.lastPathComponent)",
            schema: schema,
            url: temp,
            cloudKitDatabase: .none
        )
        guard let container = try? ModelContainer(for: schema, configurations: [config]) else {
            return false
        }

        let legacy = ModelContext(container)
        guard let occasions = try? legacy.fetch(FetchDescriptor<Occasion>()),
              !occasions.isEmpty else {
            return false
        }

        var seenIDs = Set<UUID>()
        for occasion in occasions {
            guard seenIDs.insert(occasion.id).inserted else { continue }
            importOccasion(exportOccasion(occasion), into: context)
        }
        do {
            try context.save()
            KnownFriendsStore.remember(from: context)
            save(from: context)
            return true
        } catch {
            print("Legacy store import failed: \(error)")
            return false
        }
    }

    private static func copyStore(from source: URL, to dest: URL) {
        let fm = FileManager.default
        for suffix in ["", "-shm", "-wal"] {
            let src = URL(fileURLWithPath: source.path + suffix)
            let dst = URL(fileURLWithPath: dest.path + suffix)
            guard fm.fileExists(atPath: src.path) else { continue }
            try? fm.copyItem(at: src, to: dst)
        }
    }

    private static func deleteStore(at url: URL) {
        let fm = FileManager.default
        for suffix in ["", "-shm", "-wal"] {
            try? fm.removeItem(at: URL(fileURLWithPath: url.path + suffix))
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
            groupType: occasion.groupType,
            joinCode: occasion.joinCode,
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
    /// Pass `force: true` for an explicit user import (AirDrop / Files) so the opened
    /// file always appears, even if a deleted or newer local copy exists.
    @discardableResult
    static func upsert(_ backup: BackupOccasion, into context: ModelContext, force: Bool = false) throws -> Occasion? {
        let existing = ((try? context.fetch(FetchDescriptor<Occasion>())) ?? [])
            .first { $0.id == backup.id }

        if let existing, !force, existing.updatedAt >= backup.updatedAt {
            return nil
        }

        let occasion: Occasion
        if let existing {
            // Update in place. Deleting a live SwiftData object while @Query
            // is rendering it is a common `brk` (invalidated model / ForEach).
            existing.name = backup.name
            existing.note = backup.note
            existing.createdAt = backup.createdAt
            existing.updatedAt = backup.updatedAt
            existing.isDeleted = backup.isDeleted
            existing.groupType = backup.groupType
            if !backup.joinCode.isEmpty {
                existing.joinCode = backup.joinCode
            }
            replaceChildren(of: existing, with: backup, into: context)
            occasion = existing
        } else {
            occasion = importOccasion(backup, into: context)
        }

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
            id: backup.id,
            groupType: backup.groupType
        )
        occasion.isDeleted = backup.isDeleted
        occasion.groupType = backup.groupType
        occasion.joinCode = backup.joinCode
        populate(occasion, from: backup, into: context)
        context.insert(occasion)
        return occasion
    }

    private static func replaceChildren(of occasion: Occasion, with backup: BackupOccasion, into context: ModelContext) {
        let peopleByID = reconcileMembers(of: occasion, with: backup.members, into: context)
        reconcileExpenses(of: occasion, with: backup.expenses, peopleByID: peopleByID, into: context)
    }

    /// Updates the member graph in place. Deleting every child and re-inserting
    /// while `@Query` is showing those objects traps with `EXC_BREAKPOINT`.
    @discardableResult
    private static func reconcileMembers(
        of occasion: Occasion,
        with backupMembers: [BackupPerson],
        into context: ModelContext
    ) -> [UUID: Person] {
        var peopleByID: [UUID: Person] = [:]
        for member in occasion.members where peopleByID[member.id] == nil {
            peopleByID[member.id] = member
        }

        var keep = Set<UUID>()
        for backup in backupMembers {
            guard keep.insert(backup.id).inserted else { continue }
            if let existing = peopleByID[backup.id] {
                existing.name = backup.name
                existing.email = backup.email
                existing.phone = backup.phone
            } else {
                let person = Person(
                    name: backup.name,
                    email: backup.email,
                    phone: backup.phone,
                    id: backup.id
                )
                person.occasion = occasion
                context.insert(person)
                peopleByID[backup.id] = person
            }
        }

        for member in occasion.members where !keep.contains(member.id) {
            context.delete(member)
            peopleByID[member.id] = nil
        }
        occasion.members = backupMembers.compactMap { peopleByID[$0.id] }
        return peopleByID
    }

    private static func reconcileExpenses(
        of occasion: Occasion,
        with backupExpenses: [BackupExpense],
        peopleByID: [UUID: Person],
        into context: ModelContext
    ) {
        var expensesByID: [UUID: Expense] = [:]
        for expense in occasion.expenses where expensesByID[expense.id] == nil {
            expensesByID[expense.id] = expense
        }

        var keep = Set<UUID>()
        var next: [Expense] = []
        for backup in backupExpenses {
            guard keep.insert(backup.id).inserted else { continue }
            var seenParticipantIDs = Set<UUID>()
            let participants = backup.participantIDs.compactMap { id -> Person? in
                guard seenParticipantIDs.insert(id).inserted else { return nil }
                return peopleByID[id]
            }
            let amount = Decimal(string: backup.amount) ?? 0
            let method = SplitMethod(rawValue: backup.splitMethodRaw) ?? .equal

            let expense: Expense
            if let existing = expensesByID[backup.id] {
                existing.title = backup.title
                existing.amount = amount
                existing.date = backup.date
                existing.splitMethod = method
                existing.paidBy = backup.paidByID.flatMap { peopleByID[$0] }
                existing.participants = participants
                expense = existing
            } else {
                expense = Expense(
                    title: backup.title,
                    amount: amount,
                    date: backup.date,
                    splitMethod: method,
                    paidBy: backup.paidByID.flatMap { peopleByID[$0] },
                    participants: participants,
                    shares: [],
                    id: backup.id
                )
                expense.occasion = occasion
                context.insert(expense)
            }

            for share in expense.shares {
                context.delete(share)
            }
            expense.shares = []
            if method != .equal {
                var seenShareIDs = Set<UUID>()
                for shareBackup in backup.shares {
                    guard seenShareIDs.insert(shareBackup.personID).inserted,
                          let person = peopleByID[shareBackup.personID],
                          let value = Decimal(string: shareBackup.value) else { continue }
                    expense.shares.append(ExpenseShare(person: person, value: value))
                }
            }
            next.append(expense)
        }

        for expense in occasion.expenses where !keep.contains(expense.id) {
            for share in expense.shares {
                context.delete(share)
            }
            context.delete(expense)
        }
        occasion.expenses = next
    }

    private static func populate(_ occasion: Occasion, from backup: BackupOccasion, into context: ModelContext) {
        var peopleByID: [UUID: Person] = [:]
        for member in backup.members {
            guard peopleByID[member.id] == nil else { continue }
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

        var seenExpenseIDs = Set<UUID>()
        for expenseBackup in backup.expenses {
            guard seenExpenseIDs.insert(expenseBackup.id).inserted else { continue }
            let amount = Decimal(string: expenseBackup.amount) ?? 0
            var seenParticipantIDs = Set<UUID>()
            let participants = expenseBackup.participantIDs.compactMap { id -> Person? in
                guard seenParticipantIDs.insert(id).inserted else { return nil }
                return peopleByID[id]
            }
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

            var seenShareIDs = Set<UUID>()
            for shareBackup in expenseBackup.shares {
                guard seenShareIDs.insert(shareBackup.personID).inserted,
                      let person = peopleByID[shareBackup.personID],
                      let value = Decimal(string: shareBackup.value) else { continue }
                expense.shares.append(ExpenseShare(person: person, value: value))
            }

            context.insert(expense)
        }
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
