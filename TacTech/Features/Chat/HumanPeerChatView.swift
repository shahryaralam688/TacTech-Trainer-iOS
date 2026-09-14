import AVKit
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// Trainer↔trainee messaging — AI chat chrome, WhatsApp-like media + live video call.
struct HumanPeerChatView: View {
    var audience: HumanChatAudience
    /// When set (push / inbox deep link), open this thread after bootstrap.
    var preferredThreadId: String? = nil

    @Environment(AppStore.self) private var appStore
    @Environment(\.dismiss) private var dismiss
    @Bindable private var chatStore = HumanChatStore.shared
    @State private var selectedPeerId: String?
    @State private var pendingImage: UIImage?
    @State private var pendingVideoURL: URL?
    @State private var libraryItem: PhotosPickerItem?
    @State private var showPhotoSource = false
    @State private var showCamera = false
    @State private var showLibrary = false
    @State private var cameraImage: UIImage?
    @State private var composerFocused = false
    @State private var fullscreenImage: UIImage?
    @State private var videoPlayerURL: URL?
    @State private var enableListMotion = false
    @State private var stickyDateLabel = "Today"
    @State private var distanceFromBottom: CGFloat = 0
    @State private var unreadWhileScrolled = 0
    @State private var highlightMessageId: String?
    @State private var failedActionMessage: HumanChatMessage?
    @State private var jumpBottomTick = 0
    @State private var capabilityToast: TTToastMessage?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let orange = TTColor.actionOrange
    private let ink = Color.black
    private let muted = Color(white: 0.42)
    private let soft = Animation.spring(response: 0.38, dampingFraction: 0.86)

    private var rosterPeers: [HumanChatPeer] {
        switch audience {
        case .trainer:
            guard let trainer = appStore.currentTrainer else { return [] }
            return appStore.trainees(for: trainer).compactMap { trainee -> HumanChatPeer? in
                let userId = trainee.userId.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !userId.isEmpty else { return nil }
                return HumanChatPeer(
                    id: userId,
                    name: appStore.user(forTrainee: trainee)?.name ?? "Trainee",
                    role: .trainee,
                    profileId: trainee.id
                )
            }
        case .trainee:
            guard let trainee = appStore.currentTrainee,
                  let trainer = appStore.trainer(for: trainee) else { return [] }
            return [
                HumanChatPeer(
                    id: trainer.userId,
                    name: appStore.user(forTrainer: trainer)?.name ?? "Coach",
                    role: .trainer,
                    profileId: trainer.id
                )
            ]
        }
    }

    private var peers: [HumanChatPeer] {
        chatStore.displayPeers(roster: rosterPeers)
    }

    private var selectedPeer: HumanChatPeer? {
        peers.first { $0.id == selectedPeerId }
    }

