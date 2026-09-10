import AVFoundation
import Foundation
import Observation
import UIKit

private enum CoachPendingRetry: Equatable {
    case text(String)
    case image(jpeg: Data, caption: String?, preview: Data?)
    case voice(Data)
}

@MainActor
@Observable
final class CoachStore {
    static let maxRecordingSeconds: TimeInterval = 30

    private let api = CoachAPI()

    var conversations: [CoachConversation] = []
    var activeConversationId: String?
    var messages: [CoachDisplayMessage] = []
    var status: CoachProviderStatus?

    var isBootstrapping = false
    var isSending = false
    var isStreaming = false
    var isAnalyzingImage = false
    var isRecording = false
    var isPlaying = false
    var recordingElapsed: TimeInterval = 0
    var partialAssistantText = ""
    var lastError: String?
    var rateLimitSecondsRemaining: Int = 0
    var hapticTick = 0

    private var sendTask: Task<Void, Never>?
    private var recordLimitTask: Task<Void, Never>?
    private var rateLimitTask: Task<Void, Never>?
    private var streamAssistantId: String?
    private var audioRecorder: AVAudioRecorder?
    private var audioPlayer: AVPlayer?
    private var recordingURL: URL?
    private var playerObserver: NSObjectProtocol?
    private var pendingRetry: CoachPendingRetry?
    private let speechSynthesizer = AVSpeechSynthesizer()
    private let speechDelegate = CoachSpeechDelegate()

    var canSend: Bool { !isSending && !isStreaming && !isAnalyzingImage && rateLimitSecondsRemaining == 0 }
    var isBusy: Bool { isSending || isStreaming || isAnalyzingImage }
    var recordingSecondsLeft: Int {
        max(0, Int((Self.maxRecordingSeconds - recordingElapsed).rounded(.down)))
    }

    init() {
        speechDelegate.onFinish = { [weak self] in
            Task { @MainActor in
                self?.isPlaying = false
            }
        }
        speechSynthesizer.delegate = speechDelegate
    }

    // MARK: Bootstrap

    func bootstrap(forceReload: Bool = false) async {
        if isBootstrapping { return }
        isBootstrapping = true
        defer { isBootstrapping = false }

        // Soft-load provider status — never block the empty chat chrome.
        if let provider = try? await api.status() {
            status = provider
        }

        // Prefer disk cache instantly so previous chats appear before network returns.
        let cachedList = CoachChatDiskCache.loadConversations()
        if conversations.isEmpty, !cachedList.isEmpty {
            conversations = cachedList
        }
        if activeConversationId == nil {
            activeConversationId = CoachChatDiskCache.loadActiveId() ?? cachedList.first?.id
        }

        do {
            let list = try await api.listConversations()
            conversations = CoachChatDiskCache.merge(server: list, cached: CoachChatDiskCache.loadConversations())
            CoachChatDiskCache.saveConversations(conversations)

            let active = activeConversationId
                ?? CoachChatDiskCache.loadActiveId()
                ?? conversations.first?.id
            if let active {
                activeConversationId = active
                CoachChatDiskCache.saveActiveId(active)
                if forceReload || messages.isEmpty {
                    if let cached = CoachChatDiskCache.loadMessages(conversationId: active), messages.isEmpty {
                        messages = cached.map(CoachDisplayMessage.fromServer)
                    }
                    let server = try await api.listMessages(conversationId: active)
                    messages = server.map(CoachDisplayMessage.fromServer)
                    CoachChatDiskCache.saveMessages(server, conversationId: active)
                }
            }
            lastError = nil
        } catch {
            // Fall back to disk — terminate/relaunch still shows previous chats.
            if conversations.isEmpty {
                conversations = cachedList
            }
            if let active = activeConversationId ?? conversations.first?.id {
                activeConversationId = active
                if messages.isEmpty,
                   let cached = CoachChatDiskCache.loadMessages(conversationId: active) {
                    messages = cached.map(CoachDisplayMessage.fromServer)
                }
            } else if messages.isEmpty {
                lastError = Self.userFacingError(error)
            }
        }

        // Memory sync off the critical path.
        Task { await syncMemoryDebounced() }
    }

