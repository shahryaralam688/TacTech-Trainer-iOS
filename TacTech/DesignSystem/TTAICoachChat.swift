import PhotosUI
import SwiftUI
import UIKit

// MARK: - Models (UI-only)

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
    /// Local preview image — backend upload comes later.
    var image: UIImage? = nil

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: TTAIChatMessage, rhs: TTAIChatMessage) -> Bool {
        lhs.id == rhs.id
            && lhs.text == rhs.text
            && lhs.isVoice == rhs.isVoice
            && (lhs.image == nil) == (rhs.image == nil)
    }
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

/// Compatibility PreferenceKey — older FAB frame tracking.
/// Kept so mixed local checkouts that still publish FAB frames continue to compile.
struct TTAICoachFABFrameKey: PreferenceKey {
    static var defaultValue: CGRect = .zero

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if next != .zero {
            value = next
        }
    }
}

// MARK: - Overlay

/// Floating liquid-glass AI chat that expands from the Plus FAB like a bubble,
/// with WhatsApp-style keyboard avoidance and image sharing (UI-only).
struct TTAICoachChatOverlay: View {
    @Binding var isPresented: Bool
    var audience: TTAIChatAudience
    var namespace: Namespace.ID

    @State private var messages: [TTAIChatMessage] = []
    @State private var draft = ""
    @State private var isRecording = false
    @State private var isThinking = false
    @State private var expanded = false
    @State private var wavePhase: CGFloat = 0
    @State private var libraryItem: PhotosPickerItem?
    @State private var showPhotoSource = false
    @State private var showCamera = false
    @State private var cameraImage: UIImage?
    @State private var pendingImage: UIImage?
    @FocusState private var fieldFocused: Bool

    @StateObject private var keyboard = TTAIKeyboardObserver()

    private let orange = TTColor.actionOrange
    private let ink = Color.black
    private let muted = Color(white: 0.42)
    private let bubble = Animation.spring(response: 0.52, dampingFraction: 0.82)
    private let soft = Animation.spring(response: 0.38, dampingFraction: 0.86)

    var body: some View {
        GeometryReader { geo in
            let topSafe = max(geo.safeAreaInsets.top, 8)
            let bottomSafe = max(geo.safeAreaInsets.bottom, 8)
            let keyboardLift = max(0, keyboard.height - (keyboard.height > 0 ? bottomSafe : 0))
            let sidePad: CGFloat = 12
            let topPad = topSafe + 6

            ZStack(alignment: .bottom) {
                // Scrim
                Color.black
                    .opacity(expanded ? 0.34 : 0)
                    .ignoresSafeArea()
                    .onTapGesture { close() }
                    .allowsHitTesting(expanded)

                // Floating liquid panel
                floatingPanel
                    .frame(maxWidth: .infinity)
                    .frame(height: panelHeight(in: geo, topPad: topPad, bottomSafe: bottomSafe, keyboardLift: keyboardLift))
                    .padding(.horizontal, sidePad)
                    .padding(.bottom, keyboardLift > 0 ? keyboardLift + 6 : bottomSafe + 6)
                    .padding(.top, topPad)
                    .scaleEffect(expanded ? 1 : 0.08, anchor: .bottom)
                    .opacity(expanded ? 1 : 0)
                    .blur(radius: expanded ? 0 : 10)
                    .offset(y: expanded ? 0 : 40)
                    .matchedGeometryEffect(id: TTAICoachPortal.matchedID, in: namespace, isSource: isPresented)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
        .ignoresSafeArea()
        .onAppear(perform: openSequence)
        .onChange(of: libraryItem) { _, item in
            Task { await loadLibrary(item) }
        }
        .onChange(of: cameraImage) { _, image in
            guard let image else { return }
            pendingImage = image
            cameraImage = nil
        }
        .onChange(of: keyboard.height) { _, height in
            if height > 0 { isRecording = false }
        }
        .sheet(isPresented: $showCamera) {
            CameraImagePicker(image: $cameraImage)
                .ignoresSafeArea()
        }
        .confirmationDialog("Share a photo", isPresented: $showPhotoSource, titleVisibility: .visible) {
            Button("Take photo") { showCamera = true }
            PhotosPicker(selection: $libraryItem, matching: .images) {
                Text("Photo library")
            }
            Button("Cancel", role: .cancel) {}
        }
        .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.75), trigger: expanded)
        .sensoryFeedback(.selection, trigger: isRecording)
    }

    private func panelHeight(
        in geo: GeometryProxy,
        topPad: CGFloat,
        bottomSafe: CGFloat,
        keyboardLift: CGFloat
    ) -> CGFloat {
        let available = geo.size.height - topPad - (keyboardLift > 0 ? keyboardLift + 6 : bottomSafe + 6)
        // Floating card — not edge-to-edge full bleed.
        return min(available, geo.size.height * 0.88)
    }

    // MARK: - Floating panel

