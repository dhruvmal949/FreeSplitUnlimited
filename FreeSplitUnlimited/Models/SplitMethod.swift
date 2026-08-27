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

    var detail: String {
        switch self {
        case .equal: return "Everyone selected pays the same."
        case .percentage: return "Percentages must add up to 100%."
        case .parts: return "Example: 1 and 2 parts = 1/3 and 2/3."
        }
    }
}
