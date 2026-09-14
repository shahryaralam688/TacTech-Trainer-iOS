import SwiftUI

/// Bell → notification inbox (`GET /me/notifications`).
struct NotificationsInboxView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable private var store = NotificationStore.shared

    private let canvas = Color(red: 248 / 255, green: 249 / 255, blue: 250 / 255)

    var body: some View {
        VStack(spacing: 0) {
            header
            if store.isLoading && store.items.isEmpty {
                Spacer()
                ProgressView()
                Spacer()
            } else if store.items.isEmpty {
                Spacer()
                VStack(spacing: 10) {
                    TTIcon(icon: .bell1, size: 28)
                        .foregroundStyle(TTColor.inkMuted)
                    Text("No notifications yet")
                        .font(TTFont.heading(16))
                        .foregroundStyle(TTColor.ink)
                    Text("Chat messages and calls will show up here.")
                        .font(TTFont.body(14))
                        .foregroundStyle(TTColor.inkMuted)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 32)
                Spacer()
            } else {
                List {
                    ForEach(store.items) { note in
                        Button {
                            store.openNotification(note)
                            dismiss()
                        } label: {
                            row(note)
                        }
                        .listRowInsets(EdgeInsets(
                            top: 10,
                            leading: TTModalSheetChrome.horizontalPadding,
                            bottom: 10,
                            trailing: TTModalSheetChrome.horizontalPadding
                        ))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                    }

                    if store.items.count >= 20 {
                        Color.clear
                            .frame(height: 1)
                            .onAppear {
                                Task { await store.loadMore() }
                            }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .background(canvas.ignoresSafeArea())
        .ttHideSystemNavigationBar()
        .task {
            await store.refreshInbox()
        }
    }

    private var header: some View {
        TTModalSheetHeader(
            title: "Notifications",
            background: canvas
        ) {
            if store.unreadCount > 0 {
                Button("Mark all read") {
                    Task { await store.markAllRead() }
                }
                .font(TTFont.caption(13))
                .foregroundStyle(TTColor.actionOrange)
            }
        }
    }

    private func row(_ note: AppNotificationDTO) -> some View {
        // Keep list-row structure + open behavior; only apply Alerts semantic chrome (ISO/Material list status).
        let tone = TTAlertTone.forNotificationType(note.type)
        return HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(tone.iconFill)
                TTIcon(icon: icon(for: note.type), size: 16)
                    .foregroundStyle(.white)
            }
            .frame(width: 40, height: 40)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(note.title)
                        .font(TTFont.workSans(15, weight: .semibold))
                        .foregroundStyle(TTColor.ink)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(note.createdAt.formatted(.relative(presentation: .named)))
                        .font(TTFont.caption(11))
                        .foregroundStyle(TTColor.inkSubtle)
                }
                Text(note.body)
                    .font(TTFont.body(14))
                    .foregroundStyle(TTColor.inkMuted)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
            }
        }
        .padding(14)
        .background(tone.background)
        .clipShape(RoundedRectangle(cornerRadius: TTAlertMetrics.corner, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: TTAlertMetrics.corner, style: .continuous)
                .strokeBorder(tone.stroke.opacity(note.isUnread ? 0.7 : 0.35), lineWidth: TTAlertMetrics.borderWidth)
        }
        .overlay(alignment: .topTrailing) {
            if note.isUnread {
                Circle()
                    .fill(tone.stroke)
                    .frame(width: 8, height: 8)
                    .padding(10)
                    .accessibilityLabel("Unread")
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(inboxAccessibilityLabel(note))
        .accessibilityHint("Opens this notification")
        .accessibilityAddTraits(.isButton)
    }

    private func inboxAccessibilityLabel(_ note: AppNotificationDTO) -> String {
        var parts: [String] = []
        if note.isUnread { parts.append("Unread") }
        parts.append(TTAlertTone.forNotificationType(note.type).accessibilityName)
        parts.append(note.title)
        if !note.body.isEmpty { parts.append(note.body) }
        return parts.joined(separator: ". ")
    }

    private func icon(for type: String) -> SandowIcon {
        switch type {
        case "chat_call": return .video
        case "chat": return .chat
        default: return .bell1
        }
    }
}
