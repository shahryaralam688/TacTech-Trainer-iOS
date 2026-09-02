import SwiftUI

enum TTColor {
    static let canvas = Color("Canvas")
    static let surface = Color("Surface")
    static let surfaceAlt = Color("SurfaceAlt")
    static let ink = Color("Ink")
    static let inkMuted = Color("InkMuted")
    static let inkSubtle = Color("InkSubtle")
    static let line = Color("Line")
    static let brand = Color("Brand")
    static let brandSoft = Color("BrandSoft")
    static let energy = Color("Energy")
    static let success = Color("Success")
    static let danger = Color("Danger")
    static let protein = Color("Protein")
    static let carbs = Color("Carbs")
    static let fat = Color("Fat")
    static let calorie = Color("Calorie")
    static let sleep = Color("Sleep")
    static let heart = Color("Heart")
}

enum TTSpace {
    static let xxs: CGFloat = 4
    static let xs: CGFloat = 8
    static let sm: CGFloat = 12
    static let md: CGFloat = 16
    static let lg: CGFloat = 20
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
}

enum TTRadius {
    static let sm: CGFloat = 10
    static let md: CGFloat = 16
    static let lg: CGFloat = 22
    static let pill: CGFloat = 100
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
    }

    func ttScreenBackground() -> some View {
        self.background(TTColor.canvas.ignoresSafeArea())
    }
}
