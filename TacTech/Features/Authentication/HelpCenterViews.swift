import PhotosUI
import SwiftUI
import UIKit

// MARK: - Help Center (FAQ + Live Chat flow)

private enum HelpCenterTab: String, CaseIterable, Identifiable {
    case faq = "FAQ"
    case liveChat = "Live Chat"
    var id: String { rawValue }
}

struct HelpCenterView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var tab: HelpCenterTab = .faq
    @State private var showLiveChat = false
    @State private var showQuickSettings = false

    private let charcoal = Color(red: 28 / 255, green: 28 / 255, blue: 30 / 255)

    var body: some View {
        VStack(spacing: 0) {
            header

            Group {
                switch tab {
                case .faq:
                    HelpFAQPane()
                case .liveChat:
                    HelpLiveChatIntroPane {
                        showLiveChat = true
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color.white.ignoresSafeArea())
        .ttHideSystemNavigationBar()
        .navigationDestination(isPresented: $showLiveChat) {
            LiveChatView()
        }
        .sheet(isPresented: $showQuickSettings) {
            NavigationStack {
                NotificationSettingsView()
            }
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(spacing: 18) {
            HStack {
                TTBackButton(style: .onDark) { dismiss() }

                Spacer()

                Text("Help Center")
                    .font(TTFont.workSans(18, weight: .bold))
                    .foregroundStyle(.white)

                Spacer()

                Button { showQuickSettings = true } label: {
                    TTIcon(icon: .gear1, filled: true, size: 16)
                        .foregroundStyle(.white)
                        .frame(width: TTBackButton.size, height: TTBackButton.size)
                        .background(Color.white.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Settings")
            }

            tabSwitcher
        }
        .padding(.horizontal, 18)
        .padding(.top, 10)
        .padding(.bottom, 22)
        .background {
            UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: 32,
                bottomTrailingRadius: 32,
                topTrailingRadius: 0,
                style: .continuous
            )
            .fill(charcoal)
            .ignoresSafeArea(edges: .top)
        }
    }

    private var tabSwitcher: some View {
        HStack(spacing: 4) {
            ForEach(HelpCenterTab.allCases) { item in
                let on = tab == item
                Button {
                    withAnimation(.easeOut(duration: 0.2)) { tab = item }
                } label: {
                    Text(item.rawValue)
                        .font(TTFont.workSans(14, weight: .semibold))
                        .foregroundStyle(on ? .white : Color.white.opacity(0.55))
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .background(on ? Color.white.opacity(0.18) : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Color.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

// MARK: - FAQ

private struct HelpFAQItem: Identifiable, Hashable {
    let id: String
    let question: String
    let answer: String
}

private struct HelpFAQPane: View {
    @State private var query = ""
    @State private var expandedId: String? = "what"

    private let orange = TTColor.actionOrange
    private let cardIdle = Color(red: 243 / 255, green: 244 / 255, blue: 246 / 255)

    private let items: [HelpFAQItem] = [
        HelpFAQItem(
            id: "what",
            question: "What is TecTach?",
            answer: "TecTach is an advanced fitness app that uses AI to deliver personalized training for coaches and athletes."
        ),
        HelpFAQItem(
            id: "how",
            question: "How does TecTach work?",
            answer: "Coaches build plans and athletes follow them with progress tracking, form cues, and nutrition tools in one place."
        ),
        HelpFAQItem(
            id: "coach",
            question: "Is TecTach a replacement for a fitness coach?",
            answer: "No — TecTach amplifies coaching. Trainers stay in control while AI speeds up plans, feedback, and check-ins."
        ),
        HelpFAQItem(
            id: "free",
            question: "Is TecTach free to use?",
            answer: "Core features are available to get started. Premium coaching tools may require a plan depending on your organization."
        ),
        HelpFAQItem(
            id: "secure",
            question: "Is my data secure?",
            answer: "We protect account data with industry-standard safeguards. You control profile and notification preferences in Settings."
        ),
        HelpFAQItem(
            id: "photo",
            question: "How do I update my profile picture?",
            answer: "Open Personal Info, tap the avatar pencil, then choose Gallery or Take a photo — or pick from the avatar pack."
        )
    ]

    private var filtered: [HelpFAQItem] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return items }
        return items.filter {
            $0.question.localizedCaseInsensitiveContains(q)
                || $0.answer.localizedCaseInsensitiveContains(q)
        }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 12) {
                searchField

                ForEach(filtered) { item in
                    faqRow(item)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 18)
            .padding(.bottom, 28)
        }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            TextField("Search our FAQ...", text: $query)
                .font(TTFont.body(15))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            TTIcon(icon: .magnifyingGlass, size: 18)
                .foregroundStyle(TTColor.ink)
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
        .background(Color.white)
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(orange.opacity(0.85), lineWidth: 1.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func faqRow(_ item: HelpFAQItem) -> some View {
        let open = expandedId == item.id
        return Button {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.9)) {
                expandedId = open ? nil : item.id
            }
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    Text(item.question)
                        .font(TTFont.workSans(15, weight: .bold))
                        .foregroundStyle(open ? .white : TTColor.ink)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(open ? orange : Color.clear)
                        TTIcon(icon: .chevronDown, size: 14)
                            .foregroundStyle(open ? .white : TTColor.inkMuted)
                            .rotationEffect(.degrees(open ? 180 : 0))
                    }
                    .frame(width: 32, height: 32)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(open ? Color.clear : Color(white: 0.82), lineWidth: 1)
                    )
                }

                if open {
                    Text(item.answer)
                        .font(TTFont.body(14))
                        .foregroundStyle(Color.white.opacity(0.88))
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(16)
            .background(open ? Color.black : cardIdle)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(TTSearchPressStyle(scale: 0.99))
    }
}

// MARK: - Live Chat intro

private struct HelpLiveChatIntroPane: View {
    var onStart: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 40)

            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(TTColor.actionOrange)
                    .frame(width: 72, height: 72)
                TTIcon(icon: .chat, filled: true, size: 30)
                    .foregroundStyle(.white)
            }
            .shadow(color: TTColor.actionOrange.opacity(0.28), radius: 16, y: 8)
            .padding(.bottom, 28)

            Text("We are here to help you\nwith your fitness needs!")
                .font(TTFont.workSans(22, weight: .bold))
                .foregroundStyle(TTColor.ink)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)

            Text("We aim to reply within a few minutes! 😇")
                .font(TTFont.body(15))
                .foregroundStyle(TTColor.inkMuted)
                .multilineTextAlignment(.center)
                .padding(.top, 12)
                .padding(.horizontal, 32)

            Spacer()

            Button(action: onStart) {
                HStack(spacing: 10) {
                    Text("Start Live Chat")
                        .font(TTFont.workSans(16, weight: .bold))
                    TTIcon(icon: .chatSmile, filled: true, size: 16)
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(Color.black)
                .clipShape(Capsule())
            }
            .buttonStyle(TTSearchPressStyle(scale: 0.98))
            .padding(.horizontal, 22)
            .padding(.bottom, 28)
        }
    }
}

// MARK: - Live Chat conversation

private struct LiveChatMessage: Identifiable, Hashable {
    enum Side { case user, support }
    let id: String
    let side: Side
    let text: String
    let timeLabel: String?
}

struct LiveChatView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppStore.self) private var store

    @State private var draft = ""
    @State private var messages: [LiveChatMessage] = LiveChatView.seed
    @State private var libraryItem: PhotosPickerItem?
    @State private var showCamera = false
    @State private var showPhotoSource = false
    @State private var cameraImage: UIImage?
    @FocusState private var focused: Bool

    private let orange = TTColor.actionOrange
    private let blueSend = Color(red: 37 / 255, green: 99 / 255, blue: 235 / 255)
    private let userBubble = Color(red: 28 / 255, green: 28 / 255, blue: 30 / 255)
    private let supportBubble = Color(red: 243 / 255, green: 244 / 255, blue: 246 / 255)

    private static let seed: [LiveChatMessage] = [
        .init(id: "1", side: .user, text: "Hi! There is a problem with my account update of profile picture.", timeLabel: nil),
        .init(id: "2", side: .support, text: "Hi! Thank you for contacting TecTach support. We will investigate and resolve the issue as soon as possible.", timeLabel: nil),
        .init(id: "3", side: .user, text: "Thank you so much!", timeLabel: "10:00 AM"),
        .init(id: "4", side: .support, text: "You are welcome! The issue is fixed. Please try again.", timeLabel: nil)
    ]

    var body: some View {
        VStack(spacing: 0) {
            chatHeader

            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 14) {
                        ForEach(messages) { message in
                            if let time = message.timeLabel {
                                timeDivider(time)
                            }
                            bubble(message)
                                .id(message.id)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 18)
                    .padding(.bottom, 16)
                }
                .onChange(of: messages.count) { _, _ in
                    if let last = messages.last?.id {
                        withAnimation(.easeOut(duration: 0.25)) {
                            proxy.scrollTo(last, anchor: .bottom)
                        }
                    }
                }
            }
            .background(Color(white: 0.97))
            .clipShape(
                UnevenRoundedRectangle(
                    topLeadingRadius: 28,
                    bottomLeadingRadius: 0,
                    bottomTrailingRadius: 0,
                    topTrailingRadius: 28,
                    style: .continuous
                )
            )
            .offset(y: -10)

            composer
        }
        .background(orange.ignoresSafeArea(edges: .top))
        .ttHideSystemNavigationBar()
        .onChange(of: libraryItem) { _, item in
            Task { await attachLibrary(item) }
        }
        .onChange(of: cameraImage) { _, image in
            guard let image else { return }
            attachImage(image)
            cameraImage = nil
        }
        .sheet(isPresented: $showCamera) {
            CameraImagePicker(image: $cameraImage)
                .ignoresSafeArea()
        }
    }

    private var chatHeader: some View {
        HStack(spacing: 12) {
            Button { dismiss() } label: {
                TTIcon(icon: .chevronLeft, size: 16)
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
            }
            .buttonStyle(.plain)

            Text("Live Chat")
                .font(TTFont.workSans(20, weight: .bold))
                .foregroundStyle(.white)

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 22)
        .background(orange)
    }

    private func timeDivider(_ label: String) -> some View {
        HStack(spacing: 12) {
            Rectangle().fill(Color.black.opacity(0.08)).frame(height: 1)
            Text(label)
                .font(TTFont.caption(12))
                .foregroundStyle(TTColor.inkMuted)
            Rectangle().fill(Color.black.opacity(0.08)).frame(height: 1)
        }
        .padding(.vertical, 4)
    }

    private func bubble(_ message: LiveChatMessage) -> some View {
        let isUser = message.side == .user
        return HStack(alignment: .bottom, spacing: 8) {
            if !isUser {
                supportAvatar
            } else {
                Spacer(minLength: 40)
            }

            Text(message.text)
                .font(TTFont.body(14))
                .foregroundStyle(isUser ? .white : TTColor.ink)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(isUser ? userBubble : supportBubble)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

            if isUser {
                userAvatar
            } else {
                Spacer(minLength: 40)
            }
        }
    }

    private var supportAvatar: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(white: 0.78))
            TecTachLogoMark(size: 18, color: .white)
        }
        .frame(width: 36, height: 36)
    }

    private var userAvatar: some View {
        Group {
            let token = TTAvatarCatalog.saved(for: store.session?.userId)
            if TTAvatarCatalog.isCustom(token),
               let custom = TTAvatarCatalog.loadCustomImage(for: store.session?.userId) {
                Image(uiImage: custom)
                    .resizable()
                    .scaledToFill()
            } else if let token, TTAvatarCatalog.isAssetName(token) {
                Image(token)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(orange)
                    TTIcon(icon: .user, filled: true, size: 16)
                        .foregroundStyle(.white)
                }
            }
        }
        .frame(width: 36, height: 36)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var composer: some View {
        HStack(spacing: 10) {
            HStack(spacing: 10) {
                Button {
                    // Voice capture reserved — keep affordance.
                } label: {
                    TTIcon(icon: .microphone, size: 18)
                        .foregroundStyle(TTColor.inkMuted)
                }
                .buttonStyle(.plain)

                TextField("Type to start chatting...", text: $draft, axis: .vertical)
                    .font(TTFont.body(15))
                    .lineLimit(1...4)
                    .focused($focused)
                    .onSubmit(send)

                Button { showPhotoSource = true } label: {
                    TTIcon(icon: .camera1, size: 18)
                        .foregroundStyle(TTColor.inkMuted)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 52)
            .background(Color(white: 0.93))
            .clipShape(Capsule())

            Button(action: send) {
                TTIcon(icon: .arrowRight, filled: true, size: 18)
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 52)
                    .background(blueSend)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(TTSearchPressStyle(scale: 0.96))
            .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .opacity(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.55 : 1)
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 14)
        .background(Color.white)
        .confirmationDialog("Attach a photo", isPresented: $showPhotoSource, titleVisibility: .visible) {
            Button("Take a photo") { showCamera = true }
            PhotosPicker(selection: $libraryItem, matching: .images) {
                Text("Choose from gallery")
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        messages.append(
            LiveChatMessage(
                id: UUID().uuidString,
                side: .user,
                text: text,
                timeLabel: nil
            )
        )
        draft = ""
        focused = false
        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            messages.append(
                LiveChatMessage(
                    id: UUID().uuidString,
                    side: .support,
                    text: "Thanks — a TecTach agent will follow up shortly.",
                    timeLabel: nil
                )
            )
        }
    }

    @MainActor
    private func attachLibrary(_ item: PhotosPickerItem?) async {
        guard let item,
              let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else { return }
        attachImage(image)
        libraryItem = nil
    }

    private func attachImage(_ image: UIImage) {
        _ = image
        messages.append(
            LiveChatMessage(
                id: UUID().uuidString,
                side: .user,
                text: "📷 Photo attached",
                timeLabel: nil
            )
        )
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            messages.append(
                LiveChatMessage(
                    id: UUID().uuidString,
                    side: .support,
                    text: "Got your photo — we’ll review it and get back to you.",
                    timeLabel: nil
                )
            )
        }
    }
}

#Preview("Help Center") {
    NavigationStack {
        HelpCenterView()
            .ttPreviewTrainee()
    }
}

#Preview("Live Chat") {
    NavigationStack {
        LiveChatView()
            .ttPreviewTrainee()
    }
}
