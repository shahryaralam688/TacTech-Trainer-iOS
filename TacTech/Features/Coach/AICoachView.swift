import PhotosUI
import SwiftUI
import UIKit

/// Live AI Coach chat surface — streaming text, image vision, voice, call entry.
struct AICoachView: View {
    @Bindable var store: CoachStore
    var audience: TTAIChatAudience
    var onClose: () -> Void
    /// Floating bubble chrome used a grabber; full-screen presents without it.
    var showsGrabber: Bool = true

    @State private var draft = ""
    @State private var pendingImage: UIImage?
    @State private var libraryItem: PhotosPickerItem?
    @State private var showPhotoSource = false
    @State private var showCamera = false
    @State private var cameraImage: UIImage?
    @State private var showCall = false
    @State private var citationsToShow: [CoachCitation]?
    @State private var fullscreenImage: UIImage?
    @State private var userPinnedScroll = false
    @State private var wavePhase: CGFloat = 0
    @State private var composerFocused = false
    /// After first paint, allow soft scroll / insert motion — avoids open “whizz” through history.
    @State private var enableListMotion = false
    @State private var showChatsSheet = false
    @State private var localSessions: [LocalAIChatSession] = []
    @State private var activeSessionId = ""
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let orange = TTColor.actionOrange
    private let ink = Color.black
    private let muted = Color(white: 0.42)
    private let soft = Animation.spring(response: 0.38, dampingFraction: 0.86)

