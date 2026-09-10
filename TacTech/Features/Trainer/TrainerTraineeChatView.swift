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

/// Inbox + thread for trainer ↔ trainee messaging — TacTech list + Live Chat chrome.
struct TrainerTraineeChatView: View {
    @Environment(AppStore.self) private var appStore
    @Environment(\.dismiss) private var dismiss
    @State private var chatStore = TraineeChatStore()
    @State private var selectedTraineeId: String?
    @StateObject private var scrollCollapse = TTHomeScrollCollapseModel()
    @FocusState private var composerFocused: Bool

    private let canvas = Color(white: 0.97)
    private let cardFill = Color(red: 243 / 255, green: 243 / 255, blue: 244 / 255)
    private let charcoal = Color(red: 28 / 255, green: 28 / 255, blue: 30 / 255)
    private let peerBubble = Color(red: 243 / 255, green: 244 / 255, blue: 246 / 255)
    private let orange = TTColor.actionOrange
    private let scrollSpace = "traineeChatInbox"

    private var trainees: [TraineeProfile] {
        guard let trainer = appStore.currentTrainer else { return [] }
        return appStore.trainees(for: trainer)
    }

    var body: some View {
        Group {
            if let selectedTraineeId,
               let trainee = trainees.first(where: { $0.id == selectedTraineeId }) {
                threadView(trainee)
            } else {
                inboxView
            }
        }
        .onAppear {
            chatStore.seedIfNeeded(traineeIds: trainees.map(\.id))
        }
    }

    // MARK: Inbox (My Trainees chrome)

