import AVFoundation
import SwiftUI
import UIKit

enum AssessmentColor {
    static let ink = TTColor.ink
    static let white = Color.white
    static let slate = TTColor.inkMuted
    static let surface = TTColor.surfaceAlt
    static let charcoal = TTColor.ink
    static let coolGrey = TTColor.inkSubtle
    static let blue = TTColor.info
    static let blueSoft = TTColor.infoSoft
    static let orange = TTColor.accent
    static let grey = TTColor.inkMuted
    static let line = TTColor.line
    static let peach = TTColor.accentSoft
    static let orangeBorder = TTColor.accentBorder
    static let blueMid = TTColor.info
    static let textBoxBorder = TTColor.inkSubtle
}

/// Figma-style assessment text box — gray border, undo/redo, 250 char counter.
struct AssessmentTextBox: View {
    @Binding var text: String
    var placeholder: String
    var maxCharacters: Int = 250
    var minHeight: CGFloat = 200

    @State private var undoStack: [String] = []
    @State private var redoStack: [String] = []
    @State private var isApplyingHistory = false
    @FocusState private var focused: Bool

    private var count: Int { text.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topLeading) {
                if text.isEmpty {
                    Text(placeholder)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(AssessmentColor.coolGrey)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 8)
                        .allowsHitTesting(false)
                }

                TextField("", text: $text, axis: .vertical)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(AssessmentColor.ink)
                    .lineLimit(6...12)
                    .focused($focused)
                    .tint(AssessmentColor.orange)
                    .onChange(of: text) { oldValue, newValue in
                        if newValue.count > maxCharacters {
                            text = String(newValue.prefix(maxCharacters))
                            return
                        }
                        guard !isApplyingHistory, oldValue != newValue else { return }
                        undoStack.append(oldValue)
                        if undoStack.count > 40 { undoStack.removeFirst() }
                        redoStack.removeAll()
                    }
            }
            .frame(maxWidth: .infinity, minHeight: minHeight - 56, alignment: .topLeading)
            .padding(.horizontal, 14)
            .padding(.top, 14)

            HStack(spacing: 10) {
                toolButton(systemName: "arrow.uturn.backward", enabled: !undoStack.isEmpty, action: undo)
                toolButton(systemName: "arrow.uturn.forward", enabled: !redoStack.isEmpty, action: redo)

                Spacer()

                HStack(spacing: 6) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 13, weight: .semibold))
                    Text("\(count)/\(maxCharacters)")
                        .font(.system(size: 13, weight: .semibold))
                        .monospacedDigit()
                }
                .foregroundStyle(count >= maxCharacters ? AssessmentColor.orange : AssessmentColor.slate)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
            .padding(.top, 4)
        }
        .background(AssessmentColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(AssessmentColor.textBoxBorder, lineWidth: 1.5)
        )
        .shadow(color: Color.black.opacity(0.06), radius: 10, y: 4)
    }

    private func toolButton(systemName: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(enabled ? AssessmentColor.ink : AssessmentColor.coolGrey)
                .frame(width: 40, height: 40)
                .background(AssessmentColor.white)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .shadow(color: Color.black.opacity(0.05), radius: 3, y: 1)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    private func undo() {
        guard let previous = undoStack.popLast() else { return }
        isApplyingHistory = true
        redoStack.append(text)
        text = previous
        DispatchQueue.main.async { isApplyingHistory = false }
    }

    private func redo() {
        guard let next = redoStack.popLast() else { return }
        isApplyingHistory = true
        undoStack.append(text)
        text = next
        DispatchQueue.main.async { isApplyingHistory = false }
    }
}

struct GoalStep: View {
    @Binding var draft: FitnessAssessment

    private let options: [(title: String, icon: SandowIcon)] = [
        ("I wanna lose weight", .weightScale),
        ("I wanna try AI Coach", .robotFace1),
        ("I wanna get bulks", .barbellHorizontal),
        ("I wanna gain endurance", .heartEcg),
        ("Just trying out the app! 👍", .mobile)
    ]

    var body: some View {
        AssessmentQuestion("What’s your fitness goal/target?", centered: true) {
            VStack(spacing: 12) {
                ForEach(options, id: \.title) { item in
                    AssessmentChoice(
                        title: item.title,
                        icon: item.icon,
                        selected: draft.goal == item.title
                    ) {
                        draft.goal = item.title
                    }
                }
            }
        }
    }
}

struct GenderStep: View {
    @Binding var draft: FitnessAssessment
    var onSkip: () -> Void

