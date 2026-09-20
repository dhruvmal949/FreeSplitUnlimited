//
//  ShareLink.swift
//  FreeSplitUnlimited
//
//  Short https:// links other apps will actually make tappable.
//  The split itself is stored at paste.rs; the shared URL is just an opener page.
//

import Foundation

enum ShareLink {
    private static let pasteHost = "https://paste.rs"
    static let appStoreURL = URL(string: "https://apps.apple.com/search?term=Free%20Split%20Unlimited")!

    /// Custom-scheme URL the join page tries first. If Free Split is on the phone, iOS opens it.
    static func appURL(payloadID: String) -> URL? {
        guard isSafeSlug(payloadID) else { return nil }
        return URL(string: "\(SplitShare.urlScheme)://p/\(payloadID)")
    }

    /// Compact, compressed bytes for one split (not a pretty JSON file).
    static func payload(from package: SplitShare.Package) throws -> Data {
        let encoder = JSONEncoder()
        let json = try encoder.encode(WirePackage(package))
        return try (json as NSData).compressed(using: .zlib) as Data
    }

    static func package(fromPayload data: Data) throws -> SplitShare.Package {
        let json: Data
        if let unzipped = try? (data as NSData).decompressed(using: .zlib) {
            json = unzipped as Data
        } else {
            json = data
        }
        return try JSONDecoder().decode(WirePackage.self, from: json).asPackage()
    }

    /// Uploads the split and a markdown opener. paste.rs `.html` shows source; `.md` renders a real page.
    static func publish(_ package: SplitShare.Package, groupName: String = "") async throws -> URL {
        let payload = try payload(from: package)
        let dataID = try await post(payload, contentType: "application/octet-stream")
        let markdown = JoinPage.markdown(payloadID: dataID, groupName: groupName)
        let pageID = try await post(Data(markdown.utf8), contentType: "text/markdown")
        return try publishedPageURL(pageID: pageID)
    }

    static func publishedPageURL(pageID: String) throws -> URL {
        guard isSafeSlug(pageID), let url = URL(string: "\(pasteHost)/\(pageID).md") else {
            throw SplitShare.ShareError.linkUnavailable
        }
        return url
    }

    static func joinURL(payloadID: String, groupName: String) throws -> URL {
        guard isSafeSlug(payloadID) else {
            throw SplitShare.ShareError.linkUnavailable
        }
        return try publishedPageURL(pageID: payloadID)
    }

    static func isPayloadLink(_ url: URL) -> Bool {
        url.scheme?.lowercased() == SplitShare.urlScheme && url.host?.lowercased() == "p"
    }

    static func payloadID(from url: URL) -> String? {
        guard isPayloadLink(url) else { return nil }
        let slug = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return isSafeSlug(slug) ? slug : nil
    }

