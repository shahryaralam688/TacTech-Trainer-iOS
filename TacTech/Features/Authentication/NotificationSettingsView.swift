import SwiftUI
import UIKit

/// Sandow Notification Settings — light canvas, shared `TTBackButton`, Sandow icons.
struct NotificationSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.ttRootTabBarClearance) private var tabBarClearance

    @AppStorage("notifications.push") private var pushEnabled = true
    @AppStorage("notifications.aiCoach") private var aiCoachEnabled = false
    @AppStorage("notifications.metrics") private var metricsEnabled = true
    @AppStorage("notifications.vibrations") private var vibrationsEnabled = false
    @AppStorage("notifications.sound") private var soundEnabled = true
    @AppStorage("notifications.appUpdate") private var appUpdateEnabled = true
    @AppStorage("notifications.resources") private var resourcesEnabled = false
    @AppStorage("notifications.chatMessages") private var chatMessagesEnabled = true
    @AppStorage("notifications.chatCalls") private var chatCallsEnabled = true
    /// Bool preference (not device name). Legacy String values read as `false`.
    @AppStorage("notifications.offersDevice") private var offersDeviceEnabled = false

    @State private var draftPush = true
    @State private var draftAICoach = false
    @State private var draftMetrics = true
    @State private var draftVibrations = false
    @State private var draftSound = true
    @State private var draftAppUpdate = true
    @State private var draftResources = false
    @State private var draftChatMessages = true
    @State private var draftChatCalls = true
    @State private var draftOffersDevice = false
    @State private var toast: TTToastMessage?
    @State private var isSaving = false

    private let canvas = Color(red: 248 / 255, green: 249 / 255, blue: 250 / 255)
    private let cardFill = Color(red: 243 / 255, green: 244 / 255, blue: 246 / 255)
    private let iconTile = Color.white
    private let ctaFill = Color(red: 18 / 255, green: 19 / 255, blue: 22 / 255)

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
                            icon: .chat,
                            title: "Chat Messages",
                            isOn: $draftChatMessages
                        )
                        iconToggleRow(
                            icon: .video,
                            title: "Video Calls",
                            isOn: $draftChatCalls
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
                        iconToggleRow(
                            icon: .currencyUsd,
                            title: "Offers",
                            isOn: $draftOffersDevice
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

                    saveButton
                        .padding(.top, 8)
                }
                .padding(.horizontal, 18)
                .padding(.top, 18)
                .padding(.bottom, tabBarClearance + 24)
            }
        }
        .background(canvas.ignoresSafeArea())
        .ttHideSystemNavigationBar()
        // Tab-bar clearance is applied inside `ttToast` via `ttRootTabBarClearance`.
        .ttToast($toast, bottomInset: 16)
        .task { await hydrateFromServer() }
    }

    // MARK: - Header

    private var header: some View {
        TTModalSheetHeader(
            title: "Notification Settings",
            background: canvas
        )
    }

    // MARK: - Sections

    private func section<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title)
                    .font(TTFont.workSans(17, weight: .semibold))
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
                .font(TTFont.workSans(15, weight: .medium))
                .foregroundStyle(TTColor.ink)
                .lineLimit(2)
            Spacer(minLength: 8)
            LiquidToggle(isOn: isOn)
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
                    .font(TTFont.workSans(15, weight: .semibold))
                    .foregroundStyle(TTColor.ink)
                Text(subtitle)
                    .font(TTFont.body(13))
                    .foregroundStyle(TTColor.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            LiquidToggle(isOn: isOn)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .background(cardFill)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.03), radius: 6, y: 2)
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

    private var saveButton: some View {
        Button(action: { Task { await save() } }) {
            HStack(spacing: 8) {
                if isSaving {
                    ProgressView()
                        .tint(.white)
                } else {
                    Text("Save Settings")
                        .font(TTFont.workSans(16, weight: .semibold))
                    TTIcon(icon: .check, filled: true, size: 14)
                }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(ctaFill)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .disabled(isSaving)
        .buttonStyle(TTSearchPressStyle(scale: 0.98))
    }

    private func hydrateFromServer() async {
        // 1) Local AppStorage drafts immediately — no blank flash.
        applyDrafts(from: currentAppStoragePreferences())
        // 2) Server hydrate.
        await NotificationStore.shared.loadPreferences()
        // 3) Copy all 10 server fields into drafts + AppStorage mirror already done in store.
        applyDrafts(from: NotificationStore.shared.preferences)
        syncAppStorage(from: NotificationStore.shared.preferences)
    }

    private func currentAppStoragePreferences() -> NotificationPreferencesDTO {
        NotificationPreferencesDTO(
            push: pushEnabled,
            aiCoach: aiCoachEnabled,
            metrics: metricsEnabled,
            vibrations: vibrationsEnabled,
            sound: soundEnabled,
            appUpdate: appUpdateEnabled,
            resources: resourcesEnabled,
            offersDevice: offersDeviceEnabled,
            chatMessages: chatMessagesEnabled,
            chatCalls: chatCallsEnabled
        )
    }

    private func applyDrafts(from prefs: NotificationPreferencesDTO) {
        draftPush = prefs.push
        draftAICoach = prefs.aiCoach
        draftMetrics = prefs.metrics
        draftVibrations = prefs.vibrations
        draftSound = prefs.sound
        draftAppUpdate = prefs.appUpdate
        draftResources = prefs.resources
        draftChatMessages = prefs.chatMessages
        draftChatCalls = prefs.chatCalls
        draftOffersDevice = prefs.offersDevice
    }

    private func syncAppStorage(from prefs: NotificationPreferencesDTO) {
        pushEnabled = prefs.push
        aiCoachEnabled = prefs.aiCoach
        metricsEnabled = prefs.metrics
        vibrationsEnabled = prefs.vibrations
        soundEnabled = prefs.sound
        appUpdateEnabled = prefs.appUpdate
        resourcesEnabled = prefs.resources
        offersDeviceEnabled = prefs.offersDevice
        chatMessagesEnabled = prefs.chatMessages
        chatCallsEnabled = prefs.chatCalls
    }

    private func draftPreferences() -> NotificationPreferencesDTO {
        NotificationPreferencesDTO(
            push: draftPush,
            aiCoach: draftAICoach,
            metrics: draftMetrics,
            vibrations: draftVibrations,
            sound: draftSound,
            appUpdate: draftAppUpdate,
            resources: draftResources,
            offersDevice: draftOffersDevice,
            chatMessages: draftChatMessages,
            chatCalls: draftChatCalls
        )
    }

    private func save() async {
        isSaving = true
        toast = nil
        defer { isSaving = false }

        let prefs = draftPreferences()
        do {
            try await NotificationStore.shared.savePreferences(prefs)
            syncAppStorage(from: NotificationStore.shared.preferences)
            applyDrafts(from: NotificationStore.shared.preferences)

            if NotificationStore.shared.preferences.push {
                await NotificationStore.shared.requestAuthorizationAndRegister()
                #if DEBUG
                if !NotificationStore.isRemotePushRegistrationEnabled {
                    toast = TTToastMessage(
                        text: "Settings saved",
                        style: .success,
                        subtitle: "Push delivery needs Push capability (DEBUG)"
                    )
                    NotificationStore.shared.playNotificationHaptic(.success)
                    return
                }
                #endif
            } else {
                await NotificationStore.shared.unregisterCurrentToken()
            }

            toast = TTToastMessage(text: "Settings saved", style: .success)
            NotificationStore.shared.playNotificationHaptic(.success)
        } catch {
            // Do not treat drafts as saved — reload from store (pre-failure server/local).
            applyDrafts(from: NotificationStore.shared.preferences)
            syncAppStorage(from: NotificationStore.shared.preferences)
            toast = TTToastMessage(
                text: (error as? AppError)?.errorDescription ?? error.localizedDescription,
                style: .error
            )
        }
    }
}

#Preview("Notification Settings") {
    NavigationStack {
        NotificationSettingsView()
    }
}
