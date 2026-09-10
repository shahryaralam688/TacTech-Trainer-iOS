import AVFoundation
import Foundation
import UIKit

/// Local-first trainer↔trainee chat store. Backend `/chat/*` + Socket.IO will replace mocks later.
@MainActor
@Observable
final class HumanChatStore {
    static let shared = HumanChatStore()
    static let maxRecordingSeconds: TimeInterval = 60

    var threads: [String: [HumanChatMessage]] = [:]
    var drafts: [String: String] = [:]
    var isRecording = false
    var recordingElapsed: TimeInterval = 0
    var lastError: String?
    var hapticTick = 0

    private var audioRecorder: AVAudioRecorder?
    private var recordingURL: URL?
    private var recordLimitTask: Task<Void, Never>?
    private var audioPlayer: AVAudioPlayer?
    private var activeRecordingPeerId: String?

    var recordingSecondsLeft: Int {
        max(0, Int((Self.maxRecordingSeconds - recordingElapsed).rounded(.up)))
    }

    // MARK: - Queries

    func messages(for peerId: String) -> [HumanChatMessage] {
        threads[peerId] ?? []
    }

    func lastMessage(for peerId: String) -> HumanChatMessage? {
        threads[peerId]?.last
    }

    func unreadCount(for peerId: String) -> Int {
        (threads[peerId] ?? []).filter { !$0.isOutgoing && !$0.isRead }.count
    }

    func markRead(peerId: String) {
        guard var list = threads[peerId] else { return }
        for i in list.indices where !list[i].isOutgoing {
            list[i].isRead = true
        }
        threads[peerId] = list
        persist(peerId: peerId)
    }

    func seedIfNeeded(peers: [HumanChatPeer], asAudience: HumanChatAudience) {
        loadAll(peerIds: peers.map(\.id))
        for peer in peers where threads[peer.id] == nil || threads[peer.id]?.isEmpty == true {
            let greeting: String
            switch asAudience {
            case .trainer:
                greeting = "Hey coach — ready when you are."
            case .trainee:
                greeting = "Hey — message me anytime about form, nutrition, or schedule."
            }
            threads[peer.id] = [
                HumanChatMessage(
                    id: UUID().uuidString,
                    peerId: peer.id,
                    isOutgoing: false,
                    kind: .text,
                    text: greeting,
                    sentAt: Date().addingTimeInterval(-3600),
                    isRead: false
                )
            ]
            persist(peerId: peer.id)
        }
    }

    // MARK: - Send

    func sendText(to peerId: String, text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        append(
            HumanChatMessage.text(peerId: peerId, outgoing: true, body: trimmed),
            peerId: peerId
        )
        drafts[peerId] = ""
        haptic()
        scheduleMockReply(peerId: peerId)
    }

    func sendImage(to peerId: String, image: UIImage, caption: String?) {
        guard let jpeg = image.jpegData(compressionQuality: 0.82) else {
            lastError = "Couldn’t encode photo."
            return
        }
        let path = storeMedia(data: jpeg, peerId: peerId, ext: "jpg")
        let trimmed = caption?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        append(
            HumanChatMessage(
                id: UUID().uuidString,
                peerId: peerId,
                isOutgoing: true,
                kind: .image,
                text: trimmed,
                sentAt: .now,
                isRead: true,
                localMediaPath: path,
                attachmentKind: .image
            ),
            peerId: peerId
        )
        drafts[peerId] = ""
        haptic()
        scheduleMockReply(peerId: peerId, kindHint: .image)
    }