    static func downloadPayload(id: String) async throws -> Data {
        guard isSafeSlug(id), let url = URL(string: "\(pasteHost)/\(id)") else {
            throw SplitShare.ShareError.invalidFile
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("FreeSplitUnlimited", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode), !data.isEmpty else {
            throw SplitShare.ShareError.unreadableFile
        }
        return data
    }

    private static func post(_ body: Data, contentType: String) async throws -> String {
        guard let url = URL(string: pasteHost) else {
            throw SplitShare.ShareError.linkUnavailable
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.httpBody = body
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.setValue("FreeSplitUnlimited", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
              let text = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              let posted = URL(string: text) else {
            throw SplitShare.ShareError.linkUnavailable
        }
        let slug = (posted.lastPathComponent as NSString).deletingPathExtension
        guard isSafeSlug(slug) else {
            throw SplitShare.ShareError.linkUnavailable
        }
        return slug
    }

    private static func isSafeSlug(_ slug: String) -> Bool {
        !slug.isEmpty
            && slug.count < 64
            && slug.unicodeScalars.allSatisfy { CharacterSet.alphanumerics.contains($0) }
    }
}

enum JoinPage {
    static func markdown(payloadID: String, groupName: String) -> String {
        let id = payloadID.filter { $0.isLetter || $0.isNumber }
        let rawName = groupName.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = rawName
            .replacingOccurrences(of: "[", with: "(")
            .replacingOccurrences(of: "]", with: ")")
        let title = name.isEmpty ? "this split" : name
        let deep = "\(SplitShare.urlScheme)://p/\(id)"
        let store = ShareLink.appStoreURL.absoluteString
        return """
        # Join \(title) on Free Split

        I added you to this split.

        **[Open in Free Split](\(deep))**

        If Free Split is on your phone, that opens the split. If not, get it here:

        **[Get Free Split on the App Store](\(store))**
        """
    }

    static func html(payloadID: String, groupName: String) -> String {
        let id = payloadID.filter { $0.isLetter || $0.isNumber }
        let idJSON = jsonString(id)
        let nameJSON = jsonString(groupName.trimmingCharacters(in: .whitespacesAndNewlines))
        let store = ShareLink.appStoreURL.absoluteString
        let deep = "\(SplitShare.urlScheme)://p/\(id)"
        return """
        <!DOCTYPE html>
        <html lang="en">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <title>Join on Free Split</title>
          <style>
            body { margin: 0; min-height: 100vh; font-family: -apple-system, sans-serif;
              background: linear-gradient(160deg, #115e59, #0d9488); display: flex;
              align-items: center; justify-content: center; padding: 24px; }
            .card { background: #fff; color: #134e4a; border-radius: 24px; padding: 32px 24px;
              max-width: 380px; width: 100%; text-align: center; }
            a.btn { display: block; background: #0f766e; color: #fff; text-decoration: none;
              font-weight: 700; padding: 14px 16px; border-radius: 14px; margin-bottom: 12px; }
            a.store { display: block; color: #0f766e; font-weight: 600; text-decoration: none; padding: 10px; }
          </style>
        </head>
        <body>
          <div class="card">
            <h1>Hey friends!</h1>
            <p id="subtitle">Join this group on Free Split.</p>
            <a class="btn" id="open" href="\(deep)">Open in Free Split</a>
            <a class="store" id="store" href="\(store)">Don't have the app? Get it on the App Store</a>
          </div>
          <script>
            var id = \(idJSON);
            var name = \(nameJSON);
            var store = \(jsonString(store));
            var deep = "freesplit://p/" + encodeURIComponent(id);
            if (name) {
              document.getElementById("subtitle").textContent = "Join my group '" + name + "' on Free Split.";
            }
            document.getElementById("open").href = deep;
            document.getElementById("store").href = store;
            if (id) {
              window.location.href = deep;
            }
          </script>
        </body>
        </html>
        """
    }

    private static func jsonString(_ value: String) -> String {
        let data = (try? JSONEncoder().encode(value)) ?? Data("\"\"".utf8)
        return String(data: data, encoding: .utf8) ?? "\"\""
    }
}

// MARK: - Compact wire format (short keys, no empty fields)

private struct WirePackage: Codable {
    var v: Int
    var t: Int
    var o: WireOccasion

    init(_ package: SplitShare.Package) {
        v = 2
        t = Int(package.exportedAt.timeIntervalSince1970)
        o = WireOccasion(package.occasion)
    }

    func asPackage() -> SplitShare.Package {
        SplitShare.Package(
            version: 1,
            kind: "freeSplit.share",
            exportedAt: Date(timeIntervalSince1970: TimeInterval(t)),
            occasion: o.asOccasion()
        )
    }
}

private struct WireOccasion: Codable {
    var i: String
    var n: String
    var k: String
    var nt: String?
    var c: Int
    var u: Int
    var d: Bool?
    var m: [WirePerson]
    var e: [WireExpense]

    init(_ occasion: BackupOccasion) {
        i = CompactID.encode(occasion.id)
        n = occasion.name
        k = occasion.groupType
        nt = occasion.note.isEmpty ? nil : occasion.note
        c = Int(occasion.createdAt.timeIntervalSince1970)
        u = Int(occasion.updatedAt.timeIntervalSince1970)
        d = occasion.isDeleted ? true : nil
        m = occasion.members.map(WirePerson.init)
        e = occasion.expenses.map(WireExpense.init)
    }

    func asOccasion() -> BackupOccasion {
        BackupOccasion(
            id: CompactID.decode(i) ?? UUID(),
            name: n,
            note: nt ?? "",
            createdAt: Date(timeIntervalSince1970: TimeInterval(c)),
            updatedAt: Date(timeIntervalSince1970: TimeInterval(u)),
            isDeleted: d ?? false,
            groupType: k,
            members: m.map { $0.asPerson() },
            expenses: e.map { $0.asExpense() }
        )
    }
}

private struct WirePerson: Codable {
    var i: String
    var n: String
    var e: String?
    var p: String?

    init(_ person: BackupPerson) {
        i = CompactID.encode(person.id)
        n = person.name
        e = person.email.isEmpty ? nil : person.email
        p = person.phone.isEmpty ? nil : person.phone
    }

    func asPerson() -> BackupPerson {
        BackupPerson(
            id: CompactID.decode(i) ?? UUID(),
            name: n,
            email: e ?? "",
            phone: p ?? ""
        )
    }
}

private struct WireExpense: Codable {
    var i: String
    var t: String
    var a: String
    var d: Int
    var m: String
    var p: String?
    var n: [String]
    var s: [WirePart]?

    init(_ expense: BackupExpense) {
        i = CompactID.encode(expense.id)
        t = expense.title
        a = expense.amount
        d = Int(expense.date.timeIntervalSince1970)
        m = expense.splitMethodRaw
        p = expense.paidByID.map(CompactID.encode)
        n = expense.participantIDs.map(CompactID.encode)
        s = expense.shares.isEmpty ? nil : expense.shares.map(WirePart.init)
    }

    func asExpense() -> BackupExpense {
        BackupExpense(
            id: CompactID.decode(i) ?? UUID(),
            title: t,
            amount: a,
            date: Date(timeIntervalSince1970: TimeInterval(d)),
            splitMethodRaw: m,
            paidByID: p.flatMap(CompactID.decode),
            participantIDs: n.compactMap(CompactID.decode),
            shares: (s ?? []).compactMap { $0.asShare() }
        )
    }
}

private struct WirePart: Codable {
    var i: String
    var v: String

    init(_ share: BackupShare) {
        i = CompactID.encode(share.personID)
        v = share.value
    }

    func asShare() -> BackupShare? {
        guard let personID = CompactID.decode(i) else { return nil }
        return BackupShare(personID: personID, value: v)
    }
}

private enum CompactID {
    static func encode(_ id: UUID) -> String {
        id.uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    }

    static func decode(_ raw: String) -> UUID? {
        if let id = UUID(uuidString: raw) { return id }
        let hex = raw.filter { $0.isHexDigit }
        guard hex.count == 32 else { return nil }
        let s = hex
        let dashed = "\(s.prefix(8))-\(s.dropFirst(8).prefix(4))-\(s.dropFirst(12).prefix(4))-\(s.dropFirst(16).prefix(4))-\(s.dropFirst(20).prefix(12))"
        return UUID(uuidString: dashed)
    }
}
