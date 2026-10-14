import Foundation
import SwiftUI

/// Supported in-app languages (BCP-47). Source / fallback: English.
enum AppLanguage: String, CaseIterable, Identifiable, Codable, Hashable {
    case english = "en"
    case arabic = "ar"
    case chineseSimplified = "zh-Hans"
    case french = "fr"
    case hindi = "hi"
    case spanish = "es"

    var id: String { rawValue }

    var locale: Locale { Locale(identifier: rawValue) }

    var isRTL: Bool { self == .arabic }

    var layoutDirection: LayoutDirection {
        isRTL ? .rightToLeft : .leftToRight
    }

    /// English name — settings subtitles / sorting.
    var displayNameEnglish: String {
        switch self {
        case .english: "English"
        case .spanish: "Spanish"
        case .arabic: "Arabic"
        case .chineseSimplified: "Chinese (Simplified)"
        case .french: "French"
        case .hindi: "Hindi"
        }
    }

    /// Native endonym — primary label in Language Settings + Account row.
    var displayNameNative: String {
        switch self {
        case .english: "English"
        case .spanish: "Español"
        case .arabic: "العربية"
        case .chineseSimplified: "简体中文"
        case .french: "Français"
        case .hindi: "हिन्दी"
        }
    }

    /// Picker order: English first, then alphabetical by English name.
    static var settingsOrder: [AppLanguage] {
        let rest = AppLanguage.allCases
            .filter { $0 != .english }
            .sorted { $0.displayNameEnglish.localizedCaseInsensitiveCompare($1.displayNameEnglish) == .orderedAscending }
        return [.english] + rest
    }

    /// Device locale if supported, else English.
    static var deviceDefault: AppLanguage {
        let preferred = Locale.preferredLanguages
        for tag in preferred {
            if let match = match(bcp47: tag) { return match }
        }
        if let match = match(bcp47: Locale.current.identifier) { return match }
        return .english
    }

    static func match(bcp47: String) -> AppLanguage? {
        let raw = bcp47.replacingOccurrences(of: "_", with: "-")
        let lower = raw.lowercased()
        if lower == "zh-hans" || lower.hasPrefix("zh-hans") || lower == "zh-cn" || lower.hasPrefix("zh-cn") {
            return .chineseSimplified
        }
        if lower.hasPrefix("zh") {
            // Other Chinese variants → Simplified for v1.
            return .chineseSimplified
        }
        let primary = lower.split(separator: "-").first.map(String.init) ?? lower
        return AppLanguage(rawValue: primary) ?? AppLanguage(rawValue: raw)
    }

    /// Migrate legacy AppStorage codes (`jp`, `us`, `uk`, `cn`, …).
    static func migrate(fromLegacy code: String?) -> AppLanguage {
        guard let code, !code.isEmpty else { return .deviceDefault }
        let c = code.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch c {
        case "en", "us", "uk":
            return .english
        case "es":
            return .spanish
        case "ar":
            return .arabic
        case "zh-hans", "cn", "zh":
            return .chineseSimplified
        case "fr":
            return .french
        case "hi":
            return .hindi
        case "jp", "it", "ru":
            return .english
        default:
            return match(bcp47: code) ?? .english
        }
    }
}
