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
                            .font(.system(size: 13, weight: .semibold))
                            .tracking(3)
                            .foregroundStyle(.white.opacity(0.72))
                        Text("Train with\nclarity.")
                            .font(.system(size: 42, weight: .bold))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                        Text("One app for coaches and athletes.")
                            .font(.system(size: 17, weight: .regular))
                            .foregroundStyle(.white.opacity(0.88))
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 28)
                    .padding(.bottom, 28)

                    VStack(spacing: 12) {
                        Button(action: onSignup) {
                            Text("Create account")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(.black)
                                .frame(maxWidth: .infinity)
                                .frame(height: 58)
                                .background(Color.white)
                                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                        }
                        Button(action: onLogin) {
                            Text("I already have an account")
                                .font(.system(size: 17, weight: .semibold))
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
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.45))
            Text("trainer@tactech.app / trainer123")
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(.white.opacity(0.62))
            Text("trainee@tactech.app / trainee123")
                .font(.system(size: 12, weight: .regular))
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
    @State private var appeared = false
    @State private var pulse = false
    @FocusState private var nameFocused: Bool
    @FocusState private var inviteFocused: Bool

    private let orange = TTColor.actionOrange

    init(draft: SignupDraft) {
        self.draft = draft
        _name = State(initialValue: draft.name)
    }

    var body: some View {
        ZStack {
            backgroundLayer

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    header
                        .padding(.bottom, 18)

                    titleBlock
                        .padding(.bottom, 22)

                    roleCards
                        .padding(.bottom, 22)

                    detailsBlock
                        .padding(.bottom, 18)

                    if let error {
                        Text(error)
                            .font(TTFont.caption(13))
                            .foregroundStyle(TTColor.danger)
                            .padding(.bottom, 12)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    continueButton
                        .padding(.bottom, 28)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
            }
        }
        .ttHideSystemNavigationBar()
        .preferredColorScheme(.light)
        .onAppear {
            withAnimation(.spring(response: 0.72, dampingFraction: 0.84)) {
                appeared = true
            }
            withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
        .sensoryFeedback(.selection, trigger: role)
    }

    // MARK: - Background

    private var backgroundLayer: some View {
        ZStack {
            Color.white.ignoresSafeArea()

            Circle()
                .fill(orange.opacity(0.16))
                .frame(width: 280, height: 280)
                .blur(radius: 48)
                .offset(x: pulse ? 40 : -30, y: pulse ? -120 : -80)
                .ignoresSafeArea()

            Circle()
                .fill(Color.black.opacity(0.05))
                .frame(width: 220, height: 220)
                .blur(radius: 40)
                .offset(x: pulse ? -90 : -50, y: pulse ? 420 : 380)
                .ignoresSafeArea()
        }
    }

    // MARK: - Header / Title

    private var header: some View {
        HStack {
            TTBackButton(style: .onLight) { dismiss() }
            Spacer()
            Text("STEP 2 OF 2")
                .font(TTFont.caption(11))
                .tracking(1.2)
                .foregroundStyle(TTColor.inkMuted)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Color(white: 0.94))
                .clipShape(Capsule())
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : -12)
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Choose your path")
                .font(.system(size: 32, weight: .bold))
                .foregroundStyle(TTColor.ink)

            Text("Pick how you’ll use TacTech. You can always coach or train with full tools for your role.")
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(TTColor.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 18)
    }

    // MARK: - Role cards

    private var roleCards: some View {
        HStack(alignment: .top, spacing: 14) {
            ForEach(Array(UserRole.allCases.enumerated()), id: \.element.id) { index, option in
                RolePathCard(
                    role: option,
                    isSelected: role == option,
                    pulse: pulse
                ) {
                    withAnimation(.spring(response: 0.42, dampingFraction: 0.78)) {
                        self.role = option
                    }
                }
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 36)
                .scaleEffect(appeared ? 1 : 0.92)
                .animation(
                    .spring(response: 0.62, dampingFraction: 0.82).delay(0.08 + Double(index) * 0.08),
                    value: appeared
                )
            }
        }
    }

    // MARK: - Details

    private var detailsBlock: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Text("YOUR NAME")
                    .font(TTFont.caption(11))
                    .foregroundStyle(TTColor.inkMuted)
                HStack(spacing: 12) {
                    TTIcon(icon: .user, size: 18)
                        .foregroundStyle(nameFocused ? orange : TTColor.inkMuted)
                    TextField("Full name", text: $name)
                        .font(TTFont.body(16))
                        .focused($nameFocused)
                        .tint(orange)
                }
                .padding(.horizontal, 14)
                .frame(height: 54)
                .ttInputChrome(focused: nameFocused, cornerRadius: 16, idleFill: Color(white: 0.96))
            }
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 20)
            .animation(.spring(response: 0.62, dampingFraction: 0.84).delay(0.22), value: appeared)

            if role == .trainee {
                VStack(alignment: .leading, spacing: 8) {
                    Text("TRAINER INVITE (OPTIONAL)")
                        .font(TTFont.caption(11))
                        .foregroundStyle(TTColor.inkMuted)
                    HStack(spacing: 12) {
                        TTIcon(icon: .link1, size: 18)
                            .foregroundStyle(inviteFocused ? orange : TTColor.inkMuted)
                        TextField("e.g. TACT-MAYA", text: $inviteCode)
                            .font(TTFont.body(16))
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .focused($inviteFocused)
                            .tint(orange)
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 54)
                    .ttInputChrome(focused: inviteFocused, cornerRadius: 16, idleFill: Color(white: 0.96))

                    Text("Use TACT-MAYA to join the demo trainer.")
                        .font(TTFont.caption(12))
                        .foregroundStyle(TTColor.inkSubtle)
                }
                .transition(
                    .asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .top)).combined(with: .scale(scale: 0.98)),
                        removal: .opacity.combined(with: .scale(scale: 0.98))
                    )
                )
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.86), value: role)
    }

    private var continueButton: some View {
        Button {
            Task { await createAccount() }
        } label: {
            HStack(spacing: 10) {
                if isLoading {
                    ProgressView().tint(.white)
                } else {
                    Text("Continue to assessment")
                        .font(.system(size: 17, weight: .semibold))
                    Spacer(minLength: 8)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 16, weight: .semibold))
                }
            }
            .padding(.horizontal, 18)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 58)
            .background(
                LinearGradient(
                    colors: [Color.black, Color(white: 0.18)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: Color.black.opacity(0.18), radius: 16, y: 8)
        }
        .buttonStyle(TTSearchPressStyle(scale: 0.98))
        .disabled(isLoading || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        .opacity(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.55 : 1)
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 24)
        .animation(.spring(response: 0.62, dampingFraction: 0.84).delay(0.3), value: appeared)
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
            withAnimation(.spring(response: 0.4, dampingFraction: 0.86)) {
                self.error = error.localizedDescription
            }
        }
    }
}

