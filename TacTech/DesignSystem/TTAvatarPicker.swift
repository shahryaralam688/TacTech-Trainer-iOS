import SwiftUI
import UIKit

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
/// Modern picker feel: matched-geometry hero morph, spring pop, glow pulse, staggered grid.
struct AssessmentAvatarStep: View {
    @Binding var selection: String
    var title: String = "Choose your avatar"
    var subtitle: String = "Pick a look that feels like you — you can change it later."

    @Namespace private var avatarNamespace
    @State private var didAppear = false
    @State private var heroPulse = false
    @State private var swapToken = 0

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 4)
    private let orange = TTColor.actionOrange

    private var selectSpring: Animation {
        .spring(response: 0.45, dampingFraction: 0.68, blendDuration: 0.15)
    }

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

            heroPreview
                .padding(.top, 24)

            ScrollView(showsIndicators: false) {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(Array(TTAvatarCatalog.all.enumerated()), id: \.element) { index, name in
                        avatarCell(name, index: index)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 28)
                .padding(.bottom, 24)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear {
            if selection.isEmpty || !TTAvatarCatalog.isAssetName(selection) {
                selection = TTAvatarCatalog.default
            }
            withAnimation(.easeOut(duration: 0.55)) {
                didAppear = true
            }
            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
                heroPulse = true
            }
        }
        .sensoryFeedback(.selection, trigger: selection)
    }

    // MARK: - Hero

    private var heroPreview: some View {
        ZStack {
            // Soft ambient glow — trending “liquid glass” / avatar aura
            Circle()
                .fill(
                    RadialGradient(
                        colors: [orange.opacity(0.35), orange.opacity(0.08), .clear],
                        center: .center,
                        startRadius: 20,
                        endRadius: 90
                    )
                )
                .frame(width: 180, height: 180)
                .scaleEffect(heroPulse ? 1.08 : 0.92)
                .blur(radius: 6)

            // Animated selection ring
            RoundedRectangle(cornerRadius: 36, style: .continuous)
                .strokeBorder(
                    AngularGradient(
                        colors: [orange, orange.opacity(0.2), .white.opacity(0.7), orange],
                        center: .center
                    ),
                    lineWidth: 3.5
                )
                .frame(width: 136, height: 136)
                .rotationEffect(.degrees(heroPulse ? 18 : -8))
                .scaleEffect(heroPulse ? 1.03 : 0.98)

            Image(selection)
                .resizable()
                .scaledToFill()
                .frame(width: 124, height: 124)
                .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
                .matchedGeometryEffect(id: selection, in: avatarNamespace, isSource: true)
                .shadow(color: orange.opacity(0.28), radius: 18, y: 10)
                .shadow(color: .black.opacity(0.12), radius: 10, y: 6)
                .id(swapToken)
                .transition(
                    .asymmetric(
                        insertion: .scale(scale: 0.72).combined(with: .opacity),
                        removal: .scale(scale: 1.12).combined(with: .opacity)
                    )
                )
        }
        .frame(height: 180)
        .animation(selectSpring, value: selection)
    }

    // MARK: - Grid cell

    private func avatarCell(_ name: String, index: Int) -> some View {
        let isSelected = selection == name
        let delay = Double(index) * 0.028

        return Button {
            guard selection != name else {
                // Re-tap bounce on already selected
                withAnimation(selectSpring) { swapToken += 1 }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                return
            }
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            withAnimation(selectSpring) {
                selection = name
                swapToken += 1
            }
        } label: {
            ZStack {
                if isSelected {
                    // Slot reserved while hero owns the matched geometry
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color(white: 0.94))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(orange.opacity(0.55), lineWidth: 2)
                        )
                        .overlay {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 22, weight: .semibold))
                                .foregroundStyle(orange)
                                .symbolEffect(.bounce, value: swapToken)
                        }
                } else {
                    Image(name)
                        .resizable()
                        .scaledToFill()
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .matchedGeometryEffect(id: name, in: avatarNamespace, isSource: true)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(Color.black.opacity(0.04), lineWidth: 1)
                        )
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 72)
            .scaleEffect(isSelected ? 0.94 : (didAppear ? 1 : 0.82))
            .opacity(didAppear ? (isSelected ? 0.95 : 1) : 0)
            .offset(y: didAppear ? 0 : 16)
            .animation(
                .spring(response: 0.5, dampingFraction: 0.78).delay(didAppear ? 0 : delay),
                value: didAppear
            )
            .animation(selectSpring, value: selection)
        }
        .buttonStyle(AvatarCellPressStyle())
        .accessibilityLabel("Avatar \(index + 1)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Soft press — scale without dulling opacity (keeps avatars vivid).
private struct AvatarCellPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.6), value: configuration.isPressed)
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
