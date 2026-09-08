import AVFoundation
import Foundation
import Observation
import UIKit

@MainActor
@Observable
final class CoachStore {
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
    var partialAssistantText = ""
    var lastError: String?
    var hapticTick = 0

    private var sendTask: Task<Void, Never>?
    private var streamAssistantId: String?
    private var audioRecorder: AVAudioRecorder?
    private var audioPlayer: AVPlayer?
    private var recordingURL: URL?
    private var playerObserver: NSObjectProtocol?

    var canSend: Bool { !isSending && !isStreaming && !isAnalyzingImage }
    var isBusy: Bool { isSending || isStreaming || isAnalyzingImage }

    // MARK: Bootstrap

    func bootstrap(forceReload: Bool = false) async {
        if isBootstrapping { return }
        isBootstrapping = true
        lastError = nil
        defer { isBootstrapping = false }
        do {
            async let provider = api.status()
            async let list = api.listConversations()
            status = try await provider
            conversations = try await list
            if let active = activeConversationId ?? conversations.first?.id {
                activeConversationId = active
                if forceReload || messages.isEmpty {
                    let server = try await api.listMessages(conversationId: active)
                    messages = server.map(CoachDisplayMessage.fromServer)
                }
            }
            await syncMemoryDebounced()
        } catch {
            lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func refreshMessages() async {
        guard let id = activeConversationId else { return }
        do {
            let server = try await api.listMessages(conversationId: id)
            // Preserve optimistic failures / analyzing if still in-flight
            if !isBusy {
                messages = server.map(CoachDisplayMessage.fromServer)
            }
            lastError = nil
        } catch {
            lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
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
        } catch {
            lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
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
                if let idx = self.messages.firstIndex(where: { $0.id == localUserId }) {
                    self.messages[idx].status = .failed((error as? LocalizedError)?.errorDescription ?? "Send failed")
                }
                self.lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
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
        case .unknown:
            break
        }
    }

    private func failAssistant(_ id: String, error: Error) {
        if let idx = messages.firstIndex(where: { $0.id == id }) {
            let msg = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
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

                var assistant = CoachDisplayMessage.fromServer(response.assistantMessage)
                self.messages.append(assistant)
                self.haptic()
                _ = displayCaption
            } catch is CancellationError {
                // superseded
            } catch {
                if let idx = self.messages.firstIndex(where: { $0.id == localUserId }) {
                    self.messages[idx].status = .failed((error as? LocalizedError)?.errorDescription ?? "Upload failed")
                    self.messages[idx].content = trimmed ?? "Photo"
                }
                self.lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    // MARK: Voice record → turn

    func startRecording() {
        guard canSend, !isRecording else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
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
            recorder.record()
            audioRecorder = recorder
            recordingURL = url
            isRecording = true
            haptic()
        } catch {
            lastError = (error as? LocalizedError)?.errorDescription ?? "Microphone unavailable."
        }
    }

    func cancelRecording() {
        audioRecorder?.stop()
        audioRecorder = nil
        if let url = recordingURL {
            try? FileManager.default.removeItem(at: url)
        }
        recordingURL = nil
        isRecording = false
    }

    func stopAndSendVoice() {
        guard isRecording else { return }
        audioRecorder?.stop()
        audioRecorder = nil
        isRecording = false
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
                if let audio = response.audioUrl ?? response.assistantMessage.audioUrl {
                    self.playAudio(urlString: audio)
                }
            } catch is CancellationError {
            } catch {
                if let idx = self.messages.firstIndex(where: { $0.id == localUserId }) {
                    self.messages[idx].status = .failed((error as? LocalizedError)?.errorDescription ?? "Voice failed")
                    self.messages[idx].content = "Voice message failed"
                }
                self.lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    // MARK: Audio playback

    func playAudio(urlString: String) {
        guard let url = URL(string: urlString) else { return }
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

    func stopAudio() {
        audioPlayer?.pause()
        audioPlayer = nil
        isPlaying = false
        if let observer = playerObserver {
            NotificationCenter.default.removeObserver(observer)
            playerObserver = nil
        }
    }

    // MARK: RTC

    func createCallSession() async throws -> CoachRtcSession {
        try await api.createRtcSession(conversationId: activeConversationId)
    }

    // MARK: Lifecycle

    func cancelInFlight() {
        sendTask?.cancel()
        sendTask = nil
        if isRecording { cancelRecording() }
    }

    func onDisappear() {
        cancelInFlight()
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
    }

    private func upsertConversation(_ conversation: CoachConversation) {
        if let idx = conversations.firstIndex(where: { $0.id == conversation.id }) {
            conversations[idx] = conversation
        } else {
            conversations.insert(conversation, at: 0)
        }
    }
}