    private var floatingPanel: some View {
        VStack(spacing: 0) {
            grabber
            header
            Divider().opacity(0.1)

            messageList

            if !audience.suggestions.isEmpty && draft.isEmpty && pendingImage == nil && !isRecording && !fieldFocused {
                suggestionRow
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            if isRecording {
                voicePanel
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else {
                composer
            }
        }
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .fill(Color.white.opacity(0.92))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.9),
                            orange.opacity(0.35),
                            Color.white.opacity(0.35)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.2
                )
        )
        .shadow(color: Color.black.opacity(0.18), radius: 28, y: 14)
        .shadow(color: orange.opacity(0.22), radius: 22, y: 8)
        .animation(soft, value: fieldFocused)
        .animation(soft, value: isRecording)
        .animation(soft, value: pendingImage != nil)
    }

    private var grabber: some View {
        Capsule()
            .fill(Color.black.opacity(0.14))
            .frame(width: 42, height: 5)
            .padding(.top, 10)
            .padding(.bottom, 4)
    }

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [orange, orange.opacity(0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 44, height: 44)
                    .shadow(color: orange.opacity(0.35), radius: 10, y: 4)

                TTIcon(icon: .robotFace1, filled: true, size: 22)
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("TacTech AI")
                    .font(.system(size: 18, weight: .bold))
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
    }

    // MARK: - Messages

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 12) {
                    ForEach(messages) { message in
                        bubble(message)
                            .id(message.id)
                            .transition(.asymmetric(
                                insertion: .opacity
                                    .combined(with: .scale(scale: 0.94, anchor: message.role == .user ? .bottomTrailing : .bottomLeading))
                                    .combined(with: .offset(y: 10)),
                                removal: .opacity
                            ))
                    }

                    if isThinking {
                        typingIndicator.id("typing")
                    }

                    Color.clear.frame(height: 4).id("bottomAnchor")
                }
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 10)
            }
            .scrollDismissesKeyboard(.interactively)
            .onTapGesture { fieldFocused = false }
            .onChange(of: messages.count) { _, _ in
                scrollToBottom(proxy)
            }
            .onChange(of: isThinking) { _, on in
                if on { scrollToBottom(proxy, id: "typing") }
            }
            .onChange(of: keyboard.height) { _, _ in
                scrollToBottom(proxy, id: "bottomAnchor")
            }
            .onChange(of: fieldFocused) { _, focused in
                if focused {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                        scrollToBottom(proxy, id: "bottomAnchor")
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white.opacity(0.35))
    }

    private func bubble(_ message: TTAIChatMessage) -> some View {
        let isUser = message.role == .user

        return HStack(alignment: .bottom, spacing: 8) {
            if !isUser {
                aiAvatar(size: 28)
            } else {
                Spacer(minLength: 42)
            }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 6) {
                if let image = message.image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: 220, maxHeight: 220)
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
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(isUser ? Color.black : Color.white.opacity(0.95))
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
                Spacer(minLength: 42)
            }
        }
    }

    private var typingIndicator: some View {
        HStack(alignment: .bottom, spacing: 8) {
            aiAvatar(size: 28)
            HStack(spacing: 5) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(orange.opacity(0.5 + Double(i) * 0.15))
                        .frame(width: 7, height: 7)
                        .offset(y: wavePhase > 0.5 ? (i == Int(wavePhase) % 3 ? -3 : 0) : 0)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .background(Color.white.opacity(0.95))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            Spacer(minLength: 42)
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

    // MARK: - Suggestions

    private var suggestionRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(audience.suggestions, id: \.self) { tip in
                    Button {
                        send(text: tip)
                    } label: {
                        Text(tip)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(ink)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(Color.white.opacity(0.95))
                            .clipShape(Capsule())
                            .overlay(
                                Capsule().strokeBorder(orange.opacity(0.4), lineWidth: 1.2)
                            )
                    }
                    .buttonStyle(AssessmentCardPressStyle())
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
    }

    // MARK: - Composer (WhatsApp-style)

    private var composer: some View {
        VStack(spacing: 8) {
            if let pendingImage {
                HStack(spacing: 10) {
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
                .padding(.top, 8)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            HStack(alignment: .bottom, spacing: 8) {
                Button { showPhotoSource = true } label: {
                    ZStack {
                        Circle()
                            .fill(Color.black.opacity(0.06))
                            .frame(width: 40, height: 40)
                        TTIcon(icon: .image1, size: 18)
                            .foregroundStyle(ink.opacity(0.75))
                    }
                }
                .buttonStyle(AssessmentCardPressStyle())
                .accessibilityLabel("Share photo")

                HStack(alignment: .bottom, spacing: 8) {
                    TextField("Message", text: $draft, axis: .vertical)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(ink)
                        .lineLimit(1...5)
                        .focused($fieldFocused)
                        .tint(orange)
                        .submitLabel(.send)
                        .onSubmit(sendDraft)

                    if canSend {
                        Button(action: sendDraft) {
                            ZStack {
                                Circle()
                                    .fill(orange)
                                    .frame(width: 34, height: 34)
                                Image(systemName: "arrow.up")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                        }
                        .buttonStyle(AssessmentCardPressStyle())
                        .transition(.scale.combined(with: .opacity))
                        .accessibilityLabel("Send")
                    } else {
                        Button(action: startVoice) {
                            TTIcon(icon: .microphone, filled: true, size: 18)
                                .foregroundStyle(ink.opacity(0.7))
                                .frame(width: 34, height: 34)
                        }
                        .buttonStyle(AssessmentCardPressStyle())
                        .accessibilityLabel("Voice message")
                    }
                }
                .padding(.leading, 14)
                .padding(.trailing, 6)
                .padding(.vertical, 6)
                .background(Color.black.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(fieldFocused ? orange : Color.clear, lineWidth: 1.5)
                )
            }
            .padding(.horizontal, 12)
            .padding(.top, pendingImage == nil ? 8 : 0)
            .padding(.bottom, 10)
            .animation(soft, value: canSend)
        }
        .background(Color.white.opacity(0.88))
    }

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || pendingImage != nil
    }

    // MARK: - Voice

    private var voicePanel: some View {
        VStack(spacing: 14) {
            Text("Listening… release to send")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(muted)

            HStack(spacing: 3) {
                ForEach(0..<20, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(orange)
                        .frame(width: 3, height: voiceBar(i))
                }
            }
            .frame(height: 44)

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
                            .frame(width: 58, height: 58)
                        Image(systemName: "arrow.up")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                .buttonStyle(AssessmentCardPressStyle())
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity)
        .background(Color.white.opacity(0.92))
        .onAppear {
            withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) {
                wavePhase = 1
            }
        }
    }

    private func voiceBar(_ index: Int) -> CGFloat {
        let t = abs(sin(Double(index) * 0.55 + Double(wavePhase) * .pi))
        return 8 + 30 * t
    }

    // MARK: - Actions

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
        withAnimation(bubble) {
            expanded = true
        }
    }

    private func close() {
        fieldFocused = false
        withAnimation(bubble) {
            expanded = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
            isPresented = false
        }
    }

    private func sendDraft() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        let image = pendingImage
        guard !text.isEmpty || image != nil else { return }
        draft = ""
        pendingImage = nil
        send(text: text, image: image)
    }

    private func send(text: String, image: UIImage? = nil, isVoice: Bool = false) {
        let user = TTAIChatMessage(
            id: UUID().uuidString,
            role: .user,
            text: text,
            timeLabel: nil,
            isVoice: isVoice,
            image: image
        )
        withAnimation(soft) {
            messages.append(user)
            isThinking = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
            let replyText: String
            if image != nil {
                replyText = "I can see your photo. Image understanding will connect with the AI backend next — thanks for sharing."
            } else {
                replyText = placeholderReply(to: text)
            }
            let reply = TTAIChatMessage(
                id: UUID().uuidString,
                role: .assistant,
                text: replyText,
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
        send(text: "Voice note — transcription coming soon", isVoice: true)
    }

    private func placeholderReply(to prompt: String) -> String {
        let clip = prompt.isEmpty ? "that" : "“\(prompt.prefix(40))”"
        switch audience {
        case .trainer:
            return "Got it — \(clip). Live coaching replies will plug in when we wire the AI backend."
        case .trainee:
            return "Noted — \(clip). Your AI coach UI is ready; real answers connect next."
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy, id: String? = nil) {
        let target = id ?? messages.last?.id ?? "bottomAnchor"
        withAnimation(.easeOut(duration: 0.2)) {
            proxy.scrollTo(target, anchor: .bottom)
        }
    }

    private func loadLibrary(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        if let data = try? await item.loadTransferable(type: Data.self),
           let image = UIImage(data: data) {
            await MainActor.run {
                pendingImage = image
                libraryItem = nil
            }
        }
    }
}

// MARK: - Keyboard observer (WhatsApp-style lift)

@MainActor
final class TTAIKeyboardObserver: ObservableObject {
    @Published var height: CGFloat = 0

    private var tokens: [NSObjectProtocol] = []

    init() {
        let center = NotificationCenter.default
        tokens.append(
            center.addObserver(forName: UIResponder.keyboardWillChangeFrameNotification, object: nil, queue: .main) { [weak self] note in
                Task { @MainActor in
                    self?.update(from: note)
                }
            }
        )
        tokens.append(
            center.addObserver(forName: UIResponder.keyboardWillHideNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    withAnimation(.easeOut(duration: 0.25)) {
                        self?.height = 0
                    }
                }
            }
        )
    }

    deinit {
        let center = NotificationCenter.default
        tokens.forEach { center.removeObserver($0) }
    }

    private func update(from note: Notification) {
        guard
            let frame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect,
            let duration = note.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double,
            let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
            let window = scene.windows.first(where: \.isKeyWindow) ?? scene.windows.first
        else { return }

        let converted = window.convert(frame, from: nil)
        let overlap = max(0, window.bounds.maxY - converted.minY)
        withAnimation(.easeOut(duration: duration)) {
            height = overlap
        }
    }
}

// MARK: - Root keyboard helper

/// When AI chat is open, allow WhatsApp-style keyboard avoidance on the root.
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

// MARK: - FAB helper

extension View {
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
