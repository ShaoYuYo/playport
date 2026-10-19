// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import UIKit

/// A shared, evictable decoded-art budget for all stores. The previous
/// dictionaries retained every cover visited for the life of the app.
/// Disk originals remain available, so eviction needs no new download.
@MainActor
final class ArtworkMemoryCache {
    static let shared = ArtworkMemoryCache()
    private let images = NSCache<NSString, UIImage>()
    private init() {
        images.totalCostLimit = 24 << 20
        images.countLimit = 48
    }
    subscript(key: String) -> UIImage? {
        get { images.object(forKey: key as NSString) }
        set {
            guard let image = newValue else { images.removeObject(forKey: key as NSString); return }
            // Estimate decoded RGBA cost without forcing a decode on the UI
            // thread. NSCache may purge sooner when iOS needs the memory.
            let pixels = image.size.width * image.size.height * image.scale * image.scale
            let cost = pixels.isFinite ? Int(min(CGFloat(64 << 20), max(0, pixels))) * 4 : 24 << 20
            images.setObject(image, forKey: key as NSString, cost: cost)
        }
    }
    func release() { images.removeAllObjects() }
}
