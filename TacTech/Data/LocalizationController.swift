import Foundation
import Observation
import SwiftUI

/// In-app language override — Airbnb / WhatsApp style (no iOS Settings restart required).
@MainActor
@Observable
final class LocalizationController {
    static let shared = LocalizationController()

    static let languageCodeKey = "settings.languageCode"
    static let languageLabelKey = "settings.language"
    /// Kept for migration only — bilingual toggle removed in v1.
    static let bilingualKey = "settings.bilingual"

    private(set) var language: AppLanguage

    var locale: Locale { language.locale }
    var layoutDirection: LayoutDirection { language.layoutDirection }
    var languageCode: String { language.rawValue }
    var languageLabel: String { language.displayNameNative }

    /// Bumps when language changes so root can `.id(revision)` and rebuild cleanly.
    private(set) var revision: Int = 0

    private init() {
        let stored = UserDefaults.standard.string(forKey: Self.languageCodeKey)
        language = AppLanguage.migrate(fromLegacy: stored)
        persistLabelOnly()
    }

    /// Apply a language immediately (UI + persistence). Soft-sync to server when logged in.
    func setLanguage(_ next: AppLanguage, syncRemote: Bool = true) {
        guard next != language else {
            persist()
            return
        }
        language = next
        revision += 1
        persist()
        if syncRemote {
            Task { await syncToServer(language: next) }
        }
    }

    /// Login / session restore — apply server preference if valid.
    func applyServerLanguageCode(_ code: String?) {
        guard let code, let lang = AppLanguage.match(bcp47: code) ?? AppLanguage(rawValue: code) else { return }
        // Valid allowed codes only.
        guard AppLanguage.allCases.contains(lang) else { return }
        setLanguage(lang, syncRemote: false)
    }

    func localized(_ key: String.LocalizationValue, comment: StaticString = "") -> String {
        String(localized: key, locale: locale, comment: comment)
    }

    /// Convenience for dynamic keys already registered in the String Catalog.
    func localized(_ key: String, comment: StaticString = "") -> String {
        String(localized: String.LocalizationValue(key), locale: locale, comment: comment)
    }

    // MARK: - Persist

    private func persist() {
        let d = UserDefaults.standard
        d.set(language.rawValue, forKey: Self.languageCodeKey)
        d.set(language.displayNameNative, forKey: Self.languageLabelKey)
        // Help UIKit formatters / some system lookups follow app language.
        d.set([language.rawValue], forKey: "AppleLanguages")
    }

    private func persistLabelOnly() {
        let d = UserDefaults.standard
        d.set(language.rawValue, forKey: Self.languageCodeKey)
        d.set(language.displayNameNative, forKey: Self.languageLabelKey)
    }

    // MARK: - Server

    private func syncToServer(language: AppLanguage) async {
        guard TokenStore.accessToken() != nil else { return }
        do {
            _ = try await NotificationAPI().putLanguagePreference(
                LanguagePreferenceDTO(languageCode: language.rawValue, bilingual: false)
            )
        } catch {
            // Soft-fail — local wins until next successful sync.
            #if DEBUG
            print("[TacTech] language preference PUT failed: \(error.localizedDescription)")
            #endif
        }
    }

    func pullFromServer() async {
        guard TokenStore.accessToken() != nil else { return }
        do {
            let dto = try await NotificationAPI().getLanguagePreference()
            applyServerLanguageCode(dto.languageCode)
        } catch {
            #if DEBUG
            print("[TacTech] language preference GET failed: \(error.localizedDescription)")
            #endif
        }
    }
}

// MARK: - SwiftUI root injection

struct LocalizationRootModifier: ViewModifier {
    @Bindable var localization: LocalizationController

    func body(content: Content) -> some View {
        content
            .environment(\.locale, localization.locale)
            .environment(\.layoutDirection, localization.layoutDirection)
            .environment(localization)
            .id(localization.revision)
    }
}

extension View {
    func ttAppLocalization(_ controller: LocalizationController = .shared) -> some View {
        modifier(LocalizationRootModifier(localization: controller))
    }
}
