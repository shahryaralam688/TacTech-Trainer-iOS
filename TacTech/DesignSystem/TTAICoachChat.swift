import PhotosUI
import SwiftUI
import UIKit

// MARK: - Models (UI-only)

enum TTAIChatRole: Hashable {
    case user
    case assistant
    case system
}

struct TTAIChatMessage: Identifiable {
    let id: String
    let role: TTAIChatRole
    var text: String
    var timeLabel: String?
    var isVoice: Bool = false
    /// Local preview — backend upload comes later.
    var image: UIImage? = nil
}

enum TTAIChatAudience {
    case trainer
    case trainee

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
            "I’m your TacTech AI. Ask about plans, trainees, or cues — type, talk, or share a photo."
        case .trainee:
            "I’m your TacTech AI. Ask about workouts, form, or nutrition — type, talk, or share a photo."
        }
    }
}

enum TTAICoachPortal {
    static let matchedID = "tactech.aiCoach.portal"
}

// MARK: - Liquid floating chat (from Plus FAB)

/// Messenger-style floating bubble that morphs open from the orange Plus.
/// UI-only: local messages, voice panel, and photo attach. Backend later.
struct TTAICoachChatOverlay: View {
    @Binding var isPresented: Bool
    var audience: TTAIChatAudience
    var namespace: Namespace.ID

    @State private var messages: [TTAIChatMessage] = []
    @State private var draft = ""
    @State private var isRecording = false
    @State private var isThinking = false
    @State private var expanded = false
    @State private var chromeVisible = false
    @State private var wavePhase: CGFloat = 0
    @State private var pendingImage: UIImage?
    @State private var libraryItem: PhotosPickerItem?
    @State private var showPhotoSource = false
    @State private var showCamera = false
    @State private var cameraImage: UIImage?
    @FocusState private var fieldFocused: Bool

    private let orange = TTColor.actionOrange
    private let ink = Color.black
    private let muted = Color(white: 0.42)
    /// Present / dismiss — Intercom-like soft spring.
    private let present = Animation.spring(response: 0.46, dampingFraction: 0.88)
    /// Keyboard / safe-area resize — critically damped so height doesn’t bounce.
    private let resize = Animation.spring(response: 0.34, dampingFraction: 0.98)
    private let soft = Animation.spring(response: 0.38, dampingFraction: 0.86)

    /// Resting gaps (unchanged visually when keyboard is hidden).
    private let sidePad: CGFloat = 14
    private let topGap: CGFloat = 10
    private let bottomGap: CGFloat = 12

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(Color.black.opacity(expanded ? 0.22 : 0))
                .ignoresSafeArea()
                .opacity(expanded ? 1 : 0)
                .animation(present, value: expanded)
                .onTapGesture { close() }
                .allowsHitTesting(expanded)