// MARK: - Role path card

private struct RolePathCard: View {
    let role: UserRole
    let isSelected: Bool
    var pulse: Bool
    let onSelect: () -> Void

    private let orange = TTColor.actionOrange

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .topTrailing) {
                    Image(role.imageName)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity)
                        .frame(height: 168)
                        .clipped()
                        .scaleEffect(isSelected ? 1.06 : 1.0)
                        .animation(.spring(response: 0.55, dampingFraction: 0.84), value: isSelected)

                    LinearGradient(
                        colors: [
                            .clear,
                            .black.opacity(0.15),
                            .black.opacity(0.72)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )

                    selectionBadge
                        .padding(10)
                }
                .frame(height: 168)
                .clipped()

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        TTIcon(icon: role.sandowIcon, filled: true, size: 16)
                            .foregroundStyle(isSelected ? orange : TTColor.inkMuted)
                        Text(role.title)
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(TTColor.ink)
                    }

                    Text(role.headline)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(isSelected ? orange : TTColor.inkMuted)

                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(role.perks, id: \.self) { perk in
                            HStack(alignment: .top, spacing: 6) {
                                Circle()
                                    .fill(isSelected ? orange : Color(white: 0.75))
                                    .frame(width: 5, height: 5)
                                    .padding(.top, 5)
                                Text(perk)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(TTColor.inkMuted)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .padding(.top, 2)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white)
            }
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(
                        isSelected ? orange : Color.black.opacity(0.06),
                        lineWidth: isSelected ? 2.5 : 1
                    )
            )
            .shadow(
                color: isSelected ? orange.opacity(pulse ? 0.34 : 0.18) : Color.black.opacity(0.08),
                radius: isSelected ? 18 : 10,
                y: isSelected ? 10 : 6
            )
            .scaleEffect(isSelected ? 1.02 : 1.0)
            .offset(y: isSelected ? -2 : 0)
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.42, dampingFraction: 0.8), value: isSelected)
        .accessibilityLabel("\(role.title). \(role.subtitle)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var selectionBadge: some View {
        ZStack {
            Circle()
                .fill(isSelected ? orange : Color.white.opacity(0.85))
                .frame(width: 30, height: 30)
                .shadow(color: .black.opacity(0.15), radius: 4, y: 2)

            if isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                    .transition(.scale.combined(with: .opacity))
            } else {
                Circle()
                    .strokeBorder(Color.black.opacity(0.2), lineWidth: 1.5)
                    .frame(width: 18, height: 18)
            }
        }
        .animation(.spring(response: 0.38, dampingFraction: 0.7), value: isSelected)
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