    var body: some View {
        VStack(spacing: 0) {
            if showsGrabber {
                grabber
            }
            header
            Divider().opacity(0.10)

            messageList
                .refreshable {
                    await store.syncMemoryDebounced(force: true)
                    await store.refreshMessages()
                }

            if shouldShowSuggestions {
                suggestionRow
            }

            if let err = store.lastError {
                errorBanner(err)
            }

            composer
        }
        .background(Color.white)
        .task {
            ensureLocalSessionSeed()
            await store.bootstrap()
            await MainActor.run {
                persistActiveSession()
                finishInitialScrollGate()
            }
        }
        .onDisappear {
            persistActiveSession()
            store.onDisappear()
        }
        .sheet(isPresented: $showChatsSheet) {
            AIChatsSheet(
                sessions: localSessions,
                activeId: activeSessionId,
                onSelect: { switchToSession($0) },
                onNew: { startLocalNewChat() }
            )
            .presentationDetents([.medium, .large])
        }
        .onChange(of: libraryItem) { _, item in
            Task { await importLibrary(item) }
        }
        .onChange(of: cameraImage) { _, image in
            guard let image else { return }
            pendingImage = image
            cameraImage = nil
        }
        .sheet(isPresented: $showCamera) {
            CameraImagePicker(image: $cameraImage)
                .ignoresSafeArea()
        }
        .sheet(isPresented: Binding(
            get: { citationsToShow != nil },
            set: { if !$0 { citationsToShow = nil } }
        )) {
            if let citationsToShow {
                CoachCitationsSheet(citations: citationsToShow)
            }
        }
        .fullScreenCover(isPresented: $showCall) {
            CoachVoiceCallView(store: store, isPresented: $showCall)
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
                        .padding()
                }
                VStack {
                    HStack {
                        Spacer()
                        Button { fullscreenImage = nil } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 28))
                                .foregroundStyle(.white.opacity(0.85))
                        }
                        .padding()
                    }
                    Spacer()
                }
            }
        }
        .confirmationDialog("Share a photo", isPresented: $showPhotoSource, titleVisibility: .visible) {
            Button("Take Photo") { showCamera = true }
            PhotosPicker(selection: $libraryItem, matching: .images) {
                Text("Photo Library")
            }
            Button("Cancel", role: .cancel) {}
        }
        .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.7), trigger: store.hapticTick)
        .sensoryFeedback(.selection, trigger: store.isRecording)
    }

    private var composer: some View {
        CoachComposerBar(
            draft: $draft,
            pendingImage: $pendingImage,
            isFocused: $composerFocused,
            isBusy: store.isBusy || store.rateLimitSecondsRemaining > 0,
            isRecording: store.isRecording,
            recordingSecondsLeft: store.recordingSecondsLeft,
            showImageChips: pendingImage != nil,
            onSendText: sendDraft,
            onSendImage: sendPendingImage,
            onPickPhoto: {
                composerFocused = false
                showPhotoSource = true
            },
            onMic: { store.startRecording() },
            onCall: { showCall = true },
            onStopVoice: { store.stopAndSendVoice() },
            onCancelVoice: { store.cancelRecording() }
        )
    }

    private var shouldShowSuggestions: Bool {
        draft.isEmpty && pendingImage == nil && !store.isRecording && store.messages.isEmpty && !store.isBusy
    }

    private var grabber: some View {
        Capsule()
            .fill(Color.black.opacity(0.14))
            .frame(width: 36, height: 4)
            .padding(.top, 10)
            .padding(.bottom, 4)
    }

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [orange, orange.opacity(0.72)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 42, height: 42)
                    .shadow(color: orange.opacity(0.35), radius: 10, y: 4)
                TTIcon(icon: .robotFace1, filled: true, size: 20)
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("TacTech AI")
                    .font(TTFont.workSans(17, weight: .bold))
                    .foregroundStyle(ink)
                HStack(spacing: 6) {
                    Circle()
                        .fill(store.status?.chatConfigured == true
                              ? Color(red: 0.2, green: 0.78, blue: 0.45)
                              : Color.orange)
                        .frame(width: 7, height: 7)
                    Text(audience.headerSubtitle)
                        .font(TTFont.workSans(12, weight: .medium))
                        .foregroundStyle(muted)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            Button {
                persistActiveSession()
                showChatsSheet = true
            } label: {
                Image(systemName: "bubble.left.and.bubble.right")
                    .font(TTFont.workSans(18, weight: .medium))
                    .foregroundStyle(ink.opacity(0.7))
                    .frame(width: 36, height: 36)
                    .background(Color.black.opacity(0.05))
                    .clipShape(Circle())
            }
            .accessibilityLabel("Chats")

            Menu {
                Button("New chat") {
                    startLocalNewChat()
                }
                Button("Sync memory") {
                    Task { await store.syncMemoryDebounced(force: true) }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(TTFont.workSans(20, weight: .medium))
                    .foregroundStyle(ink.opacity(0.7))
            }

            Button(action: onClose) {
                ZStack {
                    Circle()
                        .fill(Color.black.opacity(0.06))
                        .frame(width: 36, height: 36)
                    Image(systemName: "xmark")
                        .font(TTFont.workSans(13, weight: .bold))
                        .foregroundStyle(ink)
                }
            }
            .buttonStyle(AssessmentCardPressStyle())
            .accessibilityLabel("Close AI chat")
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
        .padding(.top, showsGrabber ? 4 : 12)
        .contentShape(Rectangle())
        .onTapGesture { composerFocused = false }
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 12) {
                    if store.messages.isEmpty {
                        welcomeCard
                            .id("welcome")
                    }

                    if store.isBootstrapping && store.messages.isEmpty {
                        skeletonRows
                    }

                    ForEach(store.messages) { message in
                        CoachMessageBubble(
                            message: message,
                            onRetry: {
                                if message.modality == .image {
                                    store.retryImage(messageId: message.id)
                                } else if message.role == .user {
                                    store.retryText(messageId: message.id)
                                }
                            },
                            onPlayAudio: {
                                if let url = message.audioUrl?.trimmingCharacters(in: .whitespacesAndNewlines),
                                   !url.isEmpty {
                                    store.playAudio(urlString: url)
                                } else if !message.content.isEmpty {
                                    store.speakLocally(message.content)
                                }
                            },
                            onCitations: {
                                citationsToShow = message.citations
                            },
                            onFullscreenImage: { fullscreenImage = $0 }
                        )
                        .id(message.id)
                        .transition(messageTransition)
                    }

                    if store.isStreaming && store.partialAssistantText.isEmpty {
                        typingIndicator.id("typing")
                    }

                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.horizontal, 14)
                .padding(.top, 10)
                .padding(.bottom, 8)
                .animation(enableListMotion && !reduceMotion ? soft : nil, value: store.messages.count)
            }
            .defaultScrollAnchor(.bottom)
            .scrollDismissesKeyboard(.never)
            .onAppear {
                jumpToBottom(proxy, animated: false)
            }
            .onChange(of: store.messages.count) { oldCount, newCount in
                guard !userPinnedScroll else { return }
                // First bulk load / history restore → hard jump. Later sends → soft follow.
                let animated = enableListMotion && abs(newCount - oldCount) <= 2
                jumpToBottom(proxy, animated: animated)
            }
            .onChange(of: store.partialAssistantText) { _, _ in
                guard !userPinnedScroll, store.isStreaming, enableListMotion else { return }
                jumpToBottom(proxy, animated: true)
            }
            .onChange(of: store.isBootstrapping) { _, bootstrapping in
                if !bootstrapping {
                    jumpToBottom(proxy, animated: false)
                    finishInitialScrollGate()
                }
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 12).onChanged { value in
                    if value.translation.height > 20 {
                        userPinnedScroll = true
                    }
                }
            )
            .onTapGesture {
                userPinnedScroll = false
                composerFocused = false
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var messageTransition: AnyTransition {
        guard enableListMotion, !reduceMotion else { return .identity }
        return .asymmetric(
            insertion: .opacity.combined(with: .scale(scale: 0.96)).combined(with: .move(edge: .bottom)),
            removal: .opacity
        )
    }

    private var welcomeCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(audience.welcome)
                .font(TTFont.workSans(15, weight: .medium))
                .foregroundStyle(ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.92))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.black.opacity(0.06), lineWidth: 1)
        )
    }

    private var skeletonRows: some View {
        VStack(spacing: 10) {
            ForEach(0..<3, id: \.self) { i in
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.black.opacity(0.06))
                    .frame(height: 44)
                    .frame(maxWidth: i == 1 ? 180 : .infinity, alignment: i % 2 == 0 ? .leading : .trailing)
                    .frame(maxWidth: .infinity, alignment: i % 2 == 0 ? .leading : .trailing)
                    .redacted(reason: .placeholder)
            }
        }
        .padding(.vertical, 8)
    }

    private var typingIndicator: some View {
        HStack(alignment: .bottom, spacing: 8) {
            ZStack {
                Circle().fill(orange.opacity(0.14))
                TTIcon(icon: .robotFace1, filled: true, size: 12)
                    .foregroundStyle(orange)
            }
            .frame(width: 26, height: 26)
            HStack(spacing: 5) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(orange.opacity(0.5 + Double(i) * 0.15))
                        .frame(width: 7, height: 7)
                        .offset(y: wavePhase > 0 ? (i == Int(wavePhase) % 3 ? -3 : 0) : 0)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .background(Color.white.opacity(0.92))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            Spacer(minLength: 40)
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) {
                wavePhase = 2
            }
        }
    }

    private var suggestionRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(audience.suggestions, id: \.self) { tip in
                    Button {
                        draft = tip
                        sendDraft()
                    } label: {
                        Text(tip)
                            .font(TTFont.workSans(13, weight: .semibold))
                            .foregroundStyle(ink)
                            .padding(.horizontal, 13)
                            .padding(.vertical, 9)
                            .background(Color.white.opacity(0.92))
                            .clipShape(Capsule())
                            .overlay(Capsule().strokeBorder(orange.opacity(0.4), lineWidth: 1.1))
                    }
                    .buttonStyle(AssessmentCardPressStyle())
                    .disabled(store.isBusy)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
    }

    private func errorBanner(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(text)
                    .font(TTFont.workSans(13, weight: .medium))
                    .foregroundStyle(Color.red.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
                if store.rateLimitSecondsRemaining > 0 {
                    Text("Auto-retry in \(store.rateLimitSecondsRemaining)s")
                        .font(TTFont.workSans(12, weight: .semibold))
                        .foregroundStyle(muted)
                        .contentTransition(.numericText())
                        .animation(.snappy(duration: 0.18), value: store.rateLimitSecondsRemaining)
                }
            }
            Spacer(minLength: 8)
            Button(store.rateLimitSecondsRemaining > 0 ? "Retry now" : "Retry") {
                store.retryLastFailure()
            }
            .font(TTFont.workSans(13, weight: .bold))
            .foregroundStyle(orange)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.red.opacity(0.06))
    }

    private func sendDraft() {
        let text = draft
        draft = ""
        store.sendText(text)
        userPinnedScroll = false
        persistActiveSession()
    }

    private func sendPendingImage(_ caption: String?) {
        guard let image = pendingImage else { return }
        pendingImage = nil
        draft = ""
        store.sendImage(image, caption: caption)
        userPinnedScroll = false
        persistActiveSession()
    }

    private func importLibrary(_ item: PhotosPickerItem?) async {
        guard let item,
              let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else { return }
        pendingImage = image
        libraryItem = nil
    }

    private func jumpToBottom(_ proxy: ScrollViewProxy, animated: Bool) {
        DispatchQueue.main.async {
            if animated {
                withAnimation(.easeOut(duration: 0.18)) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            } else {
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
        }
    }

    private func finishInitialScrollGate() {
        guard !enableListMotion else { return }
        // One more frame so LazyVStack finishes laying out history.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            enableListMotion = true
        }
    }

    private func ensureLocalSessionSeed() {
        guard localSessions.isEmpty else { return }
        let id = UUID().uuidString
        localSessions = [
            LocalAIChatSession(
                id: id,
                title: "Chat 1",
                preview: "New conversation",
                messages: [],
                updatedAt: .now
            )
        ]
        activeSessionId = id
    }

    private func persistActiveSession() {
        guard let idx = localSessions.firstIndex(where: { $0.id == activeSessionId }) else { return }
        localSessions[idx].messages = store.messages
        localSessions[idx].updatedAt = .now
        if let last = store.messages.last {
            let clip = last.content.trimmingCharacters(in: .whitespacesAndNewlines)
            localSessions[idx].preview = clip.isEmpty ? "Attachment" : String(clip.prefix(42))
            if localSessions[idx].title.hasPrefix("Chat ") || localSessions[idx].title == "New chat" {
                localSessions[idx].title = String(clip.prefix(28)).isEmpty
                    ? localSessions[idx].title
                    : String(clip.prefix(28))
            }
        }
    }

    private func startLocalNewChat() {
        persistActiveSession()
        let id = UUID().uuidString
        let session = LocalAIChatSession(
            id: id,
            title: "New chat",
            preview: "Empty conversation",
            messages: [],
            updatedAt: .now
        )
        localSessions.insert(session, at: 0)
        activeSessionId = id
        enableListMotion = false
        store.beginLocalNewChat()
        userPinnedScroll = false
        showChatsSheet = false
        finishInitialScrollGate()
    }

    private func switchToSession(_ id: String) {
        guard id != activeSessionId else {
            showChatsSheet = false
            return
        }
        persistActiveSession()
        activeSessionId = id
        enableListMotion = false
        let msgs = localSessions.first(where: { $0.id == id })?.messages ?? []
        store.replaceMessagesLocally(msgs)
        userPinnedScroll = false
        showChatsSheet = false
        finishInitialScrollGate()
    }
}

