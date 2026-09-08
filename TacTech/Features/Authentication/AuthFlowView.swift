import SwiftUI

enum AuthRoute: Hashable {
    case login
    case signup
    case role(SignupDraft)
    case resetPassword(String)
}

struct SignupDraft: Hashable {
    var name: String
    var email: String
    var password: String
}

struct AuthFlowView: View {
    @AppStorage("hasCompletedWelcome") private var hasCompletedWelcome = false
    @State private var path: [AuthRoute] = []

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if hasCompletedWelcome {
                    WelcomeView(
                        onLogin: { path.append(.login) },
                        onSignup: { path.append(.signup) }
                    )
                } else {
                    WelcomeOnboardingView {
                        withAnimation(.easeInOut(duration: 0.35)) {
                            hasCompletedWelcome = true
                        }
                    }
                }
            }
            .navigationDestination(for: AuthRoute.self) { route in
                switch route {
                case .login:
                    LoginView(
                        onSignUp: { path.append(.signup) },
                        onForgot: { path.append(.resetPassword($0)) }
                    )
                case .signup:
                    SignupView(
                        onSignIn: { path = [.login] },
                        onContinue: { path.append(.role($0)) }
                    )
                case .role(let draft):
                    RoleSelectionView(draft: draft)
                case .resetPassword(let email):
                    ResetPasswordView(email: email)
                }
            }
        }
    }
}

struct WelcomeView: View {
    let onLogin: () -> Void
    let onSignup: () -> Void

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                Image("OnboardingHero")
                    .resizable()
                    .scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()

                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0.32),
                        .init(color: .black.opacity(0.55), location: 0.58),
                        .init(color: .black.opacity(0.92), location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                VStack(spacing: 0) {
                    Spacer()
                    VStack(spacing: 12) {
                        Text("TACTECH")
                            .font(TTFont.workSans(13, weight: .semibold))
                            .tracking(3)
                            .foregroundStyle(.white.opacity(0.72))
                        Text("Train with\nclarity.")
                            .font(TTFont.workSans(42, weight: .bold))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                        Text("One app for coaches and athletes.")
                            .font(TTFont.workSans(17, weight: .regular))
                            .foregroundStyle(.white.opacity(0.88))
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 28)
                    .padding(.bottom, 28)

                    VStack(spacing: 12) {
                        Button(action: onSignup) {
                            Text("Create account")
                                .font(TTFont.workSans(17, weight: .semibold))
                                .foregroundStyle(.black)
                                .frame(maxWidth: .infinity)
                                .frame(height: 58)
                                .background(Color.white)
                                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                        }
                        Button(action: onLogin) {
                            Text("I already have an account")
                                .font(TTFont.workSans(17, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 58)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                                        .stroke(Color.white.opacity(0.55), lineWidth: 1)
                                )
                        }
                    }
                    .padding(.horizontal, 24)

                    demoHint
                        .padding(.top, 16)
                        .padding(.bottom, 8)
                }
            }
        }
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
        .toolbar(.hidden, for: .navigationBar)
    }

    private var demoHint: some View {
        VStack(spacing: 4) {
            Text("Demo accounts")
                .font(TTFont.workSans(11, weight: .medium))
                .foregroundStyle(.white.opacity(0.45))
            Text("trainer@tactech.app / trainer123")
                .font(TTFont.workSans(12, weight: .regular))
                .foregroundStyle(.white.opacity(0.62))
            Text("trainee@tactech.app / trainee123")
                .font(TTFont.workSans(12, weight: .regular))
                .foregroundStyle(.white.opacity(0.62))
        }
        .frame(maxWidth: .infinity)
    }
}

