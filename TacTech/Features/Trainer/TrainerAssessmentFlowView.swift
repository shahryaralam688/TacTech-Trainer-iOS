import SwiftUI

// MARK: - Flow

struct TrainerAssessmentFlowView: View {
    @Environment(AppStore.self) private var store
    @State private var step = 0
    @State private var draft = TrainerAssessment()
    @State private var isSaving = false
    @State private var error: String?
    @State private var capacitySlider = 2
    @State private var avatarSelection = TTAvatarCatalog.default

    private let total = 13

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
                case 11: TrainerPhilosophyStep(draft: $draft)
                default: AssessmentAvatarStep(selection: $avatarSelection, userId: store.currentUser?.id)
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
                        .font(TTFont.workSans(17, weight: .semibold))
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
        .ttHideSystemNavigationBar()
        .safeAreaPadding(.top)
        .safeAreaPadding(.bottom)
        .onAppear {
            capacitySlider = TrainerAssessmentCatalog.capacityIndex(for: draft.maxClients)
            if let saved = TTAvatarCatalog.saved(for: store.currentUser?.id) {
                avatarSelection = saved
            }
        }
    }

    private var header: some View {
        ZStack {
            Text("Assessment")
                .font(TTFont.workSans(17, weight: .bold))
                .foregroundStyle(AssessmentColor.ink)

            HStack {
                if step > 0 {
                    TTBackButton { step -= 1 }
                } else {
                    Color.clear.frame(width: TTBackButton.size, height: TTBackButton.size)
                }

                Spacer()

                Text("\(step + 1) of \(total)")
                    .font(TTFont.workSans(13, weight: .semibold))
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
            TTAvatarCatalog.persistSelection(avatarSelection, for: store.currentUser?.id)
            try await store.submitTrainerAssessment(draft)
        } catch {
            TTAvatarCatalog.persistSelection(avatarSelection, for: store.currentUser?.id)
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
                .padding(.bottom, 8)

            AssessmentAgeWheel(selection: $draft.yearsExperience, range: 0...30)
                .frame(maxWidth: .infinity)
                .frame(maxHeight: .infinity)

            VStack(spacing: 6) {
                Text(draft.yearsExperience == 0 ? "Just getting started" : "\(draft.yearsExperience)")
                    .font(TTFont.workSans(22, weight: .bold))
                    .foregroundStyle(AssessmentColor.ink)
                    .contentTransition(.numericText())
                    .animation(.snappy(duration: 0.18), value: draft.yearsExperience)

                Text(draft.yearsExperience == 0 ? "New to coaching" : "years of coaching experience")
                    .font(TTFont.workSans(14, weight: .medium))
                    .foregroundStyle(AssessmentColor.slate)
                    .animation(.snappy(duration: 0.18), value: draft.yearsExperience == 0)
            }
            .padding(.top, 10)
            .padding(.bottom, 16)
        }
        .sensoryFeedback(.selection, trigger: draft.yearsExperience)
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
                    .font(TTFont.workSans(14, weight: .medium))
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
                        .font(TTFont.workSans(20, weight: .semibold))
                        .foregroundStyle(selected ? AssessmentColor.white : AssessmentColor.coolGrey)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(TTFont.workSans(16, weight: .bold))
                        .foregroundStyle(selected ? AssessmentColor.white : AssessmentColor.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    Text(subtitle)
                        .font(TTFont.workSans(12, weight: .medium))
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
                    .font(TTFont.workSans(14, weight: .medium))
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
                        .font(TTFont.workSans(16, weight: .bold))
                        .foregroundStyle(selected ? AssessmentColor.white : AssessmentColor.ink)
                    Text(subtitle)
                        .font(TTFont.workSans(13, weight: .medium))
                        .foregroundStyle(selected ? AssessmentColor.white.opacity(0.88) : AssessmentColor.slate)
                        .lineLimit(2)
                }

                Spacer(minLength: 8)

                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(TTFont.workSans(22, weight: .semibold))
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
                    .font(TTFont.workSans(14, weight: .medium))
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
                        .font(TTFont.workSans(20, weight: .semibold))
                        .foregroundStyle(selected ? AssessmentColor.white : AssessmentColor.coolGrey)
                        .symbolEffect(.bounce, value: selected)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(TTFont.workSans(15, weight: .bold))
                        .foregroundStyle(selected ? AssessmentColor.white : AssessmentColor.ink)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                    Text(subtitle)
                        .font(TTFont.workSans(12, weight: .medium))
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

    @State private var isEditingCustom = false
    @State private var customText = ""
    @FocusState private var customFieldFocused: Bool

    private var isCustomValue: Bool {
        !presets.contains(draft.maxClients)
    }

    /// Only a real preset lights the bar — custom (e.g. 12) leaves the bar unselected.
    private var selectedPreset: Int? {
        presets.contains(draft.maxClients) ? draft.maxClients : nil
    }

    var body: some View {
        VStack(spacing: 0) {
            title("How many clients can you\nmanage at once?")

            Text("Tap or drag the bar — or edit for a custom number")
                .font(TTFont.workSans(14, weight: .medium))
                .foregroundStyle(AssessmentColor.slate)
                .multilineTextAlignment(.center)
                .padding(.top, 8)
                .padding(.horizontal, 28)

            Spacer(minLength: 20)

            // Hero number + compact pencil (inline edit).
            HStack(alignment: .center, spacing: 10) {
                Group {
                    if isEditingCustom {
                        TextField(
                            "",
                            text: $customText,
                            prompt: Text("0")
                                .foregroundStyle(AssessmentColor.coolGrey)
                        )
                        .keyboardType(.numberPad)
                        .font(TTFont.workSans(72, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(AssessmentColor.ink)
                        .multilineTextAlignment(.center)
                        .focused($customFieldFocused)
                        .frame(minWidth: 120, maxWidth: 200)
                        .onSubmit { commitCustomEdit() }
                    } else {
                        Text("\(draft.maxClients)")
                            .font(TTFont.workSans(84, weight: .bold))
                            .foregroundStyle(AssessmentColor.ink)
                            .monospacedDigit()
                            .contentTransition(.numericText())
                    }
                }
                .animation(.snappy(duration: 0.22), value: draft.maxClients)
                .animation(.snappy(duration: 0.22), value: isEditingCustom)

                Button {
                    if isEditingCustom {
                        commitCustomEdit()
                    } else {
                        beginCustomEdit()
                    }
                } label: {
                    Image(systemName: isEditingCustom ? "checkmark" : "pencil")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(isEditingCustom ? AssessmentColor.white : AssessmentColor.orange)
                        .frame(width: 28, height: 28)
                        .background(isEditingCustom ? AssessmentColor.orange : AssessmentColor.peach)
                        .clipShape(Circle())
                        .overlay(
                            Circle()
                                .strokeBorder(AssessmentColor.orangeBorder.opacity(0.5), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .offset(y: isEditingCustom ? 0 : 6)
                .animation(.snappy(duration: 0.22), value: isEditingCustom)
                .accessibilityLabel(isEditingCustom ? "Save custom number" : "Enter a custom number")
            }

            Text(isCustomValue ? "custom capacity" : "active clients")
                .font(TTFont.workSans(18, weight: .semibold))
                .foregroundStyle(AssessmentColor.slate)
                .animation(.snappy(duration: 0.22), value: isCustomValue)

            // Preset bar — no thumb when value is custom (not in 5/10/15/20/30).
            CapacityClientsDragSlider(
                options: presets,
                selection: presetSliderBinding
            )
            .padding(.horizontal, 22)
            .padding(.top, 28)

            (
                Text("I’m set up to coach ")
                    .foregroundStyle(AssessmentColor.slate)
                + Text("\(draft.maxClients)")
                    .foregroundStyle(AssessmentColor.ink)
                    .fontWeight(.bold)
                + Text(draft.maxClients == 1 ? " client" : " clients")
                    .foregroundStyle(AssessmentColor.slate)
            )
            .font(TTFont.workSans(16, weight: .medium))
            .contentTransition(.numericText())
            .animation(.snappy(duration: 0.22), value: draft.maxClients)
            .padding(.top, 20)

            Spacer(minLength: 20)
        }
        .onAppear {
            syncSliderFromDraft()
            if isCustomValue {
                customText = "\(draft.maxClients)"
            }
        }
        .onChange(of: draft.maxClients) { _, _ in
            syncSliderFromDraft()
        }
        .sensoryFeedback(.selection, trigger: draft.maxClients)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { commitCustomEdit() }
                    .font(TTFont.workSans(16, weight: .bold))
                    .foregroundStyle(AssessmentColor.orange)
            }
        }
    }

    /// `nil` while custom — bar stays unselected until user picks a preset.
    private var presetSliderBinding: Binding<Int?> {
        Binding(
            get: { selectedPreset },
            set: { newPreset in
                guard let newPreset else { return }
                withAnimation(.snappy(duration: 0.24)) {
                    isEditingCustom = false
                    customFieldFocused = false
                    applyCapacity(newPreset)
                }
            }
        )
    }

    private func beginCustomEdit() {
        customText = "\(draft.maxClients)"
        withAnimation(.snappy(duration: 0.24)) {
            isEditingCustom = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            customFieldFocused = true
        }
    }

    private func commitCustomEdit() {
        let digits = customText.filter(\.isNumber)
        guard let parsed = Int(digits), parsed > 0 else {
            withAnimation(.snappy(duration: 0.24)) {
                isEditingCustom = false
            }
            customFieldFocused = false
            return
        }
        applyCapacity(parsed)
        withAnimation(.snappy(duration: 0.24)) {
            isEditingCustom = false
        }
        customFieldFocused = false
    }

    private func applyCapacity(_ raw: Int) {
        let clamped = min(max(raw, 1), 200)
        draft.maxClients = clamped
        slider = TrainerAssessmentCatalog.capacityIndex(for: clamped)
        if presets.contains(clamped) {
            customText = ""
        } else {
            customText = "\(clamped)"
        }
    }

    private func syncSliderFromDraft() {
        slider = TrainerAssessmentCatalog.capacityIndex(for: draft.maxClients)
    }
}

/// Orange capacity slider — same feel as Days; thumb only when a preset is selected.
private struct CapacityClientsDragSlider: View {
    let options: [Int]
    @Binding var selection: Int?

    private let thumbSize: CGFloat = 52
    private let trackHeight: CGFloat = 64

    @State private var dragX: CGFloat?
    @GestureState private var isDragging = false

    var body: some View {
        GeometryReader { geo in
            let layout = DaySliderLayout(
                width: geo.size.width,
                thumbSize: thumbSize,
                count: options.count
            )
            let indexValue = selection.flatMap { options.firstIndex(of: $0).map { $0 + 1 } }
            let thumbX = dragX ?? indexValue.map { layout.x(for: $0) }

            ZStack {
                Capsule()
                    .fill(AssessmentColor.surface)
                    .frame(height: trackHeight)

                HStack(spacing: 0) {
                    ForEach(options, id: \.self) { count in
                        let isActive = selection == count
                        Text("\(count)")
                            .font(TTFont.workSans(16, weight: .bold))
                            .monospacedDigit()
                            .foregroundStyle(isActive ? Color.clear : AssessmentColor.coolGrey)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal, thumbSize * 0.12)
                .frame(height: trackHeight)

                if let thumbX, let selection {
                    Text("\(selection)")
                        .font(TTFont.workSans(22, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(AssessmentColor.white)
                        .contentTransition(.numericText())
                        .frame(width: thumbSize, height: thumbSize)
                        .background(AssessmentColor.orange)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(AssessmentColor.orangeBorder, lineWidth: 2.5)
                        )
                        .shadow(color: AssessmentColor.orange.opacity(0.35), radius: 10, y: 2)
                        .scaleEffect(isDragging ? 1.06 : 1)
                        .position(x: thumbX, y: geo.size.height / 2)
                        .animation(.snappy(duration: 0.22), value: isDragging)
                        .animation(.snappy(duration: 0.22), value: selection)
                        .transition(.scale(scale: 0.85).combined(with: .opacity))
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .updating($isDragging) { _, state, _ in state = true }
                    .onChanged { gesture in
                        let x = min(max(gesture.location.x, layout.minX), layout.maxX)
                        dragX = x
                        let nextIndex = layout.value(at: x)
                        let next = options[nextIndex - 1]
                        if selection != next {
                            withAnimation(.snappy(duration: 0.2)) {
                                selection = next
                            }
                        }
                    }
                    .onEnded { gesture in
                        let x = min(max(gesture.location.x, layout.minX), layout.maxX)
                        let nextIndex = layout.value(at: x)
                        let next = options[nextIndex - 1]
                        withAnimation(.snappy(duration: 0.24)) {
                            selection = next
                            dragX = layout.x(for: nextIndex)
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.26) {
                            dragX = nil
                        }
                    }
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Client capacity")
            .accessibilityValue(selection.map { "\($0) clients" } ?? "Custom capacity")
            .accessibilityAdjustableAction { direction in
                let current = selection.flatMap { options.firstIndex(of: $0) } ?? 0
                switch direction {
                case .increment:
                    selection = options[min(current + 1, options.count - 1)]
                case .decrement:
                    selection = options[max(current - 1, 0)]
                @unknown default:
                    break
                }
            }
        }
        .frame(height: trackHeight)
        .animation(.snappy(duration: 0.24), value: selection)
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
                .font(TTFont.workSans(14, weight: .medium))
                .foregroundStyle(AssessmentColor.slate)
                .padding(.top, 8)

            Spacer(minLength: 20)

            Text("\(clamped)")
                .font(TTFont.workSans(84, weight: .bold))
                .foregroundStyle(AssessmentColor.ink)
                .monospacedDigit()
                .contentTransition(.numericText())
                .animation(.snappy(duration: 0.18), value: clamped)

            Text(clamped == 1 ? "day every week" : "days every week")
                .font(TTFont.workSans(18, weight: .semibold))
                .foregroundStyle(AssessmentColor.slate)
                .animation(.snappy(duration: 0.18), value: clamped)

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
            .font(TTFont.workSans(16, weight: .medium))
            .padding(.top, 20)
            .animation(.snappy(duration: 0.18), value: clamped)

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
                            .font(TTFont.workSans(16, weight: .bold))
                            .monospacedDigit()
                            .foregroundStyle(day == value ? Color.clear : AssessmentColor.coolGrey)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal, thumbSize * 0.12)
                .frame(height: trackHeight)

                Text("\(value)")
                    .font(TTFont.workSans(22, weight: .bold))
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
                    .font(TTFont.workSans(14, weight: .medium))
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
                        .font(TTFont.workSans(16, weight: .semibold))
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
                Text(title).font(TTFont.workSans(17, weight: .bold))
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
                .font(TTFont.workSans(15, weight: .medium))
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
                .font(TTFont.workSans(15, weight: .medium))
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
        .font(TTFont.workSans(28, weight: .bold))
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
