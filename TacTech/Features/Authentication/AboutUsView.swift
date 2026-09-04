import SwiftUI
import UIKit

/// Sandow About Us — light header, TecTach mark, contact cards, social row.
struct AboutUsView: View {
    @Environment(\.dismiss) private var dismiss

    private let canvas = Color.white
    private let cardFill = Color(red: 242 / 255, green: 242 / 255, blue: 242 / 255)
    private let orange = TTColor.actionOrange

    private let addressLines = [
        "578 Boolean Ave",
        "Turing St",
        "New York, NY"
    ]

    private let phones = [
        "+123-456-789",
        "+44-887-449"
    ]

    private let socials: [(asset: String, url: String)] = [
        ("SocialFacebook", "https://facebook.com"),
        ("SocialInstagram", "https://instagram.com"),
        ("SocialLinkedIn", "https://linkedin.com"),
        ("SocialYouTube", "https://youtube.com")
    ]

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    brandBlock
                        .padding(.top, 48)

                    VStack(spacing: 14) {
                        infoCard(
                            title: "Address",
                            icon: .mapPin1,
                            lines: addressLines
                        )
                        infoCard(
                            title: "Telephone",
                            icon: .telephone1,
                            lines: phones
                        )
                    }
                    .padding(.horizontal, 22)
                    .padding(.top, 44)

                    socialRow
                        .padding(.top, 48)
                        .padding(.bottom, 36)
                }
            }
        }
        .background(canvas.ignoresSafeArea())
        .ttHideSystemNavigationBar()
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 14) {
            TTBackButton(style: .onLight) { dismiss() }

            Text("About Us")
                .font(TTFont.workSans(20, weight: .bold))
                .foregroundStyle(TTColor.ink)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .background(canvas)
    }

    // MARK: - Brand

    private var brandBlock: some View {
        VStack(spacing: 18) {
            TecTachLogoMark(size: 92)
                .accessibilityHidden(true)

            VStack(spacing: 8) {
                Text("TecTach")
                    .font(TTFont.workSans(34, weight: .bold))
                    .foregroundStyle(TTColor.ink)

                Text("AI Fitness & Training Solution")
                    .font(TTFont.body(15))
                    .foregroundStyle(TTColor.inkMuted)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("TecTach, AI Fitness and Training Solution")
    }

    // MARK: - Cards

    private func infoCard(title: String, icon: SandowIcon, lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 8) {
                TTIcon(icon: icon, filled: true, size: 16)
                    .foregroundStyle(TTColor.inkMuted)
                Text(title)
                    .font(TTFont.workSans(16, weight: .bold))
                    .foregroundStyle(TTColor.ink)
                Spacer(minLength: 0)
            }

            VStack(alignment: .trailing, spacing: 4) {
                ForEach(lines, id: \.self) { line in
                    Text(line)
                        .font(TTFont.body(14))
                        .foregroundStyle(TTColor.inkMuted)
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardFill)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    // MARK: - Social

    private var socialRow: some View {
        HStack(spacing: 28) {
            ForEach(socials, id: \.asset) { item in
                Button {
                    if let url = URL(string: item.url) {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    Image(item.asset)
                        .resizable()
                        .renderingMode(.template)
                        .scaledToFit()
                        .foregroundStyle(TTColor.inkMuted)
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(TTSearchPressStyle(scale: 0.92))
                .accessibilityLabel(item.asset.replacingOccurrences(of: "Social", with: ""))
            }
        }
        .frame(maxWidth: .infinity)
    }
}

/// Orange rounded-plus mark from the About Us design.
struct TecTachLogoMark: View {
    var size: CGFloat = 92
    var color: Color = TTColor.actionOrange

    var body: some View {
        let thickness = size * 0.34
        ZStack {
            Capsule(style: .continuous)
                .fill(color)
                .frame(width: thickness, height: size)
            Capsule(style: .continuous)
                .fill(color)
                .frame(width: size, height: thickness)
        }
        .frame(width: size, height: size)
        .shadow(color: color.opacity(0.22), radius: 14, y: 8)
    }
}

#Preview("About Us") {
    NavigationStack {
        AboutUsView()
    }
}