// MARK: - Local multi-chat (UI only — backend later)

private struct LocalAIChatSession: Identifiable, Hashable {
    let id: String
    var title: String
    var preview: String
    var messages: [CoachDisplayMessage]
    var updatedAt: Date
}

private struct AIChatsSheet: View {
    let sessions: [LocalAIChatSession]
    let activeId: String
    var onSelect: (String) -> Void
    var onNew: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button(action: onNew) {
                        Label("New chat", systemImage: "plus.bubble")
                            .font(TTFont.workSans(16, weight: .semibold))
                            .foregroundStyle(TTColor.actionOrange)
                    }
                }

                Section("Your chats") {
                    ForEach(sessions) { session in
                        Button {
                            onSelect(session.id)
                        } label: {
                            HStack(spacing: 12) {
                                ZStack {
                                    Circle()
                                        .fill(TTColor.actionOrange.opacity(0.14))
                                    TTIcon(icon: .chat, filled: true, size: 16)
                                        .foregroundStyle(TTColor.actionOrange)
                                }
                                .frame(width: 40, height: 40)

                                VStack(alignment: .leading, spacing: 3) {
                                    Text(session.title)
                                        .font(TTFont.workSans(15, weight: .bold))
                                        .foregroundStyle(TTColor.ink)
                                        .lineLimit(1)
                                    Text(session.preview)
                                        .font(TTFont.caption(12))
                                        .foregroundStyle(TTColor.inkMuted)
                                        .lineLimit(1)
                                }

                                Spacer()

                                if session.id == activeId {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(TTColor.actionOrange)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle("Chats")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
