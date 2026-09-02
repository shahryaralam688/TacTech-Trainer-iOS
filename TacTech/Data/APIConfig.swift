import Foundation

enum APIConfig {
    static let baseURL = URL(string: "https://sheryl-biocellate-sympathizingly.ngrok-free.dev")!
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
}
