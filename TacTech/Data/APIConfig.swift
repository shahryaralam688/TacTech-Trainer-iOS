import Foundation

enum APIConfig {
    // static let baseURL = URL(string: "https://sheryl-biocellate-sympathizingly.ngrok-free.dev")!

    /// Neutral placeholder used when no local address is configured. It works on the iOS Simulator when the backend
    /// runs on the same Mac. A real device needs the Mac's address: see "Local backend address" below.
    static let fallbackBaseURL = URL(string: "http://localhost:8000")!

    /// The backend address. The first of these that is set wins:
    ///
    /// Local backend address (never committed):
    ///  1. Environment variable `TACTECH_API_BASE_URL`. Xcode: Product > Scheme > Manage Schemes, duplicate the scheme,
    ///     UNTICK "Shared" (so it stays in git-ignored xcuserdata), then Edit Scheme > Run > Arguments > Environment
    ///     Variables. Works on a device and in the Simulator.
    ///  2. The `TACTECH_API_BASE_URL` user default (for example the launch argument `-TACTECH_API_BASE_URL http://host:8000`).
    ///  3. Simulator only: the first line of `LocalConfig/api-base-url.txt` in the project folder (git-ignored).
    ///  4. `fallbackBaseURL`.
    ///
    /// TODO(release task): limit 1 to 3 to DEBUG builds before shipping. They are not limited yet so that today's
    /// Release-configuration runs keep working with a local address.
    static let baseURL: URL = resolveBaseURL()

    static let skipBrowserWarningHeader = "ngrok-skip-browser-warning"
    static let skipBrowserWarningValue = "true"

    static func dateQuery(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    // MARK: - Local address lookup

    private static let overrideKey = "TACTECH_API_BASE_URL"

    private static func resolveBaseURL(sourceFile: String = #filePath) -> URL {
        if let value = ProcessInfo.processInfo.environment[overrideKey], let url = validURL(value) { return url }
        if let value = UserDefaults.standard.string(forKey: overrideKey), let url = validURL(value) { return url }
        #if targetEnvironment(simulator)
        // The Simulator can read the Mac's files. `#filePath` is this file's path at build time:
        // <project>/TacTech/Data/APIConfig.swift, so the project folder is three levels up.
        let projectFolder = URL(fileURLWithPath: sourceFile)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let file = projectFolder.appendingPathComponent("LocalConfig/api-base-url.txt")
        if let text = try? String(contentsOf: file, encoding: .utf8),
           let line = text.split(whereSeparator: \.isNewline).first,
           let url = validURL(String(line)) {
            return url
        }
        #endif
        return fallbackBaseURL
    }

    private static func validURL(_ raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              url.host != nil else { return nil }
        return url
    }
}
