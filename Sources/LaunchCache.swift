import UIKit

/// Launch snapshots, like iOS keeps for apps: the first complete screen of each prototype,
/// shown the instant it's reopened and cross-faded to the live page once that's ready.
/// Keyed by host + path, stored as JPEG in Caches (the system may purge it; that's fine).
enum LaunchCache {
    private static let dir: URL = {
        let d = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("launch", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()
    /// Decoded snapshots are full-screen bitmaps (~15 MB at @3x): keep only a few in memory,
    /// and let iOS drop them under pressure (the JPEGs on disk stay).
    private static let memory: NSCache<NSString, UIImage> = {
        let c = NSCache<NSString, UIImage>()
        c.totalCostLimit = 60 * 1024 * 1024
        return c
    }()
    private static func cost(_ img: UIImage) -> Int { Int(img.size.width * img.size.height * img.scale * img.scale * 4) }

    private static func key(_ url: URL, size: CGSize) -> String {
        let raw = "\(url.host ?? "")\(url.path)@\(Int(size.width))x\(Int(size.height))"
        return raw.replacingOccurrences(of: "[^A-Za-z0-9@._-]", with: "_", options: .regularExpression)
    }

    static func image(for url: URL, size: CGSize) -> UIImage? {
        let k = key(url, size: size)
        if let m = memory.object(forKey: k as NSString) { return m }
        guard let data = try? Data(contentsOf: dir.appendingPathComponent(k + ".jpg")),
              let img = UIImage(data: data, scale: UIScreen.main.scale) else { return nil }
        memory.setObject(img, forKey: k as NSString, cost: cost(img))
        return img
    }

    static func store(_ image: UIImage, for url: URL, size: CGSize) {
        let k = key(url, size: size)
        memory.setObject(image, forKey: k as NSString, cost: cost(image))
        DispatchQueue.global(qos: .utility).async {
            if let data = image.jpegData(compressionQuality: 0.82) {
                try? data.write(to: dir.appendingPathComponent(k + ".jpg"), options: .atomic)
            }
        }
    }
}
