import LocalAuthentication
import SwiftUI

/// Sandow Security Settings — light canvas, shared `TTBackButton`, hero shield asset.
struct SecuritySettingsView: View {
    @Environment(\.dismiss) private var dismiss

    @AppStorage("security.twoFactor") private var twoFactorEnabled = false
    @AppStorage("security.googleAuth") private var googleAuthEnabled = true
    @AppStorage("security.faceId") private var faceIdEnabled = false
    @AppStorage("settings.biometric") private var biometricUnlockEnabled = true

    @State private var draftTwoFactor = false
    @State private var draftGoogleAuth = true
    @State private var draftFaceId = false
    @State private var draftBiometric = true
    @State private var savedFlash = false
    @State private var authError: String?

    private let canvas = Color(red: 248 / 255, green: 249 / 255, blue: 250 / 255)
    private let cardFill = Color(red: 243 / 255, green: 244 / 255, blue: 246 / 255)
    private let ctaFill = Color(red: 18 / 255, green: 19 / 255, blue: 22 / 255)
    private let orange = TTColor.actionOrange

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    heroShield

                    section("General") {
                        subtitleToggleRow(
                            title: "2 Factor Authenticator",
                            subtitle: "2FA is an identity and access management security method.",
                            isOn: $draftTwoFactor
                        )
                        subtitleToggleRow(
                            title: "Google Authenticator",
                            subtitle: "Google Authenticator adds an extra layer of security.",
                            isOn: $draftGoogleAuth
                        )
                        subtitleToggleRow(
                            title: "Face ID",
                            subtitle: "Face ID lets you securely unlock your iPhone or iPad.",
                            isOn: $draftFaceId
                        )
                        .onChange(of: draftFaceId) { _, on in
                            if on { Task { await requestBiometrics(for: .faceId) } }
                        }
                        subtitleToggleRow(
                            title: "Biometric Unlock",
                            subtitle: "The biometric unlock feature can be achieved through visiting our website directly.",
                            isOn: $draftBiometric
                        )
                        .onChange(of: draftBiometric) { _, on in
                            if on { Task { await requestBiometrics(for: .biometric) } }
                        }
                    }

                    if let authError {
                        Text(authError)
                            .font(TTFont.caption(13))
                            .foregroundStyle(TTColor.danger)
                            .frame(maxWidth: .infinity)
                    }

                    if savedFlash {
                        Text("Settings saved")
                            .font(TTFont.caption(13))
                            .foregroundStyle(TTColor.success)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 8)
                .padding(.bottom, 110)
            }

            saveBar
        }
        .background(canvas.ignoresSafeArea())
        .ttHideSystemNavigationBar()
        .onAppear(perform: hydrate)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 14) {
            TTBackButton(style: .onLight) { dismiss() }

            Text("Security Settings")
                .font(TTFont.workSans(20, weight: .bold))
                .foregroundStyle(TTColor.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.85)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .background(canvas)
    }

    // MARK: - Hero

    private var heroShield: some View {
        Image("SecurityShield")
            .resizable()
            .scaledToFit()
            .frame(width: 168, height: 168)
            .shadow(color: .black.opacity(0.12), radius: 18, y: 10)
            .frame(maxWidth: .infinity)
            .padding(.top, 8)
            .padding(.bottom, 4)
            .accessibilityLabel("Security shield")
    }

    // MARK: - Section

    private func section<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title)
                    .font(TTFont.workSans(17, weight: .bold))
                    .foregroundStyle(TTColor.ink)
                Spacer()
                TTIcon(icon: .kebab, size: 16)
                    .foregroundStyle(TTColor.inkMuted)
                    .accessibilityHidden(true)
            }

            VStack(spacing: 10) {
                content()
            }
        }
    }

    private func subtitleToggleRow(title: String, subtitle: String, isOn: Binding<Bool>) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(TTFont.workSans(15, weight: .bold))
                    .foregroundStyle(TTColor.ink)
                Text(subtitle)
                    .font(TTFont.body(13))
                    .foregroundStyle(TTColor.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(orange)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .background(cardFill)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.03), radius: 6, y: 2)
    }

    // MARK: - Save

    private var saveBar: some View {
        VStack(spacing: 0) {
            Button(action: save) {
                HStack(spacing: 8) {
                    Text("Save Settings")
                        .font(TTFont.workSans(16, weight: .bold))
                    TTIcon(icon: .check, filled: true, size: 14)
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(ctaFill)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            }
            .buttonStyle(TTSearchPressStyle(scale: 0.98))
            .padding(.horizontal, 18)
            .padding(.top, 12)
            .padding(.bottom, 18)
        }
        .background(
            canvas
                .shadow(color: .black.opacity(0.04), radius: 12, y: -4)
                .ignoresSafeArea(edges: .bottom)
        )
    }

    // MARK: - Logic

    private enum BioKind { case faceId, biometric }

    private func hydrate() {
        draftTwoFactor = twoFactorEnabled
        draftGoogleAuth = googleAuthEnabled
        draftFaceId = faceIdEnabled
        draftBiometric = biometricUnlockEnabled
    }

    private func save() {
        twoFactorEnabled = draftTwoFactor
        googleAuthEnabled = draftGoogleAuth
        faceIdEnabled = draftFaceId
        biometricUnlockEnabled = draftBiometric
        authError = nil
        withAnimation(.easeOut(duration: 0.2)) {
            savedFlash = true
        }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            withAnimation(.easeOut(duration: 0.2)) {
                savedFlash = false
            }
        }
    }

    @MainActor
    private func requestBiometrics(for kind: BioKind) async {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            authError = "Biometrics are not available on this device."
            switch kind {
            case .faceId: draftFaceId = false
            case .biometric: draftBiometric = false
            }
            return
        }
        let reason = kind == .faceId
            ? "Enable Face ID for TacTech"
            : "Enable biometric unlock for TacTech"
        do {
            let ok = try await context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: reason
            )
            if !ok {
                switch kind {
                case .faceId: draftFaceId = false
                case .biometric: draftBiometric = false
                }
            } else {
                authError = nil
            }
        } catch {
            authError = "Could not verify biometrics."
            switch kind {
            case .faceId: draftFaceId = false
            case .biometric: draftBiometric = false
            }
        }
    }
}

#Preview("Security Settings") {
    NavigationStack {
        SecuritySettingsView()
    }
}
