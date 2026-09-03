import SwiftUI

// MARK: - Flow

struct TrainerAssessmentFlowView: View {
    @Environment(AppStore.self) private var store
    @State private var step = 0
    @State private var draft = TrainerAssessment()
    @State private var isSaving = false
    @State private var error: String?
    @State private var capacitySlider = 2

    private let total = 12

    var body: some View {
        VStack(spacing: 0) {
            header
            Group {
                switch step {
                case 0: TrainerFocusStep(draft: $draft)
                case 1: TrainerYearsStep(draft: $draft)
                case 2: TrainerCertificationsStep(draft: $draft)
                case 3: TrainerSpecialtyStep(draft: $draft)
                case 4: TrainerClientTypesStep(draft: $draft)
                case 5: TrainerCapacityStep(draft: $draft, slider: $capacitySlider)
                case 6: TrainerSessionStyleStep(draft: $draft)
                case 7: TrainerDaysStep(draft: $draft)
                case 8: TrainerModesStep(draft: $draft)
                case 9: TrainerGenderStep(draft: $draft, onSkip: skipGender)
                case 10: TrainerBioStep(draft: $draft)
                default: TrainerPhilosophyStep(draft: $draft)
                }
            }
            .animation(.easeInOut(duration: 0.25), value: step)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if let error {
                Text(error)
                    .font(TTFont.caption(13))
                    .foregroundStyle(TTColor.danger)
                    .padding(.horizontal, 24)
            }

            Button(action: advance) {
                HStack(spacing: 8) {
                    if isSaving { ProgressView().tint(.white) }
                    Text(step == total - 1 ? "Finish" : "Continue")
                        .font(.system(size: 17, weight: .semibold))
                    Image("OnboardingArrowRight")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 16, height: 16)
                }
                .foregroundStyle(AssessmentColor.white)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(canContinue ? AssessmentColor.ink : AssessmentColor.ink.opacity(0.35))
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            }
            .disabled(!canContinue || isSaving)
            .padding(.horizontal, 24)
            .padding(.bottom, 12)
        }
        .background(AssessmentColor.white.ignoresSafeArea())
        .safeAreaPadding(.top)
        .safeAreaPadding(.bottom)
        .onAppear {
            capacitySlider = TrainerAssessmentCatalog.capacityIndex(for: draft.maxClients)
        }
    }

    private var header: some View {
        ZStack {
            Text("Assessment")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(AssessmentColor.ink)

            HStack {
                if step > 0 {
                    TTBackButton { step -= 1 }
                } else {
                    Color.clear.frame(width: TTBackButton.size, height: TTBackButton.size)
                }

                Spacer()

                Text("\(step + 1) of \(total)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AssessmentColor.blue)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(AssessmentColor.blueSoft)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 6)
        .padding(.bottom, 8)
    }

    private var canContinue: Bool {
        switch step {
        case 0: !draft.coachingFocus.isEmpty
        case 2: !draft.certifications.isEmpty
        case 3: !draft.specialty.isEmpty
        case 4: !draft.clientTypes.isEmpty
        case 6: !draft.sessionStyle.isEmpty
        case 8: !draft.trainingModes.isEmpty
        // Bio & philosophy stay optional — Continue always enabled.
        default: true
        }
    }

    private func skipGender() {
        draft.gender = ""
        withAnimation(.easeInOut(duration: 0.25)) { step = 10 }
    }

    private func advance() {
        if step < total - 1 {
            withAnimation(.easeInOut(duration: 0.25)) { step += 1 }
            return
        }
        Task { await save() }
    }

    private func save() async {
        isSaving = true
        error = nil
        defer { isSaving = false }
        do {
            try await store.submitTrainerAssessment(draft)
        } catch {
            store.persistTrainerAssessment(draft)
            store.markAssessmentCompleted()
            self.error = error.localizedDescription
        }
    }
}

// MARK: - Steps

struct TrainerFocusStep: View {
    @Binding var draft: TrainerAssessment

    private let columns = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]

    private let options: [(title: String, subtitle: String, icon: SandowIcon)] = [
        ("Strength", "Power & lifts", .barbellHorizontal),
        ("Fat Loss", "Body recomposition", .weightScale),
        ("Hypertrophy", "Muscle building", .trophy1),
        ("Endurance", "Conditioning", .heartEcg),
        ("Rehab", "Return to train", .bandaid),
        ("General Fitness", "All-round coaching", .whistle)
    ]

    var body: some View {
        VStack(spacing: 0) {
            title("What’s your coaching focus?")
            LazyVGrid(columns: columns, spacing: 14) {
                ForEach(Array(options.enumerated()), id: \.element.title) { index, item in
                    DietPreferenceCard(
                        title: item.title,
                        subtitle: item.subtitle,
                        icon: item.icon,
                        selected: draft.coachingFocus == item.title,
                        index: index
                    ) {
                        withAnimation(.spring(response: 0.52, dampingFraction: 0.86)) {
                            draft.coachingFocus = item.title
                        }
                    }
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 24)
            .padding(.bottom, 8)
            Spacer(minLength: 8)
        }
    }
}

struct TrainerYearsStep: View {
    @Binding var draft: TrainerAssessment

    var body: some View {
        VStack(spacing: 0) {
            title("How many years have you\nbeen coaching?")
            AssessmentAgeWheel(selection: $draft.yearsExperience, range: 0...30)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Text(draft.yearsExperience == 0 ? "Just getting started" : "\(draft.yearsExperience) years experience")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(AssessmentColor.slate)
                .contentTransition(.numericText())
                .animation(.easeInOut(duration: 0.15), value: draft.yearsExperience)
                .padding(.bottom, 12)
        }
    }
}

struct TrainerCertificationsStep: View {
    @Binding var draft: TrainerAssessment

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    private let options: [(title: String, subtitle: String, icon: SandowIcon)] = [
        ("CSCS", "Strength & conditioning", .trophy1),
        ("NASM", "Personal training", .academicCap),
        ("ACE", "Fitness professional", .medal),
        ("ISSA", "Certified trainer", .starFull),
        ("CrossFit L1", "Functional fitness", .barbellHorizontal),
        ("Precision Nutrition", "Nutrition coaching", .apple),
        ("None", "No certification yet", .closeX),
        ("Other", "Something else", .starFour)
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                title("Any certifications?")
                    .padding(.top, 20)

                Text("Select all that apply")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(AssessmentColor.slate)

                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(Array(options.enumerated()), id: \.element.title) { index, item in
                        let on = draft.certifications.contains(item.title)
                        CertificationPickCard(
                            title: item.title,
                            subtitle: item.subtitle,
                            icon: item.icon,
                            selected: on,
                            index: index
                        ) {
                            toggle(item.title)
                        }
                    }
                }
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 16)
        }
    }

    private func toggle(_ item: String) {
        withAnimation(.spring(response: 0.42, dampingFraction: 0.84)) {
            if item == "None" {
                draft.certifications = ["None"]
            } else {
                draft.certifications.removeAll { $0 == "None" }
                if draft.certifications.contains(item) {
                    draft.certifications.removeAll { $0 == item }
                } else {
                    draft.certifications.append(item)
                }
            }
        }
    }
}

