import AVFoundation
import Foundation
import UIKit

/// Production trainer↔trainee chat store backed by `/chat/*` + Socket.IO (with REST refresh fallback).
@MainActor
@Observable
final class HumanChatStore {
    static let shared = HumanChatStore()
    static let maxRecordingSeconds: TimeInterval = 60

    var inbox: [HumanChatPeer] = []
    var messagesByPeer: [String: [HumanChatMessage]] = [:]
    var drafts: [String: String] = [:]
    var isRecording = false
    var isRecordingPaused = false
    var recordingElapsed: TimeInterval = 0
    var lastError: String?
    var hapticTick = 0
    var isLoadingInbox = false
    var isLoadingThread = false
    var activePeerUserId: String?
    var peerTyping = false
    /// Quoted reply docked above the composer (local UI until backend replyTo exists).
    var replyDraft: HumanChatReplyDraft?
    var nextCursorByPeer: [String: String] = [:]
    var isLoadingOlder = false

    private let api = ChatAPI()
    private var realtime = ChatRealtimeClient()
    private var threadIdByPeer: [String: String] = [:]
    private var peerByThread: [String: String] = [:]
    private var currentUserId: String?
    private var pollTask: Task<Void, Never>?
    private var typingStopTask: Task<Void, Never>?
    private var typingClearTask: Task<Void, Never>?
    private var lastTypingEmitAt: Date?
    private var outgoingTypingActive = false

    private var audioRecorder: AVAudioRecorder?
    private var recordingURL: URL?
    private var recordLimitTask: Task<Void, Never>?
    private var audioPlayer: AVAudioPlayer?
    private var activeRecordingPeerId: String?
    private var voiceProgressTask: Task<Void, Never>?
    private var voiceDelegate = HumanChatVoicePlayerDelegate()
    private var listenedVoiceIds: Set<String> = []
    private let listenedKey = "humanChat.listenedVoiceIds"

    var playingVoiceId: String?
    var voiceIsPlaying = false
    var voiceProgress: Double = 0
    var voiceElapsed: TimeInterval = 0
    var voiceDuration: TimeInterval = 0
    var voiceRate: Float = 1.0

    var voiceRateLabel: String {
        if voiceRate >= 1.75 { return "2x" }
        if voiceRate >= 1.25 { return "1.5x" }
        return "1x"
    }

    var recordingSecondsLeft: Int {
        max(0, Int((Self.maxRecordingSeconds - recordingElapsed).rounded(.up)))
    }

    private init() {
        if let stored = UserDefaults.standard.array(forKey: listenedKey) as? [String] {
            listenedVoiceIds = Set(stored)
        }
        voiceDelegate.onFinish = { [weak self] in
            self?.voiceDidFinishPlaying()
        }
    }

    // MARK: - Lifecycle

    func bootstrap() async {
        lastError = nil
        currentUserId = Self.jwtUserId()
        realtime.onEvent = { [weak self] event in
            self?.handleRealtime(event)
        }
        realtime.connect()
        // Inbox load is background sync — never modal (iMessage / WhatsApp style).
        await refreshInbox(quiet: true)
        if pollTask == nil {
            startPollingFallback()
        }
    }

    func teardown() {
        pollTask?.cancel()
        pollTask = nil
        if let peer = activePeerUserId, let threadId = threadIdByPeer[peer] {
            realtime.leave(threadId: threadId)
        }
        realtime.disconnect()
        cancelRecording()
        lastError = nil
        activePeerUserId = nil
        peerTyping = false
        replyDraft = nil
        stopOutgoingTyping()
    }

    // MARK: - Inbox

    func refreshInbox(quiet: Bool = false) async {
        if Task.isCancelled { return }
        if !quiet { isLoadingInbox = true }
        defer { if !quiet { isLoadingInbox = false } }
        do {
            let threads = try await api.listThreads()
            if Task.isCancelled { return }
            for thread in threads {
                threadIdByPeer[thread.peerUserId] = thread.id
                peerByThread[thread.id] = thread.peerUserId
            }
            inbox = threads.map(HumanChatPeer.init(from:))
        } catch {
            // Sync failures stay silent — pull-to-refresh / reopen will retry.
        }
    }

    /// Roster peers (may have no messages yet) merged with server inbox.
    func displayPeers(roster: [HumanChatPeer]) -> [HumanChatPeer] {
        var byId: [String: HumanChatPeer] = [:]
        for peer in roster {
            byId[peer.id] = peer
        }
        for threadPeer in inbox {
            if var existing = byId[threadPeer.id] {
                existing.threadId = threadPeer.threadId ?? existing.threadId
                existing.lastPreview = threadPeer.lastPreview ?? existing.lastPreview
                existing.lastAt = threadPeer.lastAt ?? existing.lastAt
                existing.unreadCount = threadPeer.unreadCount
                existing.avatarUrl = threadPeer.avatarUrl ?? existing.avatarUrl
                existing.name = threadPeer.name.isEmpty ? existing.name : threadPeer.name
                byId[threadPeer.id] = existing
            } else {
                byId[threadPeer.id] = threadPeer
            }
        }
        return byId.values.sorted {
            ($0.lastAt ?? .distantPast) > ($1.lastAt ?? .distantPast)
        }
    }