            GeometryReader { geo in
                let topInset = geo.safeAreaInsets.top + topGap
                let bottomInset = geo.safeAreaInsets.bottom + bottomGap
                let maxBubbleHeight = max(280, geo.size.height - topInset - bottomInset)
                let bubbleHeight = min(max(440, maxBubbleHeight * 0.9), maxBubbleHeight)

                floatingBubble(height: bubbleHeight)
                    .padding(.horizontal, sidePad)
                    .padding(.top, topInset)
                    .padding(.bottom, bottomInset)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .scaleEffect(expanded ? 1 : 0.84, anchor: UnitPoint(x: 0.5, y: 1.0))
                    .opacity(expanded ? 1 : 0)
                    .offset(y: expanded ? 0 : 28)
                    .animation(present, value: expanded)
                    .animation(resize, value: bubbleHeight)
                    .animation(resize, value: bottomInset)
                    .animation(resize, value: topInset)
            }
        }
        .onAppear(perform: openSequence)
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
        .confirmationDialog("Share a photo", isPresented: $showPhotoSource, titleVisibility: .visible) {
            Button("Take Photo") { showCamera = true }
            PhotosPicker(selection: $libraryItem, matching: .images) {
                Text("Photo Library")
            }
            Button("Cancel", role: .cancel) {}
        }
        .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.75), trigger: isPresented)
        .sensoryFeedback(.selection, trigger: isRecording)
    }

    // MARK: Floating bubble

    private func floatingBubble(height: CGFloat) -> some View {
        VStack(spacing: 0) {
            grabber
            header
            Divider().opacity(0.10)

            messageList
                .opacity(chromeVisible ? 1 : 0)

            if !audience.suggestions.isEmpty && draft.isEmpty && pendingImage == nil && !isRecording {
                suggestionRow
                    .opacity(chromeVisible ? 1 : 0)
                    .transition(.opacity)
            }

            if isRecording {
                voicePanel
                    .transition(.opacity)
            } else {
                composer
                    .opacity(chromeVisible ? 1 : 0)
            }
        }
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity)
        .frame(height: height, alignment: .top)
        .background { liquidBackground }
        .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.85),
                            orange.opacity(0.35),
                            Color.white.opacity(0.25)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.2
                )
        )
        .shadow(color: orange.opacity(expanded ? 0.22 : 0.08), radius: expanded ? 28 : 10, y: expanded ? 14 : 6)
        .shadow(color: Color.black.opacity(expanded ? 0.16 : 0.06), radius: expanded ? 30 : 12, y: expanded ? 18 : 8)
    }

    private var liquidBackground: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(.ultraThinMaterial)
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(Color.white.opacity(0.88))
            // Soft orange bloom (liquid accent).
            Circle()
                .fill(orange.opacity(0.14))
                .frame(width: 180, height: 180)
                .blur(radius: 40)
                .offset(x: 110, y: -160)
                .allowsHitTesting(false)
        }
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
                        .fill(Color.black.opacity(0.06))
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
        .padding(.bottom, 12)
        .padding(.top, 4)
        .opacity(chromeVisible ? 1 : 0)
    }

    // MARK: Messages

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 12) {
                    ForEach(messages) { message in
                        bubble(message)
                            .id(message.id)
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .scale(scale: 0.96)).combined(with: .move(edge: .bottom)),
                                removal: .opacity
                            ))
                    }
                    if isThinking {
                        typingIndicator.id("typing")
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 10)
                .padding(.bottom, 8)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: messages.count) { _, _ in scrollToEnd(proxy) }
            .onChange(of: isThinking) { _, on in
                if on { scrollToEnd(proxy, id: "typing") }
            }
            .onChange(of: fieldFocused) { _, focused in
                guard focused else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                    scrollToEnd(proxy)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func bubble(_ message: TTAIChatMessage) -> some View {
        let isUser = message.role == .user

        return HStack(alignment: .bottom, spacing: 8) {
            if isUser {
                Spacer(minLength: 40)
            } else {
                aiAvatar(size: 26)
            }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 6) {
                if let image = message.image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: 210, maxHeight: 210)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(Color.black.opacity(0.06), lineWidth: 1)
                        )
                }

                if !message.text.isEmpty {
                    HStack(spacing: 6) {
                        if message.isVoice {
                            TTIcon(icon: .waveSine, size: 12)
                                .foregroundStyle(isUser ? Color.white.opacity(0.85) : orange)
                        }
                        Text(message.text)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(isUser ? Color.white : ink)
                            .multilineTextAlignment(.leading)
                    }
                    .padding(.horizontal, 13)
                    .padding(.vertical, 10)
                    .background(isUser ? Color.black : Color.white.opacity(0.92))
                    .clipShape(
                        UnevenRoundedRectangle(
                            topLeadingRadius: 18,
                            bottomLeadingRadius: isUser ? 18 : 5,
                            bottomTrailingRadius: isUser ? 5 : 18,
                            topTrailingRadius: 18,
                            style: .continuous
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(isUser ? Color.clear : Color.black.opacity(0.06), lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(isUser ? 0.12 : 0.04), radius: 8, y: 3)
                }

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
            aiAvatar(size: 26)
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
            withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) {
                wavePhase = 2
            }
        }
    }

    private func aiAvatar(size: CGFloat) -> some View {
        ZStack {
            Circle().fill(orange.opacity(0.14))
            TTIcon(icon: .robotFace1, filled: true, size: size * 0.48)
                .foregroundStyle(orange)
        }
        .frame(width: size, height: size)
    }

    // MARK: Suggestions

    private var suggestionRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(audience.suggestions, id: \.self) { tip in
                    Button { send(text: tip) } label: {
                        Text(tip)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(ink)
                            .padding(.horizontal, 13)
                            .padding(.vertical, 9)
                            .background(Color.white.opacity(0.92))
                            .clipShape(Capsule())
                            .overlay(Capsule().strokeBorder(orange.opacity(0.4), lineWidth: 1.1))
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
        VStack(spacing: 8) {
            if let pendingImage {
                HStack {
                    Image(uiImage: pendingImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 56, height: 56)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    Text("Photo ready to send")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(muted)
                    Spacer()
                    Button {
                        withAnimation(soft) { self.pendingImage = nil }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(Color(white: 0.55))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 14)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            HStack(spacing: 8) {
                Button { showPhotoSource = true } label: {
                    composerIcon(icon: .plus, filled: false)
                }
                .buttonStyle(AssessmentCardPressStyle())
                .accessibilityLabel("Share photo")

                Button { startVoice() } label: {
                    composerIcon(icon: .microphone, filled: true)
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

                    if canSend {
                        Button(action: sendDraft) {
                            ZStack {
                                Circle().fill(orange).frame(width: 32, height: 32)
                                Image(systemName: "arrow.up")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                        }
                        .buttonStyle(AssessmentCardPressStyle())
                        .transition(.scale.combined(with: .opacity))
                    }
                }
                .padding(.leading, 12)
                .padding(.trailing, 7)
                .padding(.vertical, 7)
                .background(Color.black.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(fieldFocused ? orange : Color.clear, lineWidth: 1.5)
                )
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
            .animation(soft, value: canSend)
        }
        .background(Color.white.opacity(0.55))
    }

    private func composerIcon(icon: SandowIcon, filled: Bool) -> some View {
        ZStack {
            Circle()
                .fill(Color.black.opacity(0.05))
                .frame(width: 40, height: 40)
            TTIcon(icon: icon, filled: filled, size: 17)
                .foregroundStyle(ink)
        }
    }

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || pendingImage != nil
    }

    // MARK: Voice

    private var voicePanel: some View {
        VStack(spacing: 14) {
            Text("Listening…")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(muted)

            HStack(spacing: 4) {
                ForEach(0..<18, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(orange)
                        .frame(width: 3.5, height: voiceBar(i))
                }
            }
            .frame(height: 44)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) {
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

                Button(action: finishVoice) {
                    ZStack {
                        Circle()
                            .fill(Color.black)
                            .frame(width: 60, height: 60)
                            .shadow(color: .black.opacity(0.2), radius: 12, y: 6)
                        TTIcon(icon: .chatSmile, filled: true, size: 20)
                            .foregroundStyle(.white)
                    }
                }
                .buttonStyle(AssessmentCardPressStyle())
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 12)
        .padding(.bottom, 18)
        .frame(maxWidth: .infinity)
        .background(Color.white.opacity(0.55))
    }

    private func voiceBar(_ index: Int) -> CGFloat {
        8 + 26 * abs(sin(Double(index) * 0.65 + Double(wavePhase) * .pi))
    }

    // MARK: Actions

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
        chromeVisible = false
        // Next run-loop so the view mounts at the collapsed state first.
        DispatchQueue.main.async {
            withAnimation(present) {
                expanded = true
            }
            withAnimation(present.delay(0.08)) {
                chromeVisible = true
            }
        }
    }

    private func close() {
        fieldFocused = false
        withAnimation(present) {
            chromeVisible = false
            expanded = false
        }
        // Keep the view alive until the spring finishes, then tear down.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.38) {
            guard !expanded else { return }
            isPresented = false
        }
    }

    private func sendDraft() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        let image = pendingImage
        guard !text.isEmpty || image != nil else { return }
        draft = ""
        pendingImage = nil
        send(text: text.isEmpty ? (image == nil ? "" : "Shared a photo") : text, image: image)
    }

    private func send(text: String, image: UIImage? = nil, isVoice: Bool = false) {
        fieldFocused = false
        let user = TTAIChatMessage(
            id: UUID().uuidString,
            role: .user,
            text: text,
            isVoice: isVoice,
            image: image
        )
        withAnimation(soft) {
            messages.append(user)
            isThinking = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
            let reply = TTAIChatMessage(
                id: UUID().uuidString,
                role: .assistant,
                text: placeholderReply(to: text, hasImage: image != nil)
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
        send(text: "Voice note — (transcription coming soon)", isVoice: true)
    }

    private func placeholderReply(to prompt: String, hasImage: Bool) -> String {
        if hasImage {
            return "Got your photo. Live vision analysis will plug in next — for now this is the chat UI."
        }
        let clip = prompt.prefix(48)
        switch audience {
        case .trainer:
            return "Got it — “\(clip)”. Live AI replies will connect here next."
        case .trainee:
            return "Noted — “\(clip)”. Your AI coach UI is ready for the backend hookup."
        }
    }

    private func scrollToEnd(_ proxy: ScrollViewProxy, id: String? = nil) {
        let target = id ?? messages.last?.id
        guard let target else { return }
        withAnimation(.easeOut(duration: 0.22)) {
            proxy.scrollTo(target, anchor: .bottom)
        }
    }

    @MainActor
    private func importLibrary(_ item: PhotosPickerItem?) async {
        guard let item,
              let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else { return }
        pendingImage = image
        libraryItem = nil
    }
}

// MARK: - FAB morph helper

extension View {
    func ttAICoachFABSource(namespace: Namespace.ID, isChatPresented: Bool) -> some View {
        self
            .opacity(isChatPresented ? 0 : 1)
            .scaleEffect(isChatPresented ? 0.82 : 1, anchor: .center)
            .animation(.spring(response: 0.42, dampingFraction: 0.88), value: isChatPresented)
            .allowsHitTesting(!isChatPresented)
    }
}

/// Ignore keyboard at the root only while AI chat is closed.
struct TTRootKeyboardIgnore: ViewModifier {
    var enabled: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if enabled {
            content.ignoresSafeArea(.keyboard)
        } else {
            content
        }
    }
}
