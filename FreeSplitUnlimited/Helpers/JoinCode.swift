//
//  JoinCode.swift
//  FreeSplitUnlimited
//
//  Short codes like TRIP-4K so a friend can join a group without AirDrop.
//

import Foundation
import SwiftData

enum JoinCode {
    private static let alphabet = Array("23456789ABCDEFGHJKLMNPQRSTUVWXYZ")

    static func normalize(_ raw: String) -> String {
        raw
            .uppercased()
            .filter { $0.isLetter || $0.isNumber || $0 == "-" }
    }

    static func make(kind: GroupKind, name: String, taken: Set<String>) -> String {
        let prefix = prefix(for: kind, name: name)
        for _ in 0..<48 {
            let code = "\(prefix)-\(suffix())"
            if !taken.contains(code) { return code }
        }
        return "\(prefix)-\(String(UUID().uuidString.prefix(2)).uppercased())"
    }

    static func takenCodes(in context: ModelContext) -> Set<String> {
        let occasions = (try? context.fetch(FetchDescriptor<Occasion>())) ?? []
        return Set(occasions.map(\.joinCode).filter { !$0.isEmpty })
    }

    static func assignIfNeeded(to occasion: Occasion, in context: ModelContext) {
        let current = normalize(occasion.joinCode)
        if !current.isEmpty {
            if occasion.joinCode != current {
                occasion.joinCode = current
            }
            return
        }
        occasion.joinCode = make(kind: occasion.kind, name: occasion.name, taken: takenCodes(in: context))
    }

    static func find(code raw: String, in context: ModelContext) -> Occasion? {
        let code = normalize(raw)
        guard !code.isEmpty else { return nil }
        let occasions = (try? context.fetch(FetchDescriptor<Occasion>())) ?? []
        return occasions.first { !$0.isDeleted && normalize($0.joinCode) == code }
    }

    private static func prefix(for kind: GroupKind, name: String) -> String {
        switch kind {
        case .trip: return "TRIP"
        case .home: return "HOME"
        case .party: return "PRTY"
        case .other:
            let letters = name.uppercased().filter(\.isLetter)
            if letters.count >= 4 { return String(letters.prefix(4)) }
            return "SPLT"
        }
    }

    private static func suffix() -> String {
        String((0..<2).map { _ in alphabet.randomElement()! })
    }
}