private struct CertificationPickCard: View {
    let title: String
    let subtitle: String
    let icon: SandowIcon
    let selected: Bool
    var index: Int = 0
    var action: () -> Void

    @State private var appeared = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(selected ? AssessmentColor.white.opacity(0.22) : AssessmentColor.white)
                        TTIcon(icon: icon, filled: selected, size: 22)
                            .foregroundStyle(selected ? AssessmentColor.white : AssessmentColor.orange)
                    }
                    .frame(width: 44, height: 44)

                    Spacer(minLength: 8)

                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(selected ? AssessmentColor.white : AssessmentColor.coolGrey)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(selected ? AssessmentColor.white : AssessmentColor.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    Text(subtitle)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(selected ? AssessmentColor.white.opacity(0.9) : AssessmentColor.slate)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 128, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(selected ? AssessmentColor.orange : AssessmentColor.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(
                        selected ? AssessmentColor.orangeBorder : Color.clear,
                        lineWidth: selected ? 2.5 : 0
                    )
            )
            .shadow(
                color: selected ? AssessmentColor.orange.opacity(0.28) : .clear,
                radius: selected ? 12 : 0,
                y: selected ? 5 : 0
            )
            .scaleEffect(appeared ? (selected ? 1.02 : 1) : 0.94)
            .opacity(appeared ? 1 : 0)
        }
        .buttonStyle(AssessmentCardPressStyle())
        .animation(.spring(response: 0.42, dampingFraction: 0.84), value: selected)
        .sensoryFeedback(.selection, trigger: selected)
        .onAppear {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.84).delay(Double(index) * 0.04)) {
                appeared = true
            }
        }
    }
}

