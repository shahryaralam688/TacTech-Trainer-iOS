import SwiftUI

struct SplashView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            TTColor.splash.ignoresSafeArea()

            VStack(spacing: TTSpace.lg) {
                GymMorphIcon(isStatic: reduceMotion)
                    .frame(width: 112, height: 112)
                    .padding(.bottom, TTSpace.xxs)

                Text("TacTech Trainer App")
                    .font(TTFont.display(26))
                    .foregroundStyle(TTColor.inkOnDark)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.8)

                Text("Your personal AI fitness coach.")
                    .font(TTFont.body(16))
                    .foregroundStyle(TTColor.inkOnDark.opacity(0.92))
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, TTSpace.xxl)
        }
        .preferredColorScheme(.dark)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("TacTech Trainer App. Your personal AI fitness coach.")
    }
}

private struct GymMorphIcon: View {
    var isStatic: Bool
    @State private var startedAt = Date()

    var body: some View {
        TimelineView(.animation(minimumInterval: isStatic ? 1 : 1 / 60, paused: isStatic)) { context in
            morphShape(at: context.date)
        }
    }

    private func morphShape(at date: Date) -> some View {
        let glyphs = GymMorphGlyph.allCases
        let fromIndex: Int
        let toIndex: Int
        let localT: CGFloat

        if isStatic {
            fromIndex = 0
            toIndex = 0
            localT = 0
        } else {
            let elapsed = date.timeIntervalSince(startedAt)
            let secondsPerMorph = 1.35
            let total = Double(glyphs.count) * secondsPerMorph
            let wrapped = elapsed.truncatingRemainder(dividingBy: total)
            let raw = wrapped / secondsPerMorph
            fromIndex = Int(raw) % glyphs.count
            toIndex = (fromIndex + 1) % glyphs.count
            localT = expoInOut(raw - floor(raw))
        }

        return GymMorphShape(
            from: glyphs[fromIndex].samples,
            to: glyphs[toIndex].samples,
            progress: localT
        )
        .fill(
            LinearGradient(
                colors: [
                    Color.white,
                    Color(red: 1, green: 0.93, blue: 0.86)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    /// Matches GSAP `expo.inOut`.
    private func expoInOut(_ t: Double) -> CGFloat {
        if t <= 0 { return 0 }
        if t >= 1 { return 1 }
        if t < 0.5 {
            return CGFloat(pow(2, 20 * t - 10) / 2)
        }
        return CGFloat((2 - pow(2, -20 * t + 10)) / 2)
    }
}

private struct GymMorphShape: Shape {
    var from: [CGPoint]
    var to: [CGPoint]
    var progress: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let count = min(from.count, to.count)
        guard count > 1 else { return Path() }

        var path = Path()
        for index in 0..<count {
            let a = from[index]
            let b = to[index]
            let point = CGPoint(
                x: (a.x + (b.x - a.x) * progress) / 100 * rect.width,
                y: (a.y + (b.y - a.y) * progress) / 100 * rect.height
            )
            if index == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        path.closeSubpath()
        return path
    }
}

/// Gym silhouettes only — no plus/cross mark.
private enum GymMorphGlyph: CaseIterable {
    case dumbbell
    case kettlebell
    case lightning
    case flame
    case heart

    var samples: [CGPoint] {
        switch self {
        case .dumbbell: Self.dumbbellSamples
        case .kettlebell: Self.kettlebellSamples
        case .lightning: Self.lightningSamples
        case .flame: Self.flameSamples
        case .heart: Self.heartSamples
        }
    }

    private static let dumbbellSamples = sample(makeDumbbell(), count: 96)
    private static let kettlebellSamples = sample(makeKettlebell(), count: 96)
    private static let lightningSamples = sample(makeLightning(), count: 96)
    private static let flameSamples = sample(makeFlame(), count: 96)
    private static let heartSamples = sample(makeHeart(), count: 96)

    private static func makeDumbbell() -> Path {
        Path { path in
            path.move(to: CGPoint(x: 5, y: 28))
            path.addLine(to: CGPoint(x: 21, y: 28))
            path.addLine(to: CGPoint(x: 21, y: 40))
            path.addLine(to: CGPoint(x: 79, y: 40))
            path.addLine(to: CGPoint(x: 79, y: 28))
            path.addLine(to: CGPoint(x: 95, y: 28))
            path.addLine(to: CGPoint(x: 95, y: 72))
            path.addLine(to: CGPoint(x: 79, y: 72))
            path.addLine(to: CGPoint(x: 79, y: 60))
            path.addLine(to: CGPoint(x: 21, y: 60))
            path.addLine(to: CGPoint(x: 21, y: 72))
            path.addLine(to: CGPoint(x: 5, y: 72))
            path.closeSubpath()
        }
    }

    private static func makeKettlebell() -> Path {
        Path { path in
            path.move(to: CGPoint(x: 36, y: 8))
            path.addQuadCurve(to: CGPoint(x: 64, y: 8), control: CGPoint(x: 50, y: 2))
            path.addQuadCurve(to: CGPoint(x: 70, y: 24), control: CGPoint(x: 74, y: 12))
            path.addLine(to: CGPoint(x: 62, y: 30))
            path.addQuadCurve(to: CGPoint(x: 86, y: 68), control: CGPoint(x: 88, y: 42))
            path.addQuadCurve(to: CGPoint(x: 50, y: 96), control: CGPoint(x: 86, y: 94))
            path.addQuadCurve(to: CGPoint(x: 14, y: 68), control: CGPoint(x: 14, y: 94))
            path.addQuadCurve(to: CGPoint(x: 38, y: 30), control: CGPoint(x: 12, y: 42))
            path.addLine(to: CGPoint(x: 30, y: 24))
            path.addQuadCurve(to: CGPoint(x: 36, y: 8), control: CGPoint(x: 26, y: 12))
            path.closeSubpath()
        }
    }

    private static func makeLightning() -> Path {
        Path { path in
            path.move(to: CGPoint(x: 47.1, y: 0.8))
            path.addLine(to: CGPoint(x: 73.3, y: 0.8))
            path.addLine(to: CGPoint(x: 61.9, y: 37.2))
            path.addLine(to: CGPoint(x: 77.1, y: 37.2))
            path.addLine(to: CGPoint(x: 30.7, y: 99.4))
            path.addLine(to: CGPoint(x: 45.8, y: 51.9))
            path.addLine(to: CGPoint(x: 29, y: 51.9))
            path.closeSubpath()
        }
    }

    private static func makeFlame() -> Path {
        Path { path in
            path.move(to: CGPoint(x: 50, y: 6))
            path.addQuadCurve(to: CGPoint(x: 62, y: 28), control: CGPoint(x: 52, y: 18))
            path.addQuadCurve(to: CGPoint(x: 80, y: 56), control: CGPoint(x: 78, y: 36))
            path.addQuadCurve(to: CGPoint(x: 50, y: 96), control: CGPoint(x: 86, y: 86))
            path.addQuadCurve(to: CGPoint(x: 20, y: 56), control: CGPoint(x: 14, y: 86))
            path.addQuadCurve(to: CGPoint(x: 38, y: 28), control: CGPoint(x: 22, y: 36))
            path.addQuadCurve(to: CGPoint(x: 50, y: 6), control: CGPoint(x: 48, y: 18))
            path.closeSubpath()
        }
    }

    private static func makeHeart() -> Path {
        Path { path in
            path.move(to: CGPoint(x: 50, y: 90))
            path.addLine(to: CGPoint(x: 16, y: 52))
            path.addQuadCurve(to: CGPoint(x: 18, y: 18), control: CGPoint(x: 2, y: 34))
            path.addQuadCurve(to: CGPoint(x: 50, y: 30), control: CGPoint(x: 38, y: 4))
            path.addQuadCurve(to: CGPoint(x: 82, y: 18), control: CGPoint(x: 62, y: 4))
            path.addQuadCurve(to: CGPoint(x: 84, y: 52), control: CGPoint(x: 98, y: 34))
            path.closeSubpath()
        }
    }

    private static func sample(_ path: Path, count: Int) -> [CGPoint] {
        (0..<count).map { index in
            let start = CGFloat(index) / CGFloat(count)
            let end = min(start + 0.002, 1)
            let slice = path.trimmedPath(from: start, to: end)
            return CGPoint(x: slice.boundingRect.midX, y: slice.boundingRect.midY)
        }
    }
}

#Preview {
    SplashView()
}