    func refreshMessages() async {
        guard let id = activeConversationId else { return }
        do {
            let server = try await api.listMessages(conversationId: id)
            // Preserve optimistic failures / analyzing if still in-flight
            if !isBusy {
                messages = server.map(CoachDisplayMessage.fromServer)
                CoachChatDiskCache.saveMessages(server, conversationId: id)
            }
            lastError = nil
        } catch {
            if messages.isEmpty,
               let cached = CoachChatDiskCache.loadMessages(conversationId: id) {
                messages = cached.map(CoachDisplayMessage.fromServer)
            }
            lastError = Self.userFacingError(error)
        }
    }

    /// Reload conversation list from server (and merge disk cache so kill/relaunch keeps history).
    func refreshConversations() async {
        do {
            let list = try await api.listConversations()
            conversations = CoachChatDiskCache.merge(server: list, cached: CoachChatDiskCache.loadConversations())
            CoachChatDiskCache.saveConversations(conversations)
            lastError = nil
        } catch {
            if conversations.isEmpty {
                conversations = CoachChatDiskCache.loadConversations()
            }
            if conversations.isEmpty {
                lastError = Self.userFacingError(error)
            }
        }
    }

    func selectConversation(_ id: String) async {
        guard id != activeConversationId || messages.isEmpty else { return }
        cancelInFlight()
        partialAssistantText = ""
        pendingRetry = nil
        activeConversationId = id
        CoachChatDiskCache.saveActiveId(id)

        if let cached = CoachChatDiskCache.loadMessages(conversationId: id) {
            messages = cached.map(CoachDisplayMessage.fromServer)
        } else {
            messages = []
        }
        await refreshMessages()
    }

    func startNewConversation() async {
        cancelInFlight()
        do {
            let created = try await api.createConversation()
            conversations.insert(created, at: 0)
            activeConversationId = created.id
            messages = []
            partialAssistantText = ""
            lastError = nil
            pendingRetry = nil
            CoachChatDiskCache.saveActiveId(created.id)
            CoachChatDiskCache.saveConversations(conversations)
            CoachChatDiskCache.saveMessages([], conversationId: created.id)
        } catch {
            // Offline / API down — still allow a fresh local thread; first send creates server-side.
            beginLocalNewChat()
            lastError = Self.userFacingError(error)
        }
    }

    /// Removes a thread locally + on server. If it was active, selects the next chat or clears.
    func deleteConversation(_ id: String) async {
        let wasActive = activeConversationId == id
        let snapshot = conversations
        conversations.removeAll { $0.id == id }
        CoachChatDiskCache.removeConversation(id: id)
        CoachChatDiskCache.saveConversations(conversations)

        if wasActive {
            cancelInFlight()
            partialAssistantText = ""
            pendingRetry = nil
            if let next = conversations.first {
                activeConversationId = next.id
                CoachChatDiskCache.saveActiveId(next.id)
                if let cached = CoachChatDiskCache.loadMessages(conversationId: next.id) {
                    messages = cached.map(CoachDisplayMessage.fromServer)
                } else {
                    messages = []
                }
                await refreshMessages()
            } else {
                activeConversationId = nil
                messages = []
                UserDefaults.standard.removeObject(forKey: "tactech.coach.activeConversationId.v1")
            }
        }

        do {
            try await api.deleteConversation(id: id)
            lastError = nil
        } catch {
            // Soft restore if server rejects (404 still OK — already gone).
            if let appError = error as? AppError, case .notFound = appError {
                lastError = nil
                return
            }
            conversations = snapshot
            CoachChatDiskCache.saveConversations(snapshot)
            lastError = Self.userFacingError(error)
        }
    }

    /// Local multi-chat (no backend) — clears the active thread for a fresh UI session.
    func beginLocalNewChat() {
        cancelInFlight()
        activeConversationId = nil
        messages = []
        partialAssistantText = ""
        lastError = nil
        pendingRetry = nil
    }

    /// Restore a locally cached thread without hitting the network.
    func replaceMessagesLocally(_ msgs: [CoachDisplayMessage]) {
        cancelInFlight()
        activeConversationId = nil
        messages = msgs
        partialAssistantText = ""
        lastError = nil
        pendingRetry = nil
    }

