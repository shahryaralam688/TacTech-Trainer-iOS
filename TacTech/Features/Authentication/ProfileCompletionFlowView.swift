import LocalAuthentication
import PhotosUI
import SwiftUI
import UIKit
import UserNotifications

/// Post-assessment Profile Setup & Account Completion (Figma flow).
/// Order: Avatar → Profile → Password → OTP → Biometrics → Notifications → Score → Done
struct ProfileCompletionFlowView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var step = 0
    @State private var draft = ProfileCompletionDraft()
    @State private var generatedOTP = ""
    @State private var otpInput = ["", "", "", ""]
    @State private var otpError: String?
    @State private var passwordStrength: Double = 0
    @State private var biometricOK = false
    @State private var score = 55
    @State private var isGenerating = false

    private let totalSteps = 8

    var body: some View {
        VStack(spacing: 0) {
            if step < 7 {
                header
            }

            Group {
                switch step {
                case 0: avatarStep
                case 1: profileStep
                case 2: passwordStep
                case 3: otpIntroStep
                case 4: otpEntryStep
                case 5: biometricStep
                case 6: notificationsStep
                default: scoreStep
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if step < 7 {
                continueButton
            }
        }
        .background(Color.white.ignoresSafeArea())
        .onAppear { hydrateDraft() }
    }

    // MARK: - Header

    private var header: some View {
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
                .font(.system(size: 17, weight: .bold))
            Spacer()

            Text("\(step + 1) of \(totalSteps)")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color(red: 37 / 255, green: 99 / 255, blue: 235 / 255))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color(red: 219 / 255, green: 234 / 255, blue: 254 / 255))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 6)
    }

    private var continueButton: some View {
        Button(action: advance) {
            HStack(spacing: 8) {
                Text(step == 6 ? "Generate score" : "Continue")
                    .font(.system(size: 17, weight: .semibold))
                Image(systemName: "arrow.right")
                    .font(.system(size: 14, weight: .bold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(canContinue ? Color.black : Color.black.opacity(0.35))
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .disabled(!canContinue)
        .padding(.horizontal, 22)
        .padding(.bottom, 14)
    }

    private var canContinue: Bool {
        switch step {
        case 0: true
        case 1: !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !draft.location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case 2: draft.password.count >= 6 && draft.password == draft.confirmPassword
        case 3: true
        case 4: otpInput.joined().count == 4
        case 5: true
        case 6: true
        default: true
        }
    }

    private func advance() {
        switch step {
        case 3:
            generatedOTP = String(format: "%04d", Int.random(in: 1000...9999))
            otpInput = ["", "", "", ""]
            otpError = nil
            withAnimation(.easeInOut(duration: 0.25)) { step = 4 }
        case 4:
            let entered = otpInput.joined()
            if entered != generatedOTP {
                otpError = "Invalid OTP Code"
                return
            }
            otpError = nil
            withAnimation(.easeInOut(duration: 0.25)) { step = 5 }
        case 6:
            saveProfile()
            score = computeScore()
            withAnimation(.easeInOut(duration: 0.25)) { step = 7 }
            isGenerating = true
            Task {
                try? await Task.sleep(for: .milliseconds(2200))
                await MainActor.run { isGenerating = false }
            }
        default:
            withAnimation(.easeInOut(duration: 0.25)) { step += 1 }
        }
    }

    // MARK: - Steps

    private var avatarStep: some View {
        VStack(spacing: 24) {
            Text("Choose your avatar")
                .font(.system(size: 28, weight: .bold))
                .padding(.top, 20)

            ZStack {
                Circle()
                    .fill(Color(white: 0.94))
                    .frame(width: 120, height: 120)
                Image(systemName: draft.avatarSymbol)
                    .font(.system(size: 46, weight: .semibold))
                    .foregroundStyle(Color(white: 0.35))
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 12) {
                ForEach(ProfileCompletionDraft.avatarChoices, id: \.self) { symbol in
                    Button {
                        draft.avatarSymbol = symbol
                    } label: {
                        Image(systemName: symbol)
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(draft.avatarSymbol == symbol ? .white : .black)
                            .frame(maxWidth: .infinity)
                            .frame(height: 64)
                            .background(draft.avatarSymbol == symbol ? Color.black : Color(white: 0.94))
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 28)

            Text("Or keep the default and continue.")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color(white: 0.45))

            Spacer()
        }
    }

    private var profileStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Complete your profile")
                    .font(.system(size: 28, weight: .bold))
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(roleTitle)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color(red: 37 / 255, green: 99 / 255, blue: 235 / 255))

                boxedField("Full Name", icon: "person", text: $draft.name)
                boxedField("Email Address", icon: "envelope", text: .constant(store.currentUser?.email ?? ""), disabled: true)

                Text("Gender")
                    .font(.system(size: 14, weight: .semibold))
                HStack(spacing: 8) {
                    ForEach(["Male", "Female", "Non-binary"], id: \.self) { item in
                        chip(item, selected: draft.gender == item) { draft.gender = item }
                    }
                }

                Text("Member Type")
                    .font(.system(size: 14, weight: .semibold))
                HStack(spacing: 10) {
                    ForEach(UserRole.allCases) { option in
                        let on = store.session?.role == option
                        Text(option.title)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(on ? .white : Color(white: 0.45))
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(on ? Color(red: 37 / 255, green: 99 / 255, blue: 235 / 255) : Color(white: 0.94))
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }

                if store.session?.role == .trainee {
                    Text("Height · \(Int(draft.heightCm)) cm")
                        .font(.system(size: 14, weight: .semibold))
                    Slider(value: $draft.heightCm, in: 140...210, step: 1)
                        .tint(Color(red: 249 / 255, green: 115 / 255, blue: 22 / 255))
                    boxedField("Weight (kg)", icon: "scalemass", text: $draft.weightText, keyboard: .decimalPad)
                }

                boxedField("Location", icon: "mappin.and.ellipse", text: $draft.location)
            }
            .padding(22)
        }
    }

    private var passwordStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Secure your account")
                .font(.system(size: 28, weight: .bold))
                .padding(.top, 12)

            Text("Confirm a password for TacTech. Minimum 6 characters.")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color(white: 0.45))

            secureField("Password", text: $draft.password)
            secureField("Confirm Password", text: $draft.confirmPassword)

            VStack(alignment: .leading, spacing: 8) {
                Text("Password Strength")
                    .font(.system(size: 13, weight: .semibold))
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
                .font(.system(size: 28, weight: .bold))
            Text("We’ll send a 4-digit code so only you can access this \(roleTitle.lowercased()) account.")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color(white: 0.45))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Spacer()
        }
    }

    private var otpEntryStep: some View {
        VStack(spacing: 20) {
            Text("Enter OTP code")
                .font(.system(size: 28, weight: .bold))
                .padding(.top, 20)

            Text("Demo code: \(generatedOTP)")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color(white: 0.45))

            HStack(spacing: 12) {
                ForEach(0..<4, id: \.self) { index in
                    TextField("", text: $otpInput[index])
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.center)
                        .font(.system(size: 24, weight: .bold))
                        .frame(width: 64, height: 64)
                        .background(Color(white: 0.96))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(Color(white: 0.78), lineWidth: 1.2)
                        )
                        .onChange(of: otpInput[index]) { _, newValue in
                            if newValue.count > 1 {
                                otpInput[index] = String(newValue.prefix(1))
                            }
                        }
                }
            }

            if let otpError {
                Text(otpError)
                    .font(.system(size: 14, weight: .semibold))
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
                .font(.system(size: 72, weight: .regular))
                .foregroundStyle(Color(red: 249 / 255, green: 115 / 255, blue: 22 / 255))
            Text("Enable biometrics")
                .font(.system(size: 28, weight: .bold))
            Text("Use Face ID / Touch ID for faster secure access. You can skip and do this later.")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color(white: 0.45))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)

            Button {
                Task { await enableBiometrics() }
            } label: {
                Text(biometricOK ? "Fingerprint enabled" : "Press Fingerprint")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(Color(red: 249 / 255, green: 115 / 255, blue: 22 / 255))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .padding(.horizontal, 28)

            Spacer()
        }
    }

    private var notificationsStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Stay in the loop")
                .font(.system(size: 28, weight: .bold))
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
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                }
            } else {
                VStack(spacing: 22) {
                    Spacer()
                    Text(scoreTitle)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))

                    Text("+\(score)")
                        .font(.system(size: 72, weight: .bold))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 28)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                        .padding(.horizontal, 36)

                    Text(scoreMessage)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)

                    Spacer()

                    Button {
                        store.markProfileSetupCompleted()
                        dismiss()
                    } label: {
                        Text("GET STARTED")
                            .font(.system(size: 17, weight: .bold))
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

    private func hydrateDraft() {
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
           let symbol = UserDefaults.standard.string(forKey: "profile.avatar.\(userId)") {
            draft.avatarSymbol = symbol
        }
    }

    private func saveProfile() {
        let weight = Double(draft.weightText.replacingOccurrences(of: ",", with: "."))
        store.applyProfileSetup(
            gender: draft.gender,
            location: draft.location,
            heightCm: store.session?.role == .trainee ? Int(draft.heightCm) : nil,
            weightKg: store.session?.role == .trainee ? weight : nil
        )
        if let userId = store.session?.userId {
            UserDefaults.standard.set(draft.avatarSymbol, forKey: "profile.avatar.\(userId)")
            UserDefaults.standard.set(draft.notifyWorkouts, forKey: "notify.workouts.\(userId)")
            UserDefaults.standard.set(draft.notifyMessages, forKey: "notify.messages.\(userId)")
            UserDefaults.standard.set(draft.notifyProgress, forKey: "notify.progress.\(userId)")
        }
        store.updateCurrentUserName(draft.name)
    }

    private func computeScore() -> Int {
        var value = 40
        if !draft.location.isEmpty { value += 8 }
        if draft.password.count >= 8 { value += 10 }
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
        icon: String,
        text: Binding<String>,
        keyboard: UIKeyboardType = .default,
        disabled: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .foregroundStyle(Color(white: 0.45))
                    .frame(width: 20)
                TextField(title, text: text)
                    .keyboardType(keyboard)
                    .disabled(disabled)
            }
            .padding(.horizontal, 14)
            .frame(height: 52)
            .background(Color(white: 0.97))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color(white: 0.78), lineWidth: 1.2)
            )
        }
    }

    private func secureField(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
            SecureField(title, text: text)
                .padding(.horizontal, 14)
                .frame(height: 52)
                .background(Color(white: 0.97))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color(white: 0.78), lineWidth: 1.2)
                )
        }
    }

    private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(selected ? .white : .black)
                .frame(maxWidth: .infinity)
                .frame(height: 42)
                .background(selected ? Color(red: 37 / 255, green: 99 / 255, blue: 235 / 255) : Color(white: 0.94))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func notificationRow(_ title: String, icon: String, color: Color, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(color)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            Text(title)
                .font(.system(size: 16, weight: .semibold))
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
    var avatarSymbol = "person.fill"
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

    static let avatarChoices = [
        "person.fill", "figure.run", "figure.strengthtraining.traditional",
        "figure.yoga", "heart.fill", "flame.fill", "star.fill", "bolt.fill"
    ]
}

#Preview("Profile Completion") {
    ProfileCompletionFlowView()
        .ttPreviewTrainee()
}
