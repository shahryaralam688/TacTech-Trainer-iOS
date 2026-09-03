import SwiftUI

private enum AuthPalette {
    static let ink = Color.black
    static let muted = Color(white: 0.45)
    static let field = Color(white: 0.96)
    static let line = Color(white: 0.90)
    static let accent = Color(red: 1.0, green: 0.43, blue: 0.08)
    static let brand = Color(red: 0.694, green: 0.325, blue: 0.122)
    static let error = Color(red: 0.90, green: 0.18, blue: 0.20)
    static let errorSoft = Color(red: 1.0, green: 0.92, blue: 0.93)
}

enum AuthField: Hashable {
    case email, password, confirm, name
}

private enum AuthLayout {
    static let formMaxWidth: CGFloat = 440

    /// Outer screen margin for auth forms — keeps fields/buttons off the screen edge.
    static func screenHorizontalPadding(for width: CGFloat) -> CGFloat {
        switch width {
        case ..<360: return 24
        case ..<390: return 28
        case ..<430: return 32
        default:     return 36
        }
    }

    /// Inner padding inside text fields.
    static let fieldHorizontalPadding: CGFloat = 18
}

struct LoginView: View {
    @Environment(AppStore.self) private var store
    var onSignUp: () -> Void
    var onForgot: (String) -> Void

    @State private var email = ""
    @State private var password = ""
    @State private var showPassword = false
    @State private var error: String?
    @State private var isLoading = false
    @FocusState private var focused: AuthField?

