import ImageIO
import SwiftUI
import UIKit

// MARK: - Remote image cache (memory + disk)

/// Shared URL image cache for avatars — keyed by full URL string (versioned URLs bust cache).
actor TTRemoteImageCache {
    static let shared = TTRemoteImageCache()

    private let memory = NSCache<NSString, UIImage>()
    /// Display-sized versions (decoded once, off the main thread), keyed by URL + pixel bucket.
    private let thumbMemory = NSCache<NSString, UIImage>()
    private static let thumbBuckets = [64, 96, 128, 192, 256, 384]
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.urlCache = URLCache(
            memoryCapacity: 8 * 1024 * 1024,
            diskCapacity: 40 * 1024 * 1024,
            diskPath: "TTRemoteImageURLCache"
        )
        config.requestCachePolicy = .returnCacheDataElseLoad
        return URLSession(configuration: config)
    }()

    private var diskDirectory: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("AvatarURL", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func diskURL(for urlString: String) -> URL {
        let name = urlString.data(using: .utf8).map {
            $0.base64EncodedString()
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "+", with: "-")
        } ?? "avatar"
        let truncated = String(name.prefix(180))
        return diskDirectory.appendingPathComponent("\(truncated).jpg")
    }

    func cachedImage(for urlString: String) -> UIImage? {
        let key = urlString as NSString
        if let hit = memory.object(forKey: key) { return hit }
        let file = diskURL(for: urlString)
        guard let data = try? Data(contentsOf: file), let image = UIImage(data: data) else {
            return nil
        }
        memory.setObject(image, forKey: key)
        return image
    }

    func store(_ image: UIImage, for urlString: String) {
        guard !urlString.isEmpty else { return }
        removeThumbnails(for: urlString) // a new original invalidates the small versions
        memory.setObject(image, forKey: urlString as NSString)
        if let data = image.jpegData(compressionQuality: 0.9) {
            try? data.write(to: diskURL(for: urlString), options: .atomic)
        }
    }

    func remove(for urlString: String?) {
        guard let urlString, !urlString.isEmpty else { return }
        removeThumbnails(for: urlString)
        memory.removeObject(forKey: urlString as NSString)
        try? FileManager.default.removeItem(at: diskURL(for: urlString))
    }

    // MARK: Display-sized thumbnails

    /// Smallest bucket that is at least ~2× the shown point size (so avatars share a few small versions).
    nonisolated static func thumbnailBucket(forPoints points: CGFloat) -> Int {
        let pixels = Int((points * 2).rounded(.up))
        return thumbBuckets.first(where: { $0 >= pixels }) ?? (thumbBuckets.last ?? 384)
    }

    private func thumbDiskURL(for urlString: String, maxPixel: Int) -> URL {
        let original = diskURL(for: urlString)
        let base = original.deletingPathExtension().lastPathComponent
        return diskDirectory.appendingPathComponent("\(base)@\(maxPixel).jpg")
    }

    private func removeThumbnails(for urlString: String) {
        for bucket in Self.thumbBuckets {
            thumbMemory.removeObject(forKey: "\(urlString)|\(bucket)" as NSString)
            try? FileManager.default.removeItem(at: thumbDiskURL(for: urlString, maxPixel: bucket))
        }
    }

    /// Decodes a small, ready-to-draw image. Runs on this actor (never the main thread); `ShouldCacheImmediately`
    /// means the pixels are decoded here, not lazily on the first draw.
    private nonisolated static func makeThumbnail(from data: Data, maxPixel: Int) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    /// The avatar at display size. Order: memory → small file on disk → shrink the cached original once
    /// (then cache the small version) → download the original (only if `allowDownload`).
    func thumbnail(for urlString: String, maxPixel: Int, allowDownload: Bool) async -> UIImage? {
        let key = "\(urlString)|\(maxPixel)" as NSString
        if let hit = thumbMemory.object(forKey: key) { return hit }

        let smallFile = thumbDiskURL(for: urlString, maxPixel: maxPixel)
        if let data = try? Data(contentsOf: smallFile), let image = Self.makeThumbnail(from: data, maxPixel: maxPixel) {
            thumbMemory.setObject(image, forKey: key)
            return image
        }

        var originalData = try? Data(contentsOf: diskURL(for: urlString))
        if originalData == nil, allowDownload, await image(for: urlString) != nil {
            originalData = try? Data(contentsOf: diskURL(for: urlString))
        }
        guard let originalData, let small = Self.makeThumbnail(from: originalData, maxPixel: maxPixel) else { return nil }
        thumbMemory.setObject(small, forKey: key)
        if let jpeg = small.jpegData(compressionQuality: 0.85) {
            try? jpeg.write(to: smallFile, options: .atomic)
        }
        return small
    }

    /// Returns memory/disk hit immediately path; otherwise downloads once.
    func image(for urlString: String) async -> UIImage? {
        if let hit = cachedImage(for: urlString) { return hit }
        guard let url = URL(string: urlString), url.scheme == "http" || url.scheme == "https" else {
            return nil
        }
        do {
            let (data, response) = try await session.data(from: url)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                return nil
            }
            guard let image = UIImage(data: data) else { return nil }
            store(image, for: urlString)
            return image
        } catch {
            return cachedImage(for: urlString)
        }
    }
}

