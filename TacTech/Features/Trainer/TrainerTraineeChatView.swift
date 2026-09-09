import SwiftUI

// MARK: - Local trainee chat (UI ready — socket/backend later)

struct TraineeChatMessage: Identifiable, Hashable {
    let id: String
    let traineeId: String
    let isFromTrainer: Bool
    var text: String
    var sentAt: Date
    var isRead: Bool
}

@MainActor
@Observable
final class TraineeChatStore {
    /// traineeId → messages
    var threads: [String: [TraineeChatMessage]] = [:]
    var drafts: [String: String] = [:]

    func messages(for traineeId: String) -> [TraineeChatMessage] {
        threads[traineeId] ?? []
    }

    func lastMessage(for traineeId: String) -> TraineeChatMessage? {
        threads[traineeId]?.last
    }

    func unreadCount(for traineeId: String) -> Int {
        (threads[traineeId] ?? []).filter { !$0.isFromTrainer && !$0.isRead }.count
    }

    func markRead(traineeId: String) {
        guard var list = threads[traineeId] else { return }
        for i in list.indices where !list[i].isFromTrainer {
            list[i].isRead = true
        }
        threads[traineeId] = list
    }

    func send(to traineeId: String, text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var list = threads[traineeId] ?? []
        list.append(
            TraineeChatMessage(
                id: UUID().uuidString,
                traineeId: traineeId,
                isFromTrainer: true,
                text: trimmed,
                sentAt: .now,
                isRead: true
            )
        )
        threads[traineeId] = list
        drafts[traineeId] = ""

        // Local mock reply so the thread feels alive until sockets land.
        let replyId = UUID().uuidString
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in
            guard let self else { return }
            var updated = self.threads[traineeId] ?? []
            updated.append(
                TraineeChatMessage(
                    id: replyId,
                    traineeId: traineeId,
                    isFromTrainer: false,
                    text: "Got it — thanks coach!",
                    sentAt: .now,
                    isRead: false
                )
            )
            self.threads[traineeId] = updated
        }
    }

    func seedIfNeeded(traineeIds: [String]) {
        for id in traineeIds where threads[id] == nil {
            threads[id] = [
                TraineeChatMessage(
                    id: UUID().uuidString,
                    traineeId: id,
                    isFromTrainer: false,
                    text: "Hey coach — ready when you are.",
                    sentAt: Date().addingTimeInterval(-3600),
                    isRead: false
                )
            ]
        }
    }
}

/// Inbox + thread for trainer ↔ trainee messaging (local only for now).
struct TrainerTraineeChatView: View {
    @Environment(AppStore.self) private var appStore
    @Environment(\.dismiss) private var dismiss
    @State private var chatStore = TraineeChatStore()
    @State private var selectedTraineeId: String?

    private let canvas = Color(white: 0.97)
    private let cardFill = Color(red: 243 / 255, green: 243 / 255, blue: 244 / 255)

    private var trainees: [TraineeProfile] {
        guard let trainer = appStore.currentTrainer else { return [] }
        return appStore.trainees(for: trainer)
    }

