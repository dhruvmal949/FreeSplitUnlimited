//
//  MeshSyncService.swift
//  FreeSplitUnlimited
//
//  Bitchat-style peer-to-peer sync: phones discover each other directly over
//  Bluetooth / Wi-Fi (no server, no internet needed) and gossip split data.
//  Every connected phone also relays what it knows to the next phone it meets,
//  so a change can hop from phone to phone without any two "ends" ever
//  connecting directly — the same store-and-forward idea Bitchat uses for chat.
//

import Foundation
import MultipeerConnectivity
import SwiftData
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

    private enum Kind: String, Codable { case manifest, request, occasions }
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
        }
    }
}

@MainActor
final class MeshSyncService: NSObject, ObservableObject {
    static let shared = MeshSyncService()

    /// Bonjour service type: lowercase letters/numbers/hyphens, 1–15 chars.
    private let serviceType = "freesplit-mesh"

    @Published private(set) var connectedPeerCount = 0

    private var context: ModelContext?
    private let myPeerID: MCPeerID
    /// Optional encryption is more reliable offline over Bluetooth than `.required`.
    private lazy var session: MCSession = {
        let session = MCSession(peer: myPeerID, securityIdentity: nil, encryptionPreference: .optional)
        session.delegate = self
        return session
    }()
    private lazy var advertiser = MCNearbyServiceAdvertiser(
        peer: myPeerID,
        discoveryInfo: ["app": "freesplit"],
        serviceType: serviceType
    )
    private lazy var browser = MCNearbyServiceBrowser(peer: myPeerID, serviceType: serviceType)
    private var restartTask: Task<Void, Never>?

    private override init() {
        let name = Self.persistedDisplayName()
        self.myPeerID = MCPeerID(displayName: name)
        super.init()
        advertiser.delegate = self
        browser.delegate = self
    }

    func start(context: ModelContext) {
        self.context = context
        advertiser.startAdvertisingPeer()
        browser.startBrowsingForPeers()

        // Multipeer discovery can stall when radios sleep; gently restart browse/advertise.
        restartTask?.cancel()
        restartTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(45))
                guard !Task.isCancelled else { return }
                if self.session.connectedPeers.isEmpty {
                    self.browser.stopBrowsingForPeers()
                    self.advertiser.stopAdvertisingPeer()
                    self.advertiser.startAdvertisingPeer()
                    self.browser.startBrowsingForPeers()
                }
            }
        }
    }

    func stop() {
        restartTask?.cancel()
        restartTask = nil
        advertiser.stopAdvertisingPeer()
        browser.stopBrowsingForPeers()
        session.disconnect()
    }

    /// Call after any local save so already-connected peers get the update immediately,
    /// without waiting for the next manifest exchange.
    func broadcastLocalChanges() {
        guard !session.connectedPeers.isEmpty, let context else { return }
        let occasions = (try? context.fetch(FetchDescriptor<Occasion>())) ?? []
        guard !occasions.isEmpty else { return }
        let backups = occasions.map(SplitBackup.exportOccasion)
        send(.occasions(backups), to: session.connectedPeers)
    }

    // MARK: Messaging

    private func send(_ message: MeshMessage, to peers: [MCPeerID]) {
        guard !peers.isEmpty else { return }
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
            let localByID = Dictionary(uniqueKeysWithValues: localOccasions.map { ($0.id, $0) })

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

            let peerByID = Dictionary(uniqueKeysWithValues: peerEntries.map { ($0.id, $0) })
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
            }
            guard !appliedIDs.isEmpty else { return }

            NotificationCenter.default.post(name: .freeSplitDidImport, object: appliedIDs.first)

            // Relay to every other connected peer so the change keeps hopping (mesh flood).
            let otherPeers = session.connectedPeers.filter { $0 != peer }
            if !otherPeers.isEmpty {
                send(.occasions(backups), to: otherPeers)
            }
        }
    }

    private static func persistedDisplayName() -> String {
        let key = "freeSplit.mesh.displayName"
        if let saved = UserDefaults.standard.string(forKey: key) {
            return saved
        }
        #if canImport(UIKit)
        let base = UIDevice.current.name
        #else
        let base = "Free Split User"
        #endif
        let name = String(base.prefix(60))
        UserDefaults.standard.set(name, forKey: key)
        return name
    }
}

// MARK: - MCSessionDelegate

extension MeshSyncService: MCSessionDelegate {
    nonisolated func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        Task { @MainActor in
            self.connectedPeerCount = session.connectedPeers.count
            if state == .connected {
                self.sendManifest(to: peerID)
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
        Task { @MainActor in
            invitationHandler(true, self.session)
        }
    }

    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        print("Mesh advertising failed: \(error.localizedDescription)")
    }
}

// MARK: - MCNearbyServiceBrowserDelegate

extension MeshSyncService: MCNearbyServiceBrowserDelegate {
    nonisolated func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        Task { @MainActor in
            guard self.session.connectedPeers.contains(peerID) == false else { return }
            // Skip inviting ourselves / same display name loops when testing two sims is impossible;
            // on two real devices, different phone names keep this safe.
            browser.invitePeer(peerID, to: self.session, withContext: nil, timeout: 20)
        }
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {}

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        print("Mesh browsing failed: \(error.localizedDescription)")
    }
}