    var body: some View {
        ZStack {
            Color(white: 0.98).ignoresSafeArea()
            if let peer = selectedPeer {
                threadColumn(peer)
            } else {
                inboxColumn
            }
        }
        .task {
            chatStore.lastError = nil
            await chatStore.bootstrap()
            guard !Task.isCancelled else { return }
            if let preferredThreadId,
               let peerId = chatStore.peerUserId(forThreadId: preferredThreadId)
                ?? peers.first(where: { $0.threadId == preferredThreadId })?.id {
                selectedPeerId = peerId
                if let peer = peers.first(where: { $0.id == peerId }) {
                    await chatStore.openThread(peer)
                }
            } else if audience == .trainee, peers.count == 1, selectedPeerId == nil {
                let peer = peers[0]
                selectedPeerId = peer.id
                await chatStore.openThread(peer)
            }
            guard !Task.isCancelled else { return }
            try? await Task.sleep(for: .milliseconds(350))
            enableListMotion = true
        }
        .onDisappear {
            // Close the active thread; keep socket teardown soft so in-flight sync
            // cannot surface as a user-facing “cancelled” error.
            chatStore.closeThread()
            chatStore.teardown()
        }
        .onChange(of: libraryItem) { _, item in
            Task { await importLibrary(item) }
        }
        .onChange(of: cameraImage) { _, image in
            guard let image else { return }
            pendingImage = image
            pendingVideoURL = nil
            cameraImage = nil
        }
        .confirmationDialog("Share media", isPresented: $showPhotoSource, titleVisibility: .visible) {
            Button("Photo Library") { showLibrary = true }
            Button("Camera") { showCamera = true }
            Button("Cancel", role: .cancel) {}
        }
        .photosPicker(
            isPresented: $showLibrary,
            selection: $libraryItem,
            matching: .any(of: [.images, .videos])
        )
        .sheet(isPresented: $showCamera) {
            CameraImagePicker(image: $cameraImage)
                .ignoresSafeArea()
        }
        .fullScreenCover(isPresented: Binding(
            get: { fullscreenImage != nil },
            set: { if !$0 { fullscreenImage = nil } }
        )) {
            ZStack {
                Color.black.ignoresSafeArea()
                if let fullscreenImage {
                    Image(uiImage: fullscreenImage)
                        .resizable()
                        .scaledToFit()
                        .ignoresSafeArea()
                }
                VStack {
                    HStack {
                        Spacer()
                        Button {
                            fullscreenImage = nil
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 28))
                                .foregroundStyle(.white.opacity(0.9))
                        }
                        .padding()
                    }
                    Spacer()
                }
            }
        }
        .fullScreenCover(isPresented: Binding(
            get: { videoPlayerURL != nil },
            set: { if !$0 { videoPlayerURL = nil } }
        )) {
            if let videoPlayerURL {
                VideoPlayer(player: AVPlayer(url: videoPlayerURL))
                    .ignoresSafeArea()
                    .overlay(alignment: .topTrailing) {
                        Button {
                            self.videoPlayerURL = nil
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 28))
                                .foregroundStyle(.white)
                                .padding()
                        }
                    }
            }
        }
        .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.55), trigger: chatStore.hapticTick)
        // WhatsApp-style: no blocking “Chat” alert on open/sync.
        // Failed sends use the bubble “Message failed” sheet; capability errors use a soft toast.
        .ttToast($capabilityToast)
        .onChange(of: chatStore.lastError) { _, message in
            guard let message, shouldPresentCapabilityToast(message) else {
                if message != nil { chatStore.lastError = nil }
                return
            }
            capabilityToast = TTToastMessage(text: message, style: .error)
            chatStore.lastError = nil
        }
        .alert("Message failed", isPresented: Binding(
            get: { failedActionMessage != nil },
            set: { if !$0 { failedActionMessage = nil } }
        )) {
            Button("Retry sending") {
                if let msg = failedActionMessage, let peerId = selectedPeerId {
                    chatStore.retryFailed(messageId: msg.id, peerUserId: peerId)
                }
                failedActionMessage = nil
            }
            Button("Delete", role: .destructive) {
                if let msg = failedActionMessage, let peerId = selectedPeerId {
                    chatStore.deleteLocalMessage(id: msg.id, peerUserId: peerId)
                }
                failedActionMessage = nil
            }
            Button("Cancel", role: .cancel) { failedActionMessage = nil }
        } message: {
            Text("This message wasn’t delivered.")
        }
    }

    // MARK: - Inbox

    private var inboxColumn: some View {
        VStack(spacing: 0) {
            headerBar(
                title: audience == .trainer ? "Trainee chat" : "Coach chat",
                subtitle: audience == .trainer ? "Message your athletes" : "Message your trainer",
                showBack: false
            )

            if peers.isEmpty {
                emptyInbox
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 10) {
                        ForEach(peers) { peer in
                            Button {
                                selectedPeerId = peer.id
                                Task { await chatStore.openThread(peer) }
                            } label: {
                                inboxRow(peer)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(16)
                }
                .refreshable { await chatStore.refreshInbox(quiet: true) }
            }
        }
    }

    private var emptyInbox: some View {
        VStack(spacing: 12) {
            TTIcon(icon: .chat, filled: true, size: 28)
                .foregroundStyle(orange)
            Text(audience == .trainer ? "No trainees yet" : "No trainer linked")
                .font(TTFont.workSans(17, weight: .bold))
                .foregroundStyle(ink)
            Text(
                audience == .trainer
                    ? "When athletes join your roster, you can message and share media here."
                    : "Join a trainer with an invite code to start chatting."
            )
            .font(TTFont.workSans(14, weight: .medium))
            .foregroundStyle(muted)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func inboxRow(_ peer: HumanChatPeer) -> some View {
        let last = chatStore.lastMessage(for: peer.id)
        let unread = chatStore.unreadCount(for: peer.id)
        let preview = last?.previewText ?? peer.lastPreview ?? "Say hello"
        let time = last?.sentAt ?? peer.lastAt
        return HStack(spacing: 12) {
            TTAvatar(name: peer.name, size: 50)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(peer.name)
                        .font(TTFont.workSans(16, weight: .bold))
                        .foregroundStyle(ink)
                    Spacer()
                    if let time {
                        Text(time.formatted(date: .omitted, time: .shortened))
                            .font(TTFont.workSans(11, weight: .medium))
                            .foregroundStyle(Color(white: 0.55))
                    }
                }
                Text(preview)
                    .font(TTFont.workSans(13, weight: .medium))
                    .foregroundStyle(muted)
                    .lineLimit(1)
            }
            if unread > 0 {
                Text("\(unread)")
                    .font(TTFont.workSans(11, weight: .bold))
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
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.black.opacity(0.05), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.04), radius: 8, y: 3)
    }

    // MARK: - Thread

    private var threadSubtitle: String {
        if chatStore.peerTyping { return "Typing…" }
        if chatStore.isLoadingThread { return "Loading…" }
        return "tap here for contact info"
    }

    private func threadColumn(_ peer: HumanChatPeer) -> some View {
        let messages = chatStore.messages(for: peer.id)
        let items = HumanChatThreadBuilder.items(messages: messages, peerTyping: chatStore.peerTyping)
        return VStack(spacing: 0) {
            HumanChatContactHeader(
                name: peer.name,
                subtitle: threadSubtitle,
                onBack: {
                    composerFocused = false
                    TTKeyboard.dismiss()
                    if audience == .trainer || peers.count > 1 {
                        chatStore.closeThread()
                        selectedPeerId = nil
                    } else {
                        dismiss()
                    }
                },
                onVideo: {
                    composerFocused = false
                    TTKeyboard.dismiss()
                    Task { await startCall(with: peer) }
                },
                onVoice: {
                    composerFocused = false
                    TTKeyboard.dismiss()
                    Task { await startCall(with: peer) }
                }
            )

            ZStack(alignment: .bottomTrailing) {
                ScrollViewReader { proxy in
                    ScrollView(showsIndicators: false) {
                        LazyVStack(spacing: 0) {
                            if chatStore.isLoadingOlder {
                                ProgressView()
                                    .padding(.vertical, 8)
                            }
                            Color.clear
                                .frame(height: 1)
                                .id("thread-top")
                                .onAppear {
                                    Task { await chatStore.loadOlderMessages(for: peer.id) }
                                }

                            if messages.isEmpty {
                                welcomeCard(peer)
                                    .padding(.bottom, 12)
                            }

                            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                                let prev = index > 0 ? items[index - 1] : nil
                                let gap = HumanChatThreadBuilder.spacing(before: item, previous: prev)
                                threadItemView(item, peer: peer)
                                    .padding(.top, gap)
                            }
                            Color.clear.frame(height: 8).id("thread-bottom")
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .animation(enableListMotion && !reduceMotion ? soft : nil, value: messages.count)
                        .animation(enableListMotion && !reduceMotion ? soft : nil, value: chatStore.peerTyping)
                    }
                    .defaultScrollAnchor(.bottom)
                    .scrollDismissesKeyboard(.interactively)
                    .safeAreaInset(edge: .top, spacing: 0) {
                        if !messages.isEmpty {
                            HumanChatDatePill(label: stickyDateLabel)
                                .padding(.vertical, 6)
                                .background(.ultraThinMaterial.opacity(0.92))
                        }
                    }
                    .onAppear {
                        stickyDateLabel = HumanChatThreadBuilder.dateLabel(for: messages.last?.sentAt ?? .now)
                        scrollBottom(proxy, animated: false)
                    }
                    .onChange(of: messages.count) { oldCount, newCount in
                        if newCount > oldCount {
                            let newestIsOutgoing = messages.last?.isOutgoing == true
                            if newestIsOutgoing || distanceFromBottom < 100 {
                                scrollBottom(proxy, animated: true)
                                unreadWhileScrolled = 0
                            } else if messages.last?.isOutgoing == false {
                                unreadWhileScrolled += 1
                            }
                        }
                        if let last = messages.last {
                            stickyDateLabel = HumanChatThreadBuilder.dateLabel(for: last.sentAt)
                        }
                    }
                    .onChange(of: highlightMessageId) { _, id in
                        guard let id else { return }
                        withAnimation(.easeInOut(duration: 0.35)) {
                            proxy.scrollTo(id, anchor: .center)
                        }
                        Task {
                            try? await Task.sleep(for: .milliseconds(900))
                            await MainActor.run { highlightMessageId = nil }
                        }
                    }
                    .onChange(of: jumpBottomTick) { _, _ in
                        scrollBottom(proxy, animated: true)
                    }
                }

                if distanceFromBottom > 300 || unreadWhileScrolled > 0 {
                    jumpToBottomButton
                        .padding(.trailing, 16)
                        .padding(.bottom, 12)
                        .transition(.scale.combined(with: .opacity))
                }
            }

            HumanChatComposerBar(
                draft: draftBinding(for: peer.id),
                pendingImage: $pendingImage,
                pendingVideoURL: $pendingVideoURL,
                isFocused: $composerFocused,
                peerName: peer.name,
                isRecording: chatStore.isRecording,
                isRecordingPaused: chatStore.isRecordingPaused,
                recordingSecondsLeft: chatStore.recordingSecondsLeft,
                recordingElapsed: chatStore.recordingElapsed,
                replyDraft: chatStore.replyDraft,
                onClearReply: { chatStore.clearReplyDraft() },
                onDraftChange: { chatStore.noteComposerTyping(peerUserId: peer.id, draft: $0) },
                onSendText: {
                    chatStore.sendText(to: peer.id, text: chatStore.drafts[peer.id] ?? "")
                    unreadWhileScrolled = 0
                    distanceFromBottom = 0
                },
                onSendImage: { caption in
                    guard let pendingImage else { return }
                    chatStore.sendImage(to: peer.id, image: pendingImage, caption: caption)
                    self.pendingImage = nil
                },
                onSendVideo: { caption in
                    guard let pendingVideoURL else { return }
                    chatStore.sendVideo(to: peer.id, fileURL: pendingVideoURL, caption: caption)
                    self.pendingVideoURL = nil
                },
                onPickMedia: {
                    composerFocused = false
                    showPhotoSource = true
                },
                onStartVoice: {
                    chatStore.armAutoSend(peerId: peer.id)
                    Task { await chatStore.startRecording() }
                },
                onStopVoice: {
                    chatStore.stopAndSendVoice(to: peer.id)
                },
                onCancelVoice: {
                    chatStore.cancelRecording()
                },
                onPauseVoice: {
                    chatStore.pauseRecording()
                },
                onResumeVoice: {
                    chatStore.resumeRecording()
                }
            )
        }
    }

    @ViewBuilder
    private func threadItemView(
        _ item: HumanChatThreadItem,
        peer: HumanChatPeer
    ) -> some View {
        switch item {
        case .date(_, let label):
            HumanChatDatePill(label: label)
                .onAppear { stickyDateLabel = label }
        case .typing:
            HumanChatTypingBubble()
        case .message(let message, let cluster, let showAvatar):
            HumanChatBubble(
                message: message,
                peerName: peer.name,
                cluster: cluster,
                showAvatar: showAvatar,
                image: message.kind == .image ? chatStore.loadImage(message) : nil,
                mediaURL: chatStore.resolveMediaURL(message),
                highlight: highlightMessageId == message.id,
                onPlayVoice: { chatStore.playVoice(message) },
                onFullscreenImage: { fullscreenImage = $0 },
                onPlayVideo: { videoPlayerURL = $0 },
                onReply: { chatStore.setReplyDraft(to: message, peerName: peer.name) },
                onRetry: { failedActionMessage = message },
                onDelete: { chatStore.deleteLocalMessage(id: message.id, peerUserId: peer.id) },
                onReact: { chatStore.addReaction($0, to: message.id, peerUserId: peer.id) },
                onCopy: {},
                onQuoteTap: {
                    if let id = message.replyToId {
                        highlightMessageId = id
                    }
                }
            )
            .id(message.id)
            .transition(enableListMotion && !reduceMotion ? .opacity.combined(with: .move(edge: .bottom)) : .identity)
            .onAppear {
                if message.id == chatStore.messages(for: peer.id).last?.id {
                    distanceFromBottom = 0
                }
            }
            .onDisappear {
                if message.id == chatStore.messages(for: peer.id).last?.id {
                    distanceFromBottom = 320
                }
            }
        }
    }

    private var jumpToBottomButton: some View {
        Button {
            unreadWhileScrolled = 0
            distanceFromBottom = 0
            jumpBottomTick &+= 1
        } label: {
            ZStack(alignment: .topTrailing) {
                TTIcon(icon: .chevronDown, size: 14)
                    .foregroundStyle(ink)
                    .frame(width: 40, height: 40)
                    .background(.ultraThinMaterial)
                    .clipShape(Circle())
                    .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
                if unreadWhileScrolled > 0 {
                    Text("\(min(unreadWhileScrolled, 99))")
                        .font(TTFont.workSans(10, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(orange)
                        .clipShape(Capsule())
                        .offset(x: 6, y: -6)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func welcomeCard(_ peer: HumanChatPeer) -> some View {
        VStack(spacing: 10) {
            TTAvatar(name: peer.name, size: 56)
            Text(peer.name)
                .font(TTFont.workSans(20, weight: .bold))
                .foregroundStyle(ink)
            Text("Share form clips, meal photos, or voice notes — same look as TacTech AI chat.")
                .font(TTFont.workSans(14, weight: .medium))
                .foregroundStyle(muted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)
        }
        .padding(.vertical, 28)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Header

    private func headerBar<Trailing: View>(
        title: String,
        subtitle: String,
        showBack: Bool,
        @ViewBuilder trailing: () -> Trailing = { EmptyView() }
    ) -> some View {
        HStack(spacing: 10) {
            if showBack {
                Button {
                    chatStore.closeThread()
                    selectedPeerId = nil
                    composerFocused = false
                    TTKeyboard.dismiss()
                } label: {
                    TTIcon(icon: .chevronLeft, size: 16)
                        .foregroundStyle(ink)
                        .frame(width: 36, height: 36)
                        .background(Color.black.opacity(0.05))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            } else {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(ink)
                        .frame(width: 36, height: 36)
                        .background(Color.black.opacity(0.05))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(TTFont.workSans(16, weight: .bold))
                    .foregroundStyle(ink)
                    .lineLimit(1)
                Text(subtitle)
                    .font(TTFont.workSans(11, weight: .medium))
                    .foregroundStyle(muted)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)
            trailing()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.92))
        .overlay(alignment: .bottom) {
            Divider().opacity(0.12)
        }
    }

    // MARK: - Helpers

    /// Soft toast only for local capability issues (mic / encode). Never cancel / roster / sync.
    private func shouldPresentCapabilityToast(_ message: String) -> Bool {
        let lower = message.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if lower.isEmpty { return false }
        if lower.contains("cancel") { return false }
        if lower.contains("roster") { return false }
        if lower.contains("session expired") { return false }
        if lower.contains("sign in") { return false }
        return lower.contains("microphone")
            || lower.contains("permission")
            || lower.contains("encode")
            || lower.contains("audio")
            || lower.contains("couldn’t read")
            || lower.contains("couldn’t play")
            || lower.contains("missing voice")
            || lower.contains("no audio")
            || lower.contains("isn’t available")
    }

    private func startCall(with peer: HumanChatPeer) async {
        guard HumanCallFeatures.isEnabled else { return }
        do {
            let threadId = try await chatStore.ensureThreadId(peerUserId: peer.id)
            await HumanCallStore.shared.startOutgoing(
                peerUserId: peer.id,
                peerName: peer.name,
                threadId: threadId,
                fromName: appStore.currentUser?.name
            )
        } catch {
            // Calls are hidden — swallow.
        }
    }

    private func draftBinding(for peerId: String) -> Binding<String> {
        Binding(
            get: { chatStore.drafts[peerId] ?? "" },
            set: { chatStore.drafts[peerId] = $0 }
        )
    }

    private func scrollBottom(_ proxy: ScrollViewProxy, animated: Bool = false) {
        if animated {
            withAnimation(.easeOut(duration: 0.28)) {
                proxy.scrollTo("thread-bottom", anchor: .bottom)
            }
        } else {
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) { proxy.scrollTo("thread-bottom", anchor: .bottom) }
        }
    }

    private func importLibrary(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        defer { libraryItem = nil }
        if let movie = try? await item.loadTransferable(type: ChatVideoFile.self) {
            await MainActor.run {
                pendingVideoURL = movie.url
                pendingImage = nil
            }
            return
        }
        if let data = try? await item.loadTransferable(type: Data.self),
           let image = UIImage(data: data) {
            await MainActor.run {
                pendingImage = image
                pendingVideoURL = nil
            }
        }
    }
}

/// WhatsApp-style thread chrome — TacTech tokens (Sandow, Work Sans, action orange).
private struct HumanChatContactHeader: View {
    let name: String
    var subtitle: String
    var onBack: () -> Void
    var onVideo: () -> Void
    var onVoice: () -> Void

    private let accent = TTColor.actionOrange
    private let barFill = Color(red: 248 / 255, green: 249 / 255, blue: 250 / 255)

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            Button(action: onBack) {
                TTIcon(icon: .chevronLeft, size: 18)
                    .foregroundStyle(accent)
                    .frame(width: 36, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back")

            HStack(alignment: .center, spacing: 8) {
                TTAvatar(name: name, size: 36, tint: accent)
                VStack(alignment: .leading, spacing: 1) {
                    Text(name)
                        .font(TTFont.workSans(17, weight: .semibold))
                        .foregroundStyle(TTColor.ink)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(TTFont.workSans(12, weight: .regular))
                        .foregroundStyle(TTColor.inkMuted)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 6) {
                if HumanCallFeatures.isEnabled {
                    headerAction(icon: .video, label: "Video call", action: onVideo)
                    headerAction(icon: .telephone1, label: "Voice call", action: onVoice)
                }
            }
        }
        .padding(.leading, 6)
        .padding(.trailing, 10)
        .padding(.vertical, 4)
        .background(barFill)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.black.opacity(0.08))
                .frame(height: 0.5)
        }
    }

    private func headerAction(icon: SandowIcon, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            TTIcon(icon: icon, size: 22)
                .foregroundStyle(accent)
                .frame(width: 40, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

// MARK: - Video transferable

private struct ChatVideoFile: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { file in
            SentTransferredFile(file.url)
        } importing: { received in
            let temp = FileManager.default.temporaryDirectory
                .appendingPathComponent("human-video-\(UUID().uuidString).\(received.file.pathExtension)")
            try? FileManager.default.removeItem(at: temp)
            try FileManager.default.copyItem(at: received.file, to: temp)
            return ChatVideoFile(url: temp)
        }
    }
}

/// Backward-compatible entry used by trainer FAB.
struct TrainerTraineeChatView: View {
    var body: some View {
        HumanPeerChatView(audience: .trainer)
    }
}

#Preview("Trainer chat") {
    HumanPeerChatView(audience: .trainer)
        .ttPreviewTrainer()
}

#Preview("Trainee chat") {
    HumanPeerChatView(audience: .trainee)
        .ttPreviewTrainee()
}