    var body: some View {
        AuthFormCanvas {
            AuthHeroHeader(
                title: "Sign In To TacTech",
                subtitle: "Let's personalize your fitness with AI"
            )

            VStack(alignment: .leading, spacing: 18) {
                AuthLabeledField(
                    title: "Email Address",
                    icon: "envelope",
                    text: $email,
                    isFocused: focused == .email,
                    field: .email,
                    focus: $focused,
                    keyboard: .emailAddress
                )

                AuthLabeledField(
                    title: "Password",
                    icon: "lock",
                    text: $password,
                    isSecure: !showPassword,
                    isFocused: focused == .password,
                    field: .password,
                    focus: $focused
                ) {
                    AuthEyeButton(isVisible: $showPassword)
                }

                if let error {
                    AuthErrorBanner(message: error)
                }

                AuthBlackButton(title: "Sign In", isLoading: isLoading) {
                    Task { await signIn() }
                }

                AuthSocialRow()

                VStack(spacing: 10) {
                    AuthFooterLink(prompt: "Don't have an account?", actionTitle: "Sign Up.") {
                        onSignUp()
                    }
                    Button("Forgot Password") { onForgot(email) }
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(AuthPalette.brand)
                        .underline()
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
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
    var onSignIn: () -> Void
    var onContinue: (SignupDraft) -> Void

    @State private var email = ""
    @State private var password = ""
    @State private var confirm = ""
    @State private var showPassword = false
    @State private var showConfirm = false
    @State private var submitted = false
    @State private var error: String?
    @FocusState private var focused: AuthField?

    private var mismatch: Bool {
        submitted && !confirm.isEmpty && password != confirm
    }

    var body: some View {
        AuthFormCanvas {
            AuthHeroHeader(
                title: "Sign Up For Free",
                subtitle: "Quickly make your account in 1 minute"
            )

            VStack(alignment: .leading, spacing: 18) {
                AuthLabeledField(
                    title: "Email Address",
                    icon: "envelope",
                    text: $email,
                    isFocused: focused == .email,
                    field: .email,
                    focus: $focused,
                    keyboard: .emailAddress
                )

                AuthLabeledField(
                    title: "Password",
                    icon: "lock",
                    text: $password,
                    isSecure: !showPassword,
                    isFocused: focused == .password,
                    field: .password,
                    focus: $focused
                ) {
                    AuthEyeButton(isVisible: $showPassword)
                }

                AuthLabeledField(
                    title: "Confirm Password",
                    icon: "lock",
                    text: $confirm,
                    isSecure: !showConfirm,
                    isFocused: focused == .confirm,
                    isError: mismatch,
                    field: .confirm,
                    focus: $focused
                ) {
                    AuthEyeButton(isVisible: $showConfirm)
                }

                if mismatch {
                    AuthErrorBanner(message: "ERROR: Password Don't Match!")
                } else if let error {
                    AuthErrorBanner(message: error)
                }

                AuthBlackButton(title: "Sign Up") {
                    submitted = true
                    error = nil
                    guard email.contains("@") else {
                        error = "ERROR: Enter a valid email."
                        return
                    }
                    guard password.count >= 6 else {
                        error = "ERROR: Password must be at least 6 characters."
                        return
                    }
                    guard password == confirm else { return }
                    onContinue(SignupDraft(name: "", email: email, password: password))
                }

                AuthFooterLink(prompt: "Already have an account?", actionTitle: "Sign In.") {
                    onSignIn()
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 6)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

enum ResetMethod: String, CaseIterable, Identifiable {
    case email
    case twoFactor
    case googleAuth

    var id: String { rawValue }

    var title: String {
        switch self {
        case .email: "Send via Email"
        case .twoFactor: "Send via 2FA"
        case .googleAuth: "Send via Google Auth"
        }
    }

    var subtitle: String {
        switch self {
        case .email: "Seamlessly reset your password via email address."
        case .twoFactor: "Seamlessly reset your password via 2 Factors."
        case .googleAuth: "Seamlessly reset your password via gAuth."
        }
    }

    var icon: String {
        switch self {
        case .email: "envelope.fill"
        case .twoFactor: "lock.fill"
        case .googleAuth: "flame.fill"
        }
    }

    var tint: Color {
        switch self {
        case .email: AuthPalette.accent
        case .twoFactor: Color(red: 0.18, green: 0.52, blue: 1.0)
        case .googleAuth: Color(red: 0.56, green: 0.32, blue: 0.94)
        }
    }
}

struct ResetPasswordView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State var email: String
    @State private var method: ResetMethod = .email
    @State private var error: String?
    @State private var isLoading = false
    @State private var showSent = false
    @FocusState private var focused: AuthField?

    var body: some View {
        GeometryReader { geo in
            let horizontalPad = AuthLayout.screenHorizontalPadding(for: geo.size.width)

            ZStack(alignment: .bottom) {
                Color.white.ignoresSafeArea()

                Image("AuthPadlock")
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: min(280, geo.size.width * 0.72))
                    .padding(.trailing, -36)
                    .padding(.bottom, -28)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .allowsHitTesting(false)

                VStack(alignment: .leading, spacing: 0) {
                    TTBackButton { dismiss() }
                        .padding(.bottom, 22)

                    Text("Reset Password")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundStyle(AuthPalette.ink)
                    Text("Select what method you’d like to reset.")
                        .font(.system(size: 16, weight: .regular))
                        .foregroundStyle(AuthPalette.muted)
                        .padding(.top, 6)
                        .padding(.bottom, 22)

                    VStack(spacing: 12) {
                        ForEach(ResetMethod.allCases) { item in
                            Button { method = item } label: {
                                ResetMethodRow(method: item, isSelected: method == item)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    if method == .email {
                        AuthLabeledField(
                            title: "Email Address",
                            icon: "envelope",
                            text: $email,
                            isFocused: focused == .email,
                            field: .email,
                            focus: $focused,
                            keyboard: .emailAddress
                        )
                        .padding(.top, 16)
                    }

                    if let error {
                        AuthErrorBanner(message: error)
                            .padding(.top, 14)
                    }

                    Spacer(minLength: 16)

                    AuthBlackButton(title: "Reset Password", isLoading: isLoading) {
                        Task { await reset() }
                    }
                    .padding(.bottom, 8)
                }
                .frame(maxWidth: AuthLayout.formMaxWidth, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, horizontalPad)
                .padding(.top, 8)
                .padding(.bottom, 12)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .preferredColorScheme(.light)
        .fullScreenCover(isPresented: $showSent) {
            PasswordSentView(email: email) {
                Task { await reset() }
            } onClose: {
                showSent = false
            }
        }
    }

    private func reset() async {
        error = nil
        guard method == .email else {
            error = "Only email reset is available right now."
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            try await store.requestPasswordReset(email: email)
            showSent = true
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct PasswordSentView: View {
    let email: String
    var onResend: () -> Void
    var onClose: () -> Void

    var body: some View {
        ZStack {
            Color(white: 0.93).ignoresSafeArea()
            Image("AuthPadlock")
                .resizable()
                .scaledToFill()
                .opacity(0.22)
                .blur(radius: 10)
                .ignoresSafeArea()

            VStack(spacing: 22) {
                Spacer()
                VStack(spacing: 18) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(Color(red: 0.20, green: 0.62, blue: 0.28))
                        .frame(width: 52, height: 52)
                        .background(Color(red: 0.86, green: 0.95, blue: 0.87))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                    Text("Password Sent!")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(AuthPalette.ink)

                    Text("We’ve sent the password to \(email.tactechMasked). Resend if the password is not received! 🔥")
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(AuthPalette.muted)
                        .multilineTextAlignment(.center)

                    Button(action: onResend) {
                        HStack {
                            Text("Re-Send Password")
                                .font(.system(size: 17, weight: .semibold))
                            Spacer()
                            Image(systemName: "lock")
                                .font(.system(size: 16, weight: .medium))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 22)
                        .frame(height: 56)
                        .background(Color.black)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                .padding(24)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
                .shadow(color: .black.opacity(0.08), radius: 24, y: 10)
                .padding(.horizontal, 28)

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(AuthPalette.ink)
                        .frame(width: 54, height: 54)
                        .background(Color.white)
                        .clipShape(Circle())
                        .shadow(color: .black.opacity(0.10), radius: 10, y: 4)
                }
                .buttonStyle(.plain)
                Spacer()
            }
        }
        .preferredColorScheme(.light)
    }
}

private struct AuthFormCanvas<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        GeometryReader { geo in
            let horizontalPad = AuthLayout.screenHorizontalPadding(for: geo.size.width)

            ZStack(alignment: .top) {
                Color.white.ignoresSafeArea()
                Image("AuthMachine")
                    .resizable()
                    .scaledToFill()
                    .frame(width: geo.size.width, height: min(320, geo.size.height * 0.38))
                    .clipped()
                    .opacity(0.28)
                    .mask(
                        LinearGradient(
                            colors: [.white, .white, .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .ignoresSafeArea(edges: .top)

                ScrollView {
                    VStack(spacing: 28) {
                        content()
                    }
                    .frame(maxWidth: AuthLayout.formMaxWidth)
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 32)
                }
                .contentMargins(.horizontal, horizontalPad, for: .scrollContent)
                .scrollDismissesKeyboard(.interactively)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .preferredColorScheme(.light)
    }
}

private struct AuthHeroHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "plus")
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 72, height: 72)
                .background(AuthPalette.accent)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .shadow(color: AuthPalette.accent.opacity(0.35), radius: 16, y: 8)
                .padding(.top, 86)

            Text(title)
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(AuthPalette.ink)
                .multilineTextAlignment(.center)
            Text(subtitle)
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(AuthPalette.muted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct AuthLabeledField<Trailing: View>: View {
    let title: String
    let icon: String
    @Binding var text: String
    var isSecure = false
    var isFocused = false
    var isError = false
    var field: AuthField?
    var focus: FocusState<AuthField?>.Binding?
    var keyboard: UIKeyboardType = .default
    var trailing: Trailing

    init(
        title: String,
        icon: String,
        text: Binding<String>,
        isSecure: Bool = false,
        isFocused: Bool = false,
        isError: Bool = false,
        field: AuthField? = nil,
        focus: FocusState<AuthField?>.Binding? = nil,
        keyboard: UIKeyboardType = .default,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.title = title
        self.icon = icon
        self._text = text
        self.isSecure = isSecure
        self.isFocused = isFocused
        self.isError = isError
        self.field = field
        self.focus = focus
        self.keyboard = keyboard
        self.trailing = trailing()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(AuthPalette.ink)
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(AuthPalette.ink)
                    .frame(width: 20)
                Group {
                    if isSecure {
                        SecureField("", text: $text)
                    } else {
                        TextField("", text: $text)
                    }
                }
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(AuthPalette.ink)
                .keyboardType(keyboard)
                .textInputAutocapitalization(keyboard == .emailAddress ? .never : .sentences)
                .textContentType(keyboard == .emailAddress ? .emailAddress : (isSecure ? .password : nil))
                .modifier(AuthFocusModifier(field: field, focus: focus))
                trailing
            }
            .padding(.horizontal, AuthLayout.fieldHorizontalPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 56)
            .background(isFocused || isError ? Color.white : AuthPalette.field)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(border, lineWidth: isFocused || isError ? 1.5 : 0)
            )
            .shadow(color: glow, radius: isFocused || isError ? 8 : 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var border: Color {
        if isError { return AuthPalette.error }
        if isFocused { return AuthPalette.accent }
        return .clear
    }

    private var glow: Color {
        if isError { return AuthPalette.error.opacity(0.18) }
        if isFocused { return AuthPalette.accent.opacity(0.22) }
        return .clear
    }
}

extension AuthLabeledField where Trailing == EmptyView {
    init(
        title: String,
        icon: String,
        text: Binding<String>,
        isSecure: Bool = false,
        isFocused: Bool = false,
        isError: Bool = false,
        field: AuthField? = nil,
        focus: FocusState<AuthField?>.Binding? = nil,
        keyboard: UIKeyboardType = .default
    ) {
        self.init(
            title: title,
            icon: icon,
            text: text,
            isSecure: isSecure,
            isFocused: isFocused,
            isError: isError,
            field: field,
            focus: focus,
            keyboard: keyboard
        ) { EmptyView() }
    }
}

private struct AuthFocusModifier: ViewModifier {
    var field: AuthField?
    var focus: FocusState<AuthField?>.Binding?

    func body(content: Content) -> some View {
        if let field, let focus {
            content.focused(focus, equals: field)
        } else {
            content
        }
    }
}

private struct AuthEyeButton: View {
    @Binding var isVisible: Bool

    var body: some View {
        Button {
            isVisible.toggle()
        } label: {
            Image(systemName: isVisible ? "eye.slash" : "eye")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Color(white: 0.62))
        }
        .buttonStyle(.plain)
    }
}

private struct AuthBlackButton: View {
    let title: String
    var isLoading = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if isLoading {
                    Spacer(minLength: 0)
                    ProgressView().tint(.white)
                    Spacer(minLength: 0)
                } else {
                    Text(title)
                        .font(.system(size: 17, weight: .semibold))
                    Spacer(minLength: 8)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 16, weight: .semibold))
                }
            }
            .padding(.horizontal, AuthLayout.fieldHorizontalPadding)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 58)
            .background(Color.black)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
    }
}

private struct AuthErrorBanner: View {
    let message: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(AuthPalette.error)
                .clipShape(Circle())
            Text(message)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(AuthPalette.ink)
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AuthPalette.errorSoft)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(AuthPalette.error.opacity(0.35), lineWidth: 1)
        )
    }
}

private struct AuthFooterLink: View {
    let prompt: String
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Text(prompt)
                .foregroundStyle(AuthPalette.muted)
            Button(actionTitle, action: action)
                .foregroundStyle(AuthPalette.brand)
                .underline()
        }
        .font(.system(size: 15, weight: .regular))
    }
}

private struct AuthSocialRow: View {
    var body: some View {
        HStack(spacing: 16) {
            AuthSocialButton { InstagramMark() }
            AuthSocialButton { FacebookMark() }
            AuthSocialButton { LinkedInMark() }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct AuthSocialButton<Icon: View>: View {
    @ViewBuilder var icon: () -> Icon

    var body: some View {
        icon()
            .frame(width: 54, height: 54)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(AuthPalette.line, lineWidth: 1)
            )
    }
}

private struct InstagramMark: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(AuthPalette.ink, lineWidth: 1.6)
                .frame(width: 22, height: 22)
            Circle()
                .stroke(AuthPalette.ink, lineWidth: 1.4)
                .frame(width: 9, height: 9)
            Circle()
                .fill(AuthPalette.ink)
                .frame(width: 2.4, height: 2.4)
                .offset(x: 6.5, y: -6.5)
        }
    }
}

private struct FacebookMark: View {
    var body: some View {
        Text("f")
            .font(.system(size: 26, weight: .bold, design: .serif))
            .foregroundStyle(AuthPalette.ink)
            .offset(x: 1, y: -1)
    }
}

private struct LinkedInMark: View {
    var body: some View {
        Text("in")
            .font(.system(size: 18, weight: .bold))
            .foregroundStyle(AuthPalette.ink)
    }
}

private struct ResetMethodRow: View {
    let method: ResetMethod
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: method.icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(method.tint)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text(method.title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(AuthPalette.ink)
                Text(method.subtitle)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(AuthPalette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color(white: 0.72))
        }
        .padding(14)
        .background(Color(white: 0.96))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(isSelected ? AuthPalette.ink.opacity(0.18) : .clear, lineWidth: 1.5)
        )
    }
}

extension String {
    var tactechMasked: String {
        let parts = split(separator: "@", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2 else { return self }
        let local = String(parts[0])
        let visible = local.suffix(4)
        return "**\(visible)@\(parts[1])"
    }
}

#Preview("Login") {
    NavigationStack {
        LoginView(onSignUp: {}, onForgot: { _ in })
            .ttPreviewTrainee()
    }
}

#Preview("Signup") {
    NavigationStack {
        SignupView(onSignIn: {}, onContinue: { _ in })
    }
}

#Preview("Reset Password") {
    NavigationStack {
        ResetPasswordView(email: "trainee@tactech.app")
            .ttPreviewTrainee()
    }
}

#Preview("Password Sent") {
    NavigationStack {
        PasswordSentView(email: "trainee@tactech.app", onResend: {}, onClose: {})
    }
}
