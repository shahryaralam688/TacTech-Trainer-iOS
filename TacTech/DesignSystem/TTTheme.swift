import SwiftUI

// MARK: - TacTech Design System
//
// Single source of truth for color, type, space, radius, shadow, icons,
// buttons, inputs, motion, and neumorphism. Screens must use these tokens.

// MARK: Purple palette (brand)

enum TTPurple {
    static let p100 = Color(hex: 0x29074F)
    static let p90 = Color(hex: 0x511A97)
    static let p80 = Color(hex: 0x8621EB)
    static let p70 = Color(hex: 0x9338FA)
    static let p60 = Color(hex: 0x9B42FA)
    static let p50 = Color(hex: 0xB069FF)
    static let p40 = Color(hex: 0xC491FF)
    static let p30 = Color(hex: 0xDDB8FF)
    static let p20 = Color(hex: 0xEFD1FF)
    static let p10 = Color(hex: 0xF9EBFF)
}

enum TTColor {
    // Surfaces
    static let canvas = Color("Canvas")
    static let surface = Color("Surface")
    static let surfaceAlt = Color("SurfaceAlt")
    static let header = TTPurple.p100
    static let headerWell = Color(white: 0.22)

    // Ink
    static let ink = Color("Ink")
    static let inkMuted = Color("InkMuted")
    static let inkSubtle = Color("InkSubtle")
    static let inkOnDark = Color.white
    static let inkOnDarkMuted = Color.white.opacity(0.72)
    static let dateOnDark = Color.white.opacity(0.55)
    static let line = Color("Line")

    // Brand — purple primary
    static let brand = Color("Brand")
    static let brandSoft = Color("BrandSoft")
    static let brandDark = TTPurple.p90
    static let brandLight = TTPurple.p70

    // Fitness / energy accent (secondary — workout metrics, highlights)
    static let energy = Color("Energy")
    static let energySoft = Color(red: 1, green: 0.94, blue: 0.88)
    static let energyBorder = Color(red: 253 / 255, green: 186 / 255, blue: 116 / 255)

    /// Primary interactive accent — maps to brand purple.
    static let accent = TTPurple.p80
    static let accentSoft = TTPurple.p10
    static let accentBorder = TTPurple.p40

    // Semantic
    static let success = Color("Success")
    static let danger = Color("Danger")
    static let dangerSoft = Color(red: 1, green: 0.92, blue: 0.93)
    static let info = Color(red: 37 / 255, green: 99 / 255, blue: 235 / 255)
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

    // Neumorphism pair
    static let neuLight = Color.white.opacity(0.85)
    static let neuDark = Color.black.opacity(0.10)
}

// MARK: Spacing (4pt grid)

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

// MARK: Corner radius

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
    static let button: CGFloat = 18
    static let buttonHero: CGFloat = 28
}

// MARK: Icons

enum TTIconSize {
    static let caption: CGFloat = 12
    static let body: CGFloat = 16
    static let control: CGFloat = 18
    static let nav: CGFloat = 22
    static let hero: CGFloat = 28
}

// MARK: Typography — Work Sans (StrangeHello / Google Fonts scale)

/// Named text styles from the design-system typography page.
enum TTTypography {
    // Display
    case displayLGExtraBold, displayLGBold
    case displayMDExtraBold, displayMDBold
    case displaySMExtraBold, displaySMBold

    // Heading
    case heading2XLBold, heading2XLSemiBold, heading2XLMedium
    case headingXLBold, headingXLSemiBold, headingXLMedium
    case headingLGBold, headingLGSemiBold, headingLGMedium
    case headingMDBold, headingMDSemiBold, headingMDMedium
    case headingSMBold, headingSMSemiBold, headingSMMedium
    case headingXSBold, headingXSSemiBold, headingXSMedium

    // Text
    case text2XLBold, text2XLSemiBold, text2XLMedium
    case textXLBold, textXLSemiBold, textXLMedium
    case textLGBold, textLGSemiBold, textLGMedium
    case textMDBold, textMDSemiBold, textMDMedium
    case textSMBold, textSMSemiBold, textSMMedium
    case textXSBold, textXSSemiBold, textXSMedium
    case text2XSBold, text2XSSemiBold, text2XSMedium

    // Paragraph
    case paragraphBold, paragraphMedium, paragraphRegular
    case paragraphLight, paragraphCaption, paragraphOverline

