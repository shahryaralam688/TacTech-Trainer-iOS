import AVKit
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// Trainer↔trainee messaging — AI chat chrome, WhatsApp-like media + live video call.
struct HumanPeerChatView: View {
    var audience: HumanChatAudience

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
    @State private var showCall = false
    @State private var fullscreenImage: UIImage?
    @State private var videoPlayerURL: URL?
    @State private var enableListMotion = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let orange = TTColor.actionOrange
    private let ink = Color.black
    private let muted = Color(white: 0.42)
    private let soft = Animation.spring(response: 0.38, dampingFraction: 0.86)

    private var peers: [HumanChatPeer] {
        switch audience {
        case .trainer:
            guard let trainer = appStore.currentTrainer else { return [] }
            return appStore.trainees(for: trainer).map { trainee in
                HumanChatPeer(
                    id: trainee.id,
                    name: appStore.user(forTrainee: trainee)?.name ?? "Trainee",
                    role: .trainee
                )
            }
        case .trainee:
            guard let trainee = appStore.currentTrainee,
                  let trainer = appStore.trainer(for: trainee) else { return [] }
            return [
                HumanChatPeer(
                    id: trainer.id,
                    name: appStore.user(forTrainer: trainer)?.name ?? "Coach",
                    role: .trainer
                )
            ]
        }
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
        .onAppear {
            chatStore.seedIfNeeded(peers: peers, asAudience: audience)
            if audience == .trainee, peers.count == 1, selectedPeerId == nil {
                selectedPeerId = peers.first?.id
                if let id = selectedPeerId {
                    chatStore.markRead(peerId: id)
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                enableListMotion = true
            }
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
        .fullScreenCover(isPresented: $showCall) {
            if let peer = selectedPeer {
                HumanCallView(peerName: peer.name, isPresented: $showCall) { outcome in
                    chatStore.recordCallEvent(peerId: peer.id, outcome: outcome)
                }
            }
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
        .alert("Chat", isPresented: Binding(
            get: { chatStore.lastError != nil },
            set: { if !$0 { chatStore.lastError = nil } }
        )) {
            Button("OK", role: .cancel) { chatStore.lastError = nil }
        } message: {
            Text(chatStore.lastError ?? "")
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
                                chatStore.markRead(peerId: peer.id)
                            } label: {
                                inboxRow(peer)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(16)
                }
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
                    ? "When athletes join your roster, you can message, share media, and video call here."
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
        return HStack(spacing: 12) {
            TTAvatar(name: peer.name, size: 50)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(peer.name)
                        .font(TTFont.workSans(16, weight: .bold))
                        .foregroundStyle(ink)
                    Spacer()
                    if let last {
                        Text(last.sentAt.formatted(date: .omitted, time: .shortened))
                            .font(TTFont.workSans(11, weight: .medium))
                            .foregroundStyle(Color(white: 0.55))
                    }
                }
                Text(last?.previewText ?? "Say hello")
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

    private func threadColumn(_ peer: HumanChatPeer) -> some View {
        let messages = chatStore.messages(for: peer.id)
        return VStack(spacing: 0) {
            headerBar(
                title: peer.name,
                subtitle: "Text · photo · video · voice · call",
                showBack: audience == .trainer || peers.count > 1,
                trailing: {
                    Button {
                        composerFocused = false
                        TTKeyboard.dismiss()
                        showCall = true
                    } label: {
                        Image(systemName: "video.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(ink)
                            .frame(width: 36, height: 36)
                            .background(Color.black.opacity(0.05))
                            .clipShape(Circle())
                    }
                    .buttonStyle(AssessmentCardPressStyle())
                    .accessibilityLabel("Start video call")
                }
            )

            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 12) {
                        if messages.isEmpty {
                            welcomeCard(peer)
                        }
                        ForEach(messages) { message in
                            HumanChatBubble(
                                message: message,
                                peerName: peer.name,
                                image: message.kind == .image ? chatStore.loadImage(message) : nil,
                                mediaURL: chatStore.resolveMediaURL(message),
                                onPlayVoice: { chatStore.playVoice(message) },
                                onFullscreenImage: { fullscreenImage = $0 },
                                onPlayVideo: { videoPlayerURL = $0 }
                            )
                            .id(message.id)
                            .transition(enableListMotion && !reduceMotion ? .opacity.combined(with: .move(edge: .bottom)) : .identity)
                        }
                        Color.clear.frame(height: 8).id("thread-bottom")
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .animation(enableListMotion && !reduceMotion ? soft : nil, value: messages.count)
                }
                .defaultScrollAnchor(.bottom)
                .onAppear {
                    scrollBottom(proxy)
                }
                .onChange(of: messages.count) { _, _ in
                    scrollBottom(proxy)
                }
            }

            HumanChatComposerBar(
                draft: draftBinding(for: peer.id),
                pendingImage: $pendingImage,
                pendingVideoURL: $pendingVideoURL,
                isFocused: $composerFocused,
                peerName: peer.name,
                isRecording: chatStore.isRecording,
                recordingSecondsLeft: chatStore.recordingSecondsLeft,
                onSendText: {
                    chatStore.sendText(to: peer.id, text: chatStore.drafts[peer.id] ?? "")
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
                onMic: {
                    chatStore.armAutoSend(peerId: peer.id)
                    Task { await chatStore.startRecording() }
                },
                onCall: {
                    composerFocused = false
                    TTKeyboard.dismiss()
                    showCall = true
                },
                onStopVoice: {
                    chatStore.stopAndSendVoice(to: peer.id)
                },
                onCancelVoice: {
                    chatStore.cancelRecording()
                }
            )
        }
    }

    private func welcomeCard(_ peer: HumanChatPeer) -> some View {
        VStack(spacing: 10) {
            TTAvatar(name: peer.name, size: 56)
            Text(peer.name)
                .font(TTFont.workSans(20, weight: .bold))
                .foregroundStyle(ink)
            Text("Share form clips, meal photos, voice notes, or hop on a live video call — same look as TacTech AI chat.")
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
                    selectedPeerId = nil
                    composerFocused = false
                    TTKeyboard.dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 15, weight: .semibold))
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

    private func draftBinding(for peerId: String) -> Binding<String> {
        Binding(
            get: { chatStore.drafts[peerId] ?? "" },
            set: { chatStore.drafts[peerId] = $0 }
        )
    }

    private func scrollBottom(_ proxy: ScrollViewProxy) {
        var t = Transaction()
        t.disablesAnimations = true
        withTransaction(t) { proxy.scrollTo("thread-bottom", anchor: .bottom) }
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
