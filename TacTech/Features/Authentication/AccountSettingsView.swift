import LocalAuthentication
import SwiftUI

enum AccountSettingsRoute: Hashable {
    case profileSetup
    case notifications
    case personalInfo
    case coachContact
    case language
    case linkedDevices
    case mainSecurity
    case privacyPolicy
    case aboutUs
    case helpCenter
    case submitFeedback
}

/// Figma Account Settings — shared for Trainer & Trainee.
struct AccountSettingsView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @AppStorage("settings.darkMode") private var darkMode = false
    @AppStorage("settings.biometric") private var biometricEnabled = false
    @AppStorage("settings.language") private var language = "English (EN)"

    private let charcoal = Color(red: 28 / 255, green: 28 / 255, blue: 30 / 255)
    private let orange = Color(red: 249 / 255, green: 115 / 255, blue: 22 / 255)
    private let rowBG = Color(white: 0.96)

    var body: some View {
        VStack(spacing: 0) {
            settingsHeader

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    generalSection
                    securitySection
                    helpSection
                    dangerSection
                    logoutSection
                    footer
                }
                .padding(.horizontal, 18)
                .padding(.top, 20)
                .padding(.bottom, 28)
            }
        }
        .background(Color.white.ignoresSafeArea())
        .ttHideSystemNavigationBar()
        .navigationDestination(for: AccountSettingsRoute.self) { route in
            destination(for: route)
        }
    }

    private var settingsHeader: some View {
        TTDarkPageHeader(title: "Account Settings") {
            dismiss()
        }
    }

    // MARK: - Sections

    private var generalSection: some View {
        settingsGroup(title: "General") {
            navRow("Profile Setup", icon: "person.crop.circle.badge.plus", route: .profileSetup)
            navRow("Notifications", icon: "bell", route: .notifications)
            navRow("Personal Information", icon: "person", route: .personalInfo)
            navRow(
                store.session?.role == .trainee ? "Coach Contact" : "Client Contact",
                icon: "phone",
                badge: store.session?.role == .trainee ? "15+" : nil,
                route: .coachContact
            )
            valueRow("Language", icon: "flag", value: language, route: .language)
            toggleRow("Dark Mode", icon: "moon", isOn: $darkMode)
            valueRow("Linked Devices", icon: "applewatch", value: "Apple Watch", route: .linkedDevices)
        }
    }

    private var securitySection: some View {
        settingsGroup(title: "Security & Privacy", badge: ("Beta", Color(red: 219 / 255, green: 234 / 255, blue: 254 / 255), Color(red: 37 / 255, green: 99 / 255, blue: 235 / 255))) {
            navRow("Main Security", icon: "lock", route: .mainSecurity)
            toggleRow("Enable Biometric", icon: "eye", isOn: $biometricEnabled) {
                if biometricEnabled {
                    Task { await enableBiometrics() }
                }
            }
            navRow("Privacy Policy", icon: "doc.text", badge: "3+", route: .privacyPolicy)
        }
    }

    private var helpSection: some View {
        settingsGroup(title: "Help & Support") {
            navRow("About Us", icon: "plus.circle", route: .aboutUs)
            navRow("Help Center", icon: "questionmark.circle", route: .helpCenter)
            navRow("Submit Feedback", icon: "bubble.left", route: .submitFeedback)
        }
    }

    private var dangerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("Danger Zone")
                    .font(.system(size: 16, weight: .bold))
                Text("Warning")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color(red: 185 / 255, green: 28 / 255, blue: 28 / 255))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(red: 254 / 255, green: 226 / 255, blue: 226 / 255))
                    .clipShape(Capsule())
                Spacer()
                Image(systemName: "exclamationmark.circle")
                    .foregroundStyle(Color(white: 0.55))
            }

            Button {
                // Placeholder — close account flow next.
            } label: {
                HStack {
                    Image(systemName: "trash")
                    Text("Close Account")
                        .font(.system(size: 16, weight: .semibold))
                    Spacer()
                    Image(systemName: "chevron.right")
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .frame(height: 54)
                .background(Color(red: 239 / 255, green: 68 / 255, blue: 68 / 255))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    private var logoutSection: some View {
        settingsGroup(title: "Log Out") {
            Button {
                Task { await store.logout() }
            } label: {
                settingsRowLabel(title: "Sign Out", icon: "rectangle.portrait.and.arrow.right", trailing: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color(white: 0.55))
                })
            }
            .buttonStyle(.plain)
        }
    }

    private var footer: some View {
        VStack(spacing: 8) {
            Image(systemName: "sparkle")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.white)
            Text("TacTech v1.0")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
            Text("© All Rights Reserved, 2026")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.55))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .background(charcoal)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .padding(.top, 8)
    }

    // MARK: - Row builders

    private func settingsGroup<Content: View>(
        title: String,
        badge: (String, Color, Color)? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title)
                    .font(.system(size: 16, weight: .bold))
                if let badge {
                    Text(badge.0)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(badge.2)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(badge.1)
                        .clipShape(Capsule())
                }
                Spacer()
                Image(systemName: "ellipsis")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color(white: 0.45))
            }
            VStack(spacing: 8) {
                content()
            }
        }
    }

    private func navRow(_ title: String, icon: String, badge: String? = nil, route: AccountSettingsRoute) -> some View {
        NavigationLink(value: route) {
            settingsRowLabel(title: title, icon: icon, badge: badge) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(white: 0.55))
            }
        }
        .buttonStyle(.plain)
    }

    private func valueRow(_ title: String, icon: String, value: String, route: AccountSettingsRoute) -> some View {
        NavigationLink(value: route) {
            settingsRowLabel(title: title, icon: icon) {
                HStack(spacing: 8) {
                    Text(value)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color(white: 0.45))
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color(white: 0.55))
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func toggleRow(
        _ title: String,
        icon: String,
        isOn: Binding<Bool>,
        onChange: (() -> Void)? = nil
    ) -> some View {
        settingsRowLabel(title: title, icon: icon) {
            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(orange)
                .onChange(of: isOn.wrappedValue) { _, _ in
                    onChange?()
                }
        }
    }

    private func settingsRowLabel<Trailing: View>(
        title: String,
        icon: String,
        badge: String? = nil,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.black)
                .frame(width: 28)

            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.black)

            if let badge {
                Text(badge)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(orange)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color(red: 255 / 255, green: 240 / 255, blue: 224 / 255))
                    .clipShape(Capsule())
            }

            Spacer()
            trailing()
        }
        .padding(.horizontal, 14)
        .frame(height: 54)
        .background(rowBG)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    @ViewBuilder
    private func destination(for route: AccountSettingsRoute) -> some View {
        switch route {
        case .profileSetup:
            ProfileCompletionFlowView()
        case .personalInfo:
            PersonalInformationSettingsView()
        case .notifications:
            NotificationSettingsView()
        case .coachContact:
            SettingsPlaceholderView(
                title: store.session?.role == .trainee ? "Coach Contact" : "Client Contact",
                message: "Contact details will appear here."
            )
        case .language:
            SettingsPlaceholderView(title: "Language", message: "English (EN) is currently selected.")
        case .linkedDevices:
            SettingsPlaceholderView(title: "Linked Devices", message: "Apple Watch and other devices.")
        case .mainSecurity:
            SettingsPlaceholderView(title: "Main Security", message: "Password and account security options.")
        case .privacyPolicy:
            SettingsPlaceholderView(title: "Privacy Policy", message: "How TacTech handles your data.")
        case .aboutUs:
            SettingsPlaceholderView(title: "About Us", message: "TacTech — train with clarity.")
        case .helpCenter:
            HelpCenterView()
        case .submitFeedback:
            SubmitFeedbackView()
        }
    }

    private func enableBiometrics() async {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            return
        }
        _ = try? await context.evaluatePolicy(
            .deviceOwnerAuthenticationWithBiometrics,
            localizedReason: "Enable biometrics for TacTech"
        )
    }
}