struct TrainerSpecialtyStep: View {
    @Binding var draft: TrainerAssessment

    private let options: [(title: String, subtitle: String, icon: SandowIcon)] = [
        ("Powerlifting", "Max strength & competition lifts", .barbellHorizontal),
        ("Bodybuilding", "Physique & hypertrophy focus", .trophy1),
        ("CrossFit", "Mixed modal conditioning", .target1),
        ("Sports Performance", "Athletic speed & power", .whistle),
        ("Senior Fitness", "Safe training for active aging", .user),
        ("Youth Athletes", "Developing young athletes", .usersTwo),
        ("Online Coaching", "Remote plans & check-ins", .laptopMobile),
        ("General PT", "All-round personal training", .starFull)
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                title("What’s your specialty?")
                    .padding(.top, 20)

                Text("Pick the one that fits you best")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(AssessmentColor.slate)

                VStack(spacing: 10) {
                    ForEach(Array(options.enumerated()), id: \.element.title) { index, item in
                        SpecialtyPickRow(
                            title: item.title,
                            subtitle: item.subtitle,
                            icon: item.icon,
                            selected: draft.specialty == item.title,
                            index: index
                        ) {
                            withAnimation(.spring(response: 0.42, dampingFraction: 0.84)) {
                                draft.specialty = item.title
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 16)
        }
    }
}

private struct SpecialtyPickRow: View {
    let title: String
    let subtitle: String
    let icon: SandowIcon
    let selected: Bool
    var index: Int = 0
    var action: () -> Void

    @State private var appeared = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(selected ? AssessmentColor.white.opacity(0.22) : AssessmentColor.white)
                    TTIcon(icon: icon, filled: selected, size: 22)
                        .foregroundStyle(selected ? AssessmentColor.white : AssessmentColor.orange)
                }
                .frame(width: 48, height: 48)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(selected ? AssessmentColor.white : AssessmentColor.ink)
                    Text(subtitle)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(selected ? AssessmentColor.white.opacity(0.88) : AssessmentColor.slate)
                        .lineLimit(2)
                }

                Spacer(minLength: 8)

                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(selected ? AssessmentColor.white : AssessmentColor.coolGrey)
                    .symbolEffect(.bounce, value: selected)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(selected ? AssessmentColor.orange : AssessmentColor.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(
                        selected ? AssessmentColor.orangeBorder : Color.clear,
                        lineWidth: selected ? 2.5 : 0
                    )
            )
            .shadow(
                color: selected ? AssessmentColor.orange.opacity(0.26) : .clear,
                radius: selected ? 12 : 0,
                y: selected ? 5 : 0
            )
            .scaleEffect(appeared ? (selected ? 1.015 : 1) : 0.96)
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 10)
        }
        .buttonStyle(AssessmentCardPressStyle())
        .animation(.spring(response: 0.42, dampingFraction: 0.84), value: selected)
        .sensoryFeedback(.selection, trigger: selected)
        .onAppear {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.84).delay(Double(index) * 0.045)) {
                appeared = true
            }
        }
    }
}