struct RoleSelectionView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let draft: SignupDraft

    @State private var name: String
    @State private var role: UserRole = .trainee
    @State private var inviteCode = ""
    @State private var error: String?
    @State private var isLoading = false
    @FocusState private var nameFocused: Bool
    @FocusState private var inviteFocused: Bool

    private let orange = TTColor.actionOrange
    private let ink = Color.black
    private let muted = Color(white: 0.42)
    private let selectSpring = Animation.spring(response: 0.42, dampingFraction: 0.84)

    init(draft: SignupDraft) {
        self.draft = draft
        _name = State(initialValue: draft.name)
    }

    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    header
                        .padding(.bottom, 20)

                    titleBlock
                        .padding(.bottom, 24)

                    roleCards
                        .padding(.bottom, 24)

                    detailsBlock
                        .padding(.bottom, 16)

                    if let error {
                        Text(error)
                            .font(TTFont.workSans(13, weight: .semibold))
                            .foregroundStyle(Color(red: 0.86, green: 0.15, blue: 0.15))
                            .padding(.bottom, 12)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    continueButton
                        .padding(.bottom, 32)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
            }
        }
        .background(Color.white.ignoresSafeArea())
        .ttHideSystemNavigationBar()
        .preferredColorScheme(.light)
        .toolbarBackground(Color.white, for: .navigationBar)
        .sensoryFeedback(.selection, trigger: role)
        .animation(selectSpring, value: role)
        .animation(selectSpring, value: error != nil)
    }

    // MARK: - Header / Title

    private var header: some View {
        HStack {
            TTBackButton(style: .onLight) { dismiss() }
            Spacer()
            Text("STEP 2 OF 2")
                .font(TTFont.workSans(11, weight: .bold))
                .tracking(1.4)
                .foregroundStyle(ink)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(white: 0.94))
                .clipShape(Capsule())
        }
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Choose your path")
                .font(TTFont.workSans(32, weight: .bold))
                .foregroundStyle(ink)

            Text("Pick Trainer or Trainee. Tools and screens will match the role you choose.")
                .font(TTFont.workSans(16, weight: .medium))
                .foregroundStyle(muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Role cards

    private var roleCards: some View {
        VStack(spacing: 14) {
            ForEach(Array(UserRole.allCases.enumerated()), id: \.element.id) { index, option in
                RolePathCard(
                    role: option,
                    isSelected: role == option,
                    index: index
                ) {
                    withAnimation(selectSpring) {
                        role = option
                    }
                }
            }
        }
    }

    // MARK: - Details

    private var detailsBlock: some View {
        VStack(alignment: .leading, spacing: 14) {
            fieldLabel("Your name")
            HStack(spacing: 12) {
                TTIcon(icon: .user, size: 18)
                    .foregroundStyle(nameFocused ? orange : ink.opacity(0.45))
                TextField("Full name", text: $name)
                    .font(TTFont.workSans(16, weight: .medium))
                    .foregroundStyle(ink)
                    .focused($nameFocused)
                    .tint(orange)
            }
            .padding(.horizontal, 14)
            .frame(height: 54)
            .ttInputChrome(focused: nameFocused, cornerRadius: 16, idleFill: Color(white: 0.96))

            if role == .trainee {
                VStack(alignment: .leading, spacing: 8) {
                    fieldLabel("Trainer invite (optional)")
                    HStack(spacing: 12) {
                        TTIcon(icon: .link1, size: 18)
                            .foregroundStyle(inviteFocused ? orange : ink.opacity(0.45))
                        TextField("e.g. TACT-MAYA", text: $inviteCode)
                            .font(TTFont.workSans(16, weight: .medium))
                            .foregroundStyle(ink)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .focused($inviteFocused)
                            .tint(orange)
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 54)
                    .ttInputChrome(focused: inviteFocused, cornerRadius: 16, idleFill: Color(white: 0.96))

                    Text("Use TACT-MAYA to join the demo trainer.")
                        .font(TTFont.workSans(12, weight: .medium))
                        .foregroundStyle(muted)
                }
                .transition(
                    .asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .top)).combined(with: .scale(scale: 0.98)),
                        removal: .opacity.combined(with: .scale(scale: 0.98))
                    )
                )
            }
        }
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(TTFont.workSans(11, weight: .bold))
            .tracking(0.8)
            .foregroundStyle(ink.opacity(0.55))
    }

    private var continueButton: some View {
        let canContinue = !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return Button {
            Task { await createAccount() }
        } label: {
            HStack(spacing: 10) {
                if isLoading {
                    ProgressView().tint(.white)
                } else {
                    Text("Continue to assessment")
                        .font(TTFont.workSans(17, weight: .semibold))
                    Spacer(minLength: 8)
                    Image(systemName: "arrow.right")
                        .font(TTFont.workSans(16, weight: .semibold))
                        .symbolEffect(.bounce, value: role)
                }
            }
            .padding(.horizontal, 18)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 58)
            .background(Color.black)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: Color.black.opacity(canContinue ? 0.16 : 0), radius: 14, y: 7)
        }
        .buttonStyle(AssessmentCardPressStyle())
        .disabled(isLoading || !canContinue)
        .opacity(canContinue ? 1 : 0.45)
        .animation(selectSpring, value: canContinue)
    }

    private func createAccount() async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            try await store.signup(
                name: name,
                email: draft.email,
                password: draft.password,
                role: role,
                inviteCode: inviteCode.isEmpty ? nil : inviteCode
            )
        } catch {
            withAnimation(selectSpring) {
                self.error = error.localizedDescription
            }
        }
    }
}