    // MARK: Memory

    private static var lastMemorySync: Date?
    private static let memoryDebounce: TimeInterval = 45

    func syncMemoryDebounced(force: Bool = false) async {
        if !force, let last = Self.lastMemorySync, Date().timeIntervalSince(last) < Self.memoryDebounce {
            return
        }
        do {
            _ = try await api.syncMemory()
            Self.lastMemorySync = Date()
        } catch {
            // Soft-fail — coach still works without fresh memory
        }
    }

    // MARK: Text

    func sendText(_ raw: String) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, canSend else { return }
        cancelInFlight()
        haptic()
        isSending = true
        isStreaming = true
        lastError = nil

        let localUserId = "local-user-\(UUID().uuidString)"
        let localAssistantId = "local-assistant-\(UUID().uuidString)"
        streamAssistantId = localAssistantId

        let userMsg = CoachDisplayMessage(
            id: localUserId,
            serverId: nil,
            role: .user,
            content: text,
            modality: .text,
            audioUrl: nil,
            imageUrl: nil,
            localImageData: nil,
            citations: nil,
            createdAt: Date(),
            status: .sending,
            retryJPEG: nil,
            retryCaption: nil
        )
        let assistantMsg = CoachDisplayMessage(
            id: localAssistantId,
            serverId: nil,
            role: .assistant,
            content: "",
            modality: .text,
            audioUrl: nil,
            imageUrl: nil,
            localImageData: nil,
            citations: nil,
            createdAt: Date(),
            status: .streaming,
            retryJPEG: nil,
            retryCaption: nil
        )
        messages.append(userMsg)
        messages.append(assistantMsg)
        partialAssistantText = ""

