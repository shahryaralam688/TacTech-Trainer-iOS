import SwiftUI

/// Sandow Language settings — light canvas, shared `TTBackButton`, Sandow flag icons.
struct LanguageSettingsView: View {
    @Environment(\.dismiss) private var dismiss

    @AppStorage("settings.language") private var languageLabel = "Japanese (JP)"
    @AppStorage("settings.languageCode") private var languageCode = "jp"
    @AppStorage("settings.bilingual") private var bilingualEnabled = true

    @State private var selected = "jp"
    @State private var bilingual = true

    private let canvas = Color(red: 248 / 255, green: 249 / 255, blue: 250 / 255)
    private let cardFill = Color(red: 243 / 255, green: 244 / 255, blue: 246 / 255)
    private let orange = TTColor.actionOrange

    private let languages: [(id: String, title: String)] = [
        ("jp", "Japanese (JP)"),
        ("us", "American (US)"),
        ("uk", "English (UK)"),
        ("it", "Italian (IT)"),
        ("ar", "Arabic (AR)"),
        ("cn", "Chinese (CN)"),
        ("ru", "Russian (RU)")
    ]

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    section("Selected Language") {
                        if let current = languages.first(where: { $0.id == selected }) {
                            selectedLanguageCard(current.title)
                        }
                    }

                    section("Bilingual Feature") {
                        bilingualRow
                    }

                    section("All Languages") {
                        ForEach(languages.filter { $0.id != selected }, id: \.id) { lang in
                            languageRow(lang.title) {
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
        .onAppear(perform: hydrate)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 14) {
            TTBackButton(style: .onLight) { dismiss() }

            Text("Language")
                .font(TTFont.workSans(20, weight: .bold))
                .foregroundStyle(TTColor.ink)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .background(canvas)
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

    // MARK: - Rows

    private func selectedLanguageCard(_ title: String) -> some View {
        HStack(spacing: 12) {
            iconTile(tint: orange)
            Text(title)
                .font(TTFont.workSans(15, weight: .bold))
                .foregroundStyle(.white)
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
    }

    private var bilingualRow: some View {
        HStack(spacing: 12) {
            iconTile(tint: TTColor.ink)
            Text("Enable Bilingual?")
                .font(TTFont.workSans(15, weight: .semibold))
                .foregroundStyle(TTColor.ink)
            Spacer(minLength: 8)
            Toggle("", isOn: $bilingual)
                .labelsHidden()
                .tint(orange)
                .onChange(of: bilingual) { _, value in
                    bilingualEnabled = value
                }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(cardFill)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.03), radius: 6, y: 2)
    }

    private func languageRow(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                iconTile(tint: TTColor.ink)
                Text(title)
                    .font(TTFont.workSans(15, weight: .semibold))
                    .foregroundStyle(TTColor.ink)
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

    // MARK: - Data

    private func select(_ lang: (id: String, title: String)) {
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        withAnimation(.easeOut(duration: 0.2)) {
            selected = lang.id
        }
        languageCode = lang.id
        languageLabel = lang.title
    }

    private func hydrate() {
        if let byCode = languages.first(where: { $0.id == languageCode }) {
            selected = byCode.id
            languageLabel = byCode.title
        } else if let byLabel = languages.first(where: { $0.title == languageLabel }) {
            selected = byLabel.id
            languageCode = byLabel.id
        } else if let legacy = languages.first(where: {
            languageLabel.localizedCaseInsensitiveContains("english") && ($0.id == "uk" || $0.id == "us")
        }) {
            // Older default was "English (EN)"
            selected = legacy.id
            languageCode = legacy.id
            languageLabel = legacy.title
        } else {
            selected = "jp"
            languageCode = "jp"
            languageLabel = "Japanese (JP)"
        }
        bilingual = bilingualEnabled
    }
}

#Preview("Language Settings") {
    NavigationStack {
        LanguageSettingsView()
    }
}
