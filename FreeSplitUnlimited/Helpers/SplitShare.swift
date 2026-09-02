//
//  SplitShare.swift
//  FreeSplitUnlimited
//
//  Share a split with another phone (AirDrop / Messages / Mail / Files).
//

import Foundation
import SwiftData
import UniformTypeIdentifiers
import UIKit

extension UTType {
    static let freeSplitIdentifier = "pramela.freesplitunlimited.split"

    /// Prefer the filename extension. Never call `UTType(exportedAs:)` — that can
    /// trap (`brk`) if the UTI database isn't ready during a document-open launch.
    static var freeSplit: UTType {
        UTType(filenameExtension: SplitShare.fileExtension) ?? .json
    }
}

/// Thread-safe capture of incoming file URLs. Copy happens immediately because
/// security-scoped grants expire if you hop to a later Task first.
enum IncomingURLCapture {
    private static let lock = NSLock()
    private static var urls: [URL] = []

    static func capture(_ url: URL) {
        guard SplitShare.isSplitFile(url) else { return }
        let local = SplitShare.copyIntoSandbox(url) ?? url
        lock.lock()
        urls.append(local)
        lock.unlock()
    }

    static func takeAll() -> [URL] {
        lock.lock()
        defer { lock.unlock() }
        let taken = urls
        urls.removeAll()
        return taken
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

    /// Writes a .freesplit file in Caches (not tmp) so AirDrop can still read it
    /// after the share sheet is on screen.
    static func temporaryFileURL(for occasion: Occasion) throws -> URL {
        let package = try makePackage(from: occasion)
        let data = try encode(package)
        let safeName = occasion.name
            .replacingOccurrences(of: "/", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let fileName = "\(safeName.isEmpty ? "Split" : safeName).\(fileExtension)"
        let folder = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Share", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(fileName)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        try data.write(to: url, options: .atomic)
        return url
    }

    /// Copies an AirDrop / Files / Inbox URL into Application Support while the
    /// security-scoped grant is still valid. Reads bytes only — never uses
    /// NSFileCoordinator (that can initialize iCloud/CloudKit and `brk` without entitlements).
    static func copyIntoSandbox(_ url: URL) -> URL? {
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed { url.stopAccessingSecurityScopedResource() }
        }

        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Incoming", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let ext = url.pathExtension.isEmpty ? fileExtension : url.pathExtension
        let dest = folder
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(ext)

        if let data = readBytes(from: url), !data.isEmpty {
            do {
                try data.write(to: dest, options: .atomic)
                return dest
            } catch {
                print("Incoming copy write failed: \(error)")
            }
        }

        if !isLikelyUbiquitous(url) {
            try? FileManager.default.copyItem(at: url, to: dest)
            if FileManager.default.fileExists(atPath: dest.path) {
                return dest
            }
        }
        return nil
    }

    private static func isLikelyUbiquitous(_ url: URL) -> Bool {
        let path = url.path
        return path.contains("Mobile Documents") || path.contains("CloudDocs")
    }

    private static func readBytes(from url: URL) -> Data? {
        if let data = try? Data(contentsOf: url), !data.isEmpty {
            return data
        }
        if let data = try? Data(contentsOf: url, options: [.mappedIfSafe]), !data.isEmpty {
            return data
        }
        return nil
    }

    /// Imports a shared split. Always applies the file so opening it actually shows the split.
    @discardableResult
    static func importFile(at url: URL, into context: ModelContext) throws -> Occasion {
        let local = copyIntoSandbox(url) ?? url
        defer {
            if local.path.contains("/Incoming/") {
                try? FileManager.default.removeItem(at: local)
            }
            if url.path.contains("/Incoming/") || url.path.contains("/Inbox/") {
                try? FileManager.default.removeItem(at: url)
            }
        }

        guard let data = readBytes(from: local), !data.isEmpty else {
            throw ShareError.unreadableFile
        }
        return try importData(data, into: context)
    }

    @discardableResult
    static func importData(_ data: Data, into context: ModelContext) throws -> Occasion {
        if let package = try? decode(from: data) {
            return try applyOpenedShare(package.occasion, into: context)
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let snapshot = try? decoder.decode(SplitsBackupSnapshot.self, from: data),
           !snapshot.occasions.isEmpty {
            var imported: Occasion?
            for occasion in snapshot.occasions {
                imported = try applyOpenedShare(occasion, into: context)
            }
            guard let imported else { throw ShareError.invalidFile }
            return imported
        }

        if let package = try? JSONDecoder().decode(Package.self, from: data) {
            return try applyOpenedShare(package.occasion, into: context)
        }
        if let snapshot = try? JSONDecoder().decode(SplitsBackupSnapshot.self, from: data),
           !snapshot.occasions.isEmpty {
            var imported: Occasion?
            for occasion in snapshot.occasions {
                imported = try applyOpenedShare(occasion, into: context)
            }
            guard let imported else { throw ShareError.invalidFile }
            return imported
        }

        throw ShareError.invalidFile
    }

    /// Explicit file open should always win, including undeleting a local copy.
    private static func applyOpenedShare(_ backup: BackupOccasion, into context: ModelContext) throws -> Occasion {
        var backup = backup
        backup.isDeleted = false
        backup.updatedAt = max(backup.updatedAt, Date.now)
        if let updated = try SplitBackup.upsert(backup, into: context, force: true) {
            return updated
        }
        let existing = ((try? context.fetch(FetchDescriptor<Occasion>())) ?? [])
            .first(where: { $0.id == backup.id })
        if let existing {
            existing.isDeleted = false
            return existing
        }
        throw ShareError.invalidFile
    }

    static func isSplitFile(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return ext == fileExtension || ext == "json" || ext.isEmpty
            || url.absoluteString.lowercased().contains("freesplit")
    }

    enum ShareError: LocalizedError {
        case invalidFile
        case unreadableFile

        var errorDescription: String? {
            switch self {
            case .invalidFile:
                return "This file isn't a valid Free Split share."
            case .unreadableFile:
                return "Couldn't read this split file. Try Import Split from the Free Split home screen."
            }
        }
    }
}

/// Holds incoming AirDrop / Files URLs until SwiftData is ready, then imports.
@MainActor
final class IncomingSplitOpener {
    static let shared = IncomingSplitOpener()
    private var context: ModelContext?
    private var isFlushing = false

    func attach(context: ModelContext) {
        self.context = context
        DispatchQueue.main.async {
            self.importInboxFiles()
            DispatchQueue.main.async {
                self.flush()
            }
        }
    }

    func enqueue(_ url: URL) {
        IncomingURLCapture.capture(url)
        flushWhenReady()
    }

    func flushWhenReady() {
        DispatchQueue.main.async {
            self.flush()
        }
    }

    func importInboxFiles() {
        let fm = FileManager.default
        guard let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let inbox = docs.appendingPathComponent("Inbox", isDirectory: true)
        guard let files = try? fm.contentsOfDirectory(at: inbox, includingPropertiesForKeys: nil) else { return }
        for url in files where SplitShare.isSplitFile(url) {
            IncomingURLCapture.capture(url)
            try? fm.removeItem(at: url)
        }
    }

    private func flush() {
        guard let context, !isFlushing else { return }
        let urls = IncomingURLCapture.takeAll()
        guard !urls.isEmpty else { return }
        isFlushing = true
        defer { isFlushing = false }

        for url in urls {
            do {
                let occasion = try SplitShare.importFile(at: url, into: context)
                NotificationCenter.default.post(name: .freeSplitDidImport, object: occasion.id)
            } catch {
                NotificationCenter.default.post(
                    name: .freeSplitImportFailed,
                    object: nil,
                    userInfo: ["message": error.localizedDescription]
                )
                print("Shared split import failed: \(error)")
            }
        }
    }
}

/// Supplies the .freesplit UTI so AirDrop / Files treat the share as a Free Split file.
final class SplitFileActivityItem: NSObject, UIActivityItemSource {
    let url: URL
    let title: String

    init(url: URL, title: String) {
        self.url = url
        self.title = title
    }

    func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any {
        url
    }

    func activityViewController(_ activityViewController: UIActivityViewController, itemForActivityType activityType: UIActivity.ActivityType?) -> Any? {
        url
    }

    func activityViewController(_ activityViewController: UIActivityViewController, dataTypeIdentifierForActivityType activityType: UIActivity.ActivityType?) -> String {
        UTType.freeSplitIdentifier
    }

    func activityViewController(_ activityViewController: UIActivityViewController, subjectForActivityType activityType: UIActivity.ActivityType?) -> String {
        title
    }
}
