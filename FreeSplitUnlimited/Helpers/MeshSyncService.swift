//
//  MeshSyncService.swift
//  FreeSplitUnlimited
//
//  Peer-to-peer sync: phones discover each other directly over Bluetooth / Wi-Fi
//  (no server, no internet, no AirDrop) and gossip split data. Every connected
//  phone also relays what it knows, so a change can hop from phone to phone.
//

import Foundation
import MultipeerConnectivity
import SwiftData
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// One line of a peer's "table of contents" — just enough to diff without sending full data.
private struct MeshManifestEntry: Codable {
    let id: UUID
    let updatedAt: Date
    let isDeleted: Bool
}

/// Wire format for everything exchanged between two nearby phones.
private enum MeshMessage: Codable {
    case manifest([MeshManifestEntry])
    case request([UUID])
    case occasions([BackupOccasion])
    case joinRequest(String)
    case joinMiss(String)

    private enum Kind: String, Codable { case manifest, request, occasions, joinRequest, joinMiss }
    private enum CodingKeys: String, CodingKey { case kind, payload }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .manifest:
            self = .manifest(try container.decode([MeshManifestEntry].self, forKey: .payload))
        case .request:
            self = .request(try container.decode([UUID].self, forKey: .payload))
        case .occasions:
            self = .occasions(try container.decode([BackupOccasion].self, forKey: .payload))
        case .joinRequest:
            self = .joinRequest(try container.decode(String.self, forKey: .payload))
        case .joinMiss:
            self = .joinMiss(try container.decode(String.self, forKey: .payload))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .manifest(let entries):
            try container.encode(Kind.manifest, forKey: .kind)
            try container.encode(entries, forKey: .payload)
        case .request(let ids):
            try container.encode(Kind.request, forKey: .kind)
            try container.encode(ids, forKey: .payload)
        case .occasions(let occasions):
            try container.encode(Kind.occasions, forKey: .kind)
            try container.encode(occasions, forKey: .payload)
        case .joinRequest(let code):
            try container.encode(Kind.joinRequest, forKey: .kind)
            try container.encode(code, forKey: .payload)
        case .joinMiss(let code):
            try container.encode(Kind.joinMiss, forKey: .kind)
            try container.encode(code, forKey: .payload)
        }
    }
}

@MainActor
final class MeshSyncService: NSObject, ObservableObject {
    static let shared = MeshSyncService()

    /// Bonjour service type: lowercase letters/numbers/hyphens, 1–15 chars.
    private static let serviceType = "freesplit-mesh"
    private let peerToken: String
    /// Created in `start()`, not `init()`. `MCPeerID` / radios during the first
    /// SwiftUI frame of a document-open launch can `brk`.
    private var myPeerID: MCPeerID?
    nonisolated(unsafe) private var session: MCSession?
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?

    @Published private(set) var connectedPeerCount = 0
    @Published private(set) var connectedPeerNames: [String] = []
    @Published private(set) var isRunning = false
    @Published private(set) var isConnecting = false
    @Published private(set) var lastError: String?

    var statusTitle: String {
        if connectedPeerCount > 0 {
            return connectedPeerCount == 1
                ? "1 phone nearby"
                : "\(connectedPeerCount) phones nearby"
        }
        if isConnecting {
            return "Connecting to a nearby phone"
        }
        return isRunning ? "Looking for nearby phones" : "Nearby sync off"
    }

    var statusDetail: String {
        if let lastError, connectedPeerCount == 0 {
            return lastError
        }
        if connectedPeerCount > 0 {
            let names = connectedPeerNames.joined(separator: ", ")
            if names.isEmpty {
                return "Splits sync automatically — no internet or AirDrop needed."
            }
            return "Connected to \(names). Splits sync automatically."
        }
        if isConnecting {
            return "Keep both phones unlocked with Free Split open."
        }
        return "Keep Bluetooth and Wi‑Fi on. Open Free Split on both phones."
    }

    private var context: ModelContext?
    private var restartTask: Task<Void, Never>?
    private var pendingInvites = Set<String>()
    private var connectingKeys = Set<String>()
    private var joinWaiters: [String: [CheckedContinuation<BackupOccasion?, Never>]] = [:]

    private override init() {
        self.peerToken = Self.persistedPeerToken()
        super.init()
    }