    var size: CGFloat {
        switch self {
        case .displayLGExtraBold, .displayLGBold: 72
        case .displayMDExtraBold, .displayMDBold: 60
        case .displaySMExtraBold, .displaySMBold: 48
        case .heading2XLBold, .heading2XLSemiBold, .heading2XLMedium: 40
        case .headingXLBold, .headingXLSemiBold, .headingXLMedium: 32
        case .headingLGBold, .headingLGSemiBold, .headingLGMedium: 28
        case .headingMDBold, .headingMDSemiBold, .headingMDMedium: 24
        case .headingSMBold, .headingSMSemiBold, .headingSMMedium: 20
        case .headingXSBold, .headingXSSemiBold, .headingXSMedium: 18
        case .text2XLBold, .text2XLSemiBold, .text2XLMedium: 20
        case .textXLBold, .textXLSemiBold, .textXLMedium: 18
        case .textLGBold, .textLGSemiBold, .textLGMedium: 16
        case .textMDBold, .textMDSemiBold, .textMDMedium: 14
        case .textSMBold, .textSMSemiBold, .textSMMedium: 12
        case .textXSBold, .textXSSemiBold, .textXSMedium: 11
        case .text2XSBold, .text2XSSemiBold, .text2XSMedium: 10
        case .paragraphBold: 28
        case .paragraphMedium: 24
        case .paragraphRegular: 20
        case .paragraphLight: 16
        case .paragraphCaption: 14
        case .paragraphOverline: 12
        }
    }

    var weight: Font.Weight {
        switch self {
        case .displayLGExtraBold, .displayMDExtraBold, .displaySMExtraBold,
             .heading2XLBold, .headingXLBold, .headingLGBold, .headingMDBold,
             .headingSMBold, .headingXSBold,
             .text2XLBold, .textXLBold, .textLGBold, .textMDBold, .textSMBold,
             .textXSBold, .text2XSBold,
             .displayLGBold, .displayMDBold, .displaySMBold,
             .paragraphBold:
            return .bold
        case .heading2XLSemiBold, .headingXLSemiBold, .headingLGSemiBold,
             .headingMDSemiBold, .headingSMSemiBold, .headingXSSemiBold,
             .text2XLSemiBold, .textXLSemiBold, .textLGSemiBold, .textMDSemiBold,
             .textSMSemiBold, .textXSSemiBold, .text2XSSemiBold,
             .paragraphOverline:
            return .semibold
        case .heading2XLMedium, .headingXLMedium, .headingLGMedium, .headingMDMedium,
             .headingSMMedium, .headingXSMedium,
             .text2XLMedium, .textXLMedium, .textLGMedium, .textMDMedium,
             .textSMMedium, .textXSMedium, .text2XSMedium,
             .paragraphMedium:
            return .medium
        case .paragraphLight:
            return .light
        case .paragraphRegular, .paragraphCaption:
            return .regular
        }
    }

    /// Line-height percentage from the typography spec (e.g. 100 = 100%).
    var lineHeightPercent: CGFloat {
        switch self {
        case .paragraphBold: 100
        case .paragraphMedium: 90
        case .paragraphRegular: 80
        case .paragraphLight: 70
        case .paragraphCaption: 60
        case .paragraphOverline: 50
        default: 120
        }
    }

    var tracking: CGFloat {
        switch self {
        case .paragraphOverline: 0.8
        default: 0
        }
    }

    var isUppercase: Bool {
        self == .paragraphOverline
    }

    var font: Font { TTFont.workSans(size, weight: weight) }

    var lineSpacing: CGFloat {
        TTFont.lineSpacing(size: size, lineHeightPercent: lineHeightPercent)
    }
}

enum TTFont {
    private static let regular = "WorkSans-Regular"
    private static let bold = "WorkSans-Bold"

    /// Maps semantic weight to bundled Work Sans files.
    static func workSans(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        switch weight {
        case .bold, .semibold, .heavy, .black:
            return .custom(bold, size: size)
        default:
            return .custom(regular, size: size)
        }
    }

    static func lineSpacing(size: CGFloat, lineHeightPercent: CGFloat) -> CGFloat {
        let defaultMultiplier: CGFloat = 1.2
        let target = size * (lineHeightPercent / 100)
        return target - size * defaultMultiplier
    }

    // Display
    static func displayLG(_ weight: Font.Weight = .bold) -> Font { workSans(72, weight: weight) }
    static func displayMD(_ weight: Font.Weight = .bold) -> Font { workSans(60, weight: weight) }
    static func displaySM(_ weight: Font.Weight = .bold) -> Font { workSans(48, weight: weight) }

