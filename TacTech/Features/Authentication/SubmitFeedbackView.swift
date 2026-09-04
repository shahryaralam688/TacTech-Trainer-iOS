import SwiftUI

// MARK: - Submit Feedback (Sandow bottom-sheet overlay)

struct SubmitFeedbackView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var selected: Set<FeedbackArea> = [.performance, .bug, .crashes, .navigation]
    @State private var appeared = false
    @State private var sheetVisible = false
    @State private var badgePulse = false
    @State private var submitting = false
    @State private var submitted = false
    @State private var chipReveal = false

    private let backdrop = Color(hex: 0x383B42)
    private let ink = Color(hex: 0x1C1E21)
    private let chipIdle = Color(hex: 0xF2F3F5)
    private let chipIdleText = Color(hex: 0x42464D)
    private let badgeFill = Color(hex: 0x18191B)
    private let ctaFill = Color(hex: 0x141517)

    var body: some View {
        ZStack(alignment: .bottom) {
            backdrop
                .ignoresSafeArea()
                .opacity(appeared ? 1 : 0)

            VStack(spacing: 0) {
                header
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : -12)
                Spacer(minLength: 0)
            }

            sheetStack
                .offset(y: sheetVisible ? 0 : 420)
                .opacity(sheetVisible ? 1 : 0)
        }
        .ttHideSystemNavigationBar()
        .sensoryFeedback(.selection, trigger: selected)
        .onAppear(perform: present)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 14) {
            TTBackButton(style: .onDark) { dismiss() }

            Text("Submit Feedback")
                .font(TTFont.workSans(18, weight: .bold))
                .foregroundStyle(.white)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    // MARK: - Stacked sheet

    private var sheetStack: some View {
        ZStack(alignment: .top) {
            // Subtle stacked cards behind the main sheet
            stackedCard(inset: 28, lift: 18, opacity: 0.18)
            stackedCard(inset: 14, lift: 10, opacity: 0.32)

            mainSheet
                .padding(.top, 28)
        }
        .padding(.horizontal, 0)
    }

    private func stackedCard(inset: CGFloat, lift: CGFloat, opacity: Double) -> some View {
        RoundedRectangle(cornerRadius: 28, style: .continuous)
            .fill(Color.white.opacity(opacity))
            .frame(height: 56)
            .padding(.horizontal, inset)
            .offset(y: lift)
            .blur(radius: appeared ? 0 : 2)
    }

    private var mainSheet: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: 36)

            Text("Which of the area\nneeds improvement?")
                .font(TTFont.workSans(22, weight: .bold))
                .foregroundStyle(ink)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
                .padding(.top, 8)
                .opacity(chipReveal ? 1 : 0)
                .offset(y: chipReveal ? 0 : 10)

            FlowLayout(spacing: 10) {
                ForEach(Array(FeedbackArea.allCases.enumerated()), id: \.element.id) { index, area in
                    chip(area)
                        .opacity(chipReveal ? 1 : 0)
                        .scaleEffect(chipReveal ? 1 : 0.86)
                        .animation(
                            reduceMotion
                                ? .easeOut(duration: 0.12)
                                : .spring(response: 0.42, dampingFraction: 0.78).delay(Double(index) * 0.035),
                            value: chipReveal
                        )
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 22)

            Spacer(minLength: 28)

            submitButton
                .padding(.horizontal, 22)
                .padding(.bottom, 10)
                .opacity(chipReveal ? 1 : 0)
                .offset(y: chipReveal ? 0 : 16)

            Capsule()
                .fill(Color.black.opacity(0.18))
                .frame(width: 134, height: 5)
                .padding(.bottom, 10)
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 480)
        .background(
            UnevenRoundedRectangle(
                topLeadingRadius: 32,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: 32,
                style: .continuous
            )
            .fill(Color.white)
            .shadow(color: .black.opacity(0.18), radius: 24, y: -4)
        )
        .overlay(alignment: .top) {
            avatarBadge
                .offset(y: -28)
        }
        .ignoresSafeArea(edges: .bottom)
    }

    // MARK: - Avatar badge

    private var avatarBadge: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(badgeFill)
                .frame(width: 64, height: 64)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color.white, lineWidth: 4)
                )
                .shadow(color: .black.opacity(0.2), radius: 12, y: 6)

            TTIcon(icon: .emotionHappy, filled: true, size: 28)
                .foregroundStyle(.white)
                .scaleEffect(badgePulse ? 1.08 : 1)
        }
        .scaleEffect(sheetVisible ? 1 : 0.4)
        .opacity(sheetVisible ? 1 : 0)
        .rotationEffect(.degrees(sheetVisible ? 0 : -12))
    }

    // MARK: - Chips

    private func chip(_ area: FeedbackArea) -> some View {
        let on = selected.contains(area)
        return Button {
            toggle(area)
        } label: {
            Text(area.title)
                .font(TTFont.workSans(14, weight: on ? .bold : .semibold))
                .foregroundStyle(on ? Color.white : chipIdleText)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    Capsule(style: .continuous)
                        .fill(on ? area.activeColor : chipIdle)
                )
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(on ? area.glowColor : Color.clear, lineWidth: on ? 1.5 : 0)
                )
                .shadow(color: on ? area.activeColor.opacity(0.35) : .clear, radius: on ? 10 : 0, y: on ? 3 : 0)
                .scaleEffect(on ? 1.02 : 1)
        }
        .buttonStyle(TTSearchPressStyle(scale: 0.96))
        .animation(
            reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.32, dampingFraction: 0.72),
            value: on
        )
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func toggle(_ area: FeedbackArea) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.32, dampingFraction: 0.7)) {
            if selected.contains(area) {
                selected.remove(area)
            } else {
                selected.insert(area)
            }
        }
    }

    // MARK: - CTA

    private var submitButton: some View {
        Button {
            submit()
        } label: {
            HStack(spacing: 10) {
                if submitting {
                    ProgressView()
                        .tint(.white)
                } else if submitted {
                    TTIcon(icon: .check, filled: true, size: 16)
                        .foregroundStyle(.white)
                    Text("Thanks!")
                        .font(TTFont.workSans(16, weight: .bold))
                } else {
                    Text("Submit Feedback")
                        .font(TTFont.workSans(16, weight: .bold))
                    TTIcon(icon: .arrowRight, size: 16)
                        .foregroundStyle(.white)
                        .offset(x: sheetVisible ? 0 : -6)
                }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(ctaFill)
            )
            .shadow(color: .black.opacity(0.18), radius: 14, y: 6)
            .opacity(selected.isEmpty && !submitted ? 0.45 : 1)
        }
        .buttonStyle(TTSearchPressStyle(scale: 0.97))
        .disabled(selected.isEmpty || submitting || submitted)
    }

    // MARK: - Motion / submit

    private func present() {
        let present = reduceMotion ? Animation.easeOut(duration: 0.18) : TTMotion.searchPresent
        let chrome = reduceMotion ? Animation.easeOut(duration: 0.12) : TTMotion.searchChrome
        withAnimation(chrome) { appeared = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + (reduceMotion ? 0.02 : 0.08)) {
            withAnimation(present) { sheetVisible = true }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + (reduceMotion ? 0.08 : 0.28)) {
            withAnimation(chrome) { chipReveal = true }
            if !reduceMotion {
                withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                    badgePulse = true
                }
            }
        }
    }

    private func submit() {
        guard !selected.isEmpty else { return }
        submitting = true
        UINotificationFeedbackGenerator().notificationOccurred(.success)

        let payload = selected.map(\.title).sorted().joined(separator: ", ")
        UserDefaults.standard.set(payload, forKey: "tt.appFeedback.areas")
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "tt.appFeedback.submittedAt")

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.36, dampingFraction: 0.8)) {
                submitting = false
                submitted = true
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.15) {
            dismiss()
        }
    }
}

