import Foundation
import CryptoKit

/// Disk cache for CDN Mixamo FBX clips under `Caches/Form3D/`.
enum FormStudioClipCache {
    private static let folderName = "Form3D"

    private static var cacheDirectory: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent(folderName, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Public cache root for `appcontent://cache/…` scheme serving.
    static var directory: URL { cacheDirectory }

    /// Returns a local file URL for `animationUrl`, downloading when missing or URL hash changed.
    static func cachedFile(clipId: String, animationUrl: URL) async throws -> URL {
        let safeClip = sanitize(clipId)
        let hash = shortHash(animationUrl.absoluteString)
        let filename = "\(safeClip)_\(hash).fbx"
        let dest = cacheDirectory.appendingPathComponent(filename)

        if FileManager.default.fileExists(atPath: dest.path) {
            return dest
        }

        // Drop older hashes for this clipId so cache does not grow unbounded.
        removeStaleFiles(prefix: "\(safeClip)_", keeping: filename)

        let (tempURL, response) = try await URLSession.shared.download(from: animationUrl)
        if let http = response as? HTTPURLResponse, !(200 ... 299).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }

        if FileManager.default.fileExists(atPath: dest.path) {
            try? FileManager.default.removeItem(at: dest)
        }
        try FileManager.default.moveItem(at: tempURL, to: dest)
        return dest
    }

    static func appContentURL(forLocalFile fileURL: URL) -> URL? {
        var components = URLComponents()
        components.scheme = FormStudioLocalSchemeHandler.scheme
        components.host = FormStudioLocalSchemeHandler.cacheHost
        components.path = "/" + fileURL.lastPathComponent
        return components.url
    }

    // MARK: - Helpers

    private static func sanitize(_ clipId: String) -> String {
        let trimmed = clipId.trimmingCharacters(in: .whitespacesAndNewlines)
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-"))
        let scalars = trimmed.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" }
        let value = String(scalars)
        return value.isEmpty ? "clip" : value
    }

    private static func shortHash(_ value: String) -> String {
        let digest = SHA256.hash(data: Data(value.utf8))
        return digest.prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    private static func removeStaleFiles(prefix: String, keeping keepName: String) {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: nil) else { return }
        for url in items where url.lastPathComponent.hasPrefix(prefix) && url.lastPathComponent != keepName {
            try? fm.removeItem(at: url)
        }
    }
}