    // Heading
    static func heading2XL(_ weight: Font.Weight = .bold) -> Font { workSans(40, weight: weight) }
    static func headingXL(_ weight: Font.Weight = .bold) -> Font { workSans(32, weight: weight) }
    static func headingLG(_ weight: Font.Weight = .bold) -> Font { workSans(28, weight: weight) }
    static func headingMD(_ weight: Font.Weight = .semibold) -> Font { workSans(24, weight: weight) }
    static func headingSM(_ weight: Font.Weight = .semibold) -> Font { workSans(20, weight: weight) }
    static func headingXS(_ weight: Font.Weight = .semibold) -> Font { workSans(18, weight: weight) }

    // Text
    static func text2XL(_ weight: Font.Weight = .regular) -> Font { workSans(20, weight: weight) }
    static func textXL(_ weight: Font.Weight = .regular) -> Font { workSans(18, weight: weight) }
    static func textLG(_ weight: Font.Weight = .regular) -> Font { workSans(16, weight: weight) }
    static func textMD(_ weight: Font.Weight = .regular) -> Font { workSans(14, weight: weight) }
    static func textSM(_ weight: Font.Weight = .medium) -> Font { workSans(12, weight: weight) }
    static func textXS(_ weight: Font.Weight = .medium) -> Font { workSans(11, weight: weight) }
    static func text2XS(_ weight: Font.Weight = .medium) -> Font { workSans(10, weight: weight) }

    // Paragraph scale
    static let paragraphBold = workSans(28, weight: .bold)
    static let paragraphMedium = workSans(24, weight: .medium)
    static let paragraphRegular = workSans(20, weight: .regular)
    static let paragraphLight = workSans(16, weight: .light)
    static let paragraphCaption = workSans(14, weight: .regular)
    static let paragraphOverline = workSans(12, weight: .semibold)

    // Semantic aliases (backward compatible)
    static func display(_ size: CGFloat = 48) -> Font { workSans(size, weight: .bold) }
    static func title(_ size: CGFloat = 20) -> Font { workSans(size, weight: .semibold) }
    static func heading(_ size: CGFloat = 18) -> Font { workSans(size, weight: .semibold) }
    static func body(_ size: CGFloat = 16) -> Font { workSans(size, weight: .regular) }
    static func caption(_ size: CGFloat = 12) -> Font { workSans(size, weight: .medium) }
    static func overline(_ size: CGFloat = 12) -> Font { workSans(size, weight: .semibold) }
}

// MARK: Shadows

enum TTShadow {
    static let card = Color.black.opacity(0.06)
    static let lifted = Color.black.opacity(0.12)
    static let brand = TTColor.brand.opacity(0.35)

    static let cardRadius: CGFloat = 10
    static let cardY: CGFloat = 4
    static let buttonRadius: CGFloat = 16
    static let buttonY: CGFloat = 8
}

// MARK: Motion

enum TTMotion {
    static let press: Double = 0.16
    static let panel: Double = 0.25
    static let page: Double = 0.28

    /// Airbnb-style search overlay springs (present / chrome / accordion only).
    static let searchPresent = Animation.spring(response: 0.42, dampingFraction: 0.92)
    static let searchChrome = Animation.spring(response: 0.36, dampingFraction: 0.94)
    static let searchMorph = Animation.spring(response: 0.32, dampingFraction: 0.92)
    static let searchResults = Animation.easeOut(duration: 0.15)
    static let searchDebounceNs: UInt64 = 220_000_000
}

// MARK: Button tokens

enum TTButtonSize {
    case xs, sm, md, lg, xl, xxl

    var height: CGFloat {
        switch self {
        case .xs: 36
        case .sm: 44
        case .md: 54
        case .lg: 58
        case .xl: 62
        case .xxl: 68
        }
    }

    var fontSize: CGFloat {
        switch self {
        case .xs: 12
        case .sm: 14
        case .md: 16
        case .lg: 17
        case .xl: 18
        case .xxl: 20
        }
    }

    var iconSize: CGFloat {
        switch self {
        case .xs: 12
        case .sm: 14
        case .md: 16
        case .lg: 16
        case .xl: 18
        case .xxl: 20
        }
    }

    var horizontalPadding: CGFloat {
        switch self {
        case .xs: 12
        case .sm: 14
        case .md: 18
        case .lg: 20
        case .xl: 22
        case .xxl: 24
        }
    }

    var cornerRadius: CGFloat {
        switch self {
        case .xs, .sm: TTRadius.sm
        case .md: TTRadius.button
        case .lg, .xl: TTRadius.buttonHero
        case .xxl: TTRadius.xxl
        }
    }
}

