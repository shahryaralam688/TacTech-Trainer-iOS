import LocalAuthentication
import SwiftUI
import UIKit

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
    private static let showsDarkModeRow = false
    @AppStorage("settings.biometric") private var biometricEnabled = false
    @AppStorage(LocalizationController.languageLabelKey) private var language = "English"
    @State private var isRestoringPurchases = false
    @State private var toast: TTToastMessage?
    @State private var showAIFreemiumInfo = false
    @State private var showSignOutConfirm = false
    @State private var isSigningOut = false

    private let charcoal = Color(red: 28 / 255, green: 28 / 255, blue: 30 / 255)
    private let orange = Color(red: 249 / 255, green: 115 / 255, blue: 22 / 255)
    private let rowBG = Color(white: 0.96)

    var body: some View {
        // Header is drawn over the scroll view; the content size never depends on its collapse.
        TTCollapsingHeaderScreen(
            sheetFill: .white,
            headerBackground: charcoal,
            topRadius: { _ in TTSheetChrome.pageTopRadius },
            header: { progress in settingsHeader(progress: progress) }
        ) {
            VStack(alignment: .leading, spacing: 22) {
                generalSection
                aiCoachProSection
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
        .background(charcoal.ignoresSafeArea(edges: .top))
        .ttHideSystemNavigationBar()
        .perfTempScreen("Account Settings") // PERF-TEMP
        .ttToast($toast, bottomInset: 28)
        .task {
            await store.refreshAIEntitlements()
            await store.refreshAICapabilities()
        }
        .onReceive(NotificationCenter.default.publisher(for: .ttAIEntitlementDidChange)) { _ in
            Task { await store.refreshAIEntitlements() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .ttAIPaywallUnlocked)) { _ in
            Task { await store.refreshAIEntitlements() }
        }
        .sheet(isPresented: $showAIFreemiumInfo) {
            AIFreemiumInfoSheet()
                .ttModalSheetPresentation()
        }
        .navigationDestination(for: AccountSettingsRoute.self) { route in
            destination(for: route)
        }
    }

    private func settingsHeader(progress: CGFloat) -> some View {
        TTDarkPageHeader(
            title: "Account Settings",
            collapseProgress: progress
        ) {
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
            restorePurchasesRow
            valueRow(
                String(localized: "settings.language"),
                icon: "flag",
                value: language,
                route: .language
            )
            // Hidden: the app is locked to the light appearance (UIUserInterfaceStyle = Light), so this switch did nothing.
            // Code kept; flip the constant when dark mode is supported.
            if Self.showsDarkModeRow {
                toggleRow("Dark Mode", icon: "moon", isOn: $darkMode)
            }
            valueRow("Linked Devices", icon: "applewatch", value: "Apple Watch", route: .linkedDevices)
        }
    }

    private var restorePurchasesRow: some View {
        Button {
            Task { await restorePurchases() }
        } label: {
            settingsRowLabel(title: "Restore Purchases", icon: "arrow.clockwise") {
                if isRestoringPurchases {
                    ProgressView()
                } else {
                    TTChevronForward()
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(isRestoringPurchases)
        .accessibilityLabel("Restore Purchases")
    }

    private var aiCoachProSection: some View {
        settingsGroup(title: "Subscriptions") {
            aiCoachProRow
            Button {
                showAIFreemiumInfo = true
            } label: {
                settingsRowLabel(title: "Free vs Advanced", icon: "info.circle") {
                    TTChevronForward()
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Free versus Advanced AI info")
        }
    }

    @ViewBuilder
    private var aiCoachProRow: some View {
        let ai = store.aiEntitlement
        if let ai, ai.active {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 14) {
                    Image(systemName: "sparkles")
                        .font(TTFont.workSans(16, weight: .semibold))
                        .foregroundStyle(.black)
                        .frame(width: 28)

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 8) {
                            Text("AI Coach Pro")
                                .font(TTFont.workSans(16, weight: .semibold))
                                .foregroundStyle(.black)
                            AIProBadge(
                                style: .compact,
                                label: ai.resolvedBadgeLabel,
                                fullLabel: ai.resolvedFullLabel
                            )
                        }
                        Text(ai.activeStatusLine)
                            .font(TTFont.workSans(12, weight: .medium))
                            .foregroundStyle(Color(white: 0.45))
                            .lineLimit(2)
                    }

                    Spacer(minLength: 8)

                    Text({
                        let s = ai.status?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                        return s.isEmpty ? "Active" : s
                    }())
                        .font(TTFont.workSans(13, weight: .semibold))
                        .foregroundStyle(Color(red: 22 / 255, green: 163 / 255, blue: 74 / 255))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 14)
                .background(rowBG)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("AI Coach Pro subscriber, \(ai.activeStatusLine)")
        } else {
            Button {
                store.presentAIPaywall()
            } label: {
                settingsRowLabel(title: "AI Coach Pro", icon: "sparkles") {
                    HStack(spacing: 8) {
                        Text("Not subscribed")
                            .font(TTFont.workSans(13, weight: .medium))
                            .foregroundStyle(Color(white: 0.45))
                        TTChevronForward()
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("AI Coach Pro, Not subscribed")
        }
    }

    @MainActor
    private func restorePurchases() async {
        guard !isRestoringPurchases else { return }
        isRestoringPurchases = true
        defer { isRestoringPurchases = false }
        do {
            let me = try await AIStoreKitService.shared.restorePurchases()
            store.aiEntitlement = me
            await store.refreshAIEntitlements()
            toast = TTToastMessage(text: "Purchases restored", style: .success)
        } catch let error as AppError where error.isConflict {
            toast = TTToastMessage(
                text: "Subscription linked elsewhere",
                style: .error,
                subtitle: error.localizedDescription
            )
        } catch {
            toast = TTToastMessage(
                text: "Restore failed",
                style: .error,
                subtitle: error.localizedDescription
            )
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
                    .font(TTFont.workSans(16, weight: .bold))
                Text("Warning")
                    .font(TTFont.workSans(11, weight: .bold))
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
                        .font(TTFont.workSans(16, weight: .semibold))
                    Spacer()
                    TTChevronForward(size: 14, color: .white)
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
                showSignOutConfirm = true
            } label: {
                settingsRowLabel(title: "Sign Out", icon: "rectangle.portrait.and.arrow.right", trailing: {
                    TTChevronForward()
                })
            }
            .buttonStyle(.plain)
            .sheet(isPresented: $showSignOutConfirm) {
                SignOutConfirmSheet(
                    isSigningOut: isSigningOut,
                    onConfirm: {
                        isSigningOut = true
                        Task {
                            await store.logout()
                            isSigningOut = false
                            showSignOutConfirm = false
                        }
                    },
                    onCancel: { showSignOutConfirm = false }
                )
                .ttModalSheetPresentation(detents: [.height(280)], dragIndicator: .visible)
            }
        }
    }

    private var footer: some View {
        VStack(spacing: 8) {
            Image(systemName: "sparkle")
                .font(TTFont.workSans(22, weight: .bold))
                .foregroundStyle(.white)
            Text("TacTech v1.0")
                .font(TTFont.workSans(13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
            Text("© All Rights Reserved, 2026")
                .font(TTFont.workSans(11, weight: .medium))
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
                    .font(TTFont.workSans(16, weight: .bold))
                if let badge {
                    Text(badge.0)
                        .font(TTFont.workSans(11, weight: .bold))
                        .foregroundStyle(badge.2)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(badge.1)
                        .clipShape(Capsule())
                }
                Spacer()
                Image(systemName: "ellipsis")
                    .font(TTFont.workSans(14, weight: .bold))
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
                TTChevronForward()
            }
        }
        .buttonStyle(.plain)
    }

    private func valueRow(_ title: String, icon: String, value: String, route: AccountSettingsRoute) -> some View {
        NavigationLink(value: route) {
            settingsRowLabel(title: title, icon: icon) {
                HStack(spacing: 8) {
                    Text(value)
                        .font(TTFont.workSans(13, weight: .medium))
                        .foregroundStyle(Color(white: 0.45))
                    TTChevronForward()
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
            LiquidToggle(isOn: isOn)
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
                .font(TTFont.workSans(16, weight: .semibold))
                .foregroundStyle(.black)
                .frame(width: 28)

            Text(title)
                .font(TTFont.workSans(16, weight: .semibold))
                .foregroundStyle(.black)

            if let badge {
                Text(badge)
                    .font(TTFont.workSans(11, weight: .bold))
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
            CoachContactView()
        case .language:
            LanguageSettingsView()
        case .linkedDevices:
            SettingsPlaceholderView(title: "Linked Devices", message: "Apple Watch and other devices.")
        case .mainSecurity:
            SecuritySettingsView()
        case .privacyPolicy:
            SettingsPlaceholderView(title: "Privacy Policy", message: "How TacTech handles your data.")
        case .aboutUs:
            AboutUsView()
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

// MARK: - Settings placeholder

struct SettingsPlaceholderView: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let message: String

    var body: some View {
        TTCollapsingHeaderScreen(
            sheetFill: .white,
            headerBackground: Color(red: 28 / 255, green: 28 / 255, blue: 30 / 255),
            topRadius: { _ in TTSheetChrome.pageTopRadius },
            header: { progress in
                TTDarkPageHeader(title: title, collapseProgress: progress) { dismiss() }
            }
        ) {
            Text(message)
                .font(TTFont.body(15))
                .foregroundStyle(TTColor.inkMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
                .padding(.top, 20)
                .padding(.bottom, 32)
                .frame(maxWidth: .infinity)
        }
        .background(Color(red: 28 / 255, green: 28 / 255, blue: 30 / 255).ignoresSafeArea(edges: .top))
        .ttHideSystemNavigationBar()
    }
}

private struct CoachContactView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var chatTarget: TTChatTarget?
    @State private var showFindCoaches = false
    @State private var isStartingCall = false
    @State private var toast: TTToastMessage?

    private let charcoal = Color(red: 28 / 255, green: 28 / 255, blue: 30 / 255)
    private let orange = Color(red: 249 / 255, green: 115 / 255, blue: 22 / 255)
    private let rowBG = Color(white: 0.96)

    private var isTrainee: Bool { store.session?.role == .trainee }

    var body: some View {
        TTCollapsingHeaderScreen(
            sheetFill: .white,
            headerBackground: charcoal,
            topRadius: { _ in TTSheetChrome.pageTopRadius },
            header: { progress in
                TTDarkPageHeader(
                    title: isTrainee ? "Coach Contact" : "Client Contact",
                    collapseProgress: progress
                ) {
                    dismiss()
                }
            }
        ) {
            VStack(alignment: .leading, spacing: 20) {
                if isTrainee {
                    traineeContent
                } else {
                    trainerContent
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 20)
            .padding(.bottom, 32)
        }
        .background(charcoal.ignoresSafeArea(edges: .top))
        .ttHideSystemNavigationBar()
        .ttToast($toast, bottomInset: 28)
        .fullScreenCover(item: $chatTarget) { target in
            HumanPeerChatView(
                audience: isTrainee ? .trainee : .trainer,
                preferredPeerUserId: target.id,
                preferredPeerName: target.name
            )
        }
        .sheet(isPresented: $showFindCoaches) {
            FindCoachesView().ttModalSheetPresentation(dragIndicator: .hidden)
        }
    }

    // MARK: - Trainee -> Linked Coach

    @ViewBuilder
    private var traineeContent: some View {
        if let trainee = store.currentTrainee,
           let trainer = store.trainer(for: trainee),
           let user = store.user(forTrainer: trainer) {
            coachHeroCard(user: user, trainer: trainer)
            quickActionBar(user: user)
            contactDetailsSection(user: user, inviteCode: trainer.inviteCode)
            coachingDetailsSection(trainee: trainee, trainer: trainer)
            privacyNote
        } else {
            emptyStateCard(
                icon: "person.crop.circle.badge.questionmark",
                title: "No coach linked yet",
                message: "Connect with a coach using an invite code or browse coaches to unlock direct chat, calls, and personalized plans.",
                actionTitle: "Find a Coach"
            ) {
                showFindCoaches = true
            }
        }
    }

    private func coachHeroCard(user: User, trainer: TrainerProfile) -> some View {
        HStack(spacing: 14) {
            TTUserAvatarView(
                avatarUrl: user.avatarUrl,
                avatarAsset: user.avatarAsset,
                userId: user.id,
                name: user.name,
                size: 64,
                shape: .circle
            )

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(user.name)
                        .font(TTFont.workSans(20, weight: .bold))
                        .foregroundStyle(TTColor.ink)
                        .lineLimit(1)
                    Text("Active Coach")
                        .font(TTFont.workSans(11, weight: .semibold))
                        .foregroundStyle(Color(red: 22 / 255, green: 163 / 255, blue: 74 / 255))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color(red: 22 / 255, green: 163 / 255, blue: 74 / 255).opacity(0.12))
                        .clipShape(Capsule())
                }

                let subtitleParts = [
                    trainer.specialty.isEmpty ? nil : trainer.specialty,
                    trainer.yearsExperience > 0 ? "\(trainer.yearsExperience) yrs exp" : nil
                ].compactMap { $0 }
                if !subtitleParts.isEmpty {
                    Text(subtitleParts.joined(separator: " · "))
                        .font(TTFont.workSans(13, weight: .medium))
                        .foregroundStyle(TTColor.inkMuted)
                }

                if let location = trainer.location, !location.isEmpty {
                    Label(location, systemImage: "mappin.and.ellipse")
                        .font(TTFont.workSans(12, weight: .medium))
                        .foregroundStyle(TTColor.inkMuted)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(rowBG)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func quickActionBar(user: User) -> some View {
        HStack(spacing: 10) {
            Button {
                chatTarget = TTChatTarget(id: user.id, name: user.name)
            } label: {
                Label("Chat", systemImage: "message.fill")
                    .font(TTFont.workSans(14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
                    .background(orange)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)

            if HumanCallFeatures.isEnabled {
                Button {
                    Task { await startInAppCall(peerUserId: user.id, peerName: user.name) }
                } label: {
                    Group {
                        if isStartingCall {
                            ProgressView().tint(TTColor.ink)
                        } else {
                            Label("Call", systemImage: "phone.fill")
                                .font(TTFont.workSans(14, weight: .semibold))
                        }
                    }
                    .foregroundStyle(TTColor.ink)
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
                    .background(rowBG)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(isStartingCall)
            }

            if !user.email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button {
                    openMail(user.email)
                } label: {
                    Label("Email", systemImage: "envelope.fill")
                        .font(TTFont.workSans(14, weight: .semibold))
                        .foregroundStyle(TTColor.ink)
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                        .background(rowBG)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func contactDetailsSection(user: User, inviteCode: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("CONTACT DETAILS")
                .font(TTFont.workSans(12, weight: .semibold))
                .foregroundStyle(Color(white: 0.45))
                .padding(.horizontal, 4)

            VStack(spacing: 10) {
                if !user.email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    contactRow(
                        icon: "envelope",
                        title: "Email",
                        value: user.email,
                        actionLabel: "Send",
                        onTap: { openMail(user.email) },
                        onCopy: { copyToPasteboard(user.email, label: "Email copied") }
                    )
                }

                if !inviteCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    contactRow(
                        icon: "number",
                        title: "Coach Code",
                        value: inviteCode,
                        actionLabel: nil,
                        onTap: { copyToPasteboard(inviteCode, label: "Coach code copied") },
                        onCopy: { copyToPasteboard(inviteCode, label: "Coach code copied") }
                    )
                }

                HStack(spacing: 12) {
                    Image(systemName: "phone.badge.checkmark")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(TTColor.inkMuted)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Phone Number")
                            .font(TTFont.workSans(13, weight: .semibold))
                            .foregroundStyle(TTColor.ink)
                        Text("Private by default — use in-app Chat or Voice Call above.")
                            .font(TTFont.workSans(12, weight: .regular))
                            .foregroundStyle(TTColor.inkMuted)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(rowBG)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
    }

    private func coachingDetailsSection(trainee: TraineeProfile, trainer: TrainerProfile) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("COACHING DETAILS")
                .font(TTFont.workSans(12, weight: .semibold))
                .foregroundStyle(Color(white: 0.45))
                .padding(.horizontal, 4)

            VStack(spacing: 10) {
                if !trainer.specialty.isEmpty {
                    detailRow(icon: "figure.strengthtraining.traditional", title: "Specialty", value: trainer.specialty)
                }
                if trainer.yearsExperience > 0 {
                    detailRow(icon: "clock.badge.checkmark", title: "Experience", value: "\(trainer.yearsExperience) years")
                }
                if let location = trainer.location, !location.isEmpty {
                    detailRow(icon: "mappin.and.ellipse", title: "Location", value: location)
                }
                if let plan = store.assignedPlan(for: trainee) {
                    detailRow(icon: "list.bullet.clipboard", title: "Active Plan", value: plan.title)
                }
                if !trainer.bio.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("About", systemImage: "text.alignleft")
                            .font(TTFont.workSans(13, weight: .semibold))
                            .foregroundStyle(TTColor.ink)
                        Text(trainer.bio)
                            .font(TTFont.workSans(14, weight: .regular))
                            .foregroundStyle(TTColor.inkMuted)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(rowBG)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
            }
        }
    }

    // MARK: - Trainer -> Linked Clients

    @ViewBuilder
    private var trainerContent: some View {
        let trainees = store.currentTrainer.map { store.trainees(for: $0) } ?? []
        if trainees.isEmpty {
            emptyStateCard(
                icon: "person.2",
                title: "No linked clients yet",
                message: "Share your invite code from your profile so clients can join and appear here for quick contact.",
                actionTitle: nil,
                action: nil
            )
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Text("LINKED CLIENTS (\(trainees.count))")
                    .font(TTFont.workSans(12, weight: .semibold))
                    .foregroundStyle(Color(white: 0.45))
                    .padding(.horizontal, 4)

                ForEach(trainees) { trainee in
                    if let user = store.user(forTrainee: trainee) {
                        clientContactCard(trainee: trainee, user: user)
                    }
                }
            }
            privacyNote
        }
    }

    private func clientContactCard(trainee: TraineeProfile, user: User) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                TTUserAvatarView(
                    avatarUrl: user.avatarUrl,
                    avatarAsset: user.avatarAsset,
                    userId: user.id,
                    name: user.name,
                    size: 48,
                    shape: .circle
                )
                VStack(alignment: .leading, spacing: 3) {
                    Text(user.name)
                        .font(TTFont.workSans(16, weight: .bold))
                        .foregroundStyle(TTColor.ink)
                    if !trainee.goal.isEmpty {
                        Text(trainee.goal)
                            .font(TTFont.workSans(12, weight: .medium))
                            .foregroundStyle(TTColor.inkMuted)
                    }
                    if !user.email.isEmpty {
                        Text(user.email)
                            .font(TTFont.workSans(12, weight: .regular))
                            .foregroundStyle(TTColor.inkMuted)
                    }
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 8) {
                Button {
                    chatTarget = TTChatTarget(id: user.id, name: user.name)
                } label: {
                    Label("Chat", systemImage: "message.fill")
                        .font(TTFont.workSans(13, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(orange)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)

                if HumanCallFeatures.isEnabled {
                    Button {
                        Task { await startInAppCall(peerUserId: user.id, peerName: user.name) }
                    } label: {
                        Label("Call", systemImage: "phone.fill")
                            .font(TTFont.workSans(13, weight: .semibold))
                            .foregroundStyle(TTColor.ink)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(isStartingCall)
                }

                if !user.email.isEmpty {
                    Button {
                        openMail(user.email)
                    } label: {
                        Image(systemName: "envelope.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(TTColor.ink)
                            .frame(width: 44, height: 44)
                            .background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Email \(user.name)")
                }
            }
        }
        .padding(14)
        .background(rowBG)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    // MARK: - Helpers

    private func contactRow(
        icon: String,
        title: String,
        value: String,
        actionLabel: String?,
        onTap: @escaping () -> Void,
        onCopy: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 12) {
            Button(action: onTap) {
                HStack(spacing: 12) {
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(TTColor.ink)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(TTFont.workSans(12, weight: .medium))
                            .foregroundStyle(TTColor.inkMuted)
                        Text(value)
                            .font(TTFont.workSans(14, weight: .semibold))
                            .foregroundStyle(TTColor.ink)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    if let actionLabel {
                        Text(actionLabel)
                            .font(TTFont.workSans(12, weight: .semibold))
                            .foregroundStyle(orange)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(action: onCopy) {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(TTColor.inkMuted)
                    .frame(width: 36, height: 36)
                    .background(Color.white)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Copy \(title)")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(rowBG)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func detailRow(icon: String, title: String, value: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(TTColor.ink)
                .frame(width: 24)
            Text(title)
                .font(TTFont.workSans(14, weight: .medium))
                .foregroundStyle(TTColor.inkMuted)
            Spacer(minLength: 8)
            Text(value)
                .font(TTFont.workSans(14, weight: .semibold))
                .foregroundStyle(TTColor.ink)
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 50)
        .background(rowBG)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func emptyStateCard(
        icon: String,
        title: String,
        message: String,
        actionTitle: String?,
        action: (() -> Void)?
    ) -> some View {
        VStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 32, weight: .semibold))
                .foregroundStyle(orange)
                .frame(width: 60, height: 60)
                .background(orange.opacity(0.12))
                .clipShape(Circle())

            Text(title)
                .font(TTFont.workSans(18, weight: .bold))
                .foregroundStyle(TTColor.ink)

            Text(message)
                .font(TTFont.workSans(14, weight: .regular))
                .foregroundStyle(TTColor.inkMuted)
                .multilineTextAlignment(.center)

            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle)
                        .font(TTFont.workSans(15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(orange)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity)
        .background(rowBG)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var privacyNote: some View {
        HStack(spacing: 8) {
            Image(systemName: "lock.shield")
                .font(.system(size: 13, weight: .medium))
            Text("Your contact details and messages stay private inside TacTech.")
                .font(TTFont.workSans(12, weight: .regular))
        }
        .foregroundStyle(TTColor.inkMuted)
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.top, 4)
    }

    private func openMail(_ email: String) {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let url = URL(string: "mailto:\(trimmed)") else { return }
        openURL(url)
    }

    private func copyToPasteboard(_ value: String, label: String) {
        UIPasteboard.general.string = value
        toast = TTToastMessage(text: label, style: .success)
    }

    private func startInAppCall(peerUserId: String, peerName: String) async {
        guard HumanCallFeatures.isEnabled, !isStartingCall else { return }
        isStartingCall = true
        defer { isStartingCall = false }
        do {
            let threadId = try await HumanChatStore.shared.ensureThreadId(peerUserId: peerUserId)
            await HumanCallStore.shared.startOutgoing(
                peerUserId: peerUserId,
                peerName: peerName,
                threadId: threadId,
                fromName: store.currentUser?.name
            )
        } catch {
            toast = TTToastMessage(text: "Could not start call right now.", style: .error)
        }
    }
}

private struct SignOutConfirmSheet: View {
    let isSigningOut: Bool
    let onConfirm: () -> Void
    let onCancel: () -> Void

    private let dangerRed = Color(red: 239 / 255, green: 68 / 255, blue: 68 / 255)
    private let rowBG = Color(white: 0.96)

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(dangerRed.opacity(0.12))
                    .frame(width: 52, height: 52)
                Image(systemName: "rectangle.portrait.and.arrow.right")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(dangerRed)
            }
            .padding(.top, 8)

            VStack(spacing: 6) {
                Text("Sign out?")
                    .font(TTFont.workSans(20, weight: .bold))
                    .foregroundStyle(TTColor.ink)
                Text("You can sign back in anytime with your account.")
                    .font(TTFont.workSans(14, weight: .regular))
                    .foregroundStyle(TTColor.inkMuted)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 10) {
                Button(action: onConfirm) {
                    Group {
                        if isSigningOut {
                            ProgressView().tint(.white)
                        } else {
                            Text("Sign Out")
                                .font(TTFont.workSans(16, weight: .semibold))
                        }
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(dangerRed)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(isSigningOut)

                Button(action: onCancel) {
                    Text("Cancel")
                        .font(TTFont.workSans(15, weight: .semibold))
                        .foregroundStyle(TTColor.ink)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(rowBG)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(isSigningOut)
            }
            .padding(.top, 4)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white)
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
