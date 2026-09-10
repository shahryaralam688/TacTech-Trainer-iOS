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
    /// ChatGPT / Claude-style leading history drawer.
    @State private var isDrawerOpen = false
    @State private var pendingDelete: CoachConversation?
    /// Coalesce scroll-to-bottom so streaming `partialAssistantText` can’t
    /// fire `onChange(of: String)` layout updates multiple times per frame.
    @State private var scrollBottomScheduled = false
    @State private var deleteHaptic = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let orange = TTColor.actionOrange
    private let ink = Color.black
    private let muted = Color(white: 0.42)
    private let soft = Animation.spring(response: 0.38, dampingFraction: 0.86)
    private let drawerWidthRatio: CGFloat = 0.82

    private var activeTitle: String {
        if let id = store.activeConversationId,
           let match = store.conversations.first(where: { $0.id == id }),
           !match.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return match.title
        }
        return "TacTech AI"
    }

    var body: some View {
        GeometryReader { geo in
            let drawerWidth = min(320, geo.size.width * drawerWidthRatio)
            ZStack(alignment: .leading) {
                mainColumn
                    .frame(width: geo.size.width, height: geo.size.height)
                    .offset(x: isDrawerOpen ? drawerWidth * 0.12 : 0)
                    .disabled(isDrawerOpen)
                    .overlay {
                        if isDrawerOpen {
                            Color.black.opacity(0.38)
                                .ignoresSafeArea()
                                .onTapGesture { closeDrawer() }
                                .transition(.opacity)
                        }
                    }

                if isDrawerOpen {
                    drawerPanel(width: drawerWidth)
                        .frame(width: drawerWidth)
                        .frame(maxHeight: .infinity)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                        .zIndex(2)
                }
            }
            .animation(reduceMotion ? .easeOut(duration: 0.16) : soft, value: isDrawerOpen)
            .gesture(drawerEdgeGesture)
        }
        .background(Color(white: 0.98))
        .task {
            await store.bootstrap()
            await MainActor.run {
                finishInitialScrollGate()
            }
        }
        .onDisappear {
            store.onDisappear()
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
        .sensoryFeedback(.warning, trigger: deleteHaptic)
        .confirmationDialog(
            "Delete this chat?",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                guard let pendingDelete else { return }
                let id = pendingDelete.id
                self.pendingDelete = nil
                deleteHaptic &+= 1
                Task { await store.deleteConversation(id) }
            }
            Button("Cancel", role: .cancel) {
                pendingDelete = nil
            }
        } message: {
            if let pendingDelete {
                Text("“\(pendingDelete.title.isEmpty ? "AI Coach" : pendingDelete.title)” will be removed. This can’t be undone.")
            }
        }
    }

    private var mainColumn: some View {
        VStack(spacing: 0) {
            if showsGrabber {
                grabber
            }
            header
            Divider().opacity(0.08)

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
    }

    private func openDrawer() {
        TTKeyboard.dismiss()
        composerFocused = false
        Task { await store.refreshConversations() }
        withAnimation(reduceMotion ? .easeOut(duration: 0.16) : soft) {
            isDrawerOpen = true
        }
    }

    private func closeDrawer() {
        withAnimation(reduceMotion ? .easeOut(duration: 0.14) : soft) {
            isDrawerOpen = false
        }
    }

    private func startNewChatFromUI() {
        closeDrawer()
        Task {
            await store.startNewConversation()
            await MainActor.run {
                enableListMotion = false
                userPinnedScroll = false
                finishInitialScrollGate()
            }
        }
    }

    private func selectChatFromDrawer(_ id: String) {
        closeDrawer()
        Task {
            await store.selectConversation(id)
            await MainActor.run {
                enableListMotion = false
                userPinnedScroll = false
                finishInitialScrollGate()
            }
        }
    }

    private func confirmDelete(_ conversation: CoachConversation) {
        pendingDelete = conversation
    }

    private func drawerChatRow(_ conversation: CoachConversation) -> some View {
        let isActive = conversation.id == store.activeConversationId
        return HStack(spacing: 8) {
            Button {
                selectChatFromDrawer(conversation.id)
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "bubble.left.and.bubble.right")
                        .font(TTFont.workSans(13, weight: .medium))
                        .foregroundStyle(isActive ? orange : ink.opacity(0.45))
                        .frame(width: 22)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(conversation.title.isEmpty ? "AI Coach" : conversation.title)
                            .font(TTFont.workSans(14, weight: isActive ? .bold : .semibold))
                            .foregroundStyle(ink)
                            .lineLimit(1)
                        Text(conversation.updatedAt.formatted(date: .abbreviated, time: .shortened))
                            .font(TTFont.workSans(11, weight: .medium))
                            .foregroundStyle(muted)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.leading, 12)
                .padding(.vertical, 11)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                confirmDelete(conversation)
            } label: {
                Image(systemName: "trash")
                    .font(TTFont.workSans(13, weight: .semibold))
                    .foregroundStyle(Color.red.opacity(0.75))
                    .frame(width: 36, height: 36)
                    .background(Color.red.opacity(0.08))
                    .clipShape(Circle())
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Delete chat")
            .padding(.trailing, 8)
        }
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isActive ? orange.opacity(0.12) : Color.white.opacity(0.55))
        )
    }

    private var drawerEdgeGesture: some Gesture {
        DragGesture(minimumDistance: 20, coordinateSpace: .global)
            .onEnded { value in
                let fromLeftEdge = value.startLocation.x < 28
                let horizontal = value.translation.width
                if !isDrawerOpen, fromLeftEdge, horizontal > 56 {
                    openDrawer()
                } else if isDrawerOpen, horizontal < -56 {
                    closeDrawer()
                }
            }
    }

    @ViewBuilder
    private func drawerPanel(width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [orange, orange.opacity(0.72)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 36, height: 36)
                    TTIcon(icon: .robotFace1, filled: true, size: 16)
                        .foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("TacTech AI")
                        .font(TTFont.workSans(17, weight: .bold))
                        .foregroundStyle(ink)
                    Text(audience.headerSubtitle)
                        .font(TTFont.workSans(11, weight: .medium))
                        .foregroundStyle(muted)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Button(action: closeDrawer) {
                    Image(systemName: "xmark")
                        .font(TTFont.workSans(13, weight: .bold))
                        .foregroundStyle(ink.opacity(0.55))
                        .frame(width: 32, height: 32)
                        .background(Color.black.opacity(0.05))
                        .clipShape(Circle())
                }
                .accessibilityLabel("Close sidebar")
            }
            .padding(.horizontal, 16)
            .padding(.top, showsGrabber ? 8 : 16)
            .padding(.bottom, 14)

            Button(action: startNewChatFromUI) {
                HStack(spacing: 10) {
                    Image(systemName: "square.and.pencil")
                        .font(TTFont.workSans(15, weight: .semibold))
                    Text("New chat")
                        .font(TTFont.workSans(15, weight: .bold))
                    Spacer(minLength: 0)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 13)
                .background(orange)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(AssessmentCardPressStyle())
            .padding(.horizontal, 14)
            .padding(.bottom, 12)

            Text("Your chats")
                .font(TTFont.workSans(12, weight: .bold))
                .foregroundStyle(muted)
                .textCase(.uppercase)
                .tracking(0.4)
                .padding(.horizontal, 18)
                .padding(.bottom, 6)

            List {
                if store.conversations.isEmpty {
                    Text("No chats yet — start a new one.")
                        .font(TTFont.workSans(13, weight: .medium))
                        .foregroundStyle(muted)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
                ForEach(store.conversations) { conversation in
                    drawerChatRow(conversation)
                        .listRowInsets(EdgeInsets(top: 3, leading: 10, bottom: 3, trailing: 10))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                confirmDelete(conversation)
                            } label: {
                                Label("Delete", systemImage: "trash.fill")
                            }
                            .tint(Color.red.opacity(0.92))
                        }
                        .contextMenu {
                            Button(role: .destructive) {
                                confirmDelete(conversation)
                            } label: {
                                Label("Delete chat", systemImage: "trash")
                            }
                        }
                }
                .onDelete { indexSet in
                    let ids = indexSet.compactMap { store.conversations.indices.contains($0) ? store.conversations[$0].id : nil }
                    for id in ids {
                        if let conversation = store.conversations.first(where: { $0.id == id }) {
                            confirmDelete(conversation)
                        }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .environment(\.defaultMinListRowHeight, 52)
            .animation(reduceMotion ? .easeOut(duration: 0.18) : soft, value: store.conversations.map(\.id))

            Spacer(minLength: 0)

            Divider().opacity(0.1)
            Button {
                Task { await store.syncMemoryDebounced(force: true) }
            } label: {
                Label("Sync memory", systemImage: "arrow.triangle.2.circlepath")
                    .font(TTFont.workSans(13, weight: .semibold))
                    .foregroundStyle(ink.opacity(0.7))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.plain)
        }
        .frame(width: width)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color(white: 0.97).ignoresSafeArea())
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Color.black.opacity(0.06))
                .frame(width: 1)
                .ignoresSafeArea()
        }
        .shadow(color: Color.black.opacity(0.18), radius: 24, x: 8, y: 0)
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
            onCall: {
                TTKeyboard.dismiss()
                composerFocused = false
                showCall = true
            },
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
        HStack(spacing: 10) {
            Button(action: openDrawer) {
                Image(systemName: "line.3.horizontal")
                    .font(TTFont.workSans(17, weight: .semibold))
                    .foregroundStyle(ink.opacity(0.75))
                    .frame(width: 36, height: 36)
                    .background(Color.black.opacity(0.05))
                    .clipShape(Circle())
            }
            .accessibilityLabel("Open chat history")

            VStack(spacing: 1) {
                Text(activeTitle)
                    .font(TTFont.workSans(16, weight: .bold))
                    .foregroundStyle(ink)
                    .lineLimit(1)
                HStack(spacing: 5) {
                    Circle()
                        .fill(store.status?.chatConfigured == true
                              ? Color(red: 0.2, green: 0.78, blue: 0.45)
                              : Color.orange)
                        .frame(width: 6, height: 6)
                    Text(audience.headerSubtitle)
                        .font(TTFont.workSans(11, weight: .medium))
                        .foregroundStyle(muted)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity)

            Button(action: startNewChatFromUI) {
                Image(systemName: "square.and.pencil")
                    .font(TTFont.workSans(15, weight: .semibold))
                    .foregroundStyle(ink.opacity(0.75))
                    .frame(width: 36, height: 36)
                    .background(Color.black.opacity(0.05))
                    .clipShape(Circle())
            }
            .accessibilityLabel("New chat")

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(TTFont.workSans(13, weight: .bold))
                    .foregroundStyle(ink)
                    .frame(width: 36, height: 36)
                    .background(Color.black.opacity(0.06))
                    .clipShape(Circle())
            }
            .buttonStyle(AssessmentCardPressStyle())
            .accessibilityLabel("Close AI chat")
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 10)
        .padding(.top, showsGrabber ? 2 : 10)
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
                scheduleJumpToBottom(proxy, animated: animated)
            }
            .onChange(of: store.partialAssistantText) { _, _ in
                guard !userPinnedScroll, store.isStreaming, enableListMotion else { return }
                // Once per run-loop turn — SSE can emit many string updates in one frame.
                scheduleJumpToBottom(proxy, animated: false)
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
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [orange, orange.opacity(0.72)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 56, height: 56)
                TTIcon(icon: .robotFace1, filled: true, size: 26)
                    .foregroundStyle(.white)
            }
            Text("How can I help?")
                .font(TTFont.workSans(22, weight: .bold))
                .foregroundStyle(ink)
            Text(audience.welcome)
                .font(TTFont.workSans(14, weight: .medium))
                .foregroundStyle(muted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 28)
        .frame(maxWidth: .infinity)
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
    }

    private func sendPendingImage(_ caption: String?) {
        guard let image = pendingImage else { return }
        pendingImage = nil
        draft = ""
        store.sendImage(image, caption: caption)
        userPinnedScroll = false
    }

    private func importLibrary(_ item: PhotosPickerItem?) async {
        guard let item,
              let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else { return }
        pendingImage = image
        libraryItem = nil
    }

    private func scheduleJumpToBottom(_ proxy: ScrollViewProxy, animated: Bool) {
        guard !scrollBottomScheduled else { return }
        scrollBottomScheduled = true
        DispatchQueue.main.async {
            scrollBottomScheduled = false
            jumpToBottomNow(proxy, animated: animated)
        }
    }

    private func jumpToBottom(_ proxy: ScrollViewProxy, animated: Bool) {
        scheduleJumpToBottom(proxy, animated: animated)
    }

    private func jumpToBottomNow(_ proxy: ScrollViewProxy, animated: Bool) {
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

    private func finishInitialScrollGate() {
        guard !enableListMotion else { return }
        // One more frame so LazyVStack finishes laying out history.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            enableListMotion = true
        }
    }
}
