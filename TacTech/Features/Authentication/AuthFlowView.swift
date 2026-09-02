import SwiftUI

enum AuthRoute: Hashable {
    case login
    case signup
    case role(SignupDraft)
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
                    LoginView()
                case .signup:
                    SignupView { draft in
                        path.append(.role(draft))
                    }
                case .role(let draft):
                    RoleSelectionView(draft: draft)
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

struct LoginView: View {
    @Environment(AppStore.self) private var store
    @State private var email = ""
    @State private var password = ""
    @State private var error: String?
    @State private var isLoading = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                TTScreenHeader(eyebrow: "Welcome back", title: "Sign in")
                VStack(spacing: 16) {
                    TTTextField(title: "Email", icon: "envelope", text: $email)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                    TTTextField(title: "Password", icon: "lock", isSecure: true, text: $password)
                }
                if let error {
                    Text(error)
                        .font(TTFont.caption(13))
                        .foregroundStyle(TTColor.danger)
                }
                TTButton(title: "Continue", isLoading: isLoading) {
                    Task { await signIn() }
                }
            }
            .padding(24)
        }
        .ttScreenBackground()
        .navigationBarTitleDisplayMode(.inline)
    }

    private func signIn() async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            try await store.login(email: email, password: password)
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct SignupView: View {
    let onContinue: (SignupDraft) -> Void
    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                TTScreenHeader(eyebrow: "New member", title: "Create account")
                VStack(spacing: 16) {
                    TTTextField(title: "Full name", icon: "person", text: $name)
                    TTTextField(title: "Email", icon: "envelope", text: $email)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                    TTTextField(title: "Password", icon: "lock", isSecure: true, text: $password)
                }
                if let error {
                    Text(error)
                        .font(TTFont.caption(13))
                        .foregroundStyle(TTColor.danger)
                }
                TTButton(title: "Choose your role") {
                    guard name.trimmingCharacters(in: .whitespaces).count > 1 else {
                        error = "Enter your full name."
                        return
                    }
                    guard email.contains("@") else {
                        error = "Enter a valid email."
                        return
                    }
                    guard password.count >= 6 else {
                        error = "Password must be at least 6 characters."
                        return
                    }
                    onContinue(SignupDraft(name: name, email: email, password: password))
                }
            }
            .padding(24)
        }
        .ttScreenBackground()
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct RoleSelectionView: View {
    @Environment(AppStore.self) private var store
    let draft: SignupDraft
    @State private var role: UserRole = .trainee
    @State private var inviteCode = ""
    @State private var error: String?
    @State private var isLoading = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                TTScreenHeader(eyebrow: "How will you use TacTech?", title: "Select role")
                VStack(spacing: 12) {
                    ForEach(UserRole.allCases) { option in
                        Button {
                            role = option
                        } label: {
                            HStack(spacing: 14) {
                                Image(systemName: option.icon)
                                    .font(.system(size: 20, weight: .semibold))
                                    .foregroundStyle(role == option ? TTColor.brand : TTColor.inkMuted)
                                    .frame(width: 48, height: 48)
                                    .background(role == option ? TTColor.brandSoft : TTColor.surfaceAlt)
                                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(option.title)
                                        .font(TTFont.heading(17))
                                        .foregroundStyle(TTColor.ink)
                                    Text(option.subtitle)
                                        .font(TTFont.body(13))
                                        .foregroundStyle(TTColor.inkMuted)
                                        .multilineTextAlignment(.leading)
                                }
                                Spacer()
                                Image(systemName: role == option ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(role == option ? TTColor.brand : TTColor.inkSubtle)
                            }
                            .ttCard()
                        }
                        .buttonStyle(.plain)
                    }
                }

                if role == .trainee {
                    TTTextField(title: "Trainer invite code (optional)", icon: "link", text: $inviteCode)
                    Text("Use TACT-MAYA to join the demo trainer.")
                        .font(TTFont.caption(12))
                        .foregroundStyle(TTColor.inkSubtle)
                }

                if let error {
                    Text(error)
                        .font(TTFont.caption(13))
                        .foregroundStyle(TTColor.danger)
                }

                TTButton(title: "Enter TacTech", isLoading: isLoading) {
                    Task { await createAccount() }
                }
            }
            .padding(24)
        }
        .ttScreenBackground()
        .navigationBarTitleDisplayMode(.inline)
    }

    private func createAccount() async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            try await store.signup(
                name: draft.name,
                email: draft.email,
                password: draft.password,
                role: role,
                inviteCode: inviteCode.isEmpty ? nil : inviteCode
            )
        } catch {
            self.error = error.localizedDescription
        }
    }
}
