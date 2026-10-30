//
//  SplitMethod.swift
//  FreeSplitUnlimited
//

import Foundation

enum SplitMethod: String, CaseIterable, Identifiable, Codable {
    case equal
    case percentage
    case parts

    var id: String { rawValue }

    var title: String {
        switch self {
        case .equal: return "Equally"
        case .percentage: return "By %"
        case .parts: return "By Parts"
        }
    }
}
