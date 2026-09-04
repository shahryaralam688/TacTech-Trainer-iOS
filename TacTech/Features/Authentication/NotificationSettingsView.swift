import SwiftUI
import UIKit

/// Sandow Notification Settings — light canvas, shared `TTBackButton`, Sandow icons.
struct NotificationSettingsView: View {
    @Environment(\.dismiss) private var dismiss

    @AppStorage("notifications.push") private var pushEnabled = true
    @AppStorage("notifications.aiCoach") private var aiCoachEnabled = false
    @AppStorage("notifications.metrics") private var metricsEnabled = true
    @AppStorage("notifications.vibrations") private var vibrationsEnabled = false
    @AppStorage("notifications.sound") private var soundEnabled = true
    @AppStorage("notifications.appUpdate") private var appUpdateEnabled = true
    @AppStorage("notifications.resources") private var resourcesEnabled = false
    @AppStorage("notifications.offersDevice") private var offersDevice = ""

    @State private var draftPush = true
    @State private var draftAICoach = false
    @State private var draftMetrics = true
    @State private var draftVibrations = false
    @State private var draftSound = true
    @State private var draftAppUpdate = true
    @State private var draftResources = false
    @State private var savedFlash = false

    private let canvas = Color(red: 248 / 255, green: 249 / 255, blue: 250 / 255)
    private let cardFill = Color(red: 243 / 255, green: 244 / 255, blue: 246 / 255)
    private let iconTile = Color.white
    private let ctaFill = Color(red: 18 / 255, green: 19 / 255, blue: 22 / 255)
    private let orange = TTColor.actionOrange

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    section("General") {
                        iconToggleRow(
                            icon: .bell1,
                            title: "Push Notifications",
                            isOn: $draftPush
                        )
                        iconToggleRow(
                            icon: .robotFace1,
                            title: "AI Coach Notification",
                            isOn: $draftAICoach
                        )
                        iconToggleRow(
                            icon: .chartBar3,
                            title: "Metrics Notification",
                            isOn: $draftMetrics
                        )
                    }

                    section("Sound") {
                        subtitleToggleRow(
                            title: "Vibrations",
                            subtitle: "When Vibrate Notifications are on, your phone will vibrate.",
                            isOn: $draftVibrations
                        )
                        subtitleToggleRow(
                            title: "Sound",
                            subtitle: "When Sound Notifications are on, your phone will always check for sounds.",
                            isOn: $draftSound
                        )
                    }

                    section("Misc") {
                        navValueRow(
                            icon: .currencyUsd,
                            title: "Offers",
                            value: deviceLabel
                        )
                        iconToggleRow(
                            icon: .cloudDownload1,
                            title: "App Update",
                            isOn: $draftAppUpdate
                        )
                        subtitleToggleRow(
                            title: "Resources",
                            subtitle: "Enable resource notification when there's a new resources.",
                            isOn: $draftResources
                        )
                    }

                    if savedFlash {
                        Text("Settings saved")
                            .font(TTFont.caption(13))
                            .foregroundStyle(TTColor.success)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 18)
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

            Text("Notification Settings")
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

    // MARK: - Sections

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

    // MARK: - Rows

    private func iconToggleRow(icon: SandowIcon, title: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 12) {
            iconTileView(icon)
            Text(title)
                .font(TTFont.workSans(15, weight: .semibold))
                .foregroundStyle(TTColor.ink)
                .lineLimit(2)
            Spacer(minLength: 8)
            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(orange)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(cardFill)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.03), radius: 6, y: 2)
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

    private func navValueRow(icon: SandowIcon, title: String, value: String) -> some View {
        Button {
            // Device picker reserved — shows current device for now.
        } label: {
            HStack(spacing: 12) {
                iconTileView(icon)
                Text(title)
                    .font(TTFont.workSans(15, weight: .semibold))
                    .foregroundStyle(TTColor.ink)
                Spacer(minLength: 8)
                Text(value)
                    .font(TTFont.body(13))
                    .foregroundStyle(TTColor.inkMuted)
                    .lineLimit(1)
                TTIcon(icon: .chevronRight, size: 14)
                    .foregroundStyle(TTColor.inkSubtle)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(cardFill)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: .black.opacity(0.03), radius: 6, y: 2)
        }
        .buttonStyle(TTSearchPressStyle(scale: 0.99))
    }

    private func iconTileView(_ icon: SandowIcon) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(iconTile)
            TTIcon(icon: icon, size: 18)
                .foregroundStyle(TTColor.ink)
        }
        .frame(width: 40, height: 40)
        .shadow(color: .black.opacity(0.04), radius: 4, y: 1)
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

    private var deviceLabel: String {
        let stored = offersDevice.trimmingCharacters(in: .whitespacesAndNewlines)
        if !stored.isEmpty { return stored }
        let name = UIDevice.current.name
        return name.isEmpty ? "iPhone" : name
    }

    private func hydrate() {
        draftPush = pushEnabled
        draftAICoach = aiCoachEnabled
        draftMetrics = metricsEnabled
        draftVibrations = vibrationsEnabled
        draftSound = soundEnabled
        draftAppUpdate = appUpdateEnabled
        draftResources = resourcesEnabled
        if offersDevice.isEmpty {
            offersDevice = UIDevice.current.name
        }
    }

    private func save() {
        pushEnabled = draftPush
        aiCoachEnabled = draftAICoach
        metricsEnabled = draftMetrics
        vibrationsEnabled = draftVibrations
        soundEnabled = draftSound
        appUpdateEnabled = draftAppUpdate
        resourcesEnabled = draftResources
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
}

#Preview("Notification Settings") {
    NavigationStack {
        NotificationSettingsView()
    }
}