// MARK: - Shared user avatar

enum TTUserAvatarShape {
    case roundedRect
    case circle
}

/// Single display path for the logged-in user’s avatar.
/// Precedence: `avatarUrl` → catalog `avatarAsset` → optional local custom cache → initials.
struct TTUserAvatarView: View {
    var avatarUrl: String?
    var avatarAsset: String?
    var userId: String? = nil
    var name: String = ""
    var size: CGFloat = 48
    var shape: TTUserAvatarShape = .roundedRect
    var cornerRadius: CGFloat? = nil
    var strokeColor: Color? = nil
    var strokeWidth: CGFloat = 0
    var initialsForeground: Color = Color(white: 0.35)
    var initialsBackground: Color = Color(white: 0.94)

    @State private var remoteImage: UIImage?
    @State private var loadToken = 0

    private var resolvedURL: String? {
        let trimmed = avatarUrl?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmed, !trimmed.isEmpty, trimmed.lowercased().hasPrefix("http") else { return nil }
        return trimmed
    }

    private var resolvedAsset: String? {
        guard let avatarAsset, TTAvatarCatalog.isAssetName(avatarAsset) else { return nil }
        return avatarAsset
    }

    private var corner: CGFloat {
        if shape == .circle { return size / 2 }
        return cornerRadius ?? size * 0.28
    }

    private var identity: String {
        resolvedURL ?? resolvedAsset ?? "initials:\(name)"
    }

    private var initials: String {
        let parts = name.split(separator: " ")
        let letters = parts.prefix(2).compactMap { $0.first.map(String.init) }
        let joined = letters.joined()
        if !joined.isEmpty { return joined.uppercased() }
        if let first = name.first { return String(first).uppercased() }
        return "?"
    }

    var body: some View {
        Group {
            if let remoteImage {
                Image(uiImage: remoteImage)
                    .resizable()
                    .scaledToFill()
            } else if let resolvedAsset {
                Image(resolvedAsset)
                    .resizable()
                    .scaledToFill()
            } else if resolvedURL == nil,
                      TTAvatarCatalog.isCustom(avatarAsset),
                      let custom = TTAvatarCatalog.loadCustomImage(for: userId) {
                // Soft local preview only when no server URL (upload in progress / offline).
                Image(uiImage: custom)
                    .resizable()
                    .scaledToFill()
            } else {
                Text(initials)
                    .font(TTFont.workSans(size * 0.36, weight: .bold))
                    .foregroundStyle(initialsForeground)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(initialsBackground)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        .overlay {
            if let strokeColor, strokeWidth > 0 {
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .strokeBorder(strokeColor, lineWidth: strokeWidth)
            }
        }
        .id(identity)
        .task(id: resolvedURL) {
            await loadRemoteIfNeeded()
        }
        .onAppear {
            // Instant memory/disk paint before async task schedules.
            if let url = resolvedURL, remoteImage == nil {
                Task {
                    if let hit = await TTRemoteImageCache.shared.thumbnail(for: url, maxPixel: thumbBucket, allowDownload: false) {
                        await MainActor.run { remoteImage = hit }
                    }
                }
            }
        }
        .accessibilityLabel("Profile photo")
    }

    @MainActor
    private func loadRemoteIfNeeded() async {
        loadToken += 1
        let token = loadToken
        guard let url = resolvedURL else {
            remoteImage = nil
            return
        }
        let bucket = thumbBucket
        if let hit = await TTRemoteImageCache.shared.thumbnail(for: url, maxPixel: bucket, allowDownload: false) {
            remoteImage = hit
            return
        }
        // No cache → initials placeholder (not blank), then fade the small image in once.
        remoteImage = nil
        let image = await TTRemoteImageCache.shared.thumbnail(for: url, maxPixel: bucket, allowDownload: true)
        guard token == loadToken else { return }
        if let image {
            withAnimation(.easeIn(duration: 0.18)) {
                remoteImage = image
            }
        }
    }

    /// Pixel size of the small version to load: about 2× the point size.
    private var thumbBucket: Int { TTRemoteImageCache.thumbnailBucket(forPoints: size) }
}
