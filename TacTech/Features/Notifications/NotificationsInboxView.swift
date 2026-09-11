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
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(note.isUnread ? TTColor.actionOrange.opacity(0.15) : Color(white: 0.93))
                TTIcon(icon: icon(for: note.type), size: 16)
                    .foregroundStyle(note.isUnread ? TTColor.actionOrange : TTColor.inkMuted)
            }
            .frame(width: 40, height: 40)

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
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(alignment: .topTrailing) {
            if note.isUnread {
                Circle()
                    .fill(TTColor.actionOrange)
                    .frame(width: 8, height: 8)
                    .padding(10)
            }
        }
        .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
    }

    private func icon(for type: String) -> SandowIcon {
        switch type {
        case "chat_call": return .video
        case "chat": return .chat
        default: return .bell1
        }
    }
}