// MARK: - Role path card (assessment-style motion)

private struct RolePathCard: View {
    let role: UserRole
    let isSelected: Bool
    var index: Int = 0
    let onSelect: () -> Void

    @State private var appeared = false

    private let orange = TTColor.actionOrange
    private let ink = Color.black
    private let muted = Color(white: 0.42)
    private let selectSpring = Animation.spring(response: 0.42, dampingFraction: 0.84)

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 0) {
                ZStack {
                    Image(role.imageName)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 118, height: 148)
                        .scaleEffect(isSelected ? 1.08 : 1.0)

                    LinearGradient(
                        colors: [.clear, .black.opacity(0.18)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
                .frame(width: 118, height: 148)
                .clipped()

                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 8) {
                                TTIcon(icon: role.sandowIcon, filled: true, size: 16)
                                    .foregroundStyle(isSelected ? orange : ink)
                                Text(role.title)
                                    .font(TTFont.workSans(18, weight: .bold))
                                    .foregroundStyle(ink)
                            }
                            Text(role.headline)
                                .font(TTFont.workSans(13, weight: .semibold))
                                .foregroundStyle(isSelected ? orange : muted)
                        }

                        Spacer(minLength: 8)

                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .font(TTFont.workSans(22, weight: .semibold))
                            .foregroundStyle(isSelected ? orange : Color(white: 0.72))
                            .symbolEffect(.bounce, value: isSelected)
                    }

                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(role.perks, id: \.self) { perk in
                            HStack(alignment: .top, spacing: 7) {
                                Circle()
                                    .fill(isSelected ? orange : Color(white: 0.7))
                                    .frame(width: 5, height: 5)
                                    .padding(.top, 5)
                                Text(perk)
                                    .font(TTFont.workSans(12, weight: .medium))
                                    .foregroundStyle(ink.opacity(0.72))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity, minHeight: 148, alignment: .leading)
                .background(Color.white)
            }
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(
                        isSelected ? orange : Color.black.opacity(0.08),
                        lineWidth: isSelected ? 2.5 : 1
                    )
            )
            .shadow(
                color: isSelected ? orange.opacity(0.22) : Color.black.opacity(0.06),
                radius: isSelected ? 14 : 8,
                y: isSelected ? 6 : 3
            )
            .scaleEffect(appeared ? (isSelected ? 1.015 : 1) : 0.94)
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 18)
        }
        .buttonStyle(AssessmentCardPressStyle())
        .animation(selectSpring, value: isSelected)
        .sensoryFeedback(.selection, trigger: isSelected)
        .onAppear {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.84).delay(Double(index) * 0.06)) {
                appeared = true
            }
        }
        .accessibilityLabel("\(role.title). \(role.subtitle)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

#Preview("Auth Flow") {
    AuthFlowView()
        .ttPreviewTrainee()
}

#Preview("Welcome") {
    WelcomeView(onLogin: {}, onSignup: {})
}

#Preview("Role Selection") {
    NavigationStack {
        RoleSelectionView(draft: SignupDraft(name: "Maya", email: "trainee@tactech.app", password: "secret1"))
            .ttPreviewTrainee()
    }
}
