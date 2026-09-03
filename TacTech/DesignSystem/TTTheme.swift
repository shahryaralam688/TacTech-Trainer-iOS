import SwiftUI

// MARK: - TacTech Design System
//
// Single source of truth for color, type, space, radius, shadow, icons,
// motion, and neumorphism. Screens must use these tokens — not one-off hex.

enum TTColor {
    // Surfaces
    static let canvas = Color("Canvas")
    static let surface = Color("Surface")
    static let surfaceAlt = Color("SurfaceAlt")
    static let header = Color.black
    static let headerWell = Color(white: 0.22)

    // Ink
    static let ink = Color("Ink")
    static let inkMuted = Color("InkMuted")
    static let inkSubtle = Color("InkSubtle")
    static let inkOnDark = Color.white
    static let inkOnDarkMuted = Color.white.opacity(0.72)
    static let dateOnDark = Color.white.opacity(0.55)
    static let line = Color("Line")

    // Brand — orange is the interactive accent used on Home / Figma.
    static let brand = Color("Brand")
    static let brandSoft = Color("BrandSoft")
    static let accent = Color(red: 249 / 255, green: 115 / 255, blue: 22 / 255) // #F97316
    static let accentSoft = Color(red: 255 / 255, green: 240 / 255, blue: 224 / 255)
    static let accentBorder = Color(red: 253 / 255, green: 186 / 255, blue: 116 / 255)
    static let energy = Color("Energy")

    // Semantic
    static let success = Color("Success")
    static let danger = Color("Danger")
    static let info = Color(red: 37 / 255, green: 99 / 255, blue: 235 / 255) // #2563EB
    static let infoSoft = Color(red: 219 / 255, green: 234 / 255, blue: 254 / 255)

    // Nutrition
    static let protein = Color("Protein")
    static let carbs = Color("Carbs")
    static let fat = Color("Fat")
    static let calorie = Color("Calorie")
    static let sleep = Color("Sleep")
    static let heart = Color("Heart")

    // Splash / hero
    static let splash = Color("SplashBackground")

    // Neumorphism pair — highlight + well on canvas.
    static let neuLight = Color.white.opacity(0.85)
    static let neuDark = Color.black.opacity(0.10)
}

enum TTSpace {
    static let xxs: CGFloat = 4
    static let xs: CGFloat = 8
    static let sm: CGFloat = 12
    static let md: CGFloat = 16
    static let lg: CGFloat = 20
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
    static let xxxl: CGFloat = 40

    static let screen: CGFloat = 20
    static let fieldHeight: CGFloat = 54
    static let buttonHeight: CGFloat = 56
    static let heroButtonHeight: CGFloat = 58
}

enum TTRadius {
    static let xs: CGFloat = 8
    static let sm: CGFloat = 12
    static let md: CGFloat = 16
    static let lg: CGFloat = 22
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 28
    static let header: CGFloat = 56
    static let avatar: CGFloat = 16
    static let pill: CGFloat = 100
}

enum TTIconSize {
    static let caption: CGFloat = 12
    static let body: CGFloat = 16
    static let control: CGFloat = 18
    static let nav: CGFloat = 22
    static let hero: CGFloat = 28
}

enum TTFont {
    static func display(_ size: CGFloat = 34) -> Font {
        .system(size: size, weight: .bold, design: .default)
    }

    static func title(_ size: CGFloat = 22) -> Font {
        .system(size: size, weight: .semibold, design: .default)
    }

    static func heading(_ size: CGFloat = 17) -> Font {
        .system(size: size, weight: .semibold, design: .default)
    }

    static func body(_ size: CGFloat = 16) -> Font {
        .system(size: size, weight: .regular, design: .default)
    }

    static func caption(_ size: CGFloat = 13) -> Font {
        .system(size: size, weight: .medium, design: .default)
    }

    static func overline(_ size: CGFloat = 12) -> Font {
        .system(size: size, weight: .semibold, design: .default)
    }
}

enum TTShadow {
    static let card = Color.black.opacity(0.06)
    static let lifted = Color.black.opacity(0.12)
    static let brand = TTColor.accent.opacity(0.35)

    static let cardRadius: CGFloat = 10
    static let cardY: CGFloat = 4
}

enum TTMotion {
    static let press: Double = 0.16
    static let panel: Double = 0.25
}

/// Neumorphism rules:
/// 1. Only on `TTColor.canvas` / `surfaceAlt` — never on pure white or photos.
/// 2. Soft dual shadow (light + dark), no hard drop shadow.
/// 3. Fill stays close to the parent surface so the extrusion is subtle.
/// 4. Prefer for icon wells, chips, and compact cards — not full-bleed heroes.
enum TTNeu {
    static let light = Color.white.opacity(0.70)
    static let dark = Color.black.opacity(0.08)
    static let radius: CGFloat = 8
    static let offset: CGFloat = 5
}

extension View {
    func ttCard(padding: CGFloat = TTSpace.md) -> some View {
        self
            .padding(padding)
            .background(TTColor.surface)
            .clipShape(RoundedRectangle(cornerRadius: TTRadius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: TTRadius.md, style: .continuous)
                    .stroke(TTColor.line, lineWidth: 1)
            )
            .shadow(color: TTShadow.card, radius: TTShadow.cardRadius, y: TTShadow.cardY)
    }

    func ttSoftCard(radius: CGFloat = TTRadius.xl) -> some View {
        self
            .background(TTColor.surface)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .shadow(color: TTShadow.card, radius: TTShadow.cardRadius, y: TTShadow.cardY)
    }

    func ttNeuRaised(radius: CGFloat = TTRadius.md) -> some View {
        self
            .background(TTColor.surfaceAlt)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .shadow(color: TTNeu.light, radius: TTNeu.radius, x: -TTNeu.offset, y: -TTNeu.offset)
            .shadow(color: TTNeu.dark, radius: TTNeu.radius, x: TTNeu.offset, y: TTNeu.offset)
    }

    func ttScreenBackground() -> some View {
        background(TTColor.canvas.ignoresSafeArea())
    }

    func ttPressable(_ isPressed: Bool) -> some View {
        self
            .scaleEffect(isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: TTMotion.press), value: isPressed)
    }
}

struct TTPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .ttPressable(configuration.isPressed)
    }
}
