import SwiftUI

/// Packaged avatar illustrations from Avatars_SVG_Pack.
enum TTAvatarCatalog {
    static let all: [String] = [
        "Avatar_01_Color", "Avatar_02_Color", "Avatar_03_Color", "Avatar_04_Color",
        "Avatar_05_Color", "Avatar_06_Color", "Avatar_07_Color", "Avatar_08_Color",
        "Avatar_09_Color", "Avatar_10_Color",
        "Avatar_11_Grayscale", "Avatar_12_Grayscale", "Avatar_13_Grayscale",
        "Avatar_14_Grayscale", "Avatar_15_Grayscale", "Avatar_16_Grayscale",
        "Avatar_17_Grayscale", "Avatar_18_Grayscale", "Avatar_19_Grayscale",
        "Avatar_20_Grayscale"
    ]

    static let `default` = "Avatar_01_Color"

    static func storageKey(userId: String) -> String {
        "profile.avatar.\(userId)"
    }

    static func saved(for userId: String?) -> String? {
        guard let userId else { return nil }
        return UserDefaults.standard.string(forKey: storageKey(userId: userId))
    }

    static func save(_ assetName: String, for userId: String?) {
        guard let userId else { return }
        UserDefaults.standard.set(assetName, forKey: storageKey(userId: userId))
    }

    static func isAssetName(_ value: String) -> Bool {
        value.hasPrefix("Avatar_")
    }
}

/// Renders a catalog avatar asset or falls back to initials / SF Symbol.
struct TTAvatarImage: View {
    var assetName: String?
    var systemName: String? = nil
    var initials: String = "?"
    var size: CGFloat = 120

    var body: some View {
        Group {
            if let assetName, TTAvatarCatalog.isAssetName(assetName) {
                Image(assetName)
                    .resizable()
                    .scaledToFill()
            } else if let systemName {
                Image(systemName: systemName)
                    .font(.system(size: size * 0.38, weight: .semibold))
                    .foregroundStyle(Color(white: 0.35))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(white: 0.94))
            } else {
                Text(initials.uppercased())
                    .font(TTFont.workSans(size * 0.36, weight: .bold))
                    .foregroundStyle(Color(white: 0.35))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(white: 0.94))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
    }
}

/// Shared “Choose your avatar” step — used by assessment + profile completion.
struct AssessmentAvatarStep: View {
    @Binding var selection: String
    var title: String = "Choose your avatar"
    var subtitle: String = "Pick a look that feels like you — you can change it later."

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 4)

    var body: some View {
        VStack(spacing: 0) {
            Text(title)
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(TTColor.ink)
                .multilineTextAlignment(.center)
                .padding(.top, 12)
                .padding(.horizontal, 24)

            Text(subtitle)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color(white: 0.45))
                .multilineTextAlignment(.center)
                .padding(.top, 8)
                .padding(.horizontal, 28)

            TTAvatarImage(assetName: selection, size: 128)
                .padding(.top, 28)
                .shadow(color: .black.opacity(0.08), radius: 12, y: 6)

            ScrollView(showsIndicators: false) {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(TTAvatarCatalog.all, id: \.self) { name in
                        Button {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                selection = name
                            }
                        } label: {
                            Image(name)
                                .resizable()
                                .scaledToFill()
                                .frame(maxWidth: .infinity)
                                .frame(height: 72)
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .strokeBorder(
                                            selection == name ? TTColor.actionOrange : Color.clear,
                                            lineWidth: 3
                                        )
                                )
                                .opacity(selection == name ? 1 : 0.92)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 20)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear {
            if selection.isEmpty || !TTAvatarCatalog.isAssetName(selection) {
                selection = TTAvatarCatalog.default
            }
        }
    }
}

#Preview("Avatar Step") {
    struct Demo: View {
        @State private var selection = TTAvatarCatalog.default
        var body: some View {
            AssessmentAvatarStep(selection: $selection)
                .background(Color.white)
        }
    }
    return Demo()
}