        sendTask = Task { [weak self] in
            guard let self else { return }
            defer {
                self.isSending = false
                self.isStreaming = false
                self.streamAssistantId = nil
            }
            do {
                let stream = await self.api.chatStream(message: text, conversationId: self.activeConversationId)
                for try await event in stream {
                    if Task.isCancelled { break }
                    self.applyStreamEvent(event, localUserId: localUserId, localAssistantId: localAssistantId)
                }
                if let idx = self.messages.firstIndex(where: { $0.id == localAssistantId }),
                   self.messages[idx].status == .streaming {
                    self.messages[idx].status = .sent
                    if self.messages[idx].content.isEmpty {
                        self.messages[idx].content = self.partialAssistantText
                    }
                }
                if let idx = self.messages.firstIndex(where: { $0.id == localUserId }) {
                    self.messages[idx].status = .sent
                }
                self.haptic()
            } catch is CancellationError {
                // superseded
            } catch {
                self.failAssistant(localAssistantId, error: error)
                let detail = Self.userFacingError(error)
                if let idx = self.messages.firstIndex(where: { $0.id == localUserId }) {
                    self.messages[idx].status = .failed(detail)
                }
                self.handleFailure(error, pending: .text(text))
            }
        }
    }

    private func applyStreamEvent(_ event: CoachStreamEvent, localUserId: String, localAssistantId: String) {
        switch event {
        case let .user(conversationId, message):
            activeConversationId = conversationId
            if let idx = messages.firstIndex(where: { $0.id == localUserId }) {
                messages[idx].serverId = message.id
                messages[idx].content = message.content
                messages[idx].status = .sent
                messages[idx].createdAt = message.createdAt
            }
            upsertConversationId(conversationId)
        case let .delta(text):
            partialAssistantText += text
            if let idx = messages.firstIndex(where: { $0.id == localAssistantId }) {
                messages[idx].content = partialAssistantText
                messages[idx].status = .streaming
            }
        case let .done(message, citations):
            if let idx = messages.firstIndex(where: { $0.id == localAssistantId }) {
                messages[idx].serverId = message.id
                messages[idx].content = message.content
                messages[idx].citations = citations ?? message.citations
                messages[idx].audioUrl = message.audioUrl
                messages[idx].status = .sent
                messages[idx].createdAt = message.createdAt
            }
            partialAssistantText = message.content
            activeConversationId = message.conversationId
            upsertConversationId(message.conversationId)
            // Refresh title from first user line when still generic.
            if let idx = conversations.firstIndex(where: { $0.id == message.conversationId }),
               conversations[idx].title == "AI Coach" || conversations[idx].title == "New chat",
               let user = messages.last(where: { $0.role == .user }) {
                let title = String(user.content.prefix(28))
                if !title.isEmpty {
                    conversations[idx].title = title
                    conversations[idx].updatedAt = Date()
                    CoachChatDiskCache.saveConversations(conversations)
                }
            }
            persistMessagesToDisk()
        case .unknown:
            break
        }
    }

    private func failAssistant(_ id: String, error: Error) {
        if let idx = messages.firstIndex(where: { $0.id == id }) {
            let msg = Self.userFacingError(error)
            if messages[idx].content.isEmpty {
                messages[idx].content = "Couldn’t get a reply."
            }
            messages[idx].status = .failed(msg)
        }
    }

    // MARK: Image

    func sendImage(_ image: UIImage, caption: String?) {
        guard canSend else { return }
        guard let jpeg = CoachImageEncoder.jpegData(from: image) else {
            lastError = "Could not prepare that photo. Try another image."
            return
        }
        sendImageJPEG(jpeg, preview: image, caption: caption, replaceId: nil)
    }

    func retryImage(messageId: String) {
        guard let idx = messages.firstIndex(where: { $0.id == messageId }),
              let jpeg = messages[idx].retryJPEG,
              canSend else { return }
        let caption = messages[idx].retryCaption
        let preview = messages[idx].localImage
        messages.remove(at: idx)
        sendImageJPEG(jpeg, preview: preview, caption: caption, replaceId: nil)
    }

    func retryText(messageId: String) {
        guard let idx = messages.firstIndex(where: { $0.id == messageId }),
              messages[idx].role == .user,
              canSend else { return }
        let text = messages[idx].content
        // Drop failed user bubble and any following failed/empty assistant from same turn.
        messages.remove(at: idx)
        if idx < messages.count,
           messages[idx].role == .assistant,
           case .failed = messages[idx].status {
            messages.remove(at: idx)
        }
        sendText(text)
    }

    private func sendImageJPEG(_ jpeg: Data, preview: UIImage?, caption: String?, replaceId: String?) {
        cancelInFlight()
        haptic()
        isSending = true
        isAnalyzingImage = true
        lastError = nil

        let localUserId = replaceId ?? "local-img-\(UUID().uuidString)"
        let thumb = preview.flatMap { CoachImageEncoder.jpegData(from: $0, maxSide: 480, quality: 0.7) } ?? jpeg
        let trimmed = caption?.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayCaption = (trimmed?.isEmpty == false) ? trimmed! : "Analyzing photo…"

        let userMsg = CoachDisplayMessage(
            id: localUserId,
            serverId: nil,
            role: .user,
            content: trimmed ?? "",
            modality: .image,
            audioUrl: nil,
            imageUrl: nil,
            localImageData: thumb,
            citations: nil,
            createdAt: Date(),
            status: .analyzing,
            retryJPEG: jpeg,
            retryCaption: trimmed
        )
        messages.append(userMsg)

        sendTask = Task { [weak self] in
            guard let self else { return }
            defer {
                self.isSending = false
                self.isAnalyzingImage = false
            }
            do {
                let response = try await self.api.chatImage(
                    imageData: jpeg,
                    caption: trimmed,
                    conversationId: self.activeConversationId
                )
                self.activeConversationId = response.conversation.id
                self.upsertConversation(response.conversation)

                if let idx = self.messages.firstIndex(where: { $0.id == localUserId }) {
                    var updated = CoachDisplayMessage.fromServer(response.userMessage)
                    updated.localImageData = thumb
                    updated.retryJPEG = nil
                    updated.retryCaption = nil
                    // Keep stable id for scroll if needed — replace with server id
                    self.messages[idx] = updated
                } else {
                    self.messages.append(CoachDisplayMessage.fromServer(response.userMessage))
                }

                let assistant = CoachDisplayMessage.fromServer(response.assistantMessage)
                self.messages.append(assistant)
                self.haptic()
                _ = displayCaption
            } catch is CancellationError {
                // superseded
            } catch {
                let detail = Self.userFacingError(error)
                if let idx = self.messages.firstIndex(where: { $0.id == localUserId }) {
                    self.messages[idx].status = .failed(detail)
                    self.messages[idx].content = trimmed ?? "Photo"
                }
                self.handleFailure(
                    error,
                    pending: .image(jpeg: jpeg, caption: trimmed, preview: thumb)
                )
            }
        }
    }

    // MARK: Voice record → turn

    func startRecording() {
        guard canSend, !isRecording else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothHFP])
            try session.setActive(true)
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("coach-voice-\(UUID().uuidString).m4a")
            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 44_100,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
            ]
            let recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder.record(forDuration: Self.maxRecordingSeconds)
            audioRecorder = recorder
            recordingURL = url
            isRecording = true
            recordingElapsed = 0
            haptic()
            startRecordingCapTimer()
        } catch {
            lastError = Self.userFacingError(error)
        }
    }

    private func startRecordingCapTimer() {
        recordLimitTask?.cancel()
        recordLimitTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 250_000_000)
                guard self.isRecording, let recorder = self.audioRecorder else { return }
                self.recordingElapsed = min(recorder.currentTime, Self.maxRecordingSeconds)
                if self.recordingElapsed >= Self.maxRecordingSeconds - 0.05 {
                    self.stopAndSendVoice()
                    return
                }
            }
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
        isRecording = false
        recordingElapsed = 0
    }

    func stopAndSendVoice() {
        guard isRecording else { return }
        recordLimitTask?.cancel()
        recordLimitTask = nil
        audioRecorder?.stop()
        audioRecorder = nil
        isRecording = false
        recordingElapsed = 0
        guard let url = recordingURL,
              let data = try? Data(contentsOf: url),
              !data.isEmpty else {
            lastError = "No audio captured."
            return
        }
        recordingURL = nil
        try? FileManager.default.removeItem(at: url)
        sendVoiceData(data)
    }

    private func sendVoiceData(_ data: Data) {
        guard canSend else { return }
        cancelInFlight()
        haptic()
        isSending = true
        lastError = nil

        let localUserId = "local-voice-\(UUID().uuidString)"
        let placeholder = CoachDisplayMessage(
            id: localUserId,
            serverId: nil,
            role: .user,
            content: "Listening…",
            modality: .voice,
            audioUrl: nil,
            imageUrl: nil,
            localImageData: nil,
            citations: nil,
            createdAt: Date(),
            status: .sending,
            retryJPEG: nil,
            retryCaption: nil
        )
        messages.append(placeholder)

        sendTask = Task { [weak self] in
            guard let self else { return }
            defer { self.isSending = false }
            do {
                let response = try await self.api.voiceTurn(
                    audioData: data,
                    conversationId: self.activeConversationId,
                    speak: true
                )
                self.activeConversationId = response.conversation.id
                self.upsertConversation(response.conversation)

                if let idx = self.messages.firstIndex(where: { $0.id == localUserId }) {
                    self.messages[idx] = CoachDisplayMessage.fromServer(response.userMessage)
                }
                self.messages.append(CoachDisplayMessage.fromServer(response.assistantMessage))
                self.haptic()
                let remoteAudio = (response.audioUrl ?? response.assistantMessage.audioUrl)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if let remoteAudio, !remoteAudio.isEmpty {
                    self.playAudio(urlString: remoteAudio)
                } else if !response.assistantMessage.content.isEmpty {
                    self.speakLocally(response.assistantMessage.content)
                }
            } catch is CancellationError {
            } catch {
                let detail = Self.userFacingError(error)
                if let idx = self.messages.firstIndex(where: { $0.id == localUserId }) {
                    self.messages[idx].status = .failed(detail)
                    self.messages[idx].content = "Voice message failed"
                }
                self.handleFailure(error, pending: .voice(data))
            }
        }
    }

    // MARK: Audio playback

    func playAudio(urlString: String) {
        guard let url = URL(string: urlString) else {
            return
        }
        stopAudio()
        let player = AVPlayer(url: url)
        audioPlayer = player
        isPlaying = true
        player.play()
        playerObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.isPlaying = false
            }
        }
    }

    /// On-device TTS when `/coach/voice/turn` returns no `audioUrl`.
    func speakLocally(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        stopAudio()
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try session.setActive(true)
        } catch {
            // Continue anyway — synthesizer may still work.
        }
        let utterance = AVSpeechUtterance(string: trimmed)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.96
        utterance.pitchMultiplier = 1.02
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        isPlaying = true
        speechSynthesizer.speak(utterance)
    }

    func stopAudio() {
        speechSynthesizer.stopSpeaking(at: .immediate)
        audioPlayer?.pause()
        audioPlayer = nil
        isPlaying = false
        if let observer = playerObserver {
            NotificationCenter.default.removeObserver(observer)
            playerObserver = nil
        }
    }

    // MARK: Rate limit / retry

    func retryLastFailure() {
        rateLimitTask?.cancel()
        rateLimitTask = nil
        rateLimitSecondsRemaining = 0
        guard let pending = pendingRetry else {
            Task { await bootstrap(forceReload: true) }
            return
        }
        pendingRetry = nil
        lastError = nil
        switch pending {
        case let .text(text):
            // Drop trailing failed turn bubbles before resending.
            while let last = messages.last {
                if case .failed = last.status {
                    messages.removeLast()
                    continue
                }
                break
            }
            sendText(text)
        case let .image(jpeg, caption, preview):
            let previewImage = preview.flatMap(UIImage.init(data:))
            sendImageJPEG(jpeg, preview: previewImage, caption: caption, replaceId: nil)
        case let .voice(data):
            sendVoiceData(data)
        }
    }

    private func handleFailure(_ error: Error, pending: CoachPendingRetry) {
        if let appError = error as? AppError, case let .rateLimited(detail, retryAfter) = appError {
            pendingRetry = pending
            let seconds = Int(max(5, min(retryAfter, 120)).rounded())
            lastError = Self.rateLimitMessage(serverDetail: detail, seconds: seconds)
            beginRateLimitCountdown(seconds: seconds)
            return
        }
        pendingRetry = pending
        lastError = Self.userFacingError(error)
    }

    private func beginRateLimitCountdown(seconds: Int) {
        rateLimitTask?.cancel()
        rateLimitSecondsRemaining = seconds
        let deadline = Date().addingTimeInterval(TimeInterval(seconds))
        rateLimitTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                let remaining = max(0, Int(ceil(deadline.timeIntervalSinceNow)))
                self.rateLimitSecondsRemaining = remaining
                if remaining <= 0 { break }
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
            guard !Task.isCancelled else { return }
            self.rateLimitSecondsRemaining = 0
            self.retryLastFailure()
        }
    }

    static func userFacingError(_ error: Error) -> String {
        if let app = error as? AppError, let description = app.errorDescription, !description.isEmpty {
            return description
        }
        if let localized = (error as? LocalizedError)?.errorDescription, !localized.isEmpty {
            return localized
        }
        return error.localizedDescription
    }

    private static func rateLimitMessage(serverDetail: String, seconds: Int) -> String {
        let waitHint = "Try again in \(seconds)s."
        let trimmed = serverDetail.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return "AI Coach is rate-limited. \(waitHint)"
        }
        if trimmed.localizedCaseInsensitiveContains("wait")
            || trimmed.localizedCaseInsensitiveContains("try again")
            || trimmed.localizedCaseInsensitiveContains("rate") {
            return trimmed
        }
        return "\(trimmed) \(waitHint)"
    }

    // MARK: RTC

    func createCallSession() async throws -> CoachRtcSession {
        try await api.createRtcSession(conversationId: activeConversationId)
    }

    // MARK: Lifecycle

    func cancelInFlight() {
        sendTask?.cancel()
        sendTask = nil
        recordLimitTask?.cancel()
        recordLimitTask = nil
        if isRecording { cancelRecording() }
    }

    func onDisappear() {
        cancelInFlight()
        rateLimitTask?.cancel()
        rateLimitTask = nil
        rateLimitSecondsRemaining = 0
        stopAudio()
    }

    // MARK: Helpers

    private func haptic() {
        hapticTick &+= 1
    }

    private func upsertConversationId(_ id: String) {
        if !conversations.contains(where: { $0.id == id }) {
            conversations.insert(
                CoachConversation(
                    id: id,
                    title: "AI Coach",
                    role: "user",
                    createdAt: Date(),
                    updatedAt: Date()
                ),
                at: 0
            )
        }
        activeConversationId = id
        CoachChatDiskCache.saveActiveId(id)
        CoachChatDiskCache.saveConversations(conversations)
        persistMessagesToDisk()
    }

    private func upsertConversation(_ conversation: CoachConversation) {
        if let idx = conversations.firstIndex(where: { $0.id == conversation.id }) {
            conversations[idx] = conversation
        } else {
            conversations.insert(conversation, at: 0)
        }
        activeConversationId = conversation.id
        CoachChatDiskCache.saveActiveId(conversation.id)
        CoachChatDiskCache.saveConversations(conversations)
        persistMessagesToDisk()
    }

    private func persistMessagesToDisk() {
        guard let id = activeConversationId else { return }
        let serverShaped: [CoachMessage] = messages.compactMap { display in
            guard display.role != .system else { return nil }
            return CoachMessage(
                id: display.serverId ?? display.id,
                conversationId: id,
                role: display.role,
                content: display.content,
                modality: display.modality,
                audioUrl: display.audioUrl,
                imageUrl: display.imageUrl,
                citations: display.citations,
                createdAt: display.createdAt
            )
        }
        CoachChatDiskCache.saveMessages(serverShaped, conversationId: id)
    }
}