struct TrainerClientTypesStep: View {
    @Binding var draft: TrainerAssessment

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    private let options: [(title: String, subtitle: String, icon: SandowIcon)] = [
        ("Beginners", "New to training", .userPlus),
        ("Intermediate", "Building consistency", .userCheck),
        ("Advanced Athletes", "High-level performance", .trophy1),
        ("Online Clients", "Remote coaching", .laptopMobile),
        ("In-person Clients", "Gym & studio sessions", .usersTwo)
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                title("Who do you typically coach?")
                    .padding(.top, 20)

                Text("Select all that apply")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(AssessmentColor.slate)

                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(Array(options.enumerated()), id: \.element.title) { index, item in
                        let on = draft.clientTypes.contains(item.title)
                        ClientTypePickCard(
                            title: item.title,
                            subtitle: item.subtitle,
                            icon: item.icon,
                            selected: on,
                            index: index
                        ) {
                            toggle(item.title)
                        }
                    }
                }
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 16)
        }
    }

    private func toggle(_ item: String) {
        withAnimation(.spring(response: 0.42, dampingFraction: 0.84)) {
            if draft.clientTypes.contains(item) {
                draft.clientTypes.removeAll { $0 == item }
            } else {
                draft.clientTypes.append(item)
            }
        }
    }
}

private struct ClientTypePickCard: View {
    let title: String
    let subtitle: String
    let icon: SandowIcon
    let selected: Bool
    var index: Int = 0
    var action: () -> Void

    @State private var appeared = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(selected ? AssessmentColor.white.opacity(0.22) : AssessmentColor.white)
                        TTIcon(icon: icon, filled: selected, size: 22)
                            .foregroundStyle(selected ? AssessmentColor.white : AssessmentColor.orange)
                    }
                    .frame(width: 44, height: 44)

                    Spacer(minLength: 8)

                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(selected ? AssessmentColor.white : AssessmentColor.coolGrey)
                        .symbolEffect(.bounce, value: selected)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(selected ? AssessmentColor.white : AssessmentColor.ink)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                    Text(subtitle)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(selected ? AssessmentColor.white.opacity(0.9) : AssessmentColor.slate)
                        .lineLimit(2)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 128, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(selected ? AssessmentColor.orange : AssessmentColor.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(
                        selected ? AssessmentColor.orangeBorder : Color.clear,
                        lineWidth: selected ? 2.5 : 0
                    )
            )
            .shadow(
                color: selected ? AssessmentColor.orange.opacity(0.28) : .clear,
                radius: selected ? 12 : 0,
                y: selected ? 5 : 0
            )
            .scaleEffect(appeared ? (selected ? 1.02 : 1) : 0.94)
            .opacity(appeared ? 1 : 0)
        }
        .buttonStyle(AssessmentCardPressStyle())
        .animation(.spring(response: 0.42, dampingFraction: 0.84), value: selected)
        .sensoryFeedback(.selection, trigger: selected)
        .onAppear {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.84).delay(Double(index) * 0.04)) {
                appeared = true
            }
        }
    }
}

struct TrainerCapacityStep: View {
    @Binding var draft: TrainerAssessment
    @Binding var slider: Int

    private let presets = TrainerAssessmentCatalog.capacityOptions
    @State private var isCustom = false