    func sendVideo(to peerId: String, fileURL: URL, caption: String?) {
        guard let data = try? Data(contentsOf: fileURL), !data.isEmpty else {
            lastError = "Couldn’t read video."
            return
        }
        let ext = fileURL.pathExtension.isEmpty ? "mp4" : fileURL.pathExtension
        let path = storeMedia(data: data, peerId: peerId, ext: ext)
        let trimmed = caption?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let duration = Self.videoDuration(url: mediaURL(relativePath: path) ?? fileURL)
        append(
            HumanChatMessage(
                id: UUID().uuidString,
                peerId: peerId,
                isOutgoing: true,
                kind: .video,
                text: trimmed,
                sentAt: .now,
                isRead: true,
                localMediaPath: path,
                attachmentKind: .video,
                durationSeconds: duration
            ),
            peerId: peerId
        )
        drafts[peerId] = ""
        haptic()
        scheduleMockReply(peerId: peerId, kindHint: .video)
    }

    func sendVoiceNote(to peerId: String, data: Data, duration: TimeInterval) {
        let path = storeMedia(data: data, peerId: peerId, ext: "m4a")
        append(
            HumanChatMessage(
                id: UUID().uuidString,
                peerId: peerId,
                isOutgoing: true,
                kind: .voice,
                text: "",
                sentAt: .now,
                isRead: true,
                localMediaPath: path,
                attachmentKind: .voice,
                durationSeconds: duration
            ),
            peerId: peerId
        )
        haptic()
        scheduleMockReply(peerId: peerId, kindHint: .voice)
    }

    func recordCallEvent(peerId: String, outcome: String) {
        append(
            HumanChatMessage(
                id: UUID().uuidString,
                peerId: peerId,
                isOutgoing: true,
                kind: .callEvent,
                text: "",
                sentAt: .now,
                isRead: true,
                callOutcome: outcome
            ),
            peerId: peerId
        )
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
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.play()
            haptic()
        } catch {
            lastError = "Couldn’t play voice note."
        }
    }

    func resolveMediaURL(_ message: HumanChatMessage) -> URL? {
        if let path = message.localMediaPath {
            if path.hasPrefix("/") {
                return URL(fileURLWithPath: path)
            }
            return mediaURL(relativePath: path)
        }
        if let remote = message.remoteMediaUrl, let url = URL(string: remote) {
            return url
        }
        return nil
    }

    func loadImage(_ message: HumanChatMessage) -> UIImage? {
        guard let url = resolveMediaURL(message),
              let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    // MARK: - Private

    private func append(_ message: HumanChatMessage, peerId: String) {
        var list = threads[peerId] ?? []
        list.append(message)
        threads[peerId] = list
        persist(peerId: peerId)
    }

    private func scheduleMockReply(peerId: String, kindHint: HumanChatMessageKind = .text) {
        let reply: String
        switch kindHint {
        case .image: reply = "Got the photo — reviewing now."
        case .video: reply = "Video received — I’ll check form."
        case .voice: reply = "Heard you — notes coming shortly."
        default: reply = "Got it — thanks!"
        }
        let replyId = UUID().uuidString
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(750))
            var updated = self.threads[peerId] ?? []
            updated.append(
                HumanChatMessage(
                    id: replyId,
                    peerId: peerId,
                    isOutgoing: false,
                    kind: .text,
                    text: reply,
                    sentAt: .now,
                    isRead: false
                )
            )
            self.threads[peerId] = updated
            self.persist(peerId: peerId)
        }
    }

    private func haptic() {
        hapticTick &+= 1
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

    // MARK: - Disk

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

    private func threadFile(peerId: String) -> URL {
        let root = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("HumanChatThreads", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root.appendingPathComponent("\(peerId).json")
    }

    private func persist(peerId: String) {
        guard let list = threads[peerId],
              let data = try? JSONEncoder().encode(list) else { return }
        try? data.write(to: threadFile(peerId: peerId), options: .atomic)
    }

    private func loadAll(peerIds: [String]) {
        for id in peerIds {
            let url = threadFile(peerId: id)
            guard let data = try? Data(contentsOf: url),
                  let list = try? JSONDecoder().decode([HumanChatMessage].self, from: data) else { continue }
            threads[id] = list
        }
    }

    private static func videoDuration(url: URL) -> Double? {
        let asset = AVURLAsset(url: url)
        let seconds = CMTimeGetSeconds(asset.duration)
        return seconds.isFinite ? seconds : nil
    }
}
