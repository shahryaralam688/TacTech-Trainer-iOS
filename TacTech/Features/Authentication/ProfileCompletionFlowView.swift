import LocalAuthentication
import PhotosUI
import SwiftUI
import UIKit
import UserNotifications

/// Post-login Profile Setup (Account Settings) and optional first-time account completion.
///
/// **Logged-in path (production):** Avatar → Profile → Biometrics → Notifications → Score  
/// Password + OTP are **not** shown when a session already exists — those belong in Security settings.
///
/// **Unauthenticated / first-account path (legacy):** also includes Password → OTP before biometrics.
struct ProfileCompletionFlowView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    /// Index into `activeSteps` (not a hard-coded step number).
    @State private var step = 0
    @State private var draft = ProfileCompletionDraft()
    @State private var generatedOTP = ""
    @State private var otpInput = ["", "", "", ""]
    @State private var otpError: String?
    @State private var passwordStrength: Double = 0
    @State private var biometricOK = false
    @State private var score = 55
    @State private var isGenerating = false
    @State private var isSavingProfile = false
    @State private var profileError: String?
    @FocusState private var focusedProfileField: ProfileField?
    @FocusState private var otpFocusIndex: Int?

    private enum ProfileField: Hashable {
        case fullName, email, password, confirm, weight, location
    }

    private enum SetupStep: Hashable {
        case avatar
        case profile
        case password
        case otpIntro
        case otpEntry
        case biometric
        case notifications
        case score
    }

    private let accent = TTColor.actionOrange

    /// High-quality apps never force re-password / demo OTP after login.
    private var isAuthenticatedSession: Bool {
        store.session != nil
    }

    private var activeSteps: [SetupStep] {
        if isAuthenticatedSession {
            return [.avatar, .profile, .biometric, .notifications, .score]
        }
        return [.avatar, .profile, .password, .otpIntro, .otpEntry, .biometric, .notifications, .score]
    }

    private var currentStep: SetupStep {
        let steps = activeSteps
        guard !steps.isEmpty else { return .avatar }
        return steps[min(max(step, 0), steps.count - 1)]
    }

    private var totalSteps: Int { activeSteps.count }

    private var isScoreStep: Bool { currentStep == .score }

    var body: some View {
        VStack(spacing: 0) {
            if !isScoreStep {
                header
            }

            Group {
                switch currentStep {
                case .avatar: avatarStep
                case .profile: profileStep
                case .password: passwordStep
                case .otpIntro: otpIntroStep
                case .otpEntry: otpEntryStep
                case .biometric: biometricStep
                case .notifications: notificationsStep
                case .score: scoreStep
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .id(currentStep)

            if !isScoreStep {
                continueButton
                    .disabled(isSavingProfile || !canContinue)
            }
        }
        .background(Color.white.ignoresSafeArea())
        .ttHideSystemNavigationBar()
        .task { await hydrateFromServer() }
        .alert("Profile Setup", isPresented: Binding(
            get: { profileError != nil },
            set: { if !$0 { profileError = nil } }
        )) {
            Button("OK", role: .cancel) { profileError = nil }
        } message: {
            Text(profileError ?? "")
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 10) {
            HStack {
                if step > 0 {
                    TTBackButton {
                        withAnimation(.easeInOut(duration: 0.25)) { step -= 1 }
                    }
                } else {
                    TTBackButton { dismiss() }
                }

                Spacer()
                Text("Profile Setup")
                    .font(TTFont.workSans(17, weight: .semibold))
                    .foregroundStyle(TTColor.ink)
                Spacer()

                Text("\(step + 1)/\(totalSteps)")
                    .font(TTFont.workSans(12, weight: .semibold))
                    .foregroundStyle(accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(accent.opacity(0.12))
                    .clipShape(Capsule())
                    .frame(minWidth: TTBackButton.size, alignment: .trailing)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(white: 0.92))
                    Capsule()
                        .fill(accent)
                        .frame(width: max(8, geo.size.width * CGFloat(step + 1) / CGFloat(totalSteps)))
                        .animation(.spring(response: 0.4, dampingFraction: 0.86), value: step)
                }
            }
            .frame(height: 4)
            .padding(.horizontal, 2)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 6)
    }

    private var continueButton: some View {
        Button(action: advance) {
            HStack(spacing: 8) {
                Text(continueTitle)
                    .font(TTFont.workSans(17, weight: .semibold))
                TTIcon(icon: .arrowRight, size: 16)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(canContinue ? Color.black : Color.black.opacity(0.35))
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(AssessmentCardPressStyle())
        .disabled(!canContinue)
        .padding(.horizontal, 22)
        .padding(.bottom, 14)
        .animation(.easeInOut(duration: 0.2), value: canContinue)
    }

    private var continueTitle: String {
        switch currentStep {
        case .notifications: "Generate score"
        case .biometric: biometricOK ? "Continue" : "Continue"
        default: "Continue"
        }
    }

    private var canContinue: Bool {
        switch currentStep {
        case .avatar: true
        case .profile:
            !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !draft.location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .password:
            draft.password.count >= 6 && draft.password == draft.confirmPassword
        case .otpIntro: true
        case .otpEntry: otpInput.joined().count == 4
        case .biometric: true
        case .notifications: true
        case .score: true
        }
    }

    private func advance() {
        switch currentStep {
        case .otpIntro:
            generatedOTP = String(format: "%04d", Int.random(in: 1000...9999))
            otpInput = ["", "", "", ""]
            otpError = nil
            goToNextStep()
        case .otpEntry:
            let entered = otpInput.joined()
            if entered != generatedOTP {
                otpError = "Invalid OTP Code"
                return
            }
            otpError = nil
            goToNextStep()
        case .notifications:
            Task { await finishNotificationsAndScore() }
        default:
            goToNextStep()
        }
    }

    private func finishNotificationsAndScore() async {
        isSavingProfile = true
        defer { isSavingProfile = false }
        do {
            try await saveProfileToServer()
            score = computeScore()
            goToNextStep()
            isGenerating = true
            try? await Task.sleep(for: .milliseconds(2200))
            isGenerating = false
        } catch {
            profileError = (error as? AppError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func goToNextStep() {
        guard step + 1 < activeSteps.count else { return }
        withAnimation(.easeInOut(duration: 0.25)) { step += 1 }
    }

    // MARK: - Steps

    private var avatarStep: some View {
        AssessmentAvatarStep(selection: $draft.avatarSymbol, userId: store.session?.userId ?? store.currentUser?.id)
    }

    private var profileStep: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 22) {
                profileHero

                profileSection(title: "About you") {
                    boxedField("Full Name", icon: .user, text: $draft.name, field: .fullName)
                    boxedField(
                        "Email Address",
                        icon: .envelope1,
                        text: .constant(store.currentUser?.email ?? ""),
                        field: .email,
                        keyboard: .emailAddress,
                        disabled: true
                    )
                }

                profileSection(title: "Identity") {
                    genderPicker
                    memberTypeCard
                }

                if store.session?.role == .trainee {
                    profileSection(title: "Body metrics") {
                        heightMetricCard
                        boxedField(
                            "Weight (kg)",
                            icon: .weightScale,
                            text: $draft.weightText,
                            field: .weight,
                            keyboard: .decimalPad
                        )
                    }
                }

                profileSection(title: "Where you train") {
                    boxedField("Location", icon: .mapPin1, text: $draft.location, field: .location)
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 8)
            .padding(.bottom, 28)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private var profileHero: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("PROFILE")
                .font(TTFont.workSans(11, weight: .semibold))
                .foregroundStyle(accent)
                .tracking(1.1)

            Text("Complete your profile")
                .font(TTFont.headingLG(.medium))
                .foregroundStyle(TTColor.ink)

            Text("Confirm a few details so TacTech can personalize coaching for your \(roleTitle.lowercased()) account.")
                .font(TTFont.textMD(.regular))
                .foregroundStyle(Color(white: 0.45))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func profileSection<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title.uppercased())
                .font(TTFont.workSans(11, weight: .semibold))
                .foregroundStyle(Color(white: 0.48))
                .tracking(0.8)
            content()
        }
    }

    private var genderPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Gender")
                .font(TTFont.workSans(14, weight: .semibold))
                .foregroundStyle(TTColor.ink)

            HStack(spacing: 8) {
                ForEach(["Male", "Female", "Non-binary"], id: \.self) { item in
                    genderChip(item)
                }
            }
        }
    }

    private func genderChip(_ title: String) -> some View {
        let selected = draft.gender == title
        return Button {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                draft.gender = title
            }
            TTHomeHaptics.selection()
        } label: {
            VStack(spacing: 6) {
                TTIcon(icon: genderIcon(for: title), size: 16)
                Text(title)
                    .font(TTFont.workSans(12, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .foregroundStyle(selected ? .white : TTColor.ink)
            .frame(maxWidth: .infinity)
            .frame(height: 64)
            .background(selected ? accent : Color(white: 0.95))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(selected ? Color.clear : Color.black.opacity(0.04), lineWidth: 1)
            )
        }
        .buttonStyle(AssessmentCardPressStyle())
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func genderIcon(for title: String) -> SandowIcon {
        switch title {
        case "Female": .genderFemale
        case "Male": .genderMale
        default: .genderTransgender
        }
    }

    private var memberTypeCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Member type")
                .font(TTFont.workSans(14, weight: .semibold))
                .foregroundStyle(TTColor.ink)

            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(accent.opacity(0.12))
                        .frame(width: 44, height: 44)
                    TTIcon(icon: store.session?.role == .trainer ? .starFull : .user, size: 18)
                        .foregroundStyle(accent)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(roleTitle)
                        .font(TTFont.workSans(15, weight: .semibold))
                        .foregroundStyle(TTColor.ink)
                    Text("Locked to your account role")
                        .font(TTFont.workSans(12, weight: .regular))
                        .foregroundStyle(Color(white: 0.48))
                }

                Spacer(minLength: 0)

                Text("Active")
                    .font(TTFont.workSans(11, weight: .semibold))
                    .foregroundStyle(accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(accent.opacity(0.12))
                    .clipShape(Capsule())
            }
            .padding(14)
            .background(Color(white: 0.96))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    private var heightMetricCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack(spacing: 8) {
                    TTIcon(icon: .ruler1, size: 16)
                        .foregroundStyle(accent)
                    Text("Height")
                        .font(TTFont.workSans(14, weight: .semibold))
                        .foregroundStyle(TTColor.ink)
                }
                Spacer()
                Text("\(Int(draft.heightCm)) cm")
                    .font(TTFont.workSans(15, weight: .semibold))
                    .foregroundStyle(accent)
                    .contentTransition(.numericText())
                    .animation(.snappy(duration: 0.18), value: Int(draft.heightCm))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(accent.opacity(0.12))
                    .clipShape(Capsule())
            }

            Slider(value: $draft.heightCm, in: 140...210, step: 1)
                .tint(accent)
                .sensoryFeedback(.selection, trigger: Int(draft.heightCm))

            HStack {
                Text("140")
                    .font(TTFont.workSans(11, weight: .medium))
                    .foregroundStyle(Color(white: 0.5))
                Spacer()
                Text("210 cm")
                    .font(TTFont.workSans(11, weight: .medium))
                    .foregroundStyle(Color(white: 0.5))
            }
        }
        .padding(14)
        .background(Color(white: 0.96))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var passwordStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Secure your account")
                .font(TTFont.workSans(28, weight: .bold))
                .padding(.top, 12)

            Text("Confirm a password for TacTech. Minimum 6 characters.")
                .font(TTFont.workSans(14, weight: .medium))
                .foregroundStyle(Color(white: 0.45))

            secureField("Password", text: $draft.password, field: .password)
            secureField("Confirm Password", text: $draft.confirmPassword, field: .confirm)

            VStack(alignment: .leading, spacing: 8) {
                Text("Password Strength")
                    .font(TTFont.workSans(13, weight: .semibold))
                    .foregroundStyle(strengthColor)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color(white: 0.9))
                        Capsule()
                            .fill(strengthColor)
                            .frame(width: geo.size.width * passwordStrength)
                    }
                }
                .frame(height: 8)
            }
            .onChange(of: draft.password) { _, newValue in
                passwordStrength = strength(for: newValue)
            }

            Spacer()
        }
        .padding(22)
    }

    private var otpIntroStep: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 56))
                .foregroundStyle(Color(red: 37 / 255, green: 99 / 255, blue: 235 / 255))
            Text("Two-step verification")
                .font(TTFont.workSans(28, weight: .bold))
            Text("We’ll send a 4-digit code so only you can access this \(roleTitle.lowercased()) account.")
                .font(TTFont.workSans(15, weight: .medium))
                .foregroundStyle(Color(white: 0.45))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Spacer()
        }
    }

    private var otpEntryStep: some View {
        VStack(spacing: 20) {
            Text("Enter OTP code")
                .font(TTFont.workSans(28, weight: .bold))
                .padding(.top, 20)

            Text("Demo code: \(generatedOTP)")
                .font(TTFont.workSans(13, weight: .semibold))
                .foregroundStyle(Color(white: 0.45))

            HStack(spacing: 12) {
                ForEach(0..<4, id: \.self) { index in
                    let cellFocused = otpFocusIndex == index
                    let hasValue = !otpInput[index].isEmpty
                    TextField("", text: $otpInput[index])
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.center)
                        .font(TTFont.workSans(24, weight: .bold))
                        .foregroundStyle(cellFocused && hasValue ? .white : .primary)
                        .focused($otpFocusIndex, equals: index)
                        .tint(accent)
                        .frame(width: 64, height: 64)
                        .background(cellFocused ? (hasValue ? accent : TTInputChrome.activeFill) : Color(white: 0.96))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(
                                    cellFocused || hasValue ? accent : Color(white: 0.78),
                                    lineWidth: cellFocused ? 2 : 1.2
                                )
                        )
                        .onChange(of: otpInput[index]) { _, newValue in
                            if newValue.count > 1 {
                                otpInput[index] = String(newValue.prefix(1))
                            }
                            if newValue.count == 1, index < 3 {
                                otpFocusIndex = index + 1
                            }
                        }
                }
            }

            if let otpError {
                Text(otpError)
                    .font(TTFont.workSans(14, weight: .semibold))
                    .foregroundStyle(.red)
            }

            Spacer()
        }
        .padding(22)
    }

    private var biometricStep: some View {
        VStack(spacing: 22) {
            Spacer()
            Image(systemName: "touchid")
                .font(TTFont.workSans(72, weight: .regular))
                .foregroundStyle(Color(red: 249 / 255, green: 115 / 255, blue: 22 / 255))
            Text("Enable biometrics")
                .font(TTFont.workSans(28, weight: .bold))
            Text("Optional — use Face ID / Touch ID for faster unlock. You can skip and turn this on later in Security.")
                .font(TTFont.workSans(15, weight: .medium))
                .foregroundStyle(Color(white: 0.45))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)

            Button {
                Task { await enableBiometrics() }
            } label: {
                Text(biometricOK ? "Biometrics enabled" : "Enable Face ID / Touch ID")
                    .font(TTFont.workSans(16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(Color(red: 249 / 255, green: 115 / 255, blue: 22 / 255))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(AssessmentCardPressStyle())
            .padding(.horizontal, 28)

            if !biometricOK {
                Text("You can continue without enabling this.")
                    .font(TTFont.workSans(13, weight: .medium))
                    .foregroundStyle(Color(white: 0.5))
            }

            Spacer()
        }
    }

    private var notificationsStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Stay in the loop")
                .font(TTFont.workSans(28, weight: .bold))
                .padding(.top, 12)

            notificationRow("Workout reminders", icon: "bell.fill", color: .orange, isOn: $draft.notifyWorkouts)
            notificationRow("Messages & feedback", icon: "message.fill", color: .blue, isOn: $draft.notifyMessages)
            notificationRow("Progress updates", icon: "checkmark.seal.fill", color: .green, isOn: $draft.notifyProgress)

            Spacer()
        }
        .padding(22)
    }

    private var scoreStep: some View {
        ZStack {
            scoreBackground.ignoresSafeArea()

            if isGenerating {
                VStack(spacing: 16) {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(1.3)
                    Text("Generating your TacTech Score…")
                        .font(TTFont.workSans(18, weight: .semibold))
                        .foregroundStyle(.white)
                }
            } else {
                VStack(spacing: 22) {
                    Spacer()
                    Text(scoreTitle)
                        .font(TTFont.workSans(18, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))

                    Text("+\(score)")
                        .font(TTFont.workSans(72, weight: .bold))
                        .foregroundStyle(.black)
                        .contentTransition(.numericText())
                        .animation(.snappy(duration: 0.18), value: score)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 28)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                        .padding(.horizontal, 36)

                    Text(scoreMessage)
                        .font(TTFont.workSans(16, weight: .medium))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                        .animation(.snappy(duration: 0.18), value: score)

                    Spacer()

                    Button {
                        store.markProfileSetupCompleted()
                        dismiss()
                    } label: {
                        Text("GET STARTED")
                            .font(TTFont.workSans(17, weight: .bold))
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    }
                    .padding(.horizontal, 28)
                    .padding(.bottom, 28)
                }
            }
        }
    }

    // MARK: - Helpers

    private var roleTitle: String {
        store.session?.role.title ?? "Member"
    }

    private var scoreBackground: Color {
        if score >= 75 { return Color(red: 17 / 255, green: 24 / 255, blue: 39 / 255) }
        if score >= 45 { return Color(red: 30 / 255, green: 64 / 255, blue: 175 / 255) }
        return Color(red: 153 / 255, green: 27 / 255, blue: 27 / 255)
    }

    private var scoreTitle: String {
        if score >= 75 { return "Elite readiness" }
        if score >= 45 { return "Solid foundation" }
        return "Let’s build up"
    }

    private var scoreMessage: String {
        if score >= 75 { return "You are a Fit individual. Ready to train! Let’s go." }
        if score >= 45 { return "Great start. Your TacTech plan will level you up." }
        return "We’re with you. Consistency will raise this score fast."
    }

    private var strengthColor: Color {
        if passwordStrength < 0.34 { return .red }
        if passwordStrength < 0.67 { return .orange }
        return .green
    }

    private func hydrateFromServer() async {
        hydrateDraftFromSession()
        guard isAuthenticatedSession else { return }
        do {
            let response = try await store.fetchMeProfile()
            draft.name = response.user.name
            draft.gender = response.profile.gender
                ?? response.trainee?.gender
                ?? draft.gender
            draft.location = response.profile.location
                ?? response.trainee?.location
                ?? response.trainer?.location
                ?? draft.location
            if let h = response.profile.heightCm ?? response.trainee?.heightCm, h > 0 {
                draft.heightCm = Double(h)
            }
            if let w = response.profile.weightKg ?? response.trainee?.weightKg, w > 0 {
                draft.weightText = String(Int(w))
            }
            if let url = response.profile.avatarUrl ?? response.user.avatarUrl, !url.isEmpty {
                draft.avatarSymbol = TTAvatarCatalog.customToken
            } else if let asset = response.profile.avatarAsset ?? response.user.avatarAsset,
                      TTAvatarCatalog.isAssetName(asset) {
                draft.avatarSymbol = asset
            }
        } catch {
            // Keep session hydrate; surface only if user tries to save later
        }
    }

    private func hydrateDraftFromSession() {
        draft.name = store.currentUser?.name ?? ""
        draft.gender = store.currentTrainee?.gender
            ?? store.currentTrainer?.gender
            ?? "Male"
        draft.location = store.currentTrainee?.location
            ?? store.currentTrainer?.location
            ?? ""
        if let h = store.currentTrainee?.heightCm, h > 0 {
            draft.heightCm = Double(h)
        }
        if let w = store.currentTrainee?.weightKg, w > 0 {
            draft.weightText = String(Int(w))
        }
        if let userId = store.session?.userId,
           let symbol = TTAvatarCatalog.saved(for: userId),
           TTAvatarCatalog.hasRenderableAvatar(symbol) {
            draft.avatarSymbol = symbol
        } else if store.session?.userId != nil {
            draft.avatarSymbol = TTAvatarCatalog.default
        }
    }

    private func saveProfileToServer() async throws {
        let trimmedName = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw AppError.validation("Enter your name.")
        }
        let trimmedLocation = draft.location.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedLocation.isEmpty else {
            throw AppError.validation("Enter your location.")
        }

        // Custom photo selected locally → upload first
        if TTAvatarCatalog.isCustom(draft.avatarSymbol),
           let image = TTAvatarCatalog.loadCustomImage(for: store.session?.userId),
           let data = CoachImageEncoder.jpegData(from: image) ?? image.jpegData(compressionQuality: 0.88) {
            _ = try await store.uploadProfileAvatar(jpegData: data, previewImage: image)
        }

        var body = UpdateMeProfileBody(
            name: trimmedName,
            gender: draft.gender,
            location: trimmedLocation
        )
        if store.session?.role == .trainee {
            body.heightCm = Int(draft.heightCm)
            if let weight = Double(draft.weightText.replacingOccurrences(of: ",", with: ".")) {
                body.weightKg = weight
            }
        }
        if TTAvatarCatalog.isAssetName(draft.avatarSymbol) {
            body.avatarAsset = draft.avatarSymbol
        }

        let response = try await store.saveMeProfile(body)
        if response.onboardingCompleted == true {
            store.markProfileSetupCompleted()
        }

        if let userId = store.session?.userId {
            UserDefaults.standard.set(draft.notifyWorkouts, forKey: "notify.workouts.\(userId)")
            UserDefaults.standard.set(draft.notifyMessages, forKey: "notify.messages.\(userId)")
            UserDefaults.standard.set(draft.notifyProgress, forKey: "notify.progress.\(userId)")
        }
    }

    private func computeScore() -> Int {
        var value = 40
        if !draft.location.isEmpty { value += 8 }
        // Already logged in ⇒ account credentials exist (don’t require re-password).
        if isAuthenticatedSession || draft.password.count >= 8 { value += 10 }
        if biometricOK { value += 12 }
        if draft.notifyWorkouts { value += 6 }
        if store.session?.role == .trainee {
            if draft.heightCm > 0 { value += 8 }
            if Double(draft.weightText) != nil { value += 8 }
        } else {
            value += 16
        }
        if store.assessmentCompleted { value += 10 }
        return min(value, 99)
    }

    private func enableBiometrics() async {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            biometricOK = true // allow continue on simulator / unsupported
            return
        }
        do {
            let ok = try await context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: "Enable biometrics for TacTech"
            )
            biometricOK = ok
        } catch {
            biometricOK = false
        }
    }

    private func strength(for password: String) -> Double {
        var score = 0.0
        if password.count >= 6 { score += 0.25 }
        if password.count >= 10 { score += 0.2 }
        if password.rangeOfCharacter(from: .decimalDigits) != nil { score += 0.2 }
        if password.rangeOfCharacter(from: .uppercaseLetters) != nil { score += 0.2 }
        if password.rangeOfCharacter(from: CharacterSet.punctuationCharacters.union(.symbols)) != nil { score += 0.15 }
        return min(score, 1)
    }

    private func boxedField(
        _ title: String,
        icon: SandowIcon,
        text: Binding<String>,
        field: ProfileField,
        keyboard: UIKeyboardType = .default,
        disabled: Bool = false
    ) -> some View {
        let focused = focusedProfileField == field
        return VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(TTFont.workSans(14, weight: .semibold))
                .foregroundStyle(TTColor.ink)
            HStack(spacing: 12) {
                TTIcon(icon: icon, size: 18)
                    .foregroundStyle(focused ? accent : Color(white: 0.45))
                TextField("", text: text, prompt: TTInputChrome.prompt(title))
                    .font(TTFont.body(15))
                    .keyboardType(keyboard)
                    .textInputAutocapitalization(keyboard == .emailAddress ? .never : .words)
                    .autocorrectionDisabled(keyboard == .emailAddress)
                    .disabled(disabled)
                    .focused($focusedProfileField, equals: field)
                    .foregroundStyle(disabled ? Color(white: 0.45) : Color.black)
                    .tint(accent)
                if disabled {
                    Text("Verified")
                        .font(TTFont.workSans(11, weight: .semibold))
                        .foregroundStyle(Color(white: 0.5))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(white: 0.9))
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 52)
            .ttInputChrome(
                focused: focused && !disabled,
                cornerRadius: 16,
                idleFill: Color(white: 0.96),
                showIdleBorder: true
            )
            .opacity(disabled ? 0.92 : 1)
        }
    }

    private func secureField(_ title: String, text: Binding<String>, field: ProfileField) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(TTFont.workSans(14, weight: .semibold))
            SecureField("", text: text, prompt: TTInputChrome.prompt(title))
                .focused($focusedProfileField, equals: field)
                .foregroundStyle(Color.black)
                .tint(accent)
                .padding(.horizontal, 14)
                .frame(height: 52)
                .ttInputChrome(
                    focused: focusedProfileField == field,
                    cornerRadius: 14,
                    idleFill: Color(white: 0.97),
                    showIdleBorder: true
                )
        }
    }

    private func notificationRow(_ title: String, icon: String, color: Color, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(color)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            Text(title)
                .font(TTFont.workSans(16, weight: .semibold))
            Spacer()
            Toggle("", isOn: isOn)
                .labelsHidden()
                .onChange(of: isOn.wrappedValue) { _, enabled in
                    if enabled {
                        Task {
                            _ = try? await UNUserNotificationCenter.current()
                                .requestAuthorization(options: [.alert, .badge, .sound])
                        }
                    }
                }
        }
        .padding(14)
        .background(Color(white: 0.96))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct ProfileCompletionDraft {
    var avatarSymbol = TTAvatarCatalog.default
    var name = ""
    var gender = "Male"
    var heightCm: Double = 170
    var weightText = "70"
    var location = ""
    var password = ""
    var confirmPassword = ""
    var notifyWorkouts = true
    var notifyMessages = true
    var notifyProgress = true

    static let avatarChoices = TTAvatarCatalog.all
}

#Preview("Profile Completion") {
    ProfileCompletionFlowView()
        .ttPreviewTrainee()
}
