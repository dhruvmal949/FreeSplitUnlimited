//
//  CloudSyncService.swift
//  FreeSplitUnlimited
//
//  CloudKit is disabled. This file must not import CloudKit — loading
//  CKContainer.default() without iCloud entitlements traps with brk #0x1.
//

import Foundation
import SwiftData

@MainActor
final class CloudSyncService {
    static let shared = CloudSyncService()
    private init() {}

    func refreshAvailability() async {}
    func push(_ occasion: Occasion) async {}
    func pushAll(_ occasions: [Occasion]) async {}
    func pull(ids: [UUID], into context: ModelContext) async {}
}