    func messages(for peerUserId: String) -> [HumanChatMessage] {
        messagesByPeer[peerUserId] ?? []
    }

    func lastMessage(for peerUserId: String) -> HumanChatMessage? {
        messagesByPeer[peerUserId]?.last
    }

    func unreadCount(for peerUserId: String) -> Int {
        if let peer = inbox.first(where: { $0.id == peerUserId }) {
            return peer.unreadCount
        }
        return (messagesByPeer[peerUserId] ?? []).filter { !$0.isOutgoing && !$0.isRead }.count
    }

    /// Resolve peer user id for a backend chat thread id (after inbox bootstrap).
    func peerUserId(forThreadId threadId: String) -> String? {
        peerByThread[threadId]
    }

    // MARK: - Open thread

    func openThread(_ peer: HumanChatPeer) async {
        activePeerUserId = peer.id
        peerTyping = false
        replyDraft = nil
        stopOutgoingTyping()
        isLoadingThread = true
        defer { isLoadingThread = false }

        // Clear any stale modal from a previous cancelled bootstrap.
        lastError = nil

        // Ensure inbox maps are warm so we can reuse an existing thread id (no roster POST).
        if threadIdByPeer[peer.id] == nil, peer.threadId == nil {
            await refreshInbox(quiet: true)
        }
        if Task.isCancelled { return }

        do {
            let threadId = try await resolveThreadId(for: peer)
            if Task.isCancelled { return }
            threadIdByPeer[peer.id] = threadId
            peerByThread[threadId] = peer.id
            realtime.join(threadId: threadId)

            let page = try await api.listMessages(threadId: threadId)
            if Task.isCancelled { return }
            let uid = currentUserId ?? Self.jwtUserId() ?? ""
            let mapped = page.items
                .map { HumanChatMessage.from(api: $0, currentUserId: uid, peerUserId: peer.id) }
                .sorted { $0.sentAt < $1.sentAt }
            messagesByPeer[peer.id] = mapped
            if let cursor = page.nextCursor, !cursor.isEmpty {
                nextCursorByPeer[peer.id] = cursor
            } else {
                nextCursorByPeer.removeValue(forKey: peer.id)
            }

            if let lastIncoming = mapped.last(where: { !$0.isOutgoing }) {
                _ = try? await api.markRead(threadId: threadId, upToMessageId: lastIncoming.id)
                if let idx = inbox.firstIndex(where: { $0.id == peer.id }) {
                    inbox[idx].unreadCount = 0
                }
            }
            await refreshInbox(quiet: true)
        } catch {
            // Opening a conversation must never block with a modal (industry standard).
            // Keep cached messages if any; user can still leave / retry by re-entering.
            _ = error
        }
    }

    func closeThread() {
        if let peer = activePeerUserId, let threadId = threadIdByPeer[peer] {
            realtime.leave(threadId: threadId)
        }
        activePeerUserId = nil
        peerTyping = false
        replyDraft = nil
        stopOutgoingTyping()
    }

    func loadOlderMessages(for peerUserId: String) async {
        guard !isLoadingOlder,
              let threadId = threadIdByPeer[peerUserId],
              let cursor = nextCursorByPeer[peerUserId],
              !cursor.isEmpty else { return }
        isLoadingOlder = true
        defer { isLoadingOlder = false }
        do {
            let page = try await api.listMessages(threadId: threadId, cursor: cursor)
            let uid = currentUserId ?? Self.jwtUserId() ?? ""
            let older = page.items.map {
                HumanChatMessage.from(api: $0, currentUserId: uid, peerUserId: peerUserId)
            }
            var byId: [String: HumanChatMessage] = [:]
            for m in (messagesByPeer[peerUserId] ?? []) { byId[m.id] = m }
            for m in older { byId[m.id] = m }
            messagesByPeer[peerUserId] = byId.values.sorted { $0.sentAt < $1.sentAt }
            if let next = page.nextCursor, !next.isEmpty {
                nextCursorByPeer[peerUserId] = next
            } else {
                nextCursorByPeer.removeValue(forKey: peerUserId)
            }
        } catch {
            // Soft fail — keep existing page
        }
    }

    func setReplyDraft(to message: HumanChatMessage, peerName: String) {
        replyDraft = HumanChatReplyDraft(
            messageId: message.id,
            senderName: message.isOutgoing ? "You" : peerName,
            snippet: message.previewText
        )
        haptic()
    }

    func clearReplyDraft() {
        replyDraft = nil
    }

    func addReaction(_ emoji: String, to messageId: String, peerUserId: String) {
        guard var list = messagesByPeer[peerUserId],
              let idx = list.firstIndex(where: { $0.id == messageId }) else { return }
        if list[idx].reactions.contains(emoji) {
            list[idx].reactions.removeAll { $0 == emoji }
        } else {
            list[idx].reactions.append(emoji)
            if list[idx].reactions.count > 3 {
                list[idx].reactions = Array(list[idx].reactions.suffix(3))
            }
        }
        messagesByPeer[peerUserId] = list
        haptic()
    }

