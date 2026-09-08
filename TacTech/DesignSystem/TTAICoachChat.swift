import SwiftUI

// MARK: - Models (UI-only for now)

enum TTAIChatRole: Hashable {
    case user
    case assistant
    case system
}

struct TTAIChatMessage: Identifiable, Hashable {
    let id: String
    let role: TTAIChatRole
    var text: String
    var timeLabel: String?
    var isVoice: Bool = false
}

enum TTAIChatAudience {
    case trainer
    case trainee

    var greetingName: String {
        switch self {
        case .trainer: "Coach"
        case .trainee: "Athlete"
        }
    }

    var headerSubtitle: String {
        switch self {
        case .trainer: "Plan · clients · feedback"
        case .trainee: "Workouts · form · nutrition"
        }
    }

    var suggestions: [String] {
        switch self {
        case .trainer:
            ["Draft a 4-day plan", "Check trainee progress", "Write form cues"]
        case .trainee:
            ["What’s my next workout?", "Form tips for squats", "Meal ideas today"]
        }
    }

    var welcome: String {
        switch self {
        case .trainer:
            "I’m your TacTech AI. Ask about plans, trainees, or cues — tap the mic to talk."
        case .trainee:
            "I’m your TacTech AI. Ask about workouts, form, or nutrition — tap the mic to talk."
        }
    }
}

// MARK: - Portal ID

enum TTAICoachPortal {
    static let matchedID = "tactech.aiCoach.portal"
}

// MARK: - Overlay (liquid glass floating panel from Plus FAB)

/// Floating liquid-glass AI chat that expands from the orange Plus FAB.
/// UI-only: local messages / voice state. Backend wiring comes later.
struct TTAICoachChatOverlay: View {
    @Binding var isPresented: Bool
    var audience: TTAIChatAudience
    var namespace: Namespace.ID

    @State private var messages: [TTAIChatMessage] = []
    @State private var draft = ""
    @State private var isRecording = false
    @State private var isThinking = false
    @State private var contentReady = false
    @State private var wavePhase: CGFloat = 0
    @FocusState private var fieldFocused: Bool

    private let orange = TTColor.actionOrange
    private let ink = Color.black
    private let muted = Color(white: 0.42)
    private let morph = Animation.spring(response: 0.52, dampingFraction: 0.86)
    private let soft = Animation.spring(response: 0.42, dampingFraction: 0.84)
    private let panelRadius: CGFloat = 32