enum TTButtonVariant {
    /// Solid brand purple, white label.
    case solidBrand
    /// Soft purple tint, dark purple label.
    case softBrand
    /// White surface, dark border and label.
    case outlineNeutral
    /// Solid red, white label.
    case solidDanger
    /// Muted neutral fill, muted label.
    case subtleNeutral
    /// White fill, dark label — for dark hero backgrounds.
    case solidSurface
    /// Transparent with white border — for dark hero backgrounds.
    case outlineOnDark
    /// Dark ink fill — legacy auth CTA.
    case solidInk

    var foreground: Color {
        switch self {
        case .solidBrand, .solidDanger, .solidInk, .outlineOnDark:
            return TTColor.inkOnDark
        case .softBrand:
            return TTColor.brandDark
        case .outlineNeutral, .subtleNeutral, .solidSurface:
            return TTColor.ink
        }
    }

    var background: Color {
        switch self {
        case .solidBrand: return TTColor.brand
        case .softBrand: return TTColor.brandSoft
        case .outlineNeutral, .outlineOnDark: return .clear
        case .solidDanger: return TTColor.danger
        case .subtleNeutral: return TTColor.surfaceAlt
        case .solidSurface: return TTColor.surface
        case .solidInk: return TTColor.ink
        }
    }

    var border: Color {
        switch self {
        case .outlineNeutral: return TTColor.line
        case .outlineOnDark: return TTColor.inkOnDark.opacity(0.55)
        default: return .clear
        }
    }

    var borderWidth: CGFloat {
        switch self {
        case .outlineNeutral, .outlineOnDark: return 1
        default: return 0
        }
    }

    /// Subtle/muted variant foreground override.
    func mutedForeground(_ isMuted: Bool) -> Color {
        guard isMuted else { return foreground }
        switch self {
        case .solidBrand, .solidDanger, .solidInk: return TTColor.inkMuted
        case .softBrand: return TTColor.brandLight
        case .outlineNeutral, .subtleNeutral, .solidSurface, .outlineOnDark:
            return TTColor.inkMuted
        }
    }

    func mutedBackground(_ isMuted: Bool) -> Color {
        guard isMuted else { return background }
        switch self {
        case .solidBrand, .solidDanger, .solidInk:
            return TTColor.surfaceAlt
        case .softBrand:
            return TTColor.canvas
        default:
            return background
        }
    }
}

// MARK: Neumorphism

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
    static let pressedScale: CGFloat = 0.98
}

// MARK: View modifiers

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

    func ttNeuPressed(_ isPressed: Bool, radius: CGFloat = TTRadius.md) -> some View {
        let lightX: CGFloat = isPressed ? TTNeu.offset / 2 : -TTNeu.offset
        let lightY: CGFloat = isPressed ? TTNeu.offset / 2 : -TTNeu.offset
        let darkX: CGFloat = isPressed ? -TTNeu.offset / 2 : TTNeu.offset
        let darkY: CGFloat = isPressed ? -TTNeu.offset / 2 : TTNeu.offset
        let lightColor = isPressed ? TTNeu.dark.opacity(0.04) : TTNeu.light
        let darkColor = isPressed ? TTNeu.light.opacity(0.04) : TTNeu.dark

        return self
            .scaleEffect(isPressed ? TTNeu.pressedScale : 1)
            .shadow(color: lightColor, radius: TTNeu.radius, x: lightX, y: lightY)
            .shadow(color: darkColor, radius: TTNeu.radius, x: darkX, y: darkY)
            .animation(.easeOut(duration: TTMotion.press), value: isPressed)
    }

    func ttScreenBackground() -> some View {
        background(TTColor.canvas.ignoresSafeArea())
    }

    func ttPressable(_ isPressed: Bool) -> some View {
        self
            .scaleEffect(isPressed ? TTNeu.pressedScale : 1)
            .animation(.easeOut(duration: TTMotion.press), value: isPressed)
    }

    /// Apply a named Work Sans style from the design-system typography scale.
    func ttTypography(_ style: TTTypography) -> some View {
        font(style.font)
            .tracking(style.tracking)
            .lineSpacing(style.lineSpacing)
            .textCase(style.isUppercase ? .uppercase : nil)
    }
}

struct TTPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .ttPressable(configuration.isPressed)
    }
}

// MARK: Color hex helper

extension Color {
    init(hex: UInt, alpha: Double = 1) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}