    var body: some View {
        NavigationStack {
            Group {
                if let selectedTraineeId,
                   let trainee = trainees.first(where: { $0.id == selectedTraineeId }) {
                    threadView(trainee)
                } else {
                    inboxView
                }
            }
            .background(canvas.ignoresSafeArea())
            .navigationTitle(selectedTraineeId == nil ? "Trainee chat" : "Chat")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if selectedTraineeId != nil {
                        Button("Back") { selectedTraineeId = nil }
                    } else {
                        Button("Close") { dismiss() }
                    }
                }
            }
            .onAppear {
                chatStore.seedIfNeeded(traineeIds: trainees.map(\.id))
            }
        }
    }

    private var inboxView: some View {
        Group {
            if trainees.isEmpty {
                VStack(spacing: 12) {
                    TTIcon(icon: .chat, filled: true, size: 28)
                        .foregroundStyle(TTColor.actionOrange)
                    Text("No trainees yet")
                        .font(TTFont.workSans(17, weight: .bold))
                    Text("When athletes join your roster, you can message them here.")
                        .font(TTFont.body(14))
                        .foregroundStyle(TTColor.inkMuted)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 28)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 10) {
                        ForEach(trainees) { trainee in
                            Button {
                                selectedTraineeId = trainee.id
                                chatStore.markRead(traineeId: trainee.id)
                            } label: {
                                inboxRow(trainee)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(16)
                }
            }
        }
    }

    private func inboxRow(_ trainee: TraineeProfile) -> some View {
        let name = appStore.user(forTrainee: trainee)?.name ?? "Trainee"
        let last = chatStore.lastMessage(for: trainee.id)
        let unread = chatStore.unreadCount(for: trainee.id)

        return HStack(spacing: 12) {
            TTAvatar(name: name, size: 50)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(name)
                        .font(TTFont.workSans(16, weight: .bold))
                        .foregroundStyle(TTColor.ink)
                    Spacer()
                    if let last {
                        Text(last.sentAt.formatted(date: .omitted, time: .shortened))
                            .font(TTFont.caption(11))
                            .foregroundStyle(TTColor.inkSubtle)
                    }
                }
                Text(last?.text ?? "Say hello")
                    .font(TTFont.caption(13))
                    .foregroundStyle(TTColor.inkMuted)
                    .lineLimit(1)
            }

            if unread > 0 {
                Text("\(unread)")
                    .font(TTFont.caption(11))
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(TTColor.actionOrange)
                    .clipShape(Capsule())
            } else {
                TTChevronForward(size: 12)
            }
        }
        .padding(14)
        .background(cardFill)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func threadView(_ trainee: TraineeProfile) -> some View {
        let name = appStore.user(forTrainee: trainee)?.name ?? "Trainee"
        let messages = chatStore.messages(for: trainee.id)
        let draft = Binding(
            get: { chatStore.drafts[trainee.id] ?? "" },
            set: { chatStore.drafts[trainee.id] = $0 }
        )

        return VStack(spacing: 0) {
            HStack(spacing: 10) {
                TTAvatar(name: name, size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(TTFont.workSans(16, weight: .bold))
                    Text("Local preview · sockets later")
                        .font(TTFont.caption(11))
                        .foregroundStyle(TTColor.inkMuted)
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.white)

            Divider().opacity(0.12)

            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 10) {
                        ForEach(messages) { message in
                            bubble(message)
                                .id(message.id)
                        }
                        Color.clear.frame(height: 1).id("thread-bottom")
                    }
                    .padding(16)
                }
                .defaultScrollAnchor(.bottom)
                .onAppear {
                    var t = Transaction(); t.disablesAnimations = true
                    withTransaction(t) { proxy.scrollTo("thread-bottom", anchor: .bottom) }
                }
                .onChange(of: messages.count) { _, _ in
                    var t = Transaction(); t.disablesAnimations = true
                    withTransaction(t) { proxy.scrollTo("thread-bottom", anchor: .bottom) }
                }
            }

            HStack(spacing: 10) {
                TextField("Message \(name)…", text: draft, axis: .vertical)
                    .lineLimit(1...4)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(cardFill)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                Button {
                    chatStore.send(to: trainee.id, text: draft.wrappedValue)
                } label: {
                    TTIcon(icon: .paperPlaneDiagonal, filled: true, size: 18)
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(Color.black)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled((draft.wrappedValue).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .opacity((draft.wrappedValue).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.4 : 1)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.white)
        }
    }

    private func bubble(_ message: TraineeChatMessage) -> some View {
        HStack {
            if message.isFromTrainer { Spacer(minLength: 48) }
            VStack(alignment: message.isFromTrainer ? .trailing : .leading, spacing: 4) {
                Text(message.text)
                    .font(TTFont.workSans(15, weight: .medium))
                    .foregroundStyle(message.isFromTrainer ? .white : TTColor.ink)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(message.isFromTrainer ? Color.black : cardFill)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                Text(message.sentAt.formatted(date: .omitted, time: .shortened))
                    .font(TTFont.caption(10))
                    .foregroundStyle(TTColor.inkSubtle)
            }
            if !message.isFromTrainer { Spacer(minLength: 48) }
        }
    }
}

#Preview("Trainee chat") {
    TrainerTraineeChatView()
        .ttPreviewTrainer()
}