    private func prepareRadiosIfNeeded() {
        guard session == nil else { return }
        let peerID = myPeerID ?? MCPeerID(displayName: Self.persistedDisplayName())
        myPeerID = peerID
        let session = MCSession(peer: peerID, securityIdentity: nil, encryptionPreference: .optional)
        let advertiser = MCNearbyServiceAdvertiser(
            peer: peerID,
            discoveryInfo: ["app": "freesplit", "id": peerToken],
            serviceType: Self.serviceType
        )
        let browser = MCNearbyServiceBrowser(peer: peerID, serviceType: Self.serviceType)
        session.delegate = self
        advertiser.delegate = self
        browser.delegate = self
        self.session = session
        self.advertiser = advertiser
        self.browser = browser
    }

    func start(context: ModelContext) {
        self.context = context
        lastError = nil
        prepareRadiosIfNeeded()
        isRunning = true
        startDiscovery()
        ensureRestartLoop()
    }

    /// Call when the app returns to the foreground so radios start advertising again.
    func resume() {
        guard context != nil else { return }
        prepareRadiosIfNeeded()
        isRunning = true
        startDiscovery()
        ensureRestartLoop()
    }

    func stop() {
        restartTask?.cancel()
        restartTask = nil
        isRunning = false
        isConnecting = false
        lastError = nil
        advertiser?.stopAdvertisingPeer()
        browser?.stopBrowsingForPeers()
        session?.disconnect()
        pendingInvites.removeAll()
        connectingKeys.removeAll()
        refreshPeerState()
    }

    /// Re-advertise/browse and push current splits to anyone already connected.
    func restartDiscovery() {
        lastError = nil
        let idle = (session?.connectedPeers.isEmpty ?? true) && connectingKeys.isEmpty
        if idle {
            pendingInvites.removeAll()
            bounceDiscovery()
        } else {
            startDiscovery()
        }
        broadcastLocalChanges()
    }

    /// Call after any local save so already-connected peers get the update immediately,
    /// without waiting for the next manifest exchange.
    func broadcastLocalChanges() {
        guard let session, !session.connectedPeers.isEmpty, let context else { return }
        let occasions = (try? context.fetch(FetchDescriptor<Occasion>())) ?? []
        guard !occasions.isEmpty else { return }
        for occasion in occasions {
            JoinCode.assignIfNeeded(to: occasion, in: context)
        }
        let backups = occasions.map(SplitBackup.exportOccasion)
        send(.occasions(backups), to: session.connectedPeers)
    }