    var body: some View {
        VStack(spacing: 0) {
            title("How many clients can you\nmanage at once?")
            Spacer(minLength: 16)

            Text("\(draft.maxClients)")
                .font(.system(size: 84, weight: .bold))
                .foregroundStyle(AssessmentColor.ink)
                .monospacedDigit()
                .contentTransition(.numericText())
                .animation(.spring(response: 0.38, dampingFraction: 0.86), value: draft.maxClients)

            Text("active clients")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(AssessmentColor.slate)

            CapacityClientsPicker(
                selection: capacityBinding,
                isCustom: $isCustom
            )
            .padding(.horizontal, 18)
            .padding(.top, 24)

            if isCustom {
                CapacityCustomStepper(value: capacityBinding)
                    .padding(.horizontal, 28)
                    .padding(.top, 18)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            Text("I’m set up to coach \(draft.maxClients) clients")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(AssessmentColor.slate)
                .contentTransition(.numericText())
                .animation(.easeInOut(duration: 0.15), value: draft.maxClients)
                .padding(.top, 20)

            Spacer(minLength: 16)
        }
        .onAppear {
            isCustom = !presets.contains(draft.maxClients)
            if presets.contains(draft.maxClients) {
                slider = TrainerAssessmentCatalog.capacityIndex(for: draft.maxClients)
            }
        }
        .animation(.spring(response: 0.42, dampingFraction: 0.86), value: isCustom)
        .sensoryFeedback(.selection, trigger: draft.maxClients)
    }

    private var capacityBinding: Binding<Int> {
        Binding(
            get: { draft.maxClients },
            set: { newValue in
                let clamped = min(max(newValue, 1), 200)
                draft.maxClients = clamped
                if presets.contains(clamped) && !isCustom {
                    slider = TrainerAssessmentCatalog.capacityIndex(for: clamped)
                }
            }
        )
    }
}

/// Preset chips + Custom — for capacities beyond 30.
private struct CapacityClientsPicker: View {
    @Binding var selection: Int
    @Binding var isCustom: Bool
    private let options = TrainerAssessmentCatalog.capacityOptions

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                ForEach(options, id: \.self) { count in
                    capacityChip(
                        label: "\(count)",
                        selected: !isCustom && selection == count
                    ) {
                        withAnimation(.spring(response: 0.42, dampingFraction: 0.84)) {
                            isCustom = false
                            selection = count
                        }
                    }
                }
            }

            Button {
                withAnimation(.spring(response: 0.42, dampingFraction: 0.84)) {
                    isCustom = true
                    if options.contains(selection) {
                        // Start custom just above the top preset.
                        selection = max(selection, 35)
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 15, weight: .semibold))
                    Text(isCustom ? "Custom · \(selection)" : "Custom")
                        .font(.system(size: 16, weight: .bold))
                    if !isCustom {
                        Text("30+")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(AssessmentColor.orange)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(AssessmentColor.peach)
                            .clipShape(Capsule())
                    }
                }
                .foregroundStyle(isCustom ? AssessmentColor.white : AssessmentColor.ink)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(isCustom ? AssessmentColor.orange : AssessmentColor.surface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(
                            isCustom ? AssessmentColor.orangeBorder : Color.clear,
                            lineWidth: isCustom ? 2.5 : 0
                        )
                )
                .shadow(
                    color: isCustom ? AssessmentColor.orange.opacity(0.28) : .clear,
                    radius: isCustom ? 10 : 0,
                    y: isCustom ? 4 : 0
                )
            }
            .buttonStyle(AssessmentCardPressStyle())
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(AssessmentColor.surface.opacity(0.65))
        )
        .animation(.spring(response: 0.42, dampingFraction: 0.84), value: selection)
        .animation(.spring(response: 0.42, dampingFraction: 0.84), value: isCustom)
    }

    private func capacityChip(label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 17, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(selected ? AssessmentColor.white : AssessmentColor.ink)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(selected ? AssessmentColor.orange : AssessmentColor.surface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(
                            selected ? AssessmentColor.orangeBorder : Color.clear,
                            lineWidth: selected ? 2.5 : 0
                        )
                )
                .shadow(
                    color: selected ? AssessmentColor.orange.opacity(0.28) : .clear,
                    radius: selected ? 10 : 0,
                    y: selected ? 4 : 0
                )
                .scaleEffect(selected ? 1.04 : 1)
        }
        .buttonStyle(AssessmentCardPressStyle())
    }
}

private struct CapacityCustomStepper: View {
    @Binding var value: Int

    var body: some View {
        HStack(spacing: 18) {
            stepButton(systemName: "minus") {
                value = max(1, value - 1)
            }

            Text("\(value)")
                .font(.system(size: 28, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(AssessmentColor.ink)
                .frame(minWidth: 72)
                .contentTransition(.numericText())

            stepButton(systemName: "plus") {
                value = min(200, value + 1)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(AssessmentColor.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(AssessmentColor.orangeBorder, lineWidth: 2)
        )
    }

    private func stepButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.84)) {
                action()
            }
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(AssessmentColor.white)
                .frame(width: 44, height: 44)
                .background(AssessmentColor.orange)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(AssessmentCardPressStyle())
    }
}

struct TrainerSessionStyleStep: View {
    @Binding var draft: TrainerAssessment

