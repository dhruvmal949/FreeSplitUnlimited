//
//  CloudSyncService.swift
//  FreeSplitUnlimited
//
//  Fallback sync for when phones aren't near each other: uses CloudKit's public
//  database as a zero-maintenance "backend" (Apple hosts it, we write no server
//  code). Every device pushes/pulls only the splits it already knows the id for,
//  so this never needs a login system or a custom API.
//
//  Note: this requires the app target to have the iCloud → CloudKit capability
//  enabled (see FreeSplitUnlimited.entitlements) and a paid Apple Developer
//  Program membership. If either is missing, every call below just fails
//  quietly and the app keeps working via nearby mesh sync only.
//

import CloudKit
import Foundation
import SwiftData

@MainActor
final class CloudSyncService {
    static let shared = CloudSyncService()

    private static let recordType = "OccasionSync"
    private let container = CKContainer.default()
    private var database: CKDatabase { container.publicCloudDatabase }
    private(set) var isAvailable = false
    private init() {}

    func refreshAvailability() async {
        do {
            let status = try await container.accountStatus()
            isAvailable = (status == .available)
        } catch {
            isAvailable = false
        }
    }

    /// Uploads an occasion, but only if our copy is newer than (or unknown to) the cloud.
    func push(_ occasion: Occasion) async {
        guard isAvailable else { return }
        let backup = SplitBackup.exportOccasion(occasion)
        await push(backup)
    }

    func pushAll(_ occasions: [Occasion]) async {
        guard isAvailable, !occasions.isEmpty else { return }
        for occasion in occasions {
            await push(occasion)
        }
    }

    /// Pulls every occasion id we already know about and merges anything newer.
    func pull(ids: [UUID], into context: ModelContext) async {
        guard isAvailable, !ids.isEmpty else { return }
        let recordIDs = ids.map { CKRecord.ID(recordName: $0.uuidString) }
        let results = (try? await database.records(for: recordIDs)) ?? [:]

        var appliedIDs: [UUID] = []
        for (_, result) in results {
            guard case .success(let record) = result,
                  let backup = Self.decode(record) else { continue }
            if let updated = try? SplitBackup.upsert(backup, into: context) {
                appliedIDs.append(updated.id)
            }
        }
        if let first = appliedIDs.first {
            NotificationCenter.default.post(name: .freeSplitDidImport, object: first)
        }
    }

    // MARK: Private

    private func push(_ backup: BackupOccasion) async {
        let recordID = CKRecord.ID(recordName: backup.id.uuidString)

        // Don't clobber a newer remote copy — pull it down instead.
        if let existing = try? await database.record(for: recordID),
           let existingDate = existing[Self.updatedAtKey] as? Date,
           existingDate >= backup.updatedAt {
            return
        }

        guard let record = Self.encode(backup, recordID: recordID) else { return }
        _ = try? await database.save(record)
    }

    private static let payloadKey = "payload"
    private static let updatedAtKey = "updatedAt"

    private static func encode(_ backup: BackupOccasion, recordID: CKRecord.ID) -> CKRecord? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(backup),
              let json = String(data: data, encoding: .utf8) else { return nil }

        let record = CKRecord(recordType: recordType, recordID: recordID)
        record[payloadKey] = json as CKRecordValue
        record[updatedAtKey] = backup.updatedAt as CKRecordValue
        return record
    }

    private static func decode(_ record: CKRecord) -> BackupOccasion? {
        guard let json = record[payloadKey] as? String,
              let data = json.data(using: .utf8) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(BackupOccasion.self, from: data)
    }
}