    func deleteLocalMessage(id: String, peerUserId: String) {
        messagesByPeer[peerUserId]?.removeAll { $0.id == id }
        haptic()
    }

    func retryFailed(messageId: String, peerUserId: String) {
        guard let msg = messagesByPeer[peerUserId]?.first(where: { $0.id == messageId }),
              msg.resolvedDelivery == .failed,
              let clientId = msg.clientId else { return }
        messagesByPeer[peerUserId]?
            .indices
            .filter { messagesByPeer[peerUserId]?[$0].id == messageId }
            .forEach { messagesByPeer[peerUserId]?[$0].deliveryStatus = .pending }

        switch msg.kind {
        case .text:
            Task {
                do {
                    let threadId = try await ensureThreadId(peerUserId: peerUserId)
                    let dto = try await api.sendText(threadId: threadId, text: msg.text, clientId: clientId)
                    replaceOptimistic(clientId: clientId, with: dto, peerUserId: peerUserId)
                } catch {
                    markFailed(clientId: clientId, peerUserId: peerUserId)
                }
            }
        case .voice:
            guard let path = msg.localMediaPath,
                  let url = mediaURL(relativePath: path),
                  let data = try? Data(contentsOf: url),
                  !data.isEmpty else {
                lastError = "Missing voice file for retry."
                return
            }
            Task {
                do {
                    let threadId = try await ensureThreadId(peerUserId: peerUserId)
                    let dto = try await api.sendMedia(
                        threadId: threadId,
                        fileData: data,
                        filename: "voice.m4a",
                        mimeType: "audio/m4a",
                        attachmentType: "voice",
                        caption: nil,
                        durationSeconds: msg.durationSeconds,
                        clientId: clientId
                    )
                    replaceOptimistic(clientId: clientId, with: dto, peerUserId: peerUserId)
                } catch {
                    markFailed(clientId: clientId, peerUserId: peerUserId)
                }
            }
        default:
            lastError = "Retry this attachment from the composer."
        }
    }