// MARK: - Areas

private enum FeedbackArea: String, CaseIterable, Identifiable, Hashable {
    case performance, support, bug, ui, ux, crashes, loading, navigation, leadership, pricing

    var id: String { rawValue }

    var title: String {
        switch self {
        case .performance: "Performance"
        case .support: "Support"
        case .bug: "Bug"
        case .ui: "UI"
        case .ux: "UX"
        case .crashes: "Crashes"
        case .loading: "Loading"
        case .navigation: "Navigation"
        case .leadership: "Leadership"
        case .pricing: "Pricing"
        }
    }

    var activeColor: Color {
        switch self {
        case .performance: Color(hex: 0x2365ED)
        case .bug: Color(hex: 0xA855F7)
        case .crashes: Color(hex: 0x84CD1B)
        case .navigation: Color(hex: 0xFF6F1A)
        case .support: Color(hex: 0x0EA5E9)
        case .ui: Color(hex: 0xEC4899)
        case .ux: Color(hex: 0x14B8A6)
        case .loading: Color(hex: 0xF59E0B)
        case .leadership: Color(hex: 0x6366F1)
        case .pricing: Color(hex: 0xEF4444)
        }
    }

    var glowColor: Color {
        activeColor.opacity(0.55)
    }
}

#Preview("Submit Feedback") {
    NavigationStack {
        SubmitFeedbackView()
    }
}