// MARK: - Help Center (second real screen)

struct HelpCenterView: View {
    @Environment(\.dismiss) private var dismiss

    private let topics = [
        ("Getting started", "Account, roles, and first assessment"),
        ("Training plans", "How coaches assign and athletes follow plans"),
        ("Form AI", "Live form correction tips"),
        ("Billing & access", "Invites, linking trainer/trainee")
    ]

    var body: some View {
        VStack(spacing: 0) {
            TTDarkPageHeader(title: "Help Center") { dismiss() }

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Pick a topic — more articles coming soon.")
                        .font(TTFont.body(14))
                        .foregroundStyle(TTColor.inkMuted)

                    ForEach(topics, id: \.0) { topic in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(topic.0)
                                .font(TTFont.heading(16))
                            Text(topic.1)
                                .font(TTFont.body(13))
                                .foregroundStyle(TTColor.inkMuted)
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(white: 0.96))
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 12)
                .padding(.bottom, 24)
            }
        }
        .background(Color.white.ignoresSafeArea())
        .ttHideSystemNavigationBar()
    }
}

struct SettingsPlaceholderView: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 0) {
            TTDarkPageHeader(title: title) { dismiss() }

            VStack(spacing: 12) {
                Text(message)
                    .font(TTFont.body(15))
                    .foregroundStyle(TTColor.inkMuted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
                Spacer()
            }
            .padding(.top, 20)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color.white.ignoresSafeArea())
        .ttHideSystemNavigationBar()
    }
}

#Preview("Account Settings · Trainee") {
    NavigationStack {
        AccountSettingsView()
            .ttPreviewTrainee()
    }
}

#Preview("Account Settings · Trainer") {
    NavigationStack {
        AccountSettingsView()
            .ttPreviewTrainer()
    }
}

#Preview("Help Center") {
    NavigationStack {
        HelpCenterView()
    }
}

#Preview("Settings Placeholder") {
    NavigationStack {
        SettingsPlaceholderView(title: "Notifications", message: "Coming soon.")
    }
}
