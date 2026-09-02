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
    @State private var path: [AuthRoute] = []

    var body: some View {
        NavigationStack(path: $path) {
            WelcomeView(
                onLogin: { path.append(.login) },
                onSignup: { path.append(.signup) }
            )
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
        VStack(alignment: .leading, spacing: 0) {
            Spacer()
            VStack(alignment: .leading, spacing: 18) {
                Text("TACTECH")
                    .font(TTFont.caption(12))
                    .tracking(2.4)
                    .foregroundStyle(TTColor.brand)
                Text("Train with\nclarity.")
                    .font(TTFont.display(42))
                    .foregroundStyle(TTColor.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text("One app for coaches and athletes. Assign plans, correct form, and track nutrition in the same place.")
                    .font(TTFont.body(16))
                    .foregroundStyle(TTColor.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            VStack(spacing: 12) {
                TTButton(title: "Create account", icon: "arrow.right", action: onSignup)
                TTButton(title: "I already have an account", style: .secondary, action: onLogin)
            }
            demoHint
        }
        .padding(24)
        .ttScreenBackground()
    }

    private var demoHint: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Demo accounts")
                .font(TTFont.caption(11))
                .foregroundStyle(TTColor.inkSubtle)
            Text("trainer@tactech.app / trainer123")
                .font(TTFont.caption(12))
                .foregroundStyle(TTColor.inkMuted)
            Text("trainee@tactech.app / trainee123")
                .font(TTFont.caption(12))
                .foregroundStyle(TTColor.inkMuted)
        }
        .padding(.top, 18)
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