    private var inboxView: some View {
        VStack(spacing: 0) {
            TTDarkPageHeader(
                title: "Messages",
                collapseProgress: scrollCollapse.progress,
                onBack: { dismiss() }
            )

            Group {
                if trainees.isEmpty {
                    emptyInbox
                } else {
                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 0) {
                            TTHomeScrollCollapseProbe(model: scrollCollapse, space: scrollSpace)

                            LazyVStack(spacing: 10) {
                                ForEach(trainees) { trainee in
                                    Button {
                                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                        selectedTraineeId = trainee.id
                                        chatStore.markRead(traineeId: trainee.id)
                                    } label: {
                                        inboxRow(trainee)
                                    }
                                    .buttonStyle(TTSearchPressStyle(scale: 0.98))
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.top, 16)
                            .padding(.bottom, 24)
                        }
                    }
                    .ttObserveHomeScrollCollapse(scrollCollapse, space: scrollSpace)
                }
            }
            .ttTopRoundedSheet(radius: TTSheetChrome.pageTopRadius, fill: canvas)
        }
        .background(charcoal.ignoresSafeArea(edges: .top))
        .ttHideSystemNavigationBar()
    }

    private var emptyInbox: some View {
        VStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(orange.opacity(0.14))
                    .frame(width: 72, height: 72)
                TTIcon(icon: .chat, filled: true, size: 28)
                    .foregroundStyle(orange)
            }
            Text("No trainees yet")
                .font(TTFont.workSans(18, weight: .bold))
                .foregroundStyle(TTColor.ink)
            Text("When athletes join your roster, you can message them here.")
                .font(TTFont.body(14))
                .foregroundStyle(TTColor.inkMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func inboxRow(_ trainee: TraineeProfile) -> some View {
        let name = appStore.user(forTrainee: trainee)?.name ?? "Trainee"
        let last = chatStore.lastMessage(for: trainee.id)
        let unread = chatStore.unreadCount(for: trainee.id)

        return HStack(spacing: 12) {
            TTAvatar(name: name, size: 50, tint: orange)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(name)
                        .font(TTFont.workSans(16, weight: .bold))
                        .foregroundStyle(TTColor.ink)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    if let last {
                        Text(last.sentAt.formatted(date: .omitted, time: .shortened))
                            .font(TTFont.caption(11))
                            .foregroundStyle(unread > 0 ? orange : TTColor.inkSubtle)
                    }
                }
                Text(last?.text ?? "Say hello")
                    .font(TTFont.caption(13))
                    .fontWeight(unread > 0 ? .semibold : .regular)
                    .foregroundStyle(unread > 0 ? TTColor.ink : TTColor.inkMuted)
                    .lineLimit(1)
            }

            if unread > 0 {
                Text("\(unread)")
                    .font(TTFont.caption(11))
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(orange)
                    .clipShape(Capsule())
            } else {
                TTChevronForward(size: 12)
            }
        }
        .padding(14)
        .background(cardFill)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    // MARK: Thread (Live Chat chrome)

    private func threadView(_ trainee: TraineeProfile) -> some View {
        let name = appStore.user(forTrainee: trainee)?.name ?? "Trainee"
        let messages = chatStore.messages(for: trainee.id)
        let draft = Binding(
            get: { chatStore.drafts[trainee.id] ?? "" },
            set: { chatStore.drafts[trainee.id] = $0 }
        )
        let canSend = !(draft.wrappedValue).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        return VStack(spacing: 0) {
            threadHeader(name: name)

            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 14) {
                        ForEach(messages) { message in
                            bubble(message, peerName: name)
                                .id(message.id)
                        }
                        Color.clear.frame(height: 1).id("thread-bottom")
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 18)
                    .padding(.bottom, 16)
                }
                .defaultScrollAnchor(.bottom)
                .onAppear {
                    var t = Transaction(); t.disablesAnimations = true
                    withTransaction(t) { proxy.scrollTo("thread-bottom", anchor: .bottom) }
                }
                .onChange(of: messages.count) { _, _ in
                    withAnimation(.easeOut(duration: 0.25)) {
                        proxy.scrollTo("thread-bottom", anchor: .bottom)
                    }
                }
            }
            .background(canvas)
            .clipShape(
                UnevenRoundedRectangle(
                    topLeadingRadius: 28,
                    bottomLeadingRadius: 0,
                    bottomTrailingRadius: 0,
                    topTrailingRadius: 28,
                    style: .continuous
                )
            )
            .offset(y: -10)

            threadComposer(traineeId: trainee.id, name: name, draft: draft, canSend: canSend)
        }
        .background(orange.ignoresSafeArea(edges: .top))
        .ttHideSystemNavigationBar()
        .onChange(of: selectedTraineeId) { _, _ in
            composerFocused = false
        }
    }

    private func threadHeader(name: String) -> some View {
        HStack(spacing: 12) {
            Button {
                composerFocused = false
                selectedTraineeId = nil
            } label: {
                TTIcon(icon: .chevronLeft, size: 16)
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back")

            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(TTFont.workSans(20, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text("Trainee chat")
                    .font(TTFont.caption(12))
                    .foregroundStyle(.white.opacity(0.72))
            }

            Spacer(minLength: 8)

            chatSquareAvatar(name: name, fill: .white.opacity(0.22), foreground: .white)
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 22)
        .background(orange)
    }

    private func threadComposer(
        traineeId: String,
        name: String,
        draft: Binding<String>,
        canSend: Bool
    ) -> some View {
        HStack(spacing: 10) {
            TextField("Message \(name)…", text: draft, axis: .vertical)
                .font(TTFont.body(15))
                .lineLimit(1...4)
                .focused($composerFocused)
                .tint(orange)
                .padding(.horizontal, 14)
                .frame(minHeight: 52)
                .ttInputChrome(
                    focused: composerFocused,
                    cornerRadius: 26,
                    idleFill: Color(white: 0.93)
                )
                .onSubmit {
                    guard canSend else { return }
                    send(to: traineeId, draft: draft)
                }

            Button {
                send(to: traineeId, draft: draft)
            } label: {
                TTIcon(icon: .arrowRight, filled: true, size: 18)
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 52)
                    .background(orange)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(TTSearchPressStyle(scale: 0.96))
            .disabled(!canSend)
            .opacity(canSend ? 1 : 0.55)
            .accessibilityLabel("Send")
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 14)
        .background(Color.white)
    }

    private func send(to traineeId: String, draft: Binding<String>) {
        let text = draft.wrappedValue
        chatStore.send(to: traineeId, text: text)
        composerFocused = false
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func bubble(_ message: TraineeChatMessage, peerName: String) -> some View {
        let isTrainer = message.isFromTrainer
        return HStack(alignment: .bottom, spacing: 8) {
            if !isTrainer {
                chatSquareAvatar(name: peerName, fill: peerBubble, foreground: TTColor.inkMuted)
            } else {
                Spacer(minLength: 40)
            }

            VStack(alignment: isTrainer ? .trailing : .leading, spacing: 4) {
                Text(message.text)
                    .font(TTFont.body(14))
                    .foregroundStyle(isTrainer ? .white : TTColor.ink)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(isTrainer ? charcoal : peerBubble)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                Text(message.sentAt.formatted(date: .omitted, time: .shortened))
                    .font(TTFont.caption(10))
                    .foregroundStyle(TTColor.inkSubtle)
            }

            if isTrainer {
                chatSquareAvatar(name: "You", fill: orange, foreground: .white)
            } else {
                Spacer(minLength: 40)
            }
        }
    }

    private func chatSquareAvatar(name: String, fill: Color, foreground: Color) -> some View {
        let initials: String = {
            let parts = name.split(separator: " ")
            let letters = parts.prefix(2).compactMap(\.first)
            return String(letters).uppercased()
        }()

        return Text(initials.isEmpty ? "?" : initials)
            .font(TTFont.workSans(12, weight: .semibold))
            .foregroundStyle(foreground)
            .frame(width: 36, height: 36)
            .background(fill)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

#Preview("Trainee chat") {
    TrainerTraineeChatView()
        .ttPreviewTrainer()
}