    var body: some View {
        AssessmentQuestion("What is your gender?", centered: true) {
            VStack(spacing: 12) {
                genderCard("Male", icon: .genderMale, photo: "AssessmentMale")
                genderCard("Female", icon: .genderFemale, photo: "AssessmentFemale")
                Button(action: onSkip) {
                    HStack(spacing: 8) {
                        Text("Prefer to skip, thanks!")
                            .font(.system(size: 16, weight: .semibold))
                        TTIcon(icon: .closeX, size: 14)
                    }
                    .foregroundStyle(AssessmentColor.orange)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(AssessmentColor.peach)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func genderCard(_ title: String, icon: SandowIcon, photo: String) -> some View {
        let selected = draft.gender == title
        return Button {
            draft.gender = title
        } label: {
            ZStack(alignment: .trailing) {
                HStack {
                    VStack(alignment: .leading, spacing: 18) {
                        HStack(spacing: 6) {
                            Text(title)
                                .font(.system(size: 18, weight: .bold))
                            TTIcon(icon: icon, size: 16)
                        }
                        AssessmentRadio(selected: selected)
                    }
                    .foregroundStyle(AssessmentColor.ink)
                    .padding(20)
                    Spacer(minLength: 120)
                }
                Image(photo)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 148, height: 148)
                    .clipped()
            }
            .frame(height: 148)
            .background(AssessmentColor.surface)
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(selected ? AssessmentColor.orange : Color.clear, lineWidth: 2)
            )
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

struct WeightStep: View {
    @Binding var draft: FitnessAssessment

    var body: some View {
        VStack(spacing: 0) {
            Text("What is your weight?")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(AssessmentColor.ink)
                .multilineTextAlignment(.center)
                .padding(.top, 28)
            AssessmentUnitToggle(selection: $draft.weightUnit, left: ("kg", "kg"), right: ("lbs", "lbs"))
                .padding(.top, 28)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(displayNumber)
                    .font(.system(size: 72, weight: .bold))
                    .foregroundStyle(AssessmentColor.ink)
                    .contentTransition(.numericText())
                Text(draft.weightUnit)
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(AssessmentColor.grey)
            }
            .padding(.top, 36)
            AssessmentRuler(
                value: displayBinding,
                range: draft.weightUnit == "lbs" ? 80...400 : 35...220,
                step: 0.1
            )
            .padding(.top, 28)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 8)
    }

    private var displayNumber: String {
        displayedWeight.rounded(to: 1).truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", displayedWeight)
            : String(format: "%.1f", displayedWeight)
    }

    private var displayedWeight: Double {
        if draft.weightUnit == "lbs" {
            return (draft.weightKg * 2.20462).rounded(to: 1)
        }
        return draft.weightKg.rounded(to: 1)
    }

    private var displayBinding: Binding<Double> {
        Binding(
            get: { displayedWeight },
            set: { newValue in
                if draft.weightUnit == "lbs" {
                    draft.weightKg = (newValue / 2.20462).rounded(to: 1)
                } else {
                    draft.weightKg = newValue.rounded(to: 1)
                }
            }
        )
    }
}

struct AgeStep: View {
    @Binding var draft: FitnessAssessment

    var body: some View {
        VStack(spacing: 0) {
            Text("What is your age?")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(AssessmentColor.ink)
                .multilineTextAlignment(.center)
                .padding(.top, 28)
                .padding(.bottom, 4)

            AssessmentAgeWheel(selection: $draft.age, range: 14...80)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sensoryFeedback(.selection, trigger: draft.age)
    }
}

struct AssessmentAgeWheel: View {
    @Binding var selection: Int
    var range: ClosedRange<Int>

    /// Orange selection plate — matches Figma (~155pt tall, ~75% width).
    private let plateHeight: CGFloat = 155
    private let plateCorner: CGFloat = 36
    /// Row pitch so 16 / 17 / 18 / 19 / 20 sit clear like the reference.
    private let rowHeight: CGFloat = 108

    var body: some View {
        ZStack {
            orangePlate
            NativeAgeWheelPicker(
                selection: $selection,
                range: range,
                rowHeight: rowHeight
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var orangePlate: some View {
        RoundedRectangle(cornerRadius: plateCorner, style: .continuous)
            .fill(AssessmentColor.orange)
            .overlay(
                RoundedRectangle(cornerRadius: plateCorner, style: .continuous)
                    .strokeBorder(AssessmentColor.orangeBorder, lineWidth: 2.5)
            )
            .frame(height: plateHeight)
            .padding(.horizontal, 46)
            .shadow(color: AssessmentColor.orange.opacity(0.18), radius: 12, y: 4)
            .allowsHitTesting(false)
    }
}

/// UIKit wheel — Clock.app physics, Figma size hierarchy (big selected, smaller neighbors).
private struct NativeAgeWheelPicker: UIViewRepresentable {
    @Binding var selection: Int
    var range: ClosedRange<Int>
    var rowHeight: CGFloat

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> UIPickerView {
        let picker = UIPickerView()
        picker.dataSource = context.coordinator
        picker.delegate = context.coordinator
        picker.backgroundColor = .clear
        picker.clipsToBounds = false
        context.coordinator.attach(picker)
        return picker
    }

    func updateUIView(_ picker: UIPickerView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.reloadIfNeeded(picker)

        let row = selection - range.lowerBound
        guard range.contains(selection), row >= 0 else { return }
        if picker.selectedRow(inComponent: 0) != row {
            picker.selectRow(row, inComponent: 0, animated: false)
            context.coordinator.refreshRowStyles(picker)
        }
        context.coordinator.clearSystemChrome(picker)
    }

    final class Coordinator: NSObject, UIPickerViewDataSource, UIPickerViewDelegate {
        var parent: NativeAgeWheelPicker
        private let feedback = UISelectionFeedbackGenerator()
        private weak var picker: UIPickerView?

        private let slate = UIColor(red: 103 / 255, green: 108 / 255, blue: 117 / 255, alpha: 1)
        private let coolGrey = UIColor(red: 186 / 255, green: 187 / 255, blue: 190 / 255, alpha: 1)

        init(_ parent: NativeAgeWheelPicker) {
            self.parent = parent
        }

        func attach(_ picker: UIPickerView) {
            self.picker = picker
            let row = parent.selection - parent.range.lowerBound
            if parent.range.contains(parent.selection), row >= 0 {
                picker.selectRow(row, inComponent: 0, animated: false)
            }
            feedback.prepare()
            DispatchQueue.main.async { [weak self, weak picker] in
                guard let self, let picker else { return }
                self.clearSystemChrome(picker)
                self.refreshRowStyles(picker)
            }
        }

        func reloadIfNeeded(_ picker: UIPickerView) {
            if picker.numberOfRows(inComponent: 0) != values.count {
                picker.reloadAllComponents()
            }
        }

        private var values: [Int] { Array(parent.range) }

        func numberOfComponents(in pickerView: UIPickerView) -> Int { 1 }

        func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int {
            values.count
        }

        func pickerView(_ pickerView: UIPickerView, rowHeightForComponent component: Int) -> CGFloat {
            parent.rowHeight
        }

        func pickerView(
            _ pickerView: UIPickerView,
            viewForRow row: Int,
            forComponent component: Int,
            reusing view: UIView?
        ) -> UIView {
            let label = (view as? UILabel) ?? UILabel()
            label.textAlignment = .center
            label.text = "\(values[row])"
            label.adjustsFontSizeToFitWidth = false

            let distance = abs(row - pickerView.selectedRow(inComponent: 0))
            switch distance {
            case 0:
                // Selected — large white digit inside orange plate (like "18").
                label.font = .monospacedDigitSystemFont(ofSize: 72, weight: .bold)
                label.textColor = .white
                label.alpha = 1
            case 1:
                // Neighbors — medium slate (17 / 19).
                label.font = .monospacedDigitSystemFont(ofSize: 44, weight: .bold)
                label.textColor = slate
                label.alpha = 1
            default:
                // Farther — smaller light grey (16 / 20).
                label.font = .monospacedDigitSystemFont(ofSize: 30, weight: .semibold)
                label.textColor = coolGrey
                label.alpha = 1
            }
            return label
        }

        func pickerView(_ pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) {
            let value = values[row]
            if parent.selection != value {
                parent.selection = value
                feedback.selectionChanged()
                feedback.prepare()
            }
            refreshRowStyles(pickerView)
        }

        func refreshRowStyles(_ pickerView: UIPickerView) {
            pickerView.reloadAllComponents()
        }

        /// Hide the default gray selection bars so only our orange plate shows.
        func clearSystemChrome(_ pickerView: UIPickerView) {
            for subview in pickerView.subviews {
                subview.backgroundColor = .clear
                if abs(subview.bounds.height - parent.rowHeight) < 8 {
                    subview.backgroundColor = .clear
                    subview.layer.cornerRadius = 0
                    subview.layer.borderWidth = 0
                }
            }
        }
    }
}

struct ExperienceStep: View {
    @Binding var draft: FitnessAssessment
    var onAnswer: (Bool) -> Void

    var body: some View {
        VStack(spacing: 0) {
            Text("Do you have previous\nfitness experience?")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(AssessmentColor.ink)
                .multilineTextAlignment(.center)
                .padding(.top, 28)
                .padding(.horizontal, 24)

            Spacer(minLength: 12)

            Image("AssessmentExperience")
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 340)
                .frame(maxHeight: 360)
                .padding(.horizontal, 20)

            Spacer(minLength: 12)

            HStack(spacing: 12) {
                experienceButton(
                    title: "No",
                    icon: .closeX,
                    foreground: AssessmentColor.grey,
                    background: AssessmentColor.surface
                ) {
                    onAnswer(false)
                }

                experienceButton(
                    title: "Yes",
                    icon: .check,
                    foreground: AssessmentColor.white,
                    background: AssessmentColor.ink
                ) {
                    onAnswer(true)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func experienceButton(
        title: String,
        icon: SandowIcon,
        foreground: Color,
        background: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                TTIcon(icon: icon, size: 16)
            }
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

struct FitnessLevelStep: View {
    @Binding var draft: FitnessAssessment

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("How would you rate your\nfitness level?")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(AssessmentColor.ink)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.top, 24)
                .padding(.horizontal, 20)

            HStack(spacing: 8) {
                TTIcon(icon: .questionMarkCircle, size: 16)
                Text("Drag to adjust")
                    .font(.system(size: 14, weight: .medium))
            }
            .foregroundStyle(AssessmentColor.slate)
            .padding(.top, 18)
            .padding(.horizontal, 24)

            ZStack(alignment: .bottomTrailing) {
                FitnessArcSlider(value: $draft.fitnessLevel, range: 1...5)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                VStack(alignment: .trailing, spacing: 6) {
                    Text("\(draft.fitnessLevel)")
                        .font(.system(size: 92, weight: .bold))
                        .foregroundStyle(AssessmentColor.ink)
                        .contentTransition(.numericText())
                        .animation(.snappy(duration: 0.18), value: draft.fitnessLevel)
                    Text(label)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(AssessmentColor.charcoal)
                        .animation(.snappy(duration: 0.18), value: draft.fitnessLevel)
                }
                .padding(.trailing, 28)
                .padding(.bottom, 36)
                .allowsHitTesting(false)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sensoryFeedback(.selection, trigger: draft.fitnessLevel)
    }

    private var label: String {
        switch draft.fitnessLevel {
        case 1: "Just starting"
        case 2: "Getting active"
        case 3: "Somewhat Athletic"
        case 4: "Athletic"
        default: "Highly Athletic"
        }
    }
}

/// Curved fitness-level slider. Handle travels along an arc; value snaps to ticks.
struct FitnessArcSlider: View {
    @Binding var value: Int
    var range: ClosedRange<Int>

    private let trackWidth: CGFloat = 12
    private let handleSize: CGFloat = 56
    /// CG degrees (0 = right, positive clockwise). Arc runs bottom-left → top on the left side (CCW).
    private let startDeg: Double = 205
    private let endDeg: Double = 75

    @State private var liveProgress: CGFloat?
    @GestureState private var isDragging = false

    private var stepCount: Int { range.upperBound - range.lowerBound }

    private var progress: CGFloat {
        liveProgress ?? progress(for: value)
    }

    var body: some View {
        GeometryReader { geo in
            let layout = layout(in: geo.size)
            ZStack {
                arcPath(layout: layout)
                    .stroke(
                        AssessmentColor.ink,
                        style: StrokeStyle(lineWidth: trackWidth, lineCap: .round)
                    )

                arcPath(layout: layout)
                    .trim(from: 0, to: max(0.002, progress))
                    .stroke(
                        AssessmentColor.orange,
                        style: StrokeStyle(lineWidth: trackWidth, lineCap: .round)
                    )

                ForEach(0...stepCount, id: \.self) { step in
                    let p = CGFloat(step) / CGFloat(max(stepCount, 1))
                    let pt = layout.point(at: p)
                    let ang = layout.radialAngle(at: p)
                    Capsule()
                        .fill(AssessmentColor.ink)
                        .frame(width: 2.5, height: 18)
                        .rotationEffect(.radians(ang))
                        .position(pt)
                }

                handle
                    .position(layout.point(at: progress))
                    .allowsHitTesting(false)
            }
            .contentShape(Rectangle())
            .gesture(dragGesture(layout: layout))
            .padding(.leading, 4)
            .padding(.trailing, 8)
        }
    }

    private var handle: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(AssessmentColor.orange)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(AssessmentColor.white, lineWidth: 3)
                )
                .shadow(color: AssessmentColor.orange.opacity(0.35), radius: 10, y: 2)
            TTIcon(icon: .arrowRotateClockwise1, size: 22)
                .foregroundStyle(AssessmentColor.white)
        }
        .frame(width: handleSize, height: handleSize)
        .scaleEffect(isDragging ? 1.08 : 1)
        .animation(.snappy(duration: 0.18), value: isDragging)
    }

    private func dragGesture(layout: ArcLayout) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .updating($isDragging) { _, state, _ in
                state = true
            }
            .onChanged { gesture in
                let next = layout.progress(for: gesture.location)
                liveProgress = next
                let snapped = snappedValue(for: next)
                if snapped != value { value = snapped }
            }
            .onEnded { gesture in
                let next = layout.progress(for: gesture.location)
                let snapped = snappedValue(for: next)
                withAnimation(.snappy(duration: 0.22)) {
                    value = snapped
                    liveProgress = progress(for: snapped)
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    liveProgress = nil
                }
            }
    }

    private func progress(for value: Int) -> CGFloat {
        CGFloat(value - range.lowerBound) / CGFloat(max(stepCount, 1))
    }

    private func snappedValue(for progress: CGFloat) -> Int {
        let clamped = min(max(progress, 0), 1)
        let raw = range.lowerBound + Int((clamped * CGFloat(stepCount)).rounded())
        return min(max(raw, range.lowerBound), range.upperBound)
    }

    private func layout(in size: CGSize) -> ArcLayout {
        let radius = min(size.width, size.height) * 0.95
        let center = CGPoint(x: size.width * 0.82, y: size.height * 0.70)
        return ArcLayout(center: center, radius: radius, startDeg: startDeg, endDeg: endDeg)
    }

    private func arcPath(layout: ArcLayout) -> Path {
        Path { path in
            path.addArc(
                center: layout.center,
                radius: layout.radius,
                startAngle: .degrees(layout.startDeg),
                endAngle: .degrees(layout.endDeg),
                clockwise: false
            )
        }
    }
}

private struct ArcLayout {
    var center: CGPoint
    var radius: CGFloat
    /// CG degrees: 0 = right, positive clockwise (y grows down).
    var startDeg: Double
    var endDeg: Double

    func point(at progress: CGFloat) -> CGPoint {
        let t = Double(min(max(progress, 0), 1))
        let deg = startDeg + (endDeg - startDeg) * t
        let rad = deg * .pi / 180
        return CGPoint(
            x: center.x + radius * CGFloat(cos(rad)),
            y: center.y + radius * CGFloat(sin(rad))
        )
    }

    func radialAngle(at progress: CGFloat) -> CGFloat {
        let deg = startDeg + (endDeg - startDeg) * Double(min(max(progress, 0), 1))
        return CGFloat(deg * .pi / 180)
    }

    func progress(for location: CGPoint) -> CGFloat {
        let dx = location.x - center.x
        let dy = location.y - center.y
        var deg = atan2(dy, dx) * 180 / .pi
        if deg < 0 { deg += 360 }

        let sweep = ccwDelta(from: startDeg, to: endDeg)
        guard sweep > 0 else { return 0 }
        let delta = ccwDelta(from: startDeg, to: deg)
        return CGFloat(min(max(delta / sweep, 0), 1))
    }

    /// Counter-clockwise travel in CG angle space (decreasing degrees).
    private func ccwDelta(from start: Double, to end: Double) -> Double {
        var d = start - end
        while d < 0 { d += 360 }
        while d >= 360 { d -= 360 }
        return d
    }
}

struct LimitationsStep: View {
    @Binding var draft: FitnessAssessment
    @State private var draftText = ""
    @FocusState private var isFieldFocused: Bool

    private let maxTags = 10

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                Text("Do you have any physical\nlimitations?")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(AssessmentColor.ink)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 20)

                Image("AssessmentLimitations")
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 170)
                    .padding(.horizontal, 40)

                limitationsField

                HStack(alignment: .center, spacing: 10) {
                    Text("Most Common:")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(AssessmentColor.slate)

                    FlowLayout(spacing: 8) {
                        ForEach(AssessmentCatalog.commonLimitations, id: \.self) { item in
                            mostCommonChip(item)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 16)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private var limitationsField: some View {
        VStack(alignment: .leading, spacing: 12) {
            FlowLayout(spacing: 8) {
                ForEach(draft.limitations, id: \.self) { item in
                    selectedTag(item)
                }

                TextField("Type here…", text: $draftText)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(AssessmentColor.ink)
                    .focused($isFieldFocused)
                    .frame(minWidth: 90)
                    .onSubmit(commitDraftText)
            }

            HStack {
                Spacer()
                HStack(spacing: 4) {
                    TTIcon(icon: .file1, size: 14)
                    Text("\(draft.limitations.count)/\(maxTags)")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(AssessmentColor.slate)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
        .background(AssessmentColor.white)
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(AssessmentColor.orangeBorder, lineWidth: 2)
        )
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private func selectedTag(_ title: String) -> some View {
        Button {
            draft.limitations.removeAll { $0 == title }
        } label: {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AssessmentColor.orange)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(AssessmentColor.peach)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func mostCommonChip(_ title: String) -> some View {
        let selected = draft.limitations.contains(title)
        return Button {
            toggle(title)
        } label: {
            HStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                TTIcon(icon: .closeX, size: 11)
            }
            .foregroundStyle(AssessmentColor.blue)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(AssessmentColor.blueSoft)
            .clipShape(Capsule())
            .opacity(selected ? 0.55 : 1)
        }
        .buttonStyle(.plain)
    }

    private func toggle(_ title: String) {
        if draft.limitations.contains(title) {
            draft.limitations.removeAll { $0 == title }
        } else {
            add(title)
        }
    }

    private func add(_ title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard draft.limitations.count < maxTags else { return }
        guard !draft.limitations.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) else { return }
        draft.limitations.removeAll { $0 == "None" }
        draft.limitations.append(trimmed)
    }

    private func commitDraftText() {
        add(draftText)
        draftText = ""
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = computeRows(proposal: proposal, subviews: subviews)
        let width = proposal.width ?? rows.map(\.width).max() ?? 0
        let height = rows.map(\.height).reduce(0) { $0 + $1 + spacing } - (rows.isEmpty ? 0 : spacing)
        return CGSize(width: width, height: max(height, 0))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = computeRows(proposal: proposal, subviews: subviews)
        var y = bounds.minY
        var index = 0
        for row in rows {
            var x = bounds.minX
            for _ in 0..<row.count {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(
                    at: CGPoint(x: x, y: y),
                    proposal: ProposedViewSize(size)
                )
                x += size.width + spacing
                index += 1
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var count: Int
        var width: CGFloat
        var height: CGFloat
    }

    private func computeRows(proposal: ProposedViewSize, subviews: Subviews) -> [Row] {
        let maxWidth = proposal.width ?? .infinity
        var rows: [Row] = []
        var current = Row(count: 0, width: 0, height: 0)

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            let nextWidth = current.count == 0 ? size.width : current.width + spacing + size.width
            if current.count > 0, nextWidth > maxWidth {
                rows.append(current)
                current = Row(count: 1, width: size.width, height: size.height)
            } else {
                current.count += 1
                current.width = nextWidth
                current.height = max(current.height, size.height)
            }
        }
        if current.count > 0 { rows.append(current) }
        return rows
    }
}

struct DietStep: View {
    @Binding var draft: FitnessAssessment

    private let options: [(title: String, subtitle: String, icon: SandowIcon)] = [
        ("Plant Based", "Vegan", .leaf),
        ("Carbo Diet", "Bread, etc", .breadToast),
        ("Specialized", "Paleo, keto, etc", .forkKnife),
        ("Traditional", "Fruit diet", .apple)
    ]

    private let columns = [
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14)
    ]

    var body: some View {
        VStack(spacing: 0) {
            Text("Do you have a specific\ndiet preference?")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(AssessmentColor.ink)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.top, 24)
                .padding(.horizontal, 24)

            LazyVGrid(columns: columns, spacing: 14) {
                ForEach(Array(options.enumerated()), id: \.element.title) { index, item in
                    DietPreferenceCard(
                        title: item.title,
                        subtitle: item.subtitle,
                        icon: item.icon,
                        selected: draft.diet == item.title,
                        index: index
                    ) {
                        withAnimation(.spring(response: 0.52, dampingFraction: 0.86)) {
                            draft.diet = item.title
                        }
                    }
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 28)

            Spacer(minLength: 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct DietPreferenceCard: View {
    let title: String
    let subtitle: String
    let icon: SandowIcon
    let selected: Bool
    var index: Int = 0
    var action: () -> Void

    @State private var appeared = false
    @State private var glowBoost = false

    /// Soft spring — matches Carbo Diet selected card feel.
    private static let gentle = Animation.spring(response: 0.52, dampingFraction: 0.86)

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topLeading) {
                // Flat card — no nested boxes (Carbo Diet style)
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(selected ? AssessmentColor.orange : AssessmentColor.surface)

                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(selected ? AssessmentColor.white : AssessmentColor.ink)
                    Text(subtitle)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(selected ? AssessmentColor.white.opacity(0.92) : AssessmentColor.slate)
                    Spacer(minLength: 0)
                }
                .padding(18)

                TTIcon(icon: icon, filled: selected, size: 40)
                    .foregroundStyle(selected ? AssessmentColor.white : AssessmentColor.coolGrey)
                    .scaleEffect(selected ? 1.08 : 1)
                    .offset(y: selected ? -2 : 0)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(18)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 148)
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .strokeBorder(
                        selected ? AssessmentColor.orangeBorder : Color.clear,
                        lineWidth: selected ? 3 : 0
                    )
            )
            .shadow(
                color: selected
                    ? AssessmentColor.orange.opacity(glowBoost ? 0.36 : 0.18)
                    : .clear,
                radius: selected ? (glowBoost ? 18 : 10) : 0,
                y: selected ? 5 : 0
            )
            .scaleEffect(appeared ? (selected ? 1.03 : 1) : 0.90)
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 18)
        }
        .buttonStyle(AssessmentCardPressStyle())
        .animation(Self.gentle, value: selected)
        .sensoryFeedback(.selection, trigger: selected)
        .onAppear {
            withAnimation(
                .spring(response: 0.58, dampingFraction: 0.84)
                .delay(Double(index) * 0.055)
            ) {
                appeared = true
            }
            if selected { startGentleGlow() }
        }
        .onChange(of: selected) { _, isOn in
            if isOn {
                startGentleGlow()
            } else {
                withAnimation(.easeOut(duration: 0.28)) {
                    glowBoost = false
                }
            }
        }
    }

    private func startGentleGlow() {
        glowBoost = false
        withAnimation(.easeInOut(duration: 1.55).repeatForever(autoreverses: true)) {
            glowBoost = true
        }
    }
}

/// Soft press — gentle scale, no harsh snap.
struct AssessmentCardPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.94 : 1)
            .animation(.spring(response: 0.32, dampingFraction: 0.78), value: configuration.isPressed)
    }
}

struct DaysStep: View {
    @Binding var draft: FitnessAssessment

    var body: some View {
        VStack(spacing: 0) {
            Text("How many days/wk will\nyou commit?")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(AssessmentColor.ink)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.top, 24)
                .padding(.horizontal, 24)

            Spacer(minLength: 24)

            Text("\(clampedDays)x")
                .font(.system(size: 84, weight: .bold))
                .foregroundStyle(AssessmentColor.ink)
                .contentTransition(.numericText())
                .animation(.snappy(duration: 0.18), value: clampedDays)

            DaysCommitmentSlider(value: daysBinding)
                .padding(.horizontal, 28)
                .padding(.top, 28)

            (
                Text("I’m committed to exercising ")
                    .foregroundStyle(AssessmentColor.slate)
                + Text("\(clampedDays)x")
                    .foregroundStyle(AssessmentColor.ink)
                    .fontWeight(.bold)
                + Text(" weekly")
                    .foregroundStyle(AssessmentColor.slate)
            )
            .font(.system(size: 16, weight: .medium))
            .multilineTextAlignment(.center)
            .padding(.top, 20)
            .padding(.horizontal, 24)
            .animation(.snappy(duration: 0.18), value: clampedDays)

            Spacer(minLength: 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            if draft.daysPerWeek < 1 || draft.daysPerWeek > 5 {
                draft.daysPerWeek = min(max(draft.daysPerWeek, 1), 5)
            }
        }
        .sensoryFeedback(.selection, trigger: clampedDays)
    }

    private var clampedDays: Int {
        min(max(draft.daysPerWeek, 1), 5)
    }

    private var daysBinding: Binding<Int> {
        Binding(
            get: { clampedDays },
            set: { draft.daysPerWeek = min(max($0, 1), 5) }
        )
    }
}

/// Horizontal 1…5 day commitment slider with a draggable blue thumb.
struct DaysCommitmentSlider: View {
    @Binding var value: Int

    private let values = Array(1...5)
    private let thumbSize: CGFloat = 54
    private let trackHeight: CGFloat = 64

    @State private var dragX: CGFloat?
    @GestureState private var isDragging = false

    var body: some View {
        GeometryReader { geo in
            let layout = DaySliderLayout(
                width: geo.size.width,
                thumbSize: thumbSize,
                count: values.count
            )
            let thumbX = dragX ?? layout.x(for: value)

            ZStack {
                Capsule()
                    .fill(AssessmentColor.surface)
                    .frame(height: trackHeight)

                HStack(spacing: 0) {
                    ForEach(values, id: \.self) { day in
                        Text("\(day)")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(day == value ? Color.clear : AssessmentColor.coolGrey)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal, thumbSize * 0.15)
                .frame(height: trackHeight)

                Text("\(value)")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(AssessmentColor.white)
                    .frame(width: thumbSize, height: thumbSize)
                    .background(AssessmentColor.blue)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(AssessmentColor.charcoal, lineWidth: 4)
                    )
                    .background {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(AssessmentColor.blueSoft)
                            .padding(-5)
                    }
                    .shadow(color: AssessmentColor.blue.opacity(0.35), radius: 10, y: 2)
                    .scaleEffect(isDragging ? 1.06 : 1)
                    .position(x: thumbX, y: geo.size.height / 2)
                    .animation(.snappy(duration: 0.18), value: isDragging)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .updating($isDragging) { _, state, _ in state = true }
                    .onChanged { gesture in
                        let x = min(max(gesture.location.x, layout.minX), layout.maxX)
                        dragX = x
                        let next = layout.value(at: x)
                        if next != value { value = next }
                    }
                    .onEnded { gesture in
                        let x = min(max(gesture.location.x, layout.minX), layout.maxX)
                        let next = layout.value(at: x)
                        withAnimation(.snappy(duration: 0.22)) {
                            value = next
                            dragX = layout.x(for: next)
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                            dragX = nil
                        }
                    }
            )
        }
        .frame(height: trackHeight)
    }
}

struct DaySliderLayout {
    var width: CGFloat
    var thumbSize: CGFloat
    var count: Int

    var minX: CGFloat { thumbSize / 2 }
    var maxX: CGFloat { width - thumbSize / 2 }
    var usable: CGFloat { max(maxX - minX, 1) }

    func x(for value: Int) -> CGFloat {
        let index = CGFloat(max(value - 1, 0))
        return minX + usable * index / CGFloat(max(count - 1, 1))
    }

    func value(at x: CGFloat) -> Int {
        let t = (x - minX) / usable
        let raw = Int((t * CGFloat(count - 1)).rounded()) + 1
        return min(max(raw, 1), count)
    }
}

struct ExercisePrefStep: View {
    @Binding var draft: FitnessAssessment
    var body: some View {
        AssessmentQuestion("Do you have a specific Exercise Preference?", image: "OnboardingWorkouts") {
            AssessmentChipGrid(items: AssessmentCatalog.exercises, selected: $draft.exercisePreferences)
        }
    }
}

struct SupplementYesNoStep: View {
    @Binding var draft: FitnessAssessment
    var body: some View {
        AssessmentQuestion("Are you taking any supplements?") {
            HStack(spacing: 12) {
                AssessmentChoice(title: "No", selected: draft.takesSupplements == false) {
                    draft.takesSupplements = false
                }
                AssessmentChoice(title: "Yes", selected: draft.takesSupplements == true) {
                    draft.takesSupplements = true
                }
            }
        }
    }
}

struct SupplementPickStep: View {
    @Binding var draft: FitnessAssessment
    @State private var query = ""
    @State private var seeAll = false

    var body: some View {
        AssessmentQuestion("Specify Supplement") {
            Text("Please specify your supplement.")
                .font(TTFont.body(15))
                .foregroundStyle(TTColor.inkMuted)
            TextField("Search supplements...", text: $query)
                .padding(12)
                .background(TTColor.surfaceAlt)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            Text(seeAll ? "All Supplements" : "Most Common")
                .font(TTFont.caption(12))
                .foregroundStyle(TTColor.inkMuted)
            AssessmentChipGrid(items: filtered, selected: $draft.supplements)
            Button(seeAll ? "Most Common" : "See All Supplements") {
                seeAll.toggle()
            }
            .font(TTFont.caption(13))
            .foregroundStyle(TTColor.brand)
            Button("Prefer to skip, thanks!") {
                draft.takesSupplements = false
                draft.supplements = []
            }
            .font(TTFont.caption(13))
            .foregroundStyle(TTColor.inkMuted)
        }
    }

    private var filtered: [String] {
        let source = seeAll ? AssessmentCatalog.allSupplements : AssessmentCatalog.commonSupplements
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return source }
        return source.filter { $0.localizedCaseInsensitiveContains(trimmed) }
    }
}

struct CalorieStep: View {
    @Binding var draft: FitnessAssessment
    var body: some View {
        AssessmentQuestion("What’s Your Calorie Goal per day?") {
            Picker("Unit", selection: $draft.calorieUnit) {
                Text("Kcal").tag("kcal")
                Text("Joule’s").tag("kJ")
            }
            .pickerStyle(.segmented)
            Text(display)
                .font(TTFont.display(36))
            Text("calories daily")
                .font(TTFont.caption(13))
                .foregroundStyle(TTColor.inkMuted)
            Slider(
                value: Binding(
                    get: { Double(draft.calorieGoal) },
                    set: { draft.calorieGoal = Int($0) }
                ),
                in: 800...4000,
                step: 10
            )
            .tint(AssessmentColor.orange)
        }
    }

    private var display: String {
        if draft.calorieUnit == "kJ" {
            return "\(Int(Double(draft.calorieGoal) * 4.184)) kJ"
        }
        return "\(draft.calorieGoal) Kcal"
    }
}

struct SleepStep: View {
    @Binding var draft: FitnessAssessment
    var body: some View {
        AssessmentQuestion("What’s your sleep quality like?") {
            VStack(spacing: 10) {
                ForEach(AssessmentCatalog.sleepOptions, id: \.title) { item in
                    AssessmentChoice(title: item.title, subtitle: item.detail, selected: draft.sleepQuality == item.title) {
                        draft.sleepQuality = item.title
                    }
                }
            }
        }
    }
}

struct BodyScanStep: View {
    @Binding var draft: FitnessAssessment
    @State private var showCamera = false
    @State private var image: UIImage?

    var body: some View {
        AssessmentQuestion("Body Analysis", image: "OnboardingCoach") {
            Text("We’ll now scan your body for a better assessment result. Ensure the following:")
                .font(TTFont.body(15))
                .foregroundStyle(TTColor.inkMuted)
            checklist("720p Camera", icon: .camera1)
            checklist("Stay Still", icon: .user)
            checklist("Good Lighting", icon: .sun)
            if image != nil {
                Label("Scan captured", systemImage: "checkmark.circle.fill")
                    .font(TTFont.heading(14))
                    .foregroundStyle(TTColor.success)
            }
            Button("Open camera") { showCamera = true }
                .font(TTFont.heading(15))
                .foregroundStyle(TTColor.brand)
        }
        .sheet(isPresented: $showCamera) {
            CameraImagePicker(image: $image)
                .ignoresSafeArea()
        }
        .onChange(of: image) { _, newValue in
            draft.bodyScanCaptured = newValue != nil
        }
    }

    private func checklist(_ title: String, icon: SandowIcon) -> some View {
        HStack(spacing: 12) {
            TTIcon(icon: icon, size: 20)
            Text(title).font(TTFont.heading(15))
            Spacer()
        }
        .padding(14)
        .background(TTColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct VoiceStep: View {
    @Binding var draft: FitnessAssessment
    @State private var recorder = AssessmentVoiceRecorder()

    var body: some View {
        AssessmentQuestion("AI Vocal Analysis", image: "OnboardingMetrics") {
            Text("Your voice is connected to your health. Say the following for better assessment.")
                .font(TTFont.body(15))
                .foregroundStyle(TTColor.inkMuted)
            Text("If there’s no pain, then there’s always no gain.")
                .font(TTFont.title(20))
                .multilineTextAlignment(.center)
            Button {
                Task { await toggle() }
            } label: {
                HStack {
                    TTIcon(icon: recorder.isRecording ? .microphoneSlash : .microphone, size: 20)
                    Text(recorder.isRecording ? "Stop" : "Use voice")
                        .font(TTFont.heading(16))
                }
                .foregroundStyle(TTColor.brand)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(TTColor.brandSoft)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            if draft.voiceCaptured {
                Text("Voice captured")
                    .font(TTFont.caption(13))
                    .foregroundStyle(TTColor.success)
            }
        }
    }

    private func toggle() async {
        if recorder.isRecording {
            recorder.stop()
            draft.voiceCaptured = true
        } else {
            do {
                try await recorder.start()
            } catch {
                draft.voiceCaptured = false
            }
        }
    }
}

struct TextAnalysisStep: View {
    @Binding var draft: FitnessAssessment
    var body: some View {
        AssessmentQuestion("AI Textual Analysis") {
            Text("Freely write down any fitness concerns on your mind. TacTech AI will listen. 👍")
                .font(TTFont.body(15))
                .foregroundStyle(TTColor.inkMuted)
            AssessmentTextBox(
                text: $draft.concerns,
                placeholder: "I can’t do more than 22 squats. Also my elbow can’t bend above 24°. Is this fine, coach?"
            )
        }
    }
}

struct AssessmentQuestion<Content: View>: View {
    let title: String
    var image: String?
    var centered: Bool
    @ViewBuilder var content: Content

    init(_ title: String, image: String? = nil, centered: Bool = false, @ViewBuilder content: () -> Content) {
        self.title = title
        self.image = image
        self.centered = centered
        self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: centered ? .center : .leading, spacing: 22) {
                if let image {
                    Image(image)
                        .resizable()
                        .scaledToFill()
                        .frame(height: 140)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
                Text(title)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(AssessmentColor.ink)
                    .multilineTextAlignment(centered ? .center : .leading)
                    .frame(maxWidth: .infinity, alignment: centered ? .center : .leading)
                content
            }
            .padding(.horizontal, 22)
            .padding(.top, 12)
            .padding(.bottom, 20)
        }
    }
}

struct AssessmentChoice: View {
    let title: String
    var subtitle: String?
    var icon: SandowIcon?
    var selected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                if let icon {
                    TTIcon(icon: icon, size: 22)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 16, weight: .semibold))
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(selected ? AssessmentColor.white.opacity(0.85) : AssessmentColor.grey)
                    }
                }
                Spacer(minLength: 8)
                AssessmentRadio(selected: selected, onDark: true)
            }
            .foregroundStyle(selected ? AssessmentColor.white : AssessmentColor.ink)
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .background(selected ? AssessmentColor.orange : AssessmentColor.surface)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

struct AssessmentRadio: View {
    var selected: Bool
    var onDark: Bool = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(onDark && selected ? AssessmentColor.white : AssessmentColor.line, lineWidth: 1.6)
            if selected {
                Circle()
                    .fill(onDark ? AssessmentColor.white : AssessmentColor.orange)
                    .padding(5)
            }
        }
        .frame(width: 22, height: 22)
    }
}

struct AssessmentUnitToggle: View {
    @Binding var selection: String
    var left: (title: String, value: String)
    var right: (title: String, value: String)

