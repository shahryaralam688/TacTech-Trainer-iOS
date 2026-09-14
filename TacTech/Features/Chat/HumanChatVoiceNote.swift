import AVFoundation
import SwiftUI

/// WhatsApp-style voice bubble — play/pause, seekable waveform, speed, remaining time.
/// Same chrome for sent and received notes.
struct HumanChatVoiceNoteView<Meta: View>: View {
    let message: HumanChatMessage
    var meta: Meta

    @Bindable private var store = HumanChatStore.shared
    @State private var bars: [CGFloat] = []

    private let orange = TTColor.actionOrange

    init(message: HumanChatMessage, @ViewBuilder meta: () -> Meta) {
        self.message = message
        self.meta = meta()
    }
    private var isOutgoing: Bool { message.isOutgoing }
    private var isActive: Bool { store.playingVoiceId == message.id }
    private var isPlaying: Bool { isActive && store.voiceIsPlaying }
    private var progress: Double { isActive ? store.voiceProgress : 0 }
    private var hasListened: Bool { message.isOutgoing || store.hasListened(to: message.id) }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            playButton
            VStack(alignment: .leading, spacing: 6) {
                waveform
                    .frame(height: 24)
                HStack(alignment: .bottom, spacing: 8) {
                    Text(timeLabel)
                        .font(TTFont.workSans(12, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(secondary)
                    speedChip
                    Spacer(minLength: 8)
                    meta
                }
            }
        }
        .padding(.leading, 10)
        .padding(.trailing, 10)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .frame(minWidth: 228)
        .background(isOutgoing ? Color.black : Color.white.opacity(0.95))
        .onAppear { bars = HumanChatVoiceWaveform.bars(for: message, url: store.resolveMediaURL(message)) }
        .task(id: message.id) {
            bars = await HumanChatVoiceWaveform.resolvedBars(for: message, url: store.resolveMediaURL(message))
        }
    }

    private var playButton: some View {
        Button {
            store.toggleVoice(message)
        } label: {
            ZStack {
                Circle()
                    .fill(playFill)
                    .frame(width: 38, height: 38)
                TTIcon(icon: isPlaying ? .pause : .play, filled: true, size: 14)
                    .foregroundStyle(playIcon)
                    .offset(x: isPlaying ? 0 : 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isPlaying ? "Pause voice note" : "Play voice note")
    }

    private var waveform: some View {
        GeometryReader { geo in
            let count = max(bars.count, 1)
            let spacing: CGFloat = 2.2
            let barW = max(2, (geo.size.width - spacing * CGFloat(count - 1)) / CGFloat(count))
            HStack(alignment: .center, spacing: spacing) {
                ForEach(Array(bars.enumerated()), id: \.offset) { index, height in
                    Capsule()
                        .fill(barColor(index: index, count: count))
                        .frame(width: barW, height: max(4, 22 * height))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 6)
                    .onChanged { value in
                        let p = max(0, min(1, value.location.x / max(geo.size.width, 1)))
                        store.seekVoice(message, progress: p)
                    }
            )
        }
        .frame(height: 24)
    }

    @ViewBuilder
    private var speedChip: some View {
        if isActive {
            Button {
                store.cycleVoiceRate()
            } label: {
                Text(store.voiceRateLabel)
                    .font(TTFont.workSans(11, weight: .bold))
                    .foregroundStyle(isOutgoing ? Color.black : .white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(isOutgoing ? Color.white : orange)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Playback speed \(store.voiceRateLabel)")
        }
    }

    private var timeLabel: String {
        if isActive {
            let remaining = max(0, store.voiceDuration - store.voiceElapsed)
            return Self.format(remaining)
        }
        return Self.format(message.durationSeconds ?? store.voiceDuration)
    }

    private func barColor(index: Int, count: Int) -> Color {
        let played = Double(index) / Double(max(count, 1)) <= progress && isActive
        if isOutgoing {
            return played ? Color.white : Color.white.opacity(0.38)
        }
        if played { return orange }
        return hasListened ? Color.black.opacity(0.28) : orange.opacity(0.45)
    }

    private var playFill: Color {
        if isOutgoing { return Color.white }
        return hasListened ? Color.black : orange
    }

    private var playIcon: Color {
        if isOutgoing { return Color.black }
        return .white
    }

    private var secondary: Color {
        isOutgoing ? Color.white.opacity(0.7) : Color(white: 0.45)
    }

    private static func format(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

enum HumanChatVoiceWaveform {
    static func bars(for message: HumanChatMessage, url: URL?, count: Int = 36) -> [CGFloat] {
        seeded(message.id, count: count)
    }

    static func resolvedBars(for message: HumanChatMessage, url: URL?, count: Int = 36) async -> [CGFloat] {
        if let url, let samples = await peaks(from: url, count: count) {
            return samples
        }
        return seeded(message.id, count: count)
    }

    private static func seeded(_ id: String, count: Int) -> [CGFloat] {
        var hash: UInt64 = 5381
        for byte in id.utf8 { hash = ((hash << 5) &+ hash) &+ UInt64(byte) }
        return (0..<count).map { i in
            hash = hash &* 1_103_515_245 &+ 12_345 &+ UInt64(i)
            let n = Double((hash >> 16) & 255) / 255
            return CGFloat(0.22 + n * 0.78)
        }
    }

    private static func peaks(from url: URL, count: Int) async -> [CGFloat]? {
        let fileURL: URL
        if url.isFileURL {
            fileURL = url
        } else {
            return nil
        }
        return await Task.detached(priority: .utility) {
            guard let file = try? AVAudioFile(forReading: fileURL) else { return nil }
            let length = file.length
            guard length > 0 else { return nil }
            let cap = min(length, 220_500)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(cap)) else {
                return nil
            }
            do { try file.read(into: buffer) } catch { return nil }
            guard let channel = buffer.floatChannelData?[0] else { return nil }
            let frames = Int(buffer.frameLength)
            guard frames > 0 else { return nil }
            let bucket = max(1, frames / count)
            var out: [CGFloat] = []
            out.reserveCapacity(count)
            for i in 0..<count {
                let start = i * bucket
                let end = min(frames, start + bucket)
                var peak: Float = 0
                var j = start
                while j < end {
                    peak = max(peak, abs(channel[j]))
                    j += 4
                }
                out.append(CGFloat(min(1, 0.18 + Double(peak) * 2.2)))
            }
            return out
        }.value
    }
}