    private let columns = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]
    private let icons: [SandowIcon] = [.user, .usersTwo, .laptopMobile, .briefcase]

    var body: some View {
        VStack(spacing: 0) {
            title("What’s your session style?")
            LazyVGrid(columns: columns, spacing: 14) {
                ForEach(Array(TrainerAssessmentCatalog.sessionStyles.enumerated()), id: \.element.title) { index, item in
                    DietPreferenceCard(
                        title: item.title,
                        subtitle: item.subtitle,
                        icon: icons[index % icons.count],
                        selected: draft.sessionStyle == item.title,
                        index: index
                    ) {
                        withAnimation(.spring(response: 0.52, dampingFraction: 0.86)) {
                            draft.sessionStyle = item.title
                        }
                    }
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 24)
            Spacer(minLength: 12)
        }
    }
}

struct TrainerDaysStep: View {
    @Binding var draft: TrainerAssessment

    var body: some View {
        VStack(spacing: 0) {
            title("How many days per week\ncan you coach?")

            Text("This is weekly — not monthly")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(AssessmentColor.slate)
                .padding(.top, 8)

            Spacer(minLength: 20)

            Text("\(clamped)")
                .font(.system(size: 84, weight: .bold))
                .foregroundStyle(AssessmentColor.ink)
                .monospacedDigit()
                .contentTransition(.numericText())
                .animation(.spring(response: 0.38, dampingFraction: 0.86), value: clamped)

            Text(clamped == 1 ? "day every week" : "days every week")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(AssessmentColor.slate)
                .animation(.easeInOut(duration: 0.15), value: clamped)

            // Tap or drag across 1…7.
            DaysPerWeekDragSlider(value: daysBinding)
                .padding(.horizontal, 22)
                .padding(.top, 28)

            (
                Text("I’m available ")
                    .foregroundStyle(AssessmentColor.slate)
                + Text("\(clamped) \(clamped == 1 ? "day" : "days")")
                    .foregroundStyle(AssessmentColor.ink)
                    .fontWeight(.bold)
                + Text(" every week")
                    .foregroundStyle(AssessmentColor.slate)
            )
            .font(.system(size: 16, weight: .medium))
            .padding(.top, 20)

            Spacer(minLength: 20)
        }
        .onAppear {
            draft.daysPerWeek = min(max(draft.daysPerWeek, 1), 7)
        }
        .sensoryFeedback(.selection, trigger: clamped)
    }

    private var clamped: Int { min(max(draft.daysPerWeek, 1), 7) }

    private var daysBinding: Binding<Int> {
        Binding(
            get: { clamped },
            set: { draft.daysPerWeek = min(max($0, 1), 7) }
        )
    }
}

/// Orange days slider — tap a number or drag the thumb across 1…7.
private struct DaysPerWeekDragSlider: View {
    @Binding var value: Int

    private let values = Array(1...7)
    private let thumbSize: CGFloat = 52
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
                            .font(.system(size: 16, weight: .bold))
                            .monospacedDigit()
                            .foregroundStyle(day == value ? Color.clear : AssessmentColor.coolGrey)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal, thumbSize * 0.12)
                .frame(height: trackHeight)

                Text("\(value)")
                    .font(.system(size: 22, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(AssessmentColor.white)
                    .frame(width: thumbSize, height: thumbSize)
                    .background(AssessmentColor.orange)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(AssessmentColor.orangeBorder, lineWidth: 2.5)
                    )
                    .shadow(color: AssessmentColor.orange.opacity(0.35), radius: 10, y: 2)
                    .scaleEffect(isDragging ? 1.08 : 1)
                    .position(x: thumbX, y: geo.size.height / 2)
                    .animation(.spring(response: 0.32, dampingFraction: 0.82), value: isDragging)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .updating($isDragging) { _, state, _ in state = true }
                    .onChanged { gesture in
                        let x = min(max(gesture.location.x, layout.minX), layout.maxX)
                        dragX = x
                        let next = layout.value(at: x)
                        if next != value {
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                                value = next
                            }
                        }
                    }
                    .onEnded { gesture in
                        let x = min(max(gesture.location.x, layout.minX), layout.maxX)
                        let next = layout.value(at: x)
                        withAnimation(.spring(response: 0.38, dampingFraction: 0.84)) {
                            value = next
                            dragX = layout.x(for: next)
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
                            dragX = nil
                        }
                    }
            )
        }
        .frame(height: trackHeight)
    }
}