    var body: some View {
        HStack(spacing: 0) {
            tab(left)
            tab(right)
        }
        .padding(3)
        .background(AssessmentColor.surface)
        .clipShape(Capsule())
    }

    private func tab(_ item: (title: String, value: String)) -> some View {
        Button {
            selection = item.value
        } label: {
            Text(item.title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(selection == item.value ? AssessmentColor.white : AssessmentColor.slate)
                .frame(width: 72, height: 34)
                .background(selection == item.value ? AssessmentColor.blue : Color.clear)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

struct AssessmentRuler: View {
    @Binding var value: Double
    var range: ClosedRange<Double>
    var step: Double = 1

    private let slotWidth: CGFloat = 9
    private let indicator = AssessmentColor.orange

    @State private var scrollID: Int?

    var body: some View {
        GeometryReader { geo in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(tickIndexes, id: \.self) { index in
                        let tick = range.lowerBound + Double(index) * step
                        VStack(spacing: 8) {
                            Capsule()
                                .fill(AssessmentColor.line)
                                .frame(width: strokeWidth(for: tick), height: tickHeight(for: tick))
                            Text(label(for: tick))
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(AssessmentColor.grey)
                                .frame(height: 16)
                        }
                        .frame(width: slotWidth, height: 72, alignment: .top)
                        .id(key(tick))
                    }
                }
                .scrollTargetLayout()
                .padding(.horizontal, geo.size.width / 2 - slotWidth / 2)
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $scrollID)
            .onAppear { scrollID = key(clamped(value)) }
            .onChange(of: scrollID) { _, newValue in
                guard let newValue else { return }
                let next = Double(newValue) * step
                if abs(next - value) > 0.001 { value = next }
            }
            .onChange(of: value) { _, newValue in
                let next = key(clamped(newValue))
                if scrollID != next { scrollID = next }
            }
            .overlay(alignment: .top) {
                Capsule()
                    .fill(indicator)
                    .frame(width: 5, height: 44)
                    .shadow(color: indicator.opacity(0.55), radius: 8)
                    .padding(.top, 0)
                    .allowsHitTesting(false)
            }
        }
        .frame(height: 80)
        .sensoryFeedback(.selection, trigger: scrollID)
    }

    private var tickIndexes: Range<Int> {
        let count = Int(((range.upperBound - range.lowerBound) / step).rounded()) + 1
        return 0..<max(count, 1)
    }

    private func clamped(_ raw: Double) -> Double {
        min(max(raw, range.lowerBound), range.upperBound)
    }

    private func key(_ tick: Double) -> Int {
        Int((tick / step).rounded())
    }

    private func tenths(_ tick: Double) -> Int {
        Int((tick * 10).rounded()) % 10
    }

    private func tickHeight(for tick: Double) -> CGFloat {
        switch tenths(tick) {
        case 0: 36
        case 5: 24
        default: 14
        }
    }

    private func strokeWidth(for tick: Double) -> CGFloat {
        tenths(tick) == 0 ? 2.2 : 1.4
    }

    private func label(for tick: Double) -> String {
        tenths(tick) == 0 ? "\(Int(tick.rounded()))" : ""
    }
}

private extension Double {
    func rounded(to places: Int) -> Double {
        let factor = pow(10.0, Double(places))
        return (self * factor).rounded() / factor
    }
}

struct AssessmentChipGrid: View {
    let items: [String]
    @Binding var selected: [String]

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 8)], spacing: 8) {
            ForEach(items, id: \.self) { item in
                let on = selected.contains(item)
                Button {
                    if item == "None" {
                        selected = ["None"]
                    } else {
                        selected.removeAll { $0 == "None" }
                        if on { selected.removeAll { $0 == item } } else { selected.append(item) }
                    }
                } label: {
                    Text(item)
                        .font(TTFont.caption(13))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity)
                        .foregroundStyle(on ? AssessmentColor.white : AssessmentColor.ink)
                        .background(on ? AssessmentColor.orange : AssessmentColor.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

@MainActor
@Observable
final class AssessmentVoiceRecorder {
    private var recorder: AVAudioRecorder?
    var isRecording = false

    func start() async throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default)
        try session.setActive(true)
        if session.recordPermission == .denied {
            throw AppError.validation("Microphone permission is required.")
        }
        if session.recordPermission == .undetermined {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                session.requestRecordPermission { allowed in
                    if allowed { cont.resume() } else {
                        cont.resume(throwing: AppError.validation("Microphone permission is required."))
                    }
                }
            }
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("tactech-assessment.m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        recorder = try AVAudioRecorder(url: url, settings: settings)
        recorder?.record()
        isRecording = true
    }

    func stop() {
        recorder?.stop()
        isRecording = false
    }
}