    /// Ask nearby phones for the group with this join code.
    func fetchByJoinCode(_ raw: String) async -> BackupOccasion? {
        let code = JoinCode.normalize(raw)
        guard !code.isEmpty else { return nil }
        guard let session, !session.connectedPeers.isEmpty else { return nil }

        return await withCheckedContinuation { continuation in
            joinWaiters[code, default: []].append(continuation)
            send(.joinRequest(code), to: session.connectedPeers)
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(10))
                self.finishJoinWait(code, with: nil)
            }
        }
    }

    private func finishJoinWait(_ code: String, with backup: BackupOccasion?) {
        let waiters = joinWaiters.removeValue(forKey: code) ?? []
        for waiter in waiters {
            waiter.resume(returning: backup)
        }
    }

    // MARK: Discovery

    private func startDiscovery() {
        prepareRadiosIfNeeded()
        advertiser?.startAdvertisingPeer()
        browser?.startBrowsingForPeers()
    }

    /// Stop/start radios only when nothing is mid-handshake. Bouncing while
    /// `.connecting` cancels the invite and the phones never pair.
    private func bounceDiscovery() {
        guard isRunning else { return }
        advertiser?.stopAdvertisingPeer()
        browser?.stopBrowsingForPeers()
        startDiscovery()
    }

    private func ensureRestartLoop() {
        guard restartTask == nil else { return }
        restartTask = Task { @MainActor in
            var ticks = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(8))
                guard !Task.isCancelled, self.isRunning else { return }
                ticks += 1
                let idle = (self.session?.connectedPeers.isEmpty ?? true)
                    && self.connectingKeys.isEmpty
                guard idle else { continue }
                if ticks % 6 == 0 {
                    self.pendingInvites.removeAll()
                    self.bounceDiscovery()
                } else {
                    self.startDiscovery()
                }
            }
        }
    }

    private func handleFoundPeer(_ peerID: MCPeerID, info: [String: String]?) {
        let key = peerID.displayName
        guard session?.connectedPeers.contains(peerID) == false else { return }
        guard pendingInvites.contains(key) == false else { return }
        guard shouldInvite(peerID, info: info) else { return }

        pendingInvites.insert(key)
        connectingKeys.insert(key)
        isConnecting = true
        lastError = nil
        guard let session else {
            pendingInvites.remove(key)
            connectingKeys.remove(key)
            isConnecting = !connectingKeys.isEmpty
            return
        }
        browser?.invitePeer(peerID, to: session, withContext: nil, timeout: 45)
    }

    /// Exactly one phone must invite. Comparing a UUID token to "iPhone" made
    /// both sides skip, so two phones never connected.
    private func shouldInvite(_ peerID: MCPeerID, info: [String: String]?) -> Bool {
        if let theirToken = info?["id"], !theirToken.isEmpty {
            return peerToken > theirToken
        }
        let myName = myPeerID?.displayName ?? ""
        if myName != peerID.displayName {
            return myName > peerID.displayName
        }
        return true
    }

    private func refreshPeerState() {
        connectedPeerCount = session?.connectedPeers.count ?? 0
        connectedPeerNames = session?.connectedPeers.map(\.displayName) ?? []
        isConnecting = !connectingKeys.isEmpty && connectedPeerCount == 0
    }

    // MARK: Messaging

    private func send(_ message: MeshMessage, to peers: [MCPeerID]) {
        guard let session, !peers.isEmpty else { return }
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(message)
            try session.send(data, toPeers: peers, with: .reliable)
        } catch {
            print("Mesh send failed: \(error)")
        }
    }

    private func sendManifest(to peer: MCPeerID) {
        guard let context else { return }
        let occasions = (try? context.fetch(FetchDescriptor<Occasion>())) ?? []
        for occasion in occasions {
            JoinCode.assignIfNeeded(to: occasion, in: context)
        }
        let entries = occasions.map {
            MeshManifestEntry(id: $0.id, updatedAt: $0.updatedAt, isDeleted: $0.isDeleted)
        }
        send(.manifest(entries), to: [peer])
    }

    private func handle(_ message: MeshMessage, from peer: MCPeerID) {
        guard let context else { return }

        switch message {
        case .manifest(let peerEntries):
            let localOccasions = (try? context.fetch(FetchDescriptor<Occasion>())) ?? []
            var localByID: [UUID: Occasion] = [:]
            for occasion in localOccasions where localByID[occasion.id] == nil {
                localByID[occasion.id] = occasion
            }

            var idsWeNeed: [UUID] = []
            for entry in peerEntries {
                if let local = localByID[entry.id] {
                    if entry.updatedAt > local.updatedAt {
                        idsWeNeed.append(entry.id)
                    }
                } else {
                    idsWeNeed.append(entry.id)
                }
            }
            if !idsWeNeed.isEmpty {
                send(.request(idsWeNeed), to: [peer])
            }

            var peerByID: [UUID: MeshManifestEntry] = [:]
            for entry in peerEntries where peerByID[entry.id] == nil {
                peerByID[entry.id] = entry
            }
            let toSend = localOccasions.filter { occasion in
                guard let peerEntry = peerByID[occasion.id] else { return true }
                return occasion.updatedAt > peerEntry.updatedAt
            }
            if !toSend.isEmpty {
                send(.occasions(toSend.map(SplitBackup.exportOccasion)), to: [peer])
            }

        case .request(let ids):
            let localOccasions = (try? context.fetch(FetchDescriptor<Occasion>())) ?? []
            let matches = localOccasions.filter { ids.contains($0.id) }
            guard !matches.isEmpty else { return }
            send(.occasions(matches.map(SplitBackup.exportOccasion)), to: [peer])

        case .occasions(let backups):
            var appliedIDs: [UUID] = []
            for backup in backups {
                if let updated = try? SplitBackup.upsert(backup, into: context) {
                    appliedIDs.append(updated.id)
                }
                let code = JoinCode.normalize(backup.joinCode)
                if !code.isEmpty {
                    finishJoinWait(code, with: backup)
                }
            }
            if !appliedIDs.isEmpty {
                NotificationCenter.default.post(name: .freeSplitDidImport, object: appliedIDs.first)
                let otherPeers = session?.connectedPeers.filter { $0 != peer } ?? []
                if !otherPeers.isEmpty {
                    send(.occasions(backups), to: otherPeers)
                }
            }

        case .joinRequest(let raw):
            let code = JoinCode.normalize(raw)
            let localOccasions = (try? context.fetch(FetchDescriptor<Occasion>())) ?? []
            if let match = localOccasions.first(where: {
                !$0.isDeleted && JoinCode.normalize($0.joinCode) == code
            }) {
                send(.occasions([SplitBackup.exportOccasion(match)]), to: [peer])
            } else {
                send(.joinMiss(code), to: [peer])
            }

        case .joinMiss(let raw):
            // Only give up early when nobody nearby has the group. If another
            // peer still might answer, the 10s timeout covers it.
            if (session?.connectedPeers.count ?? 0) <= 1 {
                finishJoinWait(JoinCode.normalize(raw), with: nil)
            }
        }
    }

    private static func persistedDisplayName() -> String {
        let key = "freeSplit.mesh.displayName"
        if let saved = UserDefaults.standard.string(forKey: key), !saved.isEmpty {
            return String(saved.prefix(63))
        }
        // Do not read `UIDevice.current.name` here — it can block the main
        // thread at launch and the system then SIGKILLs the process.
        let suffix = String(persistedPeerToken().prefix(4))
        let name = String("FreeSplit \(suffix)".prefix(63))
        UserDefaults.standard.set(name, forKey: key)
        return name
    }

    private static func persistedPeerToken() -> String {
        let key = "freeSplit.mesh.peerToken"
        if let saved = UserDefaults.standard.string(forKey: key), !saved.isEmpty {
            return saved
        }
        let token = UUID().uuidString
        UserDefaults.standard.set(token, forKey: key)
        return token
    }
}

