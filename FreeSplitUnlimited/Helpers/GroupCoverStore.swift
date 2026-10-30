//
//  GroupCoverStore.swift
//  FreeSplitUnlimited
//
//  Group photos stay out of SwiftData. Optional `Data` on a `@Model` can trap
//  with EXC_BREAKPOINT (`typeID does not match`) when the store is loaded.
//

import Foundation
import UIKit

enum GroupCoverStore {
    private static func key(_ id: UUID) -> String {
        "freeSplit.groupCover.\(id.uuidString)"
    }

    static func data(for id: UUID) -> Data? {
        guard let data = UserDefaults.standard.data(forKey: key(id)), !data.isEmpty else {
            return nil
        }
        return data
    }

    static func image(for id: UUID) -> UIImage? {
        guard let data = data(for: id) else { return nil }
        return UIImage(data: data)
    }

    static func save(_ data: Data?, for id: UUID) {
        if let data, !data.isEmpty {
            UserDefaults.standard.set(data, forKey: key(id))
        } else {
            UserDefaults.standard.removeObject(forKey: key(id))
        }
    }

    static func prepared(from image: UIImage) -> (image: UIImage, data: Data?) {
        let maxSide: CGFloat = 512
        let longest = max(image.size.width, image.size.height)
        let scale = longest > maxSide ? maxSide / longest : 1
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: size)
        let resized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        return (resized, resized.jpegData(compressionQuality: 0.72))
    }
}
