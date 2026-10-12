import SwiftUI

/// Bell → notification inbox (`GET /me/notifications`).
struct NotificationsInboxView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable private var store = NotificationStore.shared

    @State private var isSelecting = false
    @State private var selectedIds: Set<String> = []
    @State private var confirmClearAll = false
    @State private var confirmBulkDelete = false
    @State private var pendingSingleDelete: AppNotificationDTO?
    @State private var toast: TTToastMessage?

    private let canvas = Color(white: 0.97)
    private let orange = TTColor.actionOrange

    var body: some View {
        VStack(spacing: 0) {
            header

            if store.isLoading && store.items.isEmpty {
                Spacer()
                ProgressView()
                Spacer()
            } else if store.items.isEmpty {
                emptyState
            } else {
                List {
                    ForEach(store.items) { note in
                        row(note)
                            .listRowInsets(EdgeInsets(
                                top: 6,
                                leading: TTSpace.screen,
                                bottom: 6,
                                trailing: TTSpace.screen
                            ))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            .swipeActions(edge: .trailing, allowsFullSwipe: !isSelecting) {
                                if !isSelecting {
                                    Button(role: .destructive) {
                                        Task { await deleteOne(note) }
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                            }
                            .contextMenu {
                                if !isSelecting {
                                    Button {
                                        enterSelection(preselect: note.id)
                                    } label: {
                                        Label("Select", systemImage: "checkmark.circle")
                                    }
                                    if note.isUnread {
                                        Button {
                                            Task { await store.markRead(note) }
                                        } label: {
                                            Label("Mark as read", systemImage: "envelope.open")
                                        }
                                    }
                                    Button(role: .destructive) {
                                        pendingSingleDelete = note
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                            }
                    }

                    if store.items.count >= 20 {
                        Color.clear
                            .frame(height: 1)
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            .onAppear {
                                Task { await store.loadMore() }
                            }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .animation(.easeOut(duration: 0.18), value: isSelecting)
            }

            if isSelecting, !store.items.isEmpty {
                bulkBar
            }
        }
        .background(canvas.ignoresSafeArea())
        .ttHideSystemNavigationBar()
        .ttToast($toast, bottomInset: isSelecting ? 72 : 28)
        .task {
            await store.refreshInbox()
        }
        .onChange(of: store.lastError) { _, message in
            guard let message, !message.isEmpty else { return }
            let needsBackend = message.localizedCaseInsensitiveContains("404")
                || message.localizedCaseInsensitiveContains("delete api")
            toast = TTToastMessage(
                text: needsBackend ? "Backend delete not live" : "Couldn’t sync delete",
                style: .error,
                subtitle: message
            )
        }
        .confirmationDialog(
            "Clear all notifications?",
            isPresented: $confirmClearAll,
            titleVisibility: .visible
        ) {
            Button("Clear all", role: .destructive) {
                Task {
                    await store.clearAll()
                    exitSelection()
                    if store.lastError == nil {
                        toast = TTToastMessage(text: "Inbox cleared", style: .success)
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes every notification from your inbox. You can’t undo this.")
        }
        .confirmationDialog(
            bulkDeleteTitle,
            isPresented: $confirmBulkDelete,
            titleVisibility: .visible
        ) {
            Button("Delete \(selectedIds.count)", role: .destructive) {
                let ids = Array(selectedIds)
                confirmBulkDelete = false
                Task {
                    await store.deleteMany(ids)
                    exitSelection()
                    if store.lastError == nil {
                        toast = TTToastMessage(
                            text: ids.count == 1 ? "Notification deleted" : "\(ids.count) notifications deleted",
                            style: .success
                        )
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Selected notifications will be removed. This can’t be undone.")
        }
        .confirmationDialog(
            "Delete this notification?",
            isPresented: Binding(
                get: { pendingSingleDelete != nil },
                set: { if !$0 { pendingSingleDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                guard let note = pendingSingleDelete else { return }
                pendingSingleDelete = nil
                Task { await deleteOne(note) }
            }
            Button("Cancel", role: .cancel) {
                pendingSingleDelete = nil
            }
        } message: {
            Text("This can’t be undone.")
        }
    }

    // MARK: - Header

    private var header: some View {
        TTModalSheetHeader(
            title: "Notifications",
            background: canvas
        ) {
            if store.items.isEmpty {
                EmptyView()
            } else if isSelecting {
                HStack(spacing: 10) {
                    Button(allSelected ? "Deselect all" : "Select all") {
                        toggleSelectAll()
                    }
                    .font(TTFont.workSans(13, weight: .bold))
                    .foregroundStyle(orange)

                    Button("Cancel") {
                        exitSelection()
                    }
                    .font(TTFont.workSans(13, weight: .bold))
                    .foregroundStyle(TTColor.inkMuted)
                }
            } else {
                Menu {
                    Button {
                        enterSelection()
                    } label: {
                        Label("Select…", systemImage: "checkmark.circle")
                    }
                    if store.unreadCount > 0 {
                        Button {
                            Task { await store.markAllRead() }
                        } label: {
                            Label("Mark all read", systemImage: "envelope.open")
                        }
                    }
                    Button(role: .destructive) {
                        confirmClearAll = true
                    } label: {
                        Label("Clear all", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle.fill")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(orange)
                        .frame(width: TTModalSheetChrome.controlSize, height: TTModalSheetChrome.controlSize)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Notification actions")
            }
        }
    }

    private var emptyState: some View {
        VStack {
            Spacer()
            VStack(spacing: 10) {
                TTIcon(icon: .bell1, size: 28)
                    .foregroundStyle(TTColor.inkMuted)
                Text("No notifications yet")
                    .font(TTFont.workSans(16, weight: .bold))
                    .foregroundStyle(TTColor.ink)
                Text("Chat messages and calls will show up here.")
                    .font(TTFont.body(14))
                    .foregroundStyle(TTColor.inkMuted)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 32)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var bulkBar: some View {
        VStack(spacing: 0) {
            Divider().opacity(0.12)
            HStack(spacing: 12) {
                Text(selectedIds.isEmpty ? "Select notifications" : "\(selectedIds.count) selected")
                    .font(TTFont.workSans(13, weight: .semibold))
                    .foregroundStyle(TTColor.inkMuted)

                Spacer(minLength: 0)

                Button {
                    confirmBulkDelete = true
                } label: {
                    HStack(spacing: 6) {
                        TTIcon(icon: .trash1, filled: true, size: 13)
                        Text("Delete")
                            .font(TTFont.workSans(14, weight: .bold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .frame(height: 40)
                    .background(selectedIds.isEmpty ? Color.black.opacity(0.18) : Color.red.opacity(0.9))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(selectedIds.isEmpty)
            }
            .padding(.horizontal, TTSpace.screen)
            .padding(.vertical, 12)
        }
        .background(canvas)
    }

    // MARK: - Row

    private func row(_ note: AppNotificationDTO) -> some View {
        let tone = TTAlertTone.forNotificationType(note.type)
        let isSelected = selectedIds.contains(note.id)

        return HStack(alignment: .top, spacing: 12) {
            if isSelecting {
                selectionGlyph(isSelected: isSelected)
                    .padding(.top, 10)
            }

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

            if !isSelecting {
                Button {
                    pendingSingleDelete = note
                } label: {
                    TTIcon(icon: .trash1, filled: true, size: 13)
                        .foregroundStyle(Color.red.opacity(0.75))
                        .frame(width: 34, height: 34)
                        .background(Color.red.opacity(0.08))
                        .clipShape(Circle())
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Delete notification")
            }
        }
        .padding(14)
        .background(
            isSelecting && isSelected
                ? orange.opacity(0.12)
                : tone.background
        )
        .clipShape(RoundedRectangle(cornerRadius: TTAlertMetrics.corner, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: TTAlertMetrics.corner, style: .continuous)
                .strokeBorder(
                    isSelecting && isSelected
                        ? orange.opacity(0.45)
                        : tone.stroke.opacity(note.isUnread ? 0.7 : 0.35),
                    lineWidth: TTAlertMetrics.borderWidth
                )
        }
        .overlay(alignment: .topTrailing) {
            if note.isUnread, !isSelecting {
                Circle()
                    .fill(tone.stroke)
                    .frame(width: 8, height: 8)
                    .padding(10)
                    .accessibilityLabel("Unread")
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if isSelecting {
                toggleSelection(note.id)
            } else {
                store.openNotification(note)
                dismiss()
            }
        }
        .onLongPressGesture {
            if !isSelecting {
                enterSelection(preselect: note.id)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(inboxAccessibilityLabel(note))
        .accessibilityHint(isSelecting ? "Double tap to select" : "Opens this notification. Swipe or tap trash to delete.")
        .accessibilityAddTraits(.isButton)
    }

    private func selectionGlyph(isSelected: Bool) -> some View {
        ZStack {
            Circle()
                .fill(isSelected ? orange : Color.clear)
            Circle()
                .strokeBorder(isSelected ? orange : TTColor.ink.opacity(0.22), lineWidth: 1.5)
            if isSelected {
                TTIcon(icon: .check, filled: true, size: 11)
                    .foregroundStyle(.white)
            }
        }
        .frame(width: 22, height: 22)
    }

    // MARK: - Actions

    private var allSelected: Bool {
        !store.items.isEmpty && selectedIds.count == store.items.count
    }

    private var bulkDeleteTitle: String {
        let n = selectedIds.count
        return n == 1 ? "Delete 1 notification?" : "Delete \(n) notifications?"
    }

    private func enterSelection(preselect id: String? = nil) {
        withAnimation(.easeOut(duration: 0.16)) {
            isSelecting = true
            selectedIds = id.map { [$0] } ?? []
        }
    }

    private func exitSelection() {
        withAnimation(.easeOut(duration: 0.16)) {
            isSelecting = false
            selectedIds = []
        }
    }

    private func toggleSelection(_ id: String) {
        if selectedIds.contains(id) {
            selectedIds.remove(id)
        } else {
            selectedIds.insert(id)
        }
    }

    private func toggleSelectAll() {
        if allSelected {
            selectedIds = []
        } else {
            selectedIds = Set(store.items.map(\.id))
        }
    }

    private func deleteOne(_ note: AppNotificationDTO) async {
        await store.delete(note)
        if store.lastError == nil {
            toast = TTToastMessage(text: "Notification deleted", style: .success)
        }
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