    /// Debounced typing_start / typing_stop over existing Socket.IO contract.
    func noteComposerTyping(peerUserId: String, draft: String) {
        guard activePeerUserId == peerUserId,
              let threadId = threadIdByPeer[peerUserId] else { return }
        let hasText = !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        typingStopTask?.cancel()
        guard hasText else {
            stopOutgoingTyping(threadId: threadId)
            return
        }
        let now = Date()
        if !outgoingTypingActive {
            // 300ms gate approximated by immediate emit on first keystroke after idle
            realtime.setTyping(threadId: threadId, isTyping: true)
            outgoingTypingActive = true
            lastTypingEmitAt = now
        } else if let last = lastTypingEmitAt, now.timeIntervalSince(last) > 3 {
            realtime.setTyping(threadId: threadId, isTyping: true)
            lastTypingEmitAt = now
        }
        typingStopTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(2500))
            guard !Task.isCancelled else { return }
            await MainActor.run { self?.stopOutgoingTyping(threadId: threadId) }
        }
    }

    private func stopOutgoingTyping(threadId: String? = nil) {
        typingStopTask?.cancel()
        typingStopTask = nil
        guard outgoingTypingActive else { return }
        outgoingTypingActive = false
        lastTypingEmitAt = nil
        let tid = threadId ?? activePeerUserId.flatMap { threadIdByPeer[$0] }
        if let tid {
            realtime.setTyping(threadId: tid, isTyping: false)
        }
    }

    // MARK: - Send

    func sendText(to peerUserId: String, text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let reply = replyDraft
        replyDraft = nil
        stopOutgoingTyping()
        let clientId = UUID().uuidString
        let optimistic = HumanChatMessage(
            id: "local-\(clientId)",
            peerId: peerUserId,
            isOutgoing: true,
            kind: .text,
            text: trimmed,
            sentAt: .now,
            isRead: false,
            clientId: clientId,
            threadId: threadIdByPeer[peerUserId],
            deliveryStatus: .pending,
            replyToId: reply?.messageId,
            replyToText: reply?.snippet,
            replyToName: reply?.senderName
        )
        appendLocal(optimistic, peerUserId: peerUserId)
        drafts[peerUserId] = ""
        haptic()

        Task {
            do {
                let threadId = try await ensureThreadId(peerUserId: peerUserId)
                let dto = try await api.sendText(threadId: threadId, text: trimmed, clientId: clientId)
                replaceOptimistic(clientId: clientId, with: dto, peerUserId: peerUserId)
                lastError = nil
            } catch {
                markFailed(clientId: clientId, peerUserId: peerUserId)
            }
        }
    }

    func sendImage(to peerUserId: String, image: UIImage, caption: String?) {
        guard let jpeg = CoachImageEncoder.jpegData(from: image) else {
            lastError = "Couldn’t encode photo."
            return
        }
        let clientId = UUID().uuidString
        let path = storeMedia(data: jpeg, peerId: peerUserId, ext: "jpg")
        let trimmed = caption?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let optimistic = HumanChatMessage(
            id: "local-\(clientId)",
            peerId: peerUserId,
            isOutgoing: true,
            kind: .image,
            text: trimmed,
            sentAt: .now,
            isRead: false,
            localMediaPath: path,
            attachmentKind: .image,
            clientId: clientId,
            threadId: threadIdByPeer[peerUserId],
            deliveryStatus: .pending
        )
        appendLocal(optimistic, peerUserId: peerUserId)
        drafts[peerUserId] = ""
        haptic()

        Task {
            do {
                let threadId = try await ensureThreadId(peerUserId: peerUserId)
                let dto = try await api.sendMedia(
                    threadId: threadId,
                    fileData: jpeg,
                    filename: "chat.jpg",
                    mimeType: "image/jpeg",
                    attachmentType: "image",
                    caption: trimmed.nilIfEmpty,
                    durationSeconds: nil,
                    clientId: clientId
                )
                replaceOptimistic(clientId: clientId, with: dto, peerUserId: peerUserId)
                lastError = nil
            } catch {
                markFailed(clientId: clientId, peerUserId: peerUserId)
            }
        }
    }

    func sendVideo(to peerUserId: String, fileURL: URL, caption: String?) {
        guard let data = try? Data(contentsOf: fileURL), !data.isEmpty else {
            lastError = "Couldn’t read video."
            return
        }
        let ext = fileURL.pathExtension.isEmpty ? "mp4" : fileURL.pathExtension
        let path = storeMedia(data: data, peerId: peerUserId, ext: ext)
        let trimmed = caption?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let clientId = UUID().uuidString
        let resolved = mediaURL(relativePath: path) ?? fileURL

        Task { @MainActor in
            let duration = await Self.videoDuration(url: resolved)
            let optimistic = HumanChatMessage(
                id: "local-\(clientId)",
                peerId: peerUserId,
                isOutgoing: true,
                kind: .video,
                text: trimmed,
                sentAt: .now,
                isRead: false,
                localMediaPath: path,
                attachmentKind: .video,
                durationSeconds: duration,
                clientId: clientId,
                threadId: threadIdByPeer[peerUserId],
                deliveryStatus: .pending
            )
            self.appendLocal(optimistic, peerUserId: peerUserId)
            self.drafts[peerUserId] = ""
            self.haptic()

            do {
                let threadId = try await self.ensureThreadId(peerUserId: peerUserId)
                let mime = ext.lowercased() == "mov" ? "video/quicktime" : "video/mp4"
                let dto = try await self.api.sendMedia(
                    threadId: threadId,
                    fileData: data,
                    filename: "chat.\(ext)",
                    mimeType: mime,
                    attachmentType: "video",
                    caption: trimmed.nilIfEmpty,
                    durationSeconds: duration,
                    clientId: clientId
                )
                self.replaceOptimistic(clientId: clientId, with: dto, peerUserId: peerUserId)
                self.lastError = nil
            } catch {
                self.markFailed(clientId: clientId, peerUserId: peerUserId)
            }
        }
    }

    func sendVoiceNote(to peerUserId: String, data: Data, duration: TimeInterval) {
        let clientId = UUID().uuidString
        let path = storeMedia(data: data, peerId: peerUserId, ext: "m4a")
        let optimistic = HumanChatMessage(
            id: "local-\(clientId)",
            peerId: peerUserId,
            isOutgoing: true,
            kind: .voice,
            text: "",
            sentAt: .now,
            isRead: false,
            localMediaPath: path,
            attachmentKind: .voice,
            durationSeconds: duration,
            clientId: clientId,
            threadId: threadIdByPeer[peerUserId],
            deliveryStatus: .pending
        )
        appendLocal(optimistic, peerUserId: peerUserId)
        haptic()

        Task {
            do {
                let threadId = try await ensureThreadId(peerUserId: peerUserId)
                let dto = try await api.sendMedia(
                    threadId: threadId,
                    fileData: data,
                    filename: "voice.m4a",
                    mimeType: "audio/m4a",
                    attachmentType: "voice",
                    caption: nil,
                    durationSeconds: duration,
                    clientId: clientId
                )
                replaceOptimistic(clientId: clientId, with: dto, peerUserId: peerUserId)
                lastError = nil
            } catch {
                markFailed(clientId: clientId, peerUserId: peerUserId)
            }
        }
    }

    func recordCallEvent(peerId: String, outcome: String) {
        let clientId = UUID().uuidString
        let optimistic = HumanChatMessage(
            id: "local-\(clientId)",
            peerId: peerId,
            isOutgoing: true,
            kind: .callEvent,
            text: "",
            sentAt: .now,
            isRead: false,
            callOutcome: outcome,
            clientId: clientId,
            threadId: threadIdByPeer[peerId],
            deliveryStatus: .pending
        )
        appendLocal(optimistic, peerUserId: peerId)
        Task {
            do {
                let threadId = try await ensureThreadId(peerUserId: peerId)
                let dto = try await api.sendCallEvent(threadId: threadId, outcome: outcome, clientId: clientId)
                replaceOptimistic(clientId: clientId, with: dto, peerUserId: peerId)
            } catch {
                markFailed(clientId: clientId, peerUserId: peerId)
            }
        }
    }

    func startRecording() async {
        guard !isRecording else { return }
        stopVoicePlayback()
        do {
            let permission = AVAudioApplication.shared.recordPermission
            if permission == .denied {
                lastError = "Microphone permission is required for voice notes."
                return
            }
            if permission == .undetermined {
                let allowed = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
                    AVAudioApplication.requestRecordPermission { cont.resume(returning: $0) }
                }
                guard allowed else {
                    lastError = "Microphone permission is required for voice notes."
                    return
                }
            }
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothHFP])
            try session.setActive(true)
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("human-voice-\(UUID().uuidString).m4a")
            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 44_100,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
            ]
            let recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder.isMeteringEnabled = true
            recorder.record()
            audioRecorder = recorder
            recordingURL = url
            isRecording = true
            isRecordingPaused = false
            recordingElapsed = 0
            haptic()
            startRecordingCapTimer()
        } catch {
            lastError = "Couldn’t start voice recording."
        }
    }

    func cancelRecording() {
        recordLimitTask?.cancel()
        recordLimitTask = nil
        audioRecorder?.stop()
        audioRecorder = nil
        if let url = recordingURL {
            try? FileManager.default.removeItem(at: url)
        }
        recordingURL = nil
        activeRecordingPeerId = nil
        isRecording = false
        isRecordingPaused = false
        recordingElapsed = 0
    }

    func pauseRecording() {
        guard isRecording, !isRecordingPaused else { return }
        audioRecorder?.pause()
        isRecordingPaused = true
        haptic()
    }

    func resumeRecording() {
        guard isRecording, isRecordingPaused else { return }
        audioRecorder?.record()
        isRecordingPaused = false
        haptic()
    }

    func armAutoSend(peerId: String) {
        activeRecordingPeerId = peerId
    }

    func stopAndSendVoice(to peerId: String) {
        guard isRecording else { return }
        let duration = audioRecorder?.currentTime ?? recordingElapsed
        recordLimitTask?.cancel()
        recordLimitTask = nil
        audioRecorder?.stop()
        audioRecorder = nil
        isRecording = false
        isRecordingPaused = false
        recordingElapsed = 0
        activeRecordingPeerId = nil
        defer { recordingURL = nil }
        guard let url = recordingURL,
              let data = try? Data(contentsOf: url),
              !data.isEmpty else {
            lastError = "No audio captured."
            return
        }
        sendVoiceNote(to: peerId, data: data, duration: max(duration, 0.4))
        try? FileManager.default.removeItem(at: url)
    }

    func playVoice(_ message: HumanChatMessage) {
        toggleVoice(message)
    }

    func hasListened(to id: String) -> Bool {
        listenedVoiceIds.contains(id)
    }

    func toggleVoice(_ message: HumanChatMessage) {
        if playingVoiceId == message.id {
            if voiceIsPlaying {
                audioPlayer?.pause()
                voiceIsPlaying = false
                voiceProgressTask?.cancel()
            } else {
                audioPlayer?.play()
                voiceIsPlaying = true
                startVoiceProgressLoop()
            }
            return
        }
        Task { await startVoice(message) }
    }

    func seekVoice(_ message: HumanChatMessage, progress: Double) {
        let clamped = max(0, min(1, progress))
        if playingVoiceId != message.id {
            Task {
                await startVoice(message, autoplay: false)
                applySeek(clamped)
            }
            return
        }
        applySeek(clamped)
    }

    func cycleVoiceRate() {
        if voiceRate < 1.25 {
            voiceRate = 1.5
        } else if voiceRate < 1.75 {
            voiceRate = 2.0
        } else {
            voiceRate = 1.0
        }
        audioPlayer?.enableRate = true
        audioPlayer?.rate = voiceRate
    }

    func stopVoicePlayback() {
        voiceProgressTask?.cancel()
        voiceProgressTask = nil
        audioPlayer?.stop()
        audioPlayer = nil
        playingVoiceId = nil
        voiceIsPlaying = false
        voiceProgress = 0
        voiceElapsed = 0
        voiceDuration = 0
    }

    private func startVoice(_ message: HumanChatMessage, autoplay: Bool = true) async {
        guard let url = resolveMediaURL(message) else {
            lastError = "Voice note isn’t available yet."
            return
        }
        stopVoicePlayback()
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.duckOthers])
            try session.setActive(true)
            let fileURL = try await localVoiceURL(from: url)
            let player = try AVAudioPlayer(contentsOf: fileURL)
            player.enableRate = true
            player.rate = voiceRate
            player.delegate = voiceDelegate
            audioPlayer = player
            playingVoiceId = message.id
            voiceDuration = player.duration > 0 ? player.duration : (message.durationSeconds ?? 0)
            voiceElapsed = 0
            voiceProgress = 0
            markListened(message.id)
            if autoplay {
                player.play()
                voiceIsPlaying = true
                startVoiceProgressLoop()
            } else {
                voiceIsPlaying = false
            }
            haptic()
        } catch {
            lastError = "Couldn’t play voice note."
            stopVoicePlayback()
        }
    }

    private func applySeek(_ progress: Double) {
        guard let player = audioPlayer else { return }
        let duration = max(player.duration, 0.01)
        player.currentTime = duration * progress
        voiceElapsed = player.currentTime
        voiceProgress = progress
        voiceDuration = duration
    }

    private func startVoiceProgressLoop() {
        voiceProgressTask?.cancel()
        voiceProgressTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 50_000_000)
                guard let self, self.voiceIsPlaying, let player = self.audioPlayer else { return }
                let duration = max(player.duration, 0.01)
                self.voiceElapsed = player.currentTime
                self.voiceDuration = duration
                self.voiceProgress = min(1, player.currentTime / duration)
            }
        }
    }

    private func voiceDidFinishPlaying() {
        let finishedId = playingVoiceId
        let peerId = messagesByPeer.first { _, list in
            list.contains(where: { $0.id == finishedId })
        }?.key
        stopVoicePlayback()
        guard let finishedId, let peerId,
              let next = nextConsecutiveVoice(after: finishedId, peerId: peerId) else { return }
        Task { await startVoice(next) }
    }

    private func nextConsecutiveVoice(after id: String, peerId: String) -> HumanChatMessage? {
        guard let list = messagesByPeer[peerId],
              let idx = list.firstIndex(where: { $0.id == id }),
              idx + 1 < list.count else { return nil }
        let next = list[idx + 1]
        return next.kind == .voice ? next : nil
    }

    private func markListened(_ id: String) {
        listenedVoiceIds.insert(id)
        UserDefaults.standard.set(Array(listenedVoiceIds), forKey: listenedKey)
    }

    private func localVoiceURL(from url: URL) async throws -> URL {
        if url.isFileURL { return url }
        let (data, _) = try await URLSession.shared.data(from: url)
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("voice-play-\(UUID().uuidString).m4a")
        try data.write(to: temp, options: .atomic)
        return temp
    }

    func resolveMediaURL(_ message: HumanChatMessage) -> URL? {
        if let remote = message.remoteMediaUrl?.trimmingCharacters(in: .whitespacesAndNewlines),
           !remote.isEmpty {
            if let absolute = URL(string: remote), absolute.scheme != nil {
                return absolute
            }
            if let relative = URL(string: remote, relativeTo: APIConfig.baseURL)?.absoluteURL {
                return relative
            }
        }
        if let path = message.localMediaPath {
            if path.hasPrefix("/") { return URL(fileURLWithPath: path) }
            return mediaURL(relativePath: path)
        }
        return nil
    }

    func loadImage(_ message: HumanChatMessage) -> UIImage? {
        guard let url = resolveMediaURL(message), url.isFileURL,
              let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    /// Loads local or remote chat image (Bearer + ngrok headers when needed).
    func fetchImage(_ message: HumanChatMessage) async -> UIImage? {
        if let local = loadImage(message) { return local }
        guard let url = resolveMediaURL(message) else { return nil }
        if url.isFileURL {
            guard let data = try? Data(contentsOf: url) else { return nil }
            return UIImage(data: data)
        }
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(APIConfig.skipBrowserWarningValue, forHTTPHeaderField: APIConfig.skipBrowserWarningHeader)
        if let token = TokenStore.accessToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                return nil
            }
            return UIImage(data: data)
        } catch {
            return nil
        }
    }

    // MARK: - Realtime + poll

    private func handleRealtime(_ event: ChatRealtimeClient.Event) {
        let uid = currentUserId ?? Self.jwtUserId() ?? ""
        switch event {
        case .message(let dto):
            let peerId = peerByThread[dto.threadId]
                ?? (dto.senderUserId == uid ? activePeerUserId : dto.senderUserId)
                ?? dto.senderUserId
            peerByThread[dto.threadId] = peerId
            threadIdByPeer[peerId] = dto.threadId
            upsertMessage(HumanChatMessage.from(api: dto, currentUserId: uid, peerUserId: peerId), peerUserId: peerId)
            Task { await refreshInbox(quiet: true) }
        case .threadUpdated(let thread):
            threadIdByPeer[thread.peerUserId] = thread.id
            peerByThread[thread.id] = thread.peerUserId
            if let idx = inbox.firstIndex(where: { $0.id == thread.peerUserId }) {
                inbox[idx] = HumanChatPeer(from: thread)
            } else {
                inbox.insert(HumanChatPeer(from: thread), at: 0)
            }
        case .read(let threadId, _, _):
            if let peerId = peerByThread[threadId],
               var list = messagesByPeer[peerId] {
                for i in list.indices where list[i].isOutgoing {
                    list[i].isRead = true
                    list[i].deliveryStatus = .read
                }
                messagesByPeer[peerId] = list
            }
        case .typing(let threadId, let userId, let isTyping):
            if let peerId = peerByThread[threadId], peerId == activePeerUserId, userId != uid {
                peerTyping = isTyping
                typingClearTask?.cancel()
                if isTyping {
                    typingClearTask = Task { [weak self] in
                        try? await Task.sleep(for: .seconds(25))
                        guard !Task.isCancelled else { return }
                        await MainActor.run { self?.peerTyping = false }
                    }
                }
            }
        case .callIncoming, .callEnded:
            break
        case .notificationCreated(let note):
            NotificationStore.shared.handleCreated(note)
        }
    }

    private func startPollingFallback() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(8))
                guard let self else { return }
                if self.activePeerUserId != nil {
                    await self.refreshActiveThreadQuietly()
                } else {
                    await self.refreshInbox(quiet: true)
                }
            }
        }
    }

    private func refreshActiveThreadQuietly() async {
        guard let peerId = activePeerUserId,
              let threadId = threadIdByPeer[peerId] else { return }
        do {
            let page = try await api.listMessages(threadId: threadId)
            let uid = currentUserId ?? Self.jwtUserId() ?? ""
            let mapped = page.items
                .map { HumanChatMessage.from(api: $0, currentUserId: uid, peerUserId: peerId) }
                .sorted { $0.sentAt < $1.sentAt }
            // Merge preserving optimistic locals not yet acked
            let locals = (messagesByPeer[peerId] ?? []).filter { $0.id.hasPrefix("local-") }
            var byId: [String: HumanChatMessage] = [:]
            for m in mapped { byId[m.id] = m }
            for local in locals {
                if let cid = local.clientId, mapped.contains(where: { $0.clientId == cid }) { continue }
                byId[local.id] = local
            }
            messagesByPeer[peerId] = byId.values.sorted { $0.sentAt < $1.sentAt }
        } catch {
            // Soft fail — keep UI
        }
    }

    // MARK: - Helpers

    func ensureThreadId(peerUserId: String) async throws -> String {
        try await resolveThreadId(for: HumanChatPeer(
            id: peerUserId,
            name: inbox.first(where: { $0.id == peerUserId })?.name ?? "Chat",
            role: inbox.first(where: { $0.id == peerUserId })?.role ?? .trainee,
            profileId: inbox.first(where: { $0.id == peerUserId })?.profileId,
            threadId: inbox.first(where: { $0.id == peerUserId })?.threadId
        ))
    }

    /// Prefer an existing inbox thread. Create only when needed, with roster-safe fallbacks.
    private func resolveThreadId(for peer: HumanChatPeer) async throws -> String {
        let peerId = peer.id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !peerId.isEmpty else {
            throw AppError.api("Missing chat peer.")
        }
        if let id = threadIdByPeer[peerId], !id.isEmpty { return id }
        if let id = peer.threadId, !id.isEmpty {
            threadIdByPeer[peerId] = id
            peerByThread[id] = peerId
            return id
        }
        if let id = inbox.first(where: { $0.id == peerId })?.threadId, !id.isEmpty {
            threadIdByPeer[peerId] = id
            peerByThread[id] = peerId
            return id
        }

        // 1) Canonical: User.id
        do {
            let thread = try await api.createOrGetThread(peerUserId: peerId)
            return cacheThread(thread, peerUserId: peerId)
        } catch {
            if Self.isIgnorable(error) { throw error }
            // 2) Fallback: profile id (backend accepts either per chat contract)
            if let profileId = peer.profileId?.nilIfEmpty {
                do {
                    let thread = try await api.createOrGetThread(
                        peerUserId: nil,
                        peerTraineeProfileId: peer.role == .trainee ? profileId : nil,
                        peerTrainerProfileId: peer.role == .trainer ? profileId : nil
                    )
                    let canonicalPeer = thread.peerUserId.nilIfEmpty ?? peerId
                    let id = cacheThread(thread, peerUserId: canonicalPeer)
                    if canonicalPeer != peerId {
                        threadIdByPeer[peerId] = id
                    }
                    return id
                } catch {
                    if Self.isIgnorable(error) { throw error }
                }
            }
            // 3) Last chance: refresh inbox — thread may already exist under another code path
            await refreshInbox(quiet: true)
            if let id = threadIdByPeer[peerId] ?? inbox.first(where: { $0.id == peerId })?.threadId,
               !id.isEmpty {
                return id
            }
            throw error
        }
    }

    private func cacheThread(_ thread: ChatThreadDTO, peerUserId: String) -> String {
        threadIdByPeer[peerUserId] = thread.id
        peerByThread[thread.id] = peerUserId
        realtime.join(threadId: thread.id)
        return thread.id
    }

    // MARK: - Helpers (private continue below)

    private func appendLocal(_ message: HumanChatMessage, peerUserId: String) {
        var list = messagesByPeer[peerUserId] ?? []
        list.append(message)
        messagesByPeer[peerUserId] = list
    }

    private func upsertMessage(_ message: HumanChatMessage, peerUserId: String) {
        var list = messagesByPeer[peerUserId] ?? []
        if let cid = message.clientId,
           let idx = list.firstIndex(where: { $0.clientId == cid || $0.id == message.id }) {
            var merged = message
            if merged.localMediaPath == nil {
                merged.localMediaPath = list[idx].localMediaPath
            }
            if merged.replyToId == nil {
                merged.replyToId = list[idx].replyToId
                merged.replyToText = list[idx].replyToText
                merged.replyToName = list[idx].replyToName
            }
            if merged.reactions.isEmpty {
                merged.reactions = list[idx].reactions
            }
            list[idx] = merged
        } else if let idx = list.firstIndex(where: { $0.id == message.id }) {
            var merged = message
            if merged.reactions.isEmpty { merged.reactions = list[idx].reactions }
            if merged.replyToId == nil {
                merged.replyToId = list[idx].replyToId
                merged.replyToText = list[idx].replyToText
                merged.replyToName = list[idx].replyToName
            }
            list[idx] = merged
        } else {
            list.append(message)
        }
        messagesByPeer[peerUserId] = list.sorted { $0.sentAt < $1.sentAt }
    }

    private func replaceOptimistic(clientId: String, with dto: ChatMessageDTO, peerUserId: String) {
        let uid = currentUserId ?? Self.jwtUserId() ?? ""
        var mapped = HumanChatMessage.from(api: dto, currentUserId: uid, peerUserId: peerUserId)
        mapped.deliveryStatus = mapped.isRead ? .read : .sent
        if let idx = messagesByPeer[peerUserId]?.firstIndex(where: { $0.clientId == clientId }) {
            let prior = messagesByPeer[peerUserId]?[idx]
            mapped.localMediaPath = prior?.localMediaPath ?? mapped.localMediaPath
            mapped.replyToId = prior?.replyToId ?? mapped.replyToId
            mapped.replyToText = prior?.replyToText ?? mapped.replyToText
            mapped.replyToName = prior?.replyToName ?? mapped.replyToName
            mapped.reactions = prior?.reactions ?? mapped.reactions
        }
        upsertMessage(mapped, peerUserId: peerUserId)
        threadIdByPeer[peerUserId] = dto.threadId
        peerByThread[dto.threadId] = peerUserId
        Task { await refreshInbox(quiet: true) }
    }

    private func markFailed(clientId: String, peerUserId: String) {
        guard var list = messagesByPeer[peerUserId],
              let idx = list.firstIndex(where: { $0.clientId == clientId }) else { return }
        list[idx].deliveryStatus = .failed
        messagesByPeer[peerUserId] = list
    }

    private func startRecordingCapTimer() {
        recordLimitTask?.cancel()
        recordLimitTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 250_000_000)
                guard self.isRecording, let recorder = self.audioRecorder else { return }
                if self.isRecordingPaused { continue }
                recorder.updateMeters()
                self.recordingElapsed = min(recorder.currentTime, Self.maxRecordingSeconds)
                if self.recordingElapsed >= Self.maxRecordingSeconds - 0.05,
                   let peerId = self.activeRecordingPeerId {
                    self.stopAndSendVoice(to: peerId)
                    return
                }
            }
        }
    }

    private func haptic() { hapticTick &+= 1 }

    private func mediaRoot() -> URL {
        let root = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("HumanChatMedia", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func storeMedia(data: Data, peerId: String, ext: String) -> String {
        let name = "\(peerId)-\(UUID().uuidString).\(ext)"
        let url = mediaRoot().appendingPathComponent(name)
        try? data.write(to: url, options: .atomic)
        return name
    }

    private func mediaURL(relativePath: String) -> URL? {
        mediaRoot().appendingPathComponent(relativePath)
    }

    private static func videoDuration(url: URL) async -> Double? {
        let asset = AVURLAsset(url: url)
        do {
            let duration = try await asset.load(.duration)
            let seconds = CMTimeGetSeconds(duration)
            return seconds.isFinite ? seconds : nil
        } catch {
            return nil
        }
    }

    private static func jwtUserId() -> String? {
        guard let token = TokenStore.accessToken() else { return nil }
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var payload = String(parts[1])
        let pad = 4 - payload.count % 4
        if pad < 4 { payload += String(repeating: "=", count: pad) }
        guard let data = Data(base64Encoded: payload.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        if let id = obj["userId"] as? String { return id }
        if let id = obj["sub"] as? String { return id }
        if let id = obj["id"] as? String { return id }
        return nil
    }

    /// Soft toast only for local capability issues. Never cancel / roster / sync / open failures.
    func presentError(_ error: Error) {
        presentActionError(error)
    }

    func presentActionError(_ error: Error) {
        guard let message = Self.userFacing(error) else { return }
        lastError = message
    }

    private static func isIgnorable(_ error: Error) -> Bool {
        if Task.isCancelled { return true }
        if error is CancellationError { return true }
        if let url = error as? URLError, url.code == .cancelled { return true }
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain && ns.code == NSURLErrorCancelled { return true }
        let text = ((error as? AppError)?.errorDescription ?? error.localizedDescription)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if text.isEmpty { return true }
        if text.contains("cancel") { return true }
        if text.contains("roster") { return true }
        if text.contains("forbidden") { return true }
        return false
    }

    private static func userFacing(_ error: Error) -> String? {
        if isIgnorable(error) { return nil }
        if let app = error as? AppError {
            let text = (app.errorDescription ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if text.isEmpty { return nil }
            let lower = text.lowercased()
            if lower.contains("cancel") || lower.contains("roster") || lower.contains("forbidden") {
                return nil
            }
            // Only local/capability style messages — never raw API sync noise.
            if lower.contains("microphone")
                || lower.contains("permission")
                || lower.contains("encode")
                || lower.contains("audio") {
                return text
            }
            return nil
        }
        let text = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return nil }
        if text.lowercased().contains("cancel") { return nil }
        return nil
    }
}

final class HumanChatVoicePlayerDelegate: NSObject, AVAudioPlayerDelegate {
    var onFinish: (@MainActor () -> Void)?

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            onFinish?()
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
