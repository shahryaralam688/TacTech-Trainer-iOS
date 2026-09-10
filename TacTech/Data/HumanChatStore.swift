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
    var recordingElapsed: TimeInterval = 0
    var lastError: String?
    var hapticTick = 0
    var isLoadingInbox = false
    var isLoadingThread = false
    var activePeerUserId: String?
    var peerTyping = false

    private let api = ChatAPI()
    private var realtime = ChatRealtimeClient()
    private var threadIdByPeer: [String: String] = [:]
    private var peerByThread: [String: String] = [:]
    private var currentUserId: String?
    private var pollTask: Task<Void, Never>?

    private var audioRecorder: AVAudioRecorder?
    private var recordingURL: URL?
    private var recordLimitTask: Task<Void, Never>?
    private var audioPlayer: AVAudioPlayer?
    private var activeRecordingPeerId: String?

    var recordingSecondsLeft: Int {
        max(0, Int((Self.maxRecordingSeconds - recordingElapsed).rounded(.up)))
    }

    // MARK: - Lifecycle

    func bootstrap() async {
        currentUserId = Self.jwtUserId()
        realtime.onEvent = { [weak self] event in
            self?.handleRealtime(event)
        }
        realtime.connect()
        await refreshInbox()
        startPollingFallback()
    }

    func teardown() {
        pollTask?.cancel()
        pollTask = nil
        if let peer = activePeerUserId, let threadId = threadIdByPeer[peer] {
            realtime.leave(threadId: threadId)
        }
        realtime.disconnect()
        cancelRecording()
        activePeerUserId = nil
        peerTyping = false
    }

    // MARK: - Inbox

    func refreshInbox() async {
        isLoadingInbox = true
        defer { isLoadingInbox = false }
        do {
            let threads = try await api.listThreads()
            for thread in threads {
                threadIdByPeer[thread.peerUserId] = thread.id
                peerByThread[thread.id] = thread.peerUserId
            }
            inbox = threads.map(HumanChatPeer.init(from:))
            lastError = nil
        } catch {
            lastError = Self.userFacing(error)
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
        isLoadingThread = true
        defer { isLoadingThread = false }

        do {
            let thread = try await api.createOrGetThread(
                peerUserId: peer.id,
                peerTraineeProfileId: peer.role == .trainee ? peer.profileId : nil,
                peerTrainerProfileId: peer.role == .trainer ? peer.profileId : nil
            )
            threadIdByPeer[peer.id] = thread.id
            peerByThread[thread.id] = peer.id
            realtime.join(threadId: thread.id)

            let page = try await api.listMessages(threadId: thread.id)
            let uid = currentUserId ?? Self.jwtUserId() ?? ""
            let mapped = page.items
                .map { HumanChatMessage.from(api: $0, currentUserId: uid, peerUserId: peer.id) }
                .sorted { $0.sentAt < $1.sentAt }
            messagesByPeer[peer.id] = mapped

            if let lastIncoming = mapped.last(where: { !$0.isOutgoing }) {
                _ = try? await api.markRead(threadId: thread.id, upToMessageId: lastIncoming.id)
                if let idx = inbox.firstIndex(where: { $0.id == peer.id }) {
                    inbox[idx].unreadCount = 0
                }
            }
            lastError = nil
            await refreshInbox()
        } catch {
            lastError = Self.userFacing(error)
        }
    }

    func closeThread() {
        if let peer = activePeerUserId, let threadId = threadIdByPeer[peer] {
            realtime.leave(threadId: threadId)
        }
        activePeerUserId = nil
        peerTyping = false
    }

    // MARK: - Send

    func sendText(to peerUserId: String, text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let clientId = UUID().uuidString
        let optimistic = HumanChatMessage(
            id: "local-\(clientId)",
            peerId: peerUserId,
            isOutgoing: true,
            kind: .text,
            text: trimmed,
            sentAt: .now,
            isRead: true,
            clientId: clientId,
            threadId: threadIdByPeer[peerUserId]
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
                lastError = Self.userFacing(error)
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
            isRead: true,
            localMediaPath: path,
            attachmentKind: .image,
            clientId: clientId,
            threadId: threadIdByPeer[peerUserId]
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
                lastError = Self.userFacing(error)
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
                isRead: true,
                localMediaPath: path,
                attachmentKind: .video,
                durationSeconds: duration,
                clientId: clientId,
                threadId: threadIdByPeer[peerUserId]
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
                self.lastError = Self.userFacing(error)
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
            isRead: true,
            localMediaPath: path,
            attachmentKind: .voice,
            durationSeconds: duration,
            clientId: clientId,
            threadId: threadIdByPeer[peerUserId]
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
                lastError = Self.userFacing(error)
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
            isRead: true,
            callOutcome: outcome,
            clientId: clientId,
            threadId: threadIdByPeer[peerId]
        )
        appendLocal(optimistic, peerUserId: peerId)
        Task {
            do {
                let threadId = try await ensureThreadId(peerUserId: peerId)
                let dto = try await api.sendCallEvent(threadId: threadId, outcome: outcome, clientId: clientId)
                replaceOptimistic(clientId: clientId, with: dto, peerUserId: peerId)
            } catch {
                lastError = Self.userFacing(error)
            }
        }
    }

    // MARK: - Voice capture

    func startRecording() async {
        guard !isRecording else { return }
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
            recorder.record(forDuration: Self.maxRecordingSeconds)
            audioRecorder = recorder
            recordingURL = url
            isRecording = true
            recordingElapsed = 0
            haptic()
            startRecordingCapTimer()
        } catch {
            lastError = error.localizedDescription
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
        recordingElapsed = 0
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
        guard let url = resolveMediaURL(message) else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
            if url.isFileURL {
                audioPlayer = try AVAudioPlayer(contentsOf: url)
                audioPlayer?.play()
            } else {
                // Remote — download then play
                Task {
                    let (data, _) = try await URLSession.shared.data(from: url)
                    let temp = FileManager.default.temporaryDirectory
                        .appendingPathComponent("voice-play-\(UUID().uuidString).m4a")
                    try data.write(to: temp)
                    await MainActor.run {
                        self.audioPlayer = try? AVAudioPlayer(contentsOf: temp)
                        self.audioPlayer?.play()
                    }
                }
            }
            haptic()
        } catch {
            lastError = "Couldn’t play voice note."
        }
    }

    func resolveMediaURL(_ message: HumanChatMessage) -> URL? {
        if let remote = message.remoteMediaUrl, let url = URL(string: remote) {
            return url
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
            Task { await refreshInbox() }
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
                }
                messagesByPeer[peerId] = list
            }
        case .typing(let threadId, let userId, let isTyping):
            if let peerId = peerByThread[threadId], peerId == activePeerUserId, userId != uid {
                peerTyping = isTyping
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
                    await self.refreshInbox()
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
        if let id = threadIdByPeer[peerUserId] { return id }
        let peer = inbox.first(where: { $0.id == peerUserId })
        let thread = try await api.createOrGetThread(
            peerUserId: peerUserId,
            peerTraineeProfileId: peer?.role == .trainee ? peer?.profileId : nil,
            peerTrainerProfileId: peer?.role == .trainer ? peer?.profileId : nil
        )
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
            // Keep local media if remote not ready
            var merged = message
            if merged.localMediaPath == nil {
                merged.localMediaPath = list[idx].localMediaPath
            }
            list[idx] = merged
        } else if let idx = list.firstIndex(where: { $0.id == message.id }) {
            list[idx] = message
        } else {
            list.append(message)
        }
        messagesByPeer[peerUserId] = list.sorted { $0.sentAt < $1.sentAt }
    }

    private func replaceOptimistic(clientId: String, with dto: ChatMessageDTO, peerUserId: String) {
        let uid = currentUserId ?? Self.jwtUserId() ?? ""
        var mapped = HumanChatMessage.from(api: dto, currentUserId: uid, peerUserId: peerUserId)
        if let idx = messagesByPeer[peerUserId]?.firstIndex(where: { $0.clientId == clientId }) {
            mapped.localMediaPath = messagesByPeer[peerUserId]?[idx].localMediaPath
        }
        upsertMessage(mapped, peerUserId: peerUserId)
        threadIdByPeer[peerUserId] = dto.threadId
        peerByThread[dto.threadId] = peerUserId
        Task { await refreshInbox() }
    }

    private func markFailed(clientId: String, peerUserId: String) {
        // Leave optimistic bubble; user can retry later. Surface error via lastError.
        _ = clientId
        _ = peerUserId
    }

    private func startRecordingCapTimer() {
        recordLimitTask?.cancel()
        recordLimitTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 250_000_000)
                guard self.isRecording, let recorder = self.audioRecorder else { return }
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

    private static func userFacing(_ error: Error) -> String {
        if let app = error as? AppError { return app.errorDescription ?? "Something went wrong." }
        return error.localizedDescription
    }
}

private extension String {
    var nilIfEmpty: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