// MARK: - Disk cache (survive terminate; merge with server list)

enum CoachChatDiskCache {
    private static let conversationsKey = "tactech.coach.conversations.v1"
    private static let activeIdKey = "tactech.coach.activeConversationId.v1"
    private static func messagesKey(_ id: String) -> String { "tactech.coach.messages.v1.\(id)" }

    private static var encoder: JSONEncoder { JSONEncoder.tactech }
    private static var decoder: JSONDecoder { JSONDecoder.tactech }

    static func saveConversations(_ items: [CoachConversation]) {
        guard let data = try? encoder.encode(items) else { return }
        UserDefaults.standard.set(data, forKey: conversationsKey)
    }

    static func loadConversations() -> [CoachConversation] {
        guard let data = UserDefaults.standard.data(forKey: conversationsKey),
              let items = try? decoder.decode([CoachConversation].self, from: data) else {
            return []
        }
        return items.sorted { $0.updatedAt > $1.updatedAt }
    }

    static func saveActiveId(_ id: String) {
        UserDefaults.standard.set(id, forKey: activeIdKey)
    }

    static func loadActiveId() -> String? {
        UserDefaults.standard.string(forKey: activeIdKey)
    }

    static func saveMessages(_ messages: [CoachMessage], conversationId: String) {
        guard let data = try? encoder.encode(messages) else { return }
        UserDefaults.standard.set(data, forKey: messagesKey(conversationId))
    }

    static func loadMessages(conversationId: String) -> [CoachMessage]? {
        guard let data = UserDefaults.standard.data(forKey: messagesKey(conversationId)),
              let items = try? decoder.decode([CoachMessage].self, from: data) else {
            return nil
        }
        return items
    }

    static func removeConversation(id: String) {
        UserDefaults.standard.removeObject(forKey: messagesKey(id))
        var list = loadConversations().filter { $0.id != id }
        saveConversations(list)
        if loadActiveId() == id {
            UserDefaults.standard.set(list.first?.id, forKey: activeIdKey)
        }
    }

    /// Server wins on id collision; keep cached-only threads so history isn’t lost if API returns a short list.
    static func merge(server: [CoachConversation], cached: [CoachConversation]) -> [CoachConversation] {
        var byId: [String: CoachConversation] = [:]
        for item in cached { byId[item.id] = item }
        for item in server { byId[item.id] = item }
        return byId.values.sorted { $0.updatedAt > $1.updatedAt }
    }
}

// MARK: - Speech delegate

private final class CoachSpeechDelegate: NSObject, AVSpeechSynthesizerDelegate {
    var onFinish: (() -> Void)?

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        onFinish?()
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        onFinish?()
    }
}
