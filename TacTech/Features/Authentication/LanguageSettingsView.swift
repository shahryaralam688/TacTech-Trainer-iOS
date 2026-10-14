import SwiftUI
import UIKit

/// In-app language picker — 6 BCP-47 locales, immediate apply + RTL for Arabic.
struct LanguageSettingsView: View {
    @Environment(LocalizationController.self) private var localization
    @Environment(\.dismiss) private var dismiss

    @State private var toast: TTToastMessage?

    private let canvas = Color(red: 248 / 255, green: 249 / 255, blue: 250 / 255)
    private let cardFill = Color(red: 243 / 255, green: 244 / 255, blue: 246 / 255)
    private let orange = TTColor.actionOrange

    private var languages: [AppLanguage] { AppLanguage.settingsOrder }

    var body: some View {
        VStack(spacing: 0) {
            TTModalSheetHeader(
                title: String(localized: "language.title", locale: localization.locale),
                background: canvas
            )

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    section(String(localized: "language.selected", locale: localization.locale)) {
                        selectedLanguageCard(localization.language)
                    }

                    section(String(localized: "language.all", locale: localization.locale)) {
                        ForEach(languages.filter { $0 != localization.language }) { lang in
                            languageRow(lang) {
                                select(lang)
                            }
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 18)
                .padding(.bottom, 36)
            }
        }
        .background(canvas.ignoresSafeArea())
        .ttHideSystemNavigationBar()
        .ttToast($toast, bottomInset: 28)
    }

    // MARK: - Sections

    private func section<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title)
                    .font(TTFont.workSans(17, weight: .bold))
                    .foregroundStyle(TTColor.ink)
                Spacer()
                TTIcon(icon: .kebab, size: 16)
                    .foregroundStyle(TTColor.inkMuted)
                    .accessibilityHidden(true)
            }

            VStack(spacing: 10) {
                content()
            }
        }
    }

    private func selectedLanguageCard(_ lang: AppLanguage) -> some View {
        HStack(spacing: 12) {
            iconTile(tint: orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(lang.displayNameNative)
                    .font(TTFont.workSans(15, weight: .bold))
                    .foregroundStyle(.white)
                Text(lang.displayNameEnglish)
                    .font(TTFont.caption(12))
                    .foregroundStyle(.white.opacity(0.85))
            }
            Spacer(minLength: 8)
            ZStack {
                Circle()
                    .fill(.white)
                    .frame(width: 28, height: 28)
                TTIcon(icon: .check, filled: true, size: 12)
                    .foregroundStyle(orange)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .background(orange)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: orange.opacity(0.25), radius: 10, y: 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(lang.displayNameNative), \(lang.displayNameEnglish)")
        .accessibilityAddTraits(.isSelected)
    }

    private func languageRow(_ lang: AppLanguage, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                iconTile(tint: TTColor.ink)
                VStack(alignment: .leading, spacing: 2) {
                    Text(lang.displayNameNative)
                        .font(TTFont.workSans(15, weight: .semibold))
                        .foregroundStyle(TTColor.ink)
                    Text(lang.displayNameEnglish)
                        .font(TTFont.caption(12))
                        .foregroundStyle(TTColor.inkMuted)
                }
                Spacer(minLength: 8)
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color(white: 0.78), lineWidth: 1.5)
                    .frame(width: 26, height: 26)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(cardFill)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: .black.opacity(0.03), radius: 6, y: 2)
        }
        .buttonStyle(TTSearchPressStyle(scale: 0.99))
        .accessibilityLabel("\(lang.displayNameNative), \(lang.displayNameEnglish)")
    }

    private func iconTile(tint: Color) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white)
            TTIcon(icon: .flag1, size: 18)
                .foregroundStyle(tint)
        }
        .frame(width: 40, height: 40)
        .shadow(color: .black.opacity(0.04), radius: 4, y: 1)
    }

    private func select(_ lang: AppLanguage) {
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        localization.setLanguage(lang, syncRemote: true)
        toast = TTToastMessage(
            text: String(localized: "common.language_updated", locale: localization.locale),
            style: .success
        )
        NotificationStore.shared.playNotificationHaptic(.success)
    }
}

#Preview("Language Settings") {
    NavigationStack {
        LanguageSettingsView()
            .environment(LocalizationController.shared)
    }
}