    var body: some View {
        GeometryReader { geo in
            let topPad = max(geo.safeAreaInsets.top, 10) + 6
            let bottomClearance = TTFloatingTabBar<Int>.contentHeight + max(geo.safeAreaInsets.bottom, 8) + 10
            let panelHeight = min(geo.size.height - topPad - bottomClearance, geo.size.height * 0.74)

            ZStack(alignment: .bottom) {
                // Soft glass scrim — tap outside to dismiss.
                ZStack {
                    Rectangle()
                        .fill(.ultraThinMaterial)
                        .opacity(contentReady ? 1 : 0)
                    Color.black.opacity(contentReady ? 0.18 : 0)
                }
                .ignoresSafeArea()
                .onTapGesture { close() }
                .allowsHitTesting(contentReady)

                floatingPanel
                    .matchedGeometryEffect(id: TTAICoachPortal.matchedID, in: namespace, isSource: isPresented)
                    .frame(maxWidth: 520)
                    .frame(height: contentReady ? panelHeight : 56)
                    .padding(.horizontal, contentReady ? 14 : geo.size.width / 2 - 28)
                    .padding(.bottom, contentReady ? bottomClearance : bottomClearance - 8)
                    .scaleEffect(contentReady ? 1 : 0.92, anchor: .bottom)
                    .opacity(contentReady ? 1 : 0.95)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            }
        }
        .ignoresSafeArea()
        .onAppear(perform: openSequence)
        .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.75), trigger: isPresented)
        .sensoryFeedback(.selection, trigger: isRecording)
    }

    // MARK: Floating liquid glass panel

    private var floatingPanel: some View {
        VStack(spacing: 0) {
            grabber
            header

            messageList
                .opacity(contentReady ? 1 : 0)

            if !suggestions.isEmpty && draft.isEmpty && !isRecording {
                suggestionRow
                    .opacity(contentReady ? 1 : 0)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            if isRecording {
                voicePanel
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else {
                composer
                    .opacity(contentReady ? 1 : 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background { liquidGlassBackground }
        .clipShape(RoundedRectangle(cornerRadius: panelRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: panelRadius, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.95),
                            Color.white.opacity(0.35),
                            orange.opacity(0.45),
                            Color.white.opacity(0.55)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.4
                )
        }
        .shadow(color: Color.black.opacity(contentReady ? 0.22 : 0.12), radius: contentReady ? 36 : 12, y: contentReady ? 18 : 6)
        .shadow(color: orange.opacity(contentReady ? 0.28 : 0.4), radius: contentReady ? 28 : 14, y: contentReady ? 10 : 4)
    }

    private var liquidGlassBackground: some View {
        ZStack {
            RoundedRectangle(cornerRadius: panelRadius, style: .continuous)
                .fill(.ultraThinMaterial)

            RoundedRectangle(cornerRadius: panelRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.82),
                            Color.white.opacity(0.68),
                            Color.white.opacity(0.75)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            // Specular highlight (liquid glass sheen).
            RoundedRectangle(cornerRadius: panelRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.55),
                            Color.white.opacity(0.08),
                            Color.clear
                        ],
                        startPoint: .top,
                        endPoint: .center
                    )
                )
                .blendMode(.plusLighter)
                .opacity(0.7)

            // Soft orange bloom near the bottom (ties to FAB brand).
            Ellipse()
                .fill(orange.opacity(0.14))
                .frame(width: 220, height: 120)
                .blur(radius: 36)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .offset(y: 24)
                .allowsHitTesting(false)
        }
    }

    private var grabber: some View {
        Capsule()
            .fill(Color.black.opacity(0.14))
            .frame(width: 36, height: 4)
            .padding(.top, 10)
            .padding(.bottom, 4)
            .opacity(contentReady ? 1 : 0)
    }

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 44, height: 44)
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [orange, orange.opacity(0.72)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 44, height: 44)
                    .shadow(color: orange.opacity(0.4), radius: 10, y: 4)

                TTIcon(icon: .robotFace1, filled: true, size: 22)
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("TacTech AI")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(ink)
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color(red: 0.2, green: 0.78, blue: 0.45))
                        .frame(width: 7, height: 7)
                    Text(audience.headerSubtitle)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(muted)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            Button(action: close) {
                ZStack {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .frame(width: 36, height: 36)
                    Circle()
                        .fill(Color.white.opacity(0.55))
                        .frame(width: 36, height: 36)
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(ink)
                }
            }
            .buttonStyle(AssessmentCardPressStyle())
            .accessibilityLabel("Close AI chat")
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
        .opacity(contentReady ? 1 : 0)
    }

    // MARK: Messages

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 14) {
                    ForEach(messages) { message in
                        bubble(message)
                            .id(message.id)
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .move(edge: .bottom)).combined(with: .scale(scale: 0.96)),
                                removal: .opacity
                            ))
                    }

                    if isThinking {
                        typingIndicator
                            .id("typing")
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 8)
                .padding(.bottom, 8)
            }
            .onChange(of: messages.count) { _, _ in
                scrollToEnd(proxy)
            }
            .onChange(of: isThinking) { _, thinking in
                if thinking { scrollToEnd(proxy, id: "typing") }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white.opacity(0.22))
    }

    private func bubble(_ message: TTAIChatMessage) -> some View {
        let isUser = message.role == .user

        return HStack(alignment: .bottom, spacing: 8) {
            if !isUser {
                aiAvatar(size: 28)
            } else {
                Spacer(minLength: 40)
            }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
                HStack(spacing: 6) {
                    if message.isVoice {
                        TTIcon(icon: .waveSine, size: 12)
                            .foregroundStyle(isUser ? Color.white.opacity(0.8) : orange)
                    }
                    Text(message.text)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(isUser ? Color.white : ink)
                        .multilineTextAlignment(.leading)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background {
                    if isUser {
                        Color.black
                    } else {
                        ZStack {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(.ultraThinMaterial)
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(Color.white.opacity(0.78))
                        }
                    }
                }
                .clipShape(
                    UnevenRoundedRectangle(
                        topLeadingRadius: 18,
                        bottomLeadingRadius: isUser ? 18 : 6,
                        bottomTrailingRadius: isUser ? 6 : 18,
                        topTrailingRadius: 18,
                        style: .continuous
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(isUser ? Color.clear : Color.white.opacity(0.7), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(isUser ? 0.14 : 0.05), radius: 8, y: 3)

                if let time = message.timeLabel {
                    Text(time)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(muted)
                        .padding(.horizontal, 4)
                }
            }

            if !isUser {
                Spacer(minLength: 40)
            }
        }
    }

    private var typingIndicator: some View {
        HStack(alignment: .bottom, spacing: 8) {
            aiAvatar(size: 28)
            HStack(spacing: 5) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(orange.opacity(0.55 + Double(i) * 0.15))
                        .frame(width: 7, height: 7)
                        .offset(y: wavePhase == CGFloat(i) ? -3 : 0)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.ultraThinMaterial)
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.white.opacity(0.75))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            Spacer(minLength: 40)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.45).repeatForever(autoreverses: true)) {
                wavePhase = 2
            }
        }
    }

    private func aiAvatar(size: CGFloat) -> some View {
        ZStack {
            Circle().fill(.ultraThinMaterial)
            Circle().fill(orange.opacity(0.16))
            TTIcon(icon: .robotFace1, filled: true, size: size * 0.48)
                .foregroundStyle(orange)
        }
        .frame(width: size, height: size)
    }

    // MARK: Suggestions

    private var suggestions: [String] { audience.suggestions }

    private var suggestionRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(suggestions, id: \.self) { tip in
                    Button {
                        send(tip)
                    } label: {
                        Text(tip)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(ink)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background {
                                ZStack {
                                    Capsule().fill(.ultraThinMaterial)
                                    Capsule().fill(Color.white.opacity(0.7))
                                }
                            }
                            .clipShape(Capsule())
                            .overlay(
                                Capsule()
                                    .strokeBorder(orange.opacity(0.4), lineWidth: 1.2)
                            )
                    }
                    .buttonStyle(AssessmentCardPressStyle())
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
    }

    // MARK: Composer

    private var composer: some View {
        HStack(spacing: 10) {
            Button {
                startVoice()
            } label: {
                ZStack {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .frame(width: 44, height: 44)
                    Circle()
                        .fill(Color.white.opacity(0.55))
                        .frame(width: 44, height: 44)
                    TTIcon(icon: .microphone, filled: true, size: 18)
                        .foregroundStyle(ink)
                }
            }
            .buttonStyle(AssessmentCardPressStyle())
            .accessibilityLabel("Talk to AI")

            HStack(spacing: 8) {
                TextField("Message TacTech AI…", text: $draft, axis: .vertical)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(ink)
                    .lineLimit(1...4)
                    .focused($fieldFocused)
                    .tint(orange)
                    .submitLabel(.send)
                    .onSubmit(sendDraft)

                if !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Button(action: sendDraft) {
                        ZStack {
                            Circle()
                                .fill(orange)
                                .frame(width: 34, height: 34)
                                .shadow(color: orange.opacity(0.35), radius: 8, y: 3)
                            Image(systemName: "arrow.up")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(.white)
                        }
                    }
                    .buttonStyle(AssessmentCardPressStyle())
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.leading, 14)
            .padding(.trailing, 8)
            .padding(.vertical, 8)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(.ultraThinMaterial)
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(Color.white.opacity(0.55))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(fieldFocused ? orange : Color.white.opacity(0.65), lineWidth: fieldFocused ? 1.5 : 1)
            )
            .animation(soft, value: draft.isEmpty)
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .padding(.bottom, 14)
    }

    // MARK: Voice panel (UI-only)

    private var voicePanel: some View {
        VStack(spacing: 16) {
            Text("Listening…")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(muted)

            HStack(spacing: 4) {
                ForEach(0..<16, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(orange)
                        .frame(width: 4, height: barHeight(for: i))
                }
            }
            .frame(height: 48)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.55).repeatForever(autoreverses: true)) {
                    wavePhase = 1
                }
            }

            HStack(spacing: 28) {
                Button {
                    withAnimation(soft) { isRecording = false }
                } label: {
                    Text("Cancel")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(muted)
                }

                Button {
                    finishVoice()
                } label: {
                    ZStack {
                        Circle()
                            .fill(Color.black)
                            .frame(width: 64, height: 64)
                            .shadow(color: Color.black.opacity(0.2), radius: 12, y: 6)
                        TTIcon(icon: .chatSmile, filled: true, size: 22)
                            .foregroundStyle(.white)
                    }
                }
                .buttonStyle(AssessmentCardPressStyle())
                .accessibilityLabel("Send voice message")
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 18)
        .frame(maxWidth: .infinity)
    }

    private func barHeight(for index: Int) -> CGFloat {
        let base: CGFloat = 10
        let amp: CGFloat = 28
        let t = abs(sin(Double(index) * 0.7 + Double(wavePhase) * .pi))
        return base + amp * t
    }

    // MARK: Actions (local UI)

    private func openSequence() {
        if messages.isEmpty {
            messages = [
                TTAIChatMessage(
                    id: "welcome",
                    role: .assistant,
                    text: audience.welcome,
                    timeLabel: "Just now"
                )
            ]
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
            withAnimation(morph) { contentReady = true }
        }
    }

    private func close() {
        fieldFocused = false
        withAnimation(morph) {
            contentReady = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            withAnimation(morph) {
                isPresented = false
            }
        }
    }

    private func sendDraft() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        draft = ""
        send(text)
    }

    private func send(_ text: String, isVoice: Bool = false) {
        fieldFocused = false
        let user = TTAIChatMessage(
            id: UUID().uuidString,
            role: .user,
            text: text,
            timeLabel: nil,
            isVoice: isVoice
        )
        withAnimation(soft) {
            messages.append(user)
            isThinking = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.85) {
            let reply = TTAIChatMessage(
                id: UUID().uuidString,
                role: .assistant,
                text: placeholderReply(to: text),
                timeLabel: nil
            )
            withAnimation(soft) {
                isThinking = false
                messages.append(reply)
            }
        }
    }

    private func startVoice() {
        fieldFocused = false
        withAnimation(soft) { isRecording = true }
    }

    private func finishVoice() {
        withAnimation(soft) { isRecording = false }
        send("Voice note — (transcription coming soon)", isVoice: true)
    }

    private func placeholderReply(to prompt: String) -> String {
        switch audience {
        case .trainer:
            return "Got it. I’ll help with “\(prompt.prefix(48))”. Live AI replies will connect here next — for now this is the chat UI."
        case .trainee:
            return "Noted: “\(prompt.prefix(48))”. Your AI coach UI is ready — real answers will plug in when we wire the backend."
        }
    }

    private func scrollToEnd(_ proxy: ScrollViewProxy, id: String? = nil) {
        let target = id ?? messages.last?.id
        guard let target else { return }
        withAnimation(.easeOut(duration: 0.22)) {
            proxy.scrollTo(target, anchor: .bottom)
        }
    }
}

// MARK: - FAB morph source helper

extension View {
    /// Apply on the orange Plus control so it can morph into `TTAICoachChatOverlay`.
    func ttAICoachFABSource(namespace: Namespace.ID, isChatPresented: Bool) -> some View {
        self
            .matchedGeometryEffect(
                id: TTAICoachPortal.matchedID,
                in: namespace,
                isSource: !isChatPresented
            )
            .opacity(isChatPresented ? 0 : 1)
            .allowsHitTesting(!isChatPresented)
    }
}
