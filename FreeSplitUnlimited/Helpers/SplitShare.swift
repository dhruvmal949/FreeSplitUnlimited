//
//  SplitShare.swift
//  FreeSplitUnlimited
//
//  Share a split with another phone (AirDrop / Messages / Mail / Files).
//

import Foundation
import SwiftData
import SwiftUI
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

/// Thread-safe capture of incoming file URLs and `freesplit://` invite links.
/// File copy happens immediately because security-scoped grants expire if you hop later.
enum IncomingURLCapture {
    private static let lock = NSLock()
    private static var urls: [URL] = []

    static func capture(_ url: URL) {
        if SplitShare.isShareLink(url) {
            lock.lock()
            urls.append(url)
            lock.unlock()
            return
        }
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
    static let urlScheme = "freesplit"

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

    static func encode(_ package: Package, prettyPrinted: Bool = true) throws -> Data {
        let encoder = JSONEncoder()
        if prettyPrinted {
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        } else {
            encoder.outputFormatting = [.sortedKeys]
        }
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(package)
    }

    /// Invite URL another phone can tap to add this group. No internet required.
    static func shareLink(for occasion: Occasion) throws -> URL {
        let package = try makePackage(from: occasion)
        return try shareURL(fromJSON: try encode(package, prettyPrinted: false))
    }

    static func activityPayload(for occasion: Occasion) async -> ActivitySharePayload {
        let file = try? temporaryFileURL(for: occasion)
        let link: URL
        if let package = try? makePackage(from: occasion),
           let published = try? await ShareLink.publish(package, groupName: occasion.name) {
            link = published
        } else {
            link = ShareLink.appStoreURL
        }
        return ActivitySharePayload(
            message: SplitShareText.inviteMessage(groupName: occasion.name, link: link),
            link: link,
            fileURL: file,
            fileTitle: occasion.name.isEmpty ? "Split" : occasion.name
        )
    }

    static func shareURL(fromJSON data: Data) throws -> URL {
        let compressed = try (data as NSData).compressed(using: .zlib) as Data
        let token = base64URLEncoded(compressed)
        let string = "\(urlScheme)://i/\(token)"
        guard string.count < 12_000, let url = URL(string: string) else {
            throw ShareError.linkTooLong
        }
        return url
    }

    static func isShareLink(_ url: URL) -> Bool {
        url.scheme?.lowercased() == urlScheme
    }

    static func json(fromShareURL url: URL) throws -> Data {
        guard let token = shareToken(from: url),
              let payload = base64URLDecoded(token) else {
            throw ShareError.invalidFile
        }
        if let json = try? (payload as NSData).decompressed(using: .zlib) {
            return json as Data
        }
        if payload.first == UInt8(ascii: "{") {
            return payload
        }
        throw ShareError.invalidFile
    }

    private static func shareToken(from url: URL) -> String? {
        guard isShareLink(url) else { return nil }
        if let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems {
            if let value = items.first(where: { $0.name == "d" || $0.name == "payload" })?.value,
               !value.isEmpty {
                return value.removingPercentEncoding ?? value
            }
        }
        let host = url.host?.lowercased()
        if host == "i" || host == "import" {
            let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            if !path.isEmpty {
                return path.removingPercentEncoding ?? path
            }
        }
        let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return path.isEmpty ? nil : (path.removingPercentEncoding ?? path)
    }

    private static func base64URLEncoded(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func base64URLDecoded(_ string: String) -> Data? {
        var value = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = value.count % 4
        if remainder > 0 {
            value.append(String(repeating: "=", count: 4 - remainder))
        }
        return Data(base64Encoded: value)
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
    @MainActor
    @discardableResult
    static func importFile(at url: URL, into context: ModelContext) throws -> Occasion {
        if ShareLink.isPayloadLink(url) {
            throw ShareError.unreadableFile
        }
        if isShareLink(url) {
            return try importData(try json(fromShareURL: url), into: context)
        }
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

    @MainActor
    @discardableResult
    static func importData(_ data: Data, into context: ModelContext) throws -> Occasion {
        if let package = try? decode(from: data) {
            return try applyOpenedShare(package.occasion, into: context, grantCurrentUser: true)
        }
        if let package = try? ShareLink.package(fromPayload: data) {
            return try applyOpenedShare(package.occasion, into: context, grantCurrentUser: true)
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let snapshot = try? decoder.decode(SplitsBackupSnapshot.self, from: data),
           !snapshot.occasions.isEmpty {
            return try importSnapshot(snapshot, into: context)
        }

        if let package = try? JSONDecoder().decode(Package.self, from: data) {
            return try applyOpenedShare(package.occasion, into: context, grantCurrentUser: true)
        }
        if let snapshot = try? JSONDecoder().decode(SplitsBackupSnapshot.self, from: data),
           !snapshot.occasions.isEmpty {
            return try importSnapshot(snapshot, into: context)
        }

        throw ShareError.invalidFile
    }

    @MainActor
    private static func importSnapshot(_ snapshot: SplitsBackupSnapshot, into context: ModelContext) throws -> Occasion {
        let identity = AccountIdentity.current
        let grantSingle = snapshot.occasions.count == 1
        var imported: Occasion?
        for occasion in snapshot.occasions {
            if grantSingle || OccasionAccess.canAccess(occasion, as: identity) {
                imported = try applyOpenedShare(occasion, into: context, grantCurrentUser: grantSingle)
            }
        }
        guard let imported else { throw ShareError.invalidFile }
        return imported
    }

    /// Explicit file or invite link should add only this group to the current account.
    @MainActor
    private static func applyOpenedShare(
        _ backup: BackupOccasion,
        into context: ModelContext,
        grantCurrentUser: Bool
    ) throws -> Occasion {
        var backup = backup
        if grantCurrentUser {
            backup = OccasionAccess.grantCurrentUser(backup)
        }
        backup.isDeleted = false
        backup.updatedAt = max(backup.updatedAt, Date.now)
        if let updated = try SplitBackup.upsert(backup, into: context, force: true) {
            if grantCurrentUser, let accountID = AuthSession.shared.accountID {
                updated.grantAccess(to: accountID)
                try? context.save()
            }
            return updated
        }
        let existing = ((try? context.fetch(FetchDescriptor<Occasion>())) ?? [])
            .first(where: { $0.id == backup.id })
        if let existing {
            existing.isDeleted = false
            if grantCurrentUser, let accountID = AuthSession.shared.accountID {
                existing.grantAccess(to: accountID)
            }
            return existing
        }
        throw ShareError.invalidFile
    }

    static func isSplitFile(_ url: URL) -> Bool {
        if isShareLink(url) { return false }
        let ext = url.pathExtension.lowercased()
        return ext == fileExtension || ext == "json"
            || url.lastPathComponent.lowercased().contains("freesplit")
    }

    enum ShareError: LocalizedError {
        case invalidFile
        case unreadableFile
        case linkTooLong
        case linkUnavailable

        var errorDescription: String? {
            switch self {
            case .invalidFile:
                return "This file isn't a valid Free Split share."
            case .unreadableFile:
                return "Couldn't read this split file. Try Import Split from the Free Split home screen."
            case .linkTooLong:
                return "This group is too large to copy as a link. AirDrop or Messages the .freesplit file instead."
            case .linkUnavailable:
                return "Couldn't make a tap-to-open link. Check your internet, or AirDrop the .freesplit file."
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
    private(set) var pendingOpenID: UUID?

    func consumePendingOpen() -> UUID? {
        let id = pendingOpenID
        pendingOpenID = nil
        return id
    }

    func restorePendingOpen(_ id: UUID) {
        pendingOpenID = id
    }

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
            if ShareLink.isPayloadLink(url) {
                Task { await self.importRemote(url) }
                continue
            }
            do {
                let occasion = try SplitShare.importFile(at: url, into: context)
                pendingOpenID = occasion.id
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

    private func importRemote(_ url: URL) async {
        guard let context, let id = ShareLink.payloadID(from: url) else { return }
        do {
            let data = try await ShareLink.downloadPayload(id: id)
            let occasion = try SplitShare.importData(data, into: context)
            pendingOpenID = occasion.id
            NotificationCenter.default.post(name: .freeSplitDidImport, object: occasion.id)
        } catch {
            NotificationCenter.default.post(
                name: .freeSplitImportFailed,
                object: nil,
                userInfo: ["message": error.localizedDescription]
            )
            print("Remote split import failed: \(error)")
        }
    }
}

/// .freesplit file for AirDrop / Messages / Files. Omitted from Copy so JSON is not pasted.
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
        if activityType == .copyToPasteboard {
            return nil
        }
        return url
    }

    func activityViewController(_ activityViewController: UIActivityViewController, subjectForActivityType activityType: UIActivity.ActivityType?) -> String {
        title
    }
}

struct ActivitySharePayload: Identifiable {
    let id = UUID()
    let message: String
    let link: URL?
    let fileURL: URL?
    let fileTitle: String
}

struct ActivityShareSheet: UIViewControllerRepresentable {
    let payload: ActivitySharePayload

    func makeUIViewController(context: Context) -> UIActivityViewController {
        var items: [Any] = [payload.message]
        if let url = payload.fileURL {
            items.append(SplitFileActivityItem(url: url, title: payload.fileTitle))
        }
        return UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

enum SplitShareText {
    static func inviteMessage(groupName: String, link: URL? = nil) -> String {
        let name = groupName.trimmingCharacters(in: .whitespacesAndNewlines)
        let group = name.isEmpty ? "my group" : "my group '\(name)'"
        var lines = ["Hey friends! Join \(group) on Free Split."]
        if let link {
            if link.host?.contains("apps.apple.com") == true {
                lines.append("Don't have Free Split? Get it on the App Store: \(link.absoluteString)")
            } else {
                lines.append("Tap this link to open the split. If you don't have Free Split, it takes you to the App Store: \(link.absoluteString)")
            }
        }
        return lines.joined(separator: "\n")
    }
}
