import SwiftUI

// MARK: - Home delight motion (Phase 1)
//
// Shared entrance / press / micro-chart animations for trainee + trainer home.
// Respects Reduce Motion. Does not change layout sizes or spacing.

enum TTHomeDelight {
    static let entrance = Animation.spring(response: 0.52, dampingFraction: 0.86)
    static let press = Animation.spring(response: 0.28, dampingFraction: 0.62)
    static let chart = Animation.spring(response: 0.7, dampingFraction: 0.78)
    static let pulse = Animation.easeInOut(duration: 1.35)

    static func staggerDelay(_ index: Int) -> Double {
        min(0.08 + Double(index) * 0.07, 0.55)
    }

    /// Time-of-day greeting for the home header.
    static func greeting(for name: String, date: Date = .now) -> String {
        let hour = Calendar.current.component(.hour, from: date)
        let hello: String
        switch hour {
        case 5..<12: hello = "Good morning"
        case 12..<17: hello = "Good afternoon"
        case 17..<22: hello = "Good evening"
        default: hello = "Hey"
        }
        return "\(hello), \(name)!"
    }
}

// MARK: - Staggered appear

struct TTHomeAppearModifier: ViewModifier {
    var index: Int
    var enabled: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown || !enabled ? 1 : 0)
            .offset(y: shown || !enabled ? 0 : (reduceMotion ? 0 : 18))
            .scaleEffect(shown || !enabled ? 1 : (reduceMotion ? 1 : 0.96), anchor: .top)
            .onAppear {
                guard enabled else {
                    shown = true
                    return
                }
                if reduceMotion {
                    shown = true
                    return
                }
                withAnimation(TTHomeDelight.entrance.delay(TTHomeDelight.staggerDelay(index))) {
                    shown = true
                }
            }
    }
}

extension View {
    /// Staggered fade + rise when home content first lands.
    func ttHomeAppear(index: Int, enabled: Bool = true) -> some View {
        modifier(TTHomeAppearModifier(index: index, enabled: enabled))
    }
}

// MARK: - Bouncy card press

struct TTHomeCardPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? (reduceMotion ? 0.99 : 0.965) : 1)
            .brightness(configuration.isPressed ? -0.02 : 0)
            .animation(TTHomeDelight.press, value: configuration.isPressed)
    }
}

// MARK: - Soft CTA pulse (primary action)

struct TTHomeCTAPulseModifier: ViewModifier {
    var tint: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulsing = false

    func body(content: Content) -> some View {
        content
            .shadow(
                color: tint.opacity(reduceMotion ? 0.28 : (pulsing ? 0.48 : 0.22)),
                radius: reduceMotion ? 10 : (pulsing ? 16 : 8),
                y: 4
            )
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(TTHomeDelight.pulse.repeatForever(autoreverses: true)) {
                    pulsing = true
                }
            }
    }
}

extension View {
    func ttHomeCTAPulse(tint: Color) -> some View {
        modifier(TTHomeCTAPulseModifier(tint: tint))
    }
}

// MARK: - Animated mini charts (metric cards)

struct TTHomeMetricBars: View {
    var heights: [CGFloat] = [0.45, 0.7, 0.55, 0.9, 0.65]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var grown = false

    var body: some View {
        HStack(alignment: .bottom, spacing: 4) {
            ForEach(Array(heights.enumerated()), id: \.offset) { _, h in
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Color.white.opacity(0.85))
                    .frame(width: 8, height: 36 * (grown || reduceMotion ? h : 0.08))
            }
        }
        .frame(height: 40, alignment: .bottom)
        .onAppear {
            guard !reduceMotion else {
                grown = true
                return
            }
            withAnimation(TTHomeDelight.chart.delay(0.12)) {
                grown = true
            }
        }
    }
}

struct TTHomeMetricWave: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: CGFloat = 0

    var body: some View {
        TTHomeWaveShape(phase: reduceMotion ? 0 : phase)
            .stroke(Color.white.opacity(0.9), style: StrokeStyle(lineWidth: 3, lineCap: .round))
            .frame(height: 40)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: 2.4).repeatForever(autoreverses: false)) {
                    phase = .pi * 2
                }
            }
    }
}

struct TTHomeMetricDots: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var highlight = 3

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<5, id: \.self) { i in
                Circle()
                    .fill(Color.white.opacity(i == highlight ? 1 : 0.35))
                    .frame(width: 8, height: 8)
                    .scaleEffect(i == highlight && !reduceMotion ? 1.25 : 1)
            }
        }
        .frame(height: 40)
        .task(id: reduceMotion) {
            guard !reduceMotion else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(550))
                withAnimation(TTHomeDelight.press) {
                    highlight = (highlight + 1) % 5
                }
            }
        }
    }
}

/// Soft sine wave for hydration metric — `phase` animates the crest.
struct TTHomeWaveShape: Shape {
    var phase: CGFloat = 0

    var animatableData: CGFloat {
        get { phase }
        set { phase = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let midY = rect.midY
        let amp: CGFloat = 12
        path.move(to: CGPoint(x: 0, y: midY))
        let steps = 24
        for i in 1...steps {
            let x = rect.width * CGFloat(i) / CGFloat(steps)
            let t = (CGFloat(i) / CGFloat(steps)) * .pi * 2 + phase
            let y = midY + sin(t) * amp * 0.55 + cos(t * 0.5) * amp * 0.25
            path.addLine(to: CGPoint(x: x, y: y))
        }
        return path
    }
}

// MARK: - Badge pop

struct TTHomeBadgePop: ViewModifier {
    var active: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var popped = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(popped || reduceMotion || !active ? 1 : 0.4)
            .opacity(popped || !active ? 1 : 0)
            .onAppear {
                guard active, !reduceMotion else {
                    popped = true
                    return
                }
                withAnimation(.spring(response: 0.4, dampingFraction: 0.55).delay(0.35)) {
                    popped = true
                }
            }
            .onChange(of: active) { _, on in
                guard on, !reduceMotion else { return }
                popped = false
                withAnimation(.spring(response: 0.4, dampingFraction: 0.55)) {
                    popped = true
                }
            }
    }
}

extension View {
    func ttHomeBadgePop(active: Bool) -> some View {
        modifier(TTHomeBadgePop(active: active))
    }
}

// MARK: - Hero sheen

/// Soft diagonal light sweep across the workout hero image.
struct TTHomeHeroSheen: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var x: CGFloat = -0.4

    var body: some View {
        GeometryReader { geo in
            LinearGradient(
                colors: [
                    .clear,
                    Color.white.opacity(0.14),
                    .clear
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: geo.size.width * 0.45)
            .offset(x: geo.size.width * x)
            .blendMode(.plusLighter)
            .allowsHitTesting(false)
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 3.2).repeatForever(autoreverses: false)) {
                x = 1.2
            }
        }
    }
}