// MARK: - MCSessionDelegate

extension MeshSyncService: MCSessionDelegate {
    nonisolated func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        Task { @MainActor in
            switch state {
            case .connected:
                self.pendingInvites.remove(peerID.displayName)
                self.connectingKeys.remove(peerID.displayName)
                self.lastError = nil
                self.refreshPeerState()
                self.sendManifest(to: peerID)
            case .connecting:
                self.connectingKeys.insert(peerID.displayName)
                self.refreshPeerState()
            case .notConnected:
                self.pendingInvites.remove(peerID.displayName)
                self.connectingKeys.remove(peerID.displayName)
                self.refreshPeerState()
            @unknown default:
                self.refreshPeerState()
            }
        }
    }

    nonisolated func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let message = try? decoder.decode(MeshMessage.self, from: data) else { return }
        Task { @MainActor in
            self.handle(message, from: peerID)
        }
    }

    nonisolated func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    nonisolated func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    nonisolated func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}

// MARK: - MCNearbyServiceAdvertiserDelegate

extension MeshSyncService: MCNearbyServiceAdvertiserDelegate {
    nonisolated func advertiser(
        _ advertiser: MCNearbyServiceAdvertiser,
        didReceiveInvitationFromPeer peerID: MCPeerID,
        withContext context: Data?,
        invitationHandler: @escaping (Bool, MCSession?) -> Void
    ) {
        // Accept immediately on this callback thread. Hopping to MainActor first
        // is a common reason Multipeer invitations expire before they connect.
        let session = self.session
        invitationHandler(session != nil, session)
    }

    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        print("Mesh advertising failed: \(error.localizedDescription)")
        Task { @MainActor in
            self.lastError = "Couldn't start nearby sync. Allow Local Network for Free Split in iPhone Settings."
            try? await Task.sleep(for: .seconds(3))
            guard self.isRunning else { return }
            self.startDiscovery()
        }
    }
}

// MARK: - MCNearbyServiceBrowserDelegate

extension MeshSyncService: MCNearbyServiceBrowserDelegate {
    nonisolated func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        Task { @MainActor in
            self.handleFoundPeer(peerID, info: info)
        }
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        Task { @MainActor in
            self.pendingInvites.remove(peerID.displayName)
            self.connectingKeys.remove(peerID.displayName)
            self.refreshPeerState()
        }
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        print("Mesh browsing failed: \(error.localizedDescription)")
        Task { @MainActor in
            self.lastError = "Couldn't find nearby phones. Allow Local Network for Free Split in iPhone Settings."
            try? await Task.sleep(for: .seconds(3))
            guard self.isRunning else { return }
            self.startDiscovery()
        }
    }
}

// MARK: - Nearby status UI

struct NearbySyncBanner: View {
    @ObservedObject var mesh: MeshSyncService
    var onSync: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: mesh.connectedPeerCount > 0
                      ? "dot.radiowaves.left.and.right"
                      : "antenna.radiowaves.left.and.right")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(AppTheme.teal)
                    .symbolEffect(.variableColor.iterative, isActive: mesh.connectedPeerCount == 0 && mesh.isRunning)

                VStack(alignment: .leading, spacing: 2) {
                    Text(mesh.statusTitle)
                        .font(.subheadline.weight(.semibold))
                    Text(mesh.statusDetail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)
            }

            Button(action: onSync) {
                Text(mesh.connectedPeerCount > 0 ? "Sync with Nearby Phones" : "Find Nearby Phones")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .tint(AppTheme.teal)
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
