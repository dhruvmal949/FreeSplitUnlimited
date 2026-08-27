//
//  SplitShare.swift
//  FreeSplitUnlimited
//
//  Share a split with another phone (AirDrop / Messages / Mail / Files).
//

import Foundation
import SwiftData
import UniformTypeIdentifiers

extension UTType {
    static var freeSplit: UTType {
        UTType(exportedAs: "pramela.freesplitunlimited.split")
    }
}

enum SplitShare {
    static let fileExtension = "freesplit"

    /// Package one split for sharing with another device.
    struct Package: Codable {
        var version: Int = 1
        var kind: String = "freeSplit.share"
        var exportedAt: Date
        var occasion: BackupOccasion
    }

    static func makePackage(from occasion: Occasion) throws -> Package {
        Package(exportedAt: .now, occasion: SplitBackup.exportOccasion(occasion))
    }

    static func encode(_ package: Package) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(package)
    }

    static func decode(from data: Data) throws -> Package {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let package = try decoder.decode(Package.self, from: data)
        guard package.kind == "freeSplit.share" || package.version >= 1 else {
            throw ShareError.invalidFile
        }
        return package
    }

    /// Writes a temporary .freesplit file ready for the system share sheet.
    static func temporaryFileURL(for occasion: Occasion) throws -> URL {
        let package = try makePackage(from: occasion)
        let data = try encode(package)
        let safeName = occasion.name
            .replacingOccurrences(of: "/", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let fileName = "\(safeName.isEmpty ? "Split" : safeName).\(fileExtension)"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        try data.write(to: url, options: .atomic)
        return url
    }

    /// Imports a shared split. Replaces an existing split with the same id.
    @discardableResult
    static func importFile(at url: URL, into context: ModelContext) throws -> Occasion {
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed { url.stopAccessingSecurityScopedResource() }
        }

        let data = try Data(contentsOf: url)
        return try importData(data, into: context)
    }

    @discardableResult
    static func importData(_ data: Data, into context: ModelContext) throws -> Occasion {
        // Accept either a Package or a legacy full backup with one/more occasions.
        if let package = try? decode(from: data) {
            return try upsertOrFetch(package.occasion, into: context)
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let snapshot = try? decoder.decode(SplitsBackupSnapshot.self, from: data),
           !snapshot.occasions.isEmpty {
            var imported: Occasion?
            for occasion in snapshot.occasions {
                imported = try upsertOrFetch(occasion, into: context)
            }
            guard let imported else { throw ShareError.invalidFile }
            return imported
        }

        // Fallback without ISO8601 (older backups used default Date encoding)
        if let package = try? JSONDecoder().decode(Package.self, from: data) {
            return try upsertOrFetch(package.occasion, into: context)
        }
        if let snapshot = try? JSONDecoder().decode(SplitsBackupSnapshot.self, from: data),
           !snapshot.occasions.isEmpty {
            var imported: Occasion?
            for occasion in snapshot.occasions {
                imported = try upsertOrFetch(occasion, into: context)
            }
            guard let imported else { throw ShareError.invalidFile }
            return imported
        }

        throw ShareError.invalidFile
    }

    /// Applies the backup if it's newer; otherwise returns whatever is already stored locally.
    private static func upsertOrFetch(_ backup: BackupOccasion, into context: ModelContext) throws -> Occasion {
        if let updated = try SplitBackup.upsert(backup, into: context) {
            return updated
        }
        if let existing = try context.fetch(FetchDescriptor<Occasion>()).first(where: { $0.id == backup.id }) {
            return existing
        }
        throw ShareError.invalidFile
    }

    enum ShareError: LocalizedError {
        case invalidFile

        var errorDescription: String? {
            switch self {
            case .invalidFile:
                return "This file isn't a valid Free Split share."
            }
        }
    }
}