struct TrainerModesStep: View {
    @Binding var draft: TrainerAssessment

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    private let options: [(title: String, subtitle: String, icon: SandowIcon)] = [
        ("Commercial Gym", "Full equipment access", .building2),
        ("Home Gym", "Train at home setups", .house1),
        ("Outdoor", "Parks & open air", .tree),
        ("Online Only", "Remote video coaching", .laptopMobile)
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                title("Where do you train clients?")
                    .padding(.top, 20)

                Text("Select all that apply")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(AssessmentColor.slate)

                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(Array(options.enumerated()), id: \.element.title) { index, item in
                        let on = draft.trainingModes.contains(item.title)
                        ClientTypePickCard(
                            title: item.title,
                            subtitle: item.subtitle,
                            icon: item.icon,
                            selected: on,
                            index: index
                        ) {
                            toggle(item.title)
                        }
                    }
                }
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 16)
        }
    }

    private func toggle(_ item: String) {
        withAnimation(.spring(response: 0.42, dampingFraction: 0.84)) {
            if draft.trainingModes.contains(item) {
                draft.trainingModes.removeAll { $0 == item }
            } else {
                draft.trainingModes.append(item)
            }
        }
    }
}

struct TrainerGenderStep: View {
    @Binding var draft: TrainerAssessment
    var onSkip: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            title("What is your gender?")
            HStack(spacing: 12) {
                genderCard("Male", icon: .genderMale)
                genderCard("Female", icon: .genderFemale)
            }
            .padding(.horizontal, 22)
            .padding(.top, 28)

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
            .padding(.horizontal, 22)
            .padding(.top, 16)
            Spacer()
        }
    }

    private func genderCard(_ title: String, icon: SandowIcon) -> some View {
        let selected = draft.gender == title
        return Button {
            draft.gender = title
        } label: {
            VStack(spacing: 12) {
                TTIcon(icon: icon, size: 32)
                Text(title).font(.system(size: 17, weight: .bold))
            }
            .foregroundStyle(selected ? AssessmentColor.white : AssessmentColor.ink)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 32)
            .background(selected ? AssessmentColor.orange : AssessmentColor.surface)
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(selected ? AssessmentColor.orangeBorder : Color.clear, lineWidth: selected ? 3 : 0)
            )
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

struct TrainerBioStep: View {
    @Binding var draft: TrainerAssessment

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            title("Tell trainees about yourself")
            Text("A short bio helps clients trust your coaching.")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(AssessmentColor.slate)
                .frame(maxWidth: .infinity, alignment: .center)

            AssessmentTextBox(
                text: $draft.bio,
                placeholder: "Ex-athlete turned coach. I build simple, sustainable strength plans…"
            )
            Spacer(minLength: 8)
        }
        .padding(.horizontal, 22)
        .padding(.top, 8)
    }
}

struct TrainerPhilosophyStep: View {
    @Binding var draft: TrainerAssessment

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            title("Any coaching philosophy\nor notes?")
            Text("Optional — TacTech AI will use this when helping you build plans.")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(AssessmentColor.slate)
                .frame(maxWidth: .infinity, alignment: .center)

            AssessmentTextBox(
                text: $draft.philosophy,
                placeholder: "Progressive overload, form first, no ego lifting…"
            )
            Spacer(minLength: 8)
        }
        .padding(.horizontal, 22)
        .padding(.top, 8)
    }
}

// MARK: - Shared title

private func title(_ text: String) -> some View {
    Text(text)
        .font(.system(size: 28, weight: .bold))
        .foregroundStyle(AssessmentColor.ink)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.top, 24)
        .padding(.horizontal, 20)
}

#Preview("Trainer Assessment") {
    TrainerAssessmentFlowView()
        .ttPreviewTrainer()
}
