import SwiftUI

/// Trainer inbox for pending trainee join requests (Accept / Decline).
struct JoinRequestsView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var toast: TTToastMessage?
    @State private var decliningId: String?
    @State private var busyId: String?
    @State private var declineConfirm = false
    /// False until the first load finishes, so the empty state never flashes before it starts.
    @State private var didLoad = false
    @State private var loadFailed = false

    private let canvas = Color(white: 0.97)
    private let cardFill = Color(red: 243 / 255, green: 243 / 255, blue: 244 / 255)

    private var pending: [JoinRequestDTO] {
        store.trainerJoinRequests.filter(\.isPending)
    }

    var body: some View {
        TTCollapsingHeaderScreen(
            sheetFill: canvas,
            headerBackground: TTColor.charcoal,
            topRadius: { _ in TTSheetChrome.pageTopRadius },
            onRefresh: { await load() },
            header: { progress in
                TTDarkPageHeader(title: "Join requests", collapseProgress: progress) {
                dismiss()
            }
            }
        ) {
                VStack(alignment: .leading, spacing: 12) {
                    TTLoadGate(
                        isLoading: !didLoad,
                        hasData: !pending.isEmpty,
                        loadingLabel: "Loading join requests"
                    ) {
                        requestSkeleton
                    } content: {
                        if pending.isEmpty {
                            if loadFailed {
                                TTLoadError(title: "Couldn’t load requests") { Task { await load() } }
                                    .padding(.vertical, 24)
                            } else {
                                emptyCard
                            }
                        } else {
                            VStack(alignment: .leading, spacing: 12) {
                                if loadFailed {
                                    TTStaleNotice { Task { await load() } }
                                }
                                ForEach(pending) { request in
                                    requestRow(request)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 28)
            }
        .background(TTColor.charcoal.ignoresSafeArea(edges: .top))
        .ttHideSystemNavigationBar()
        .ttToast($toast)
        .task { await load() }
        .onReceive(NotificationCenter.default.publisher(for: .ttJoinRequestRealtime)) { note in
            let type = (note.userInfo?["type"] as? String) ?? ""
            Task { await store.handleJoinRequestRealtime(type: type) }
        }
        .confirmationDialog(
            "Decline this request?",
            isPresented: $declineConfirm,
            titleVisibility: .visible
        ) {
            Button("Decline", role: .destructive) {
                guard let id = decliningId else { return }
                Task { @MainActor in await decline(id: id) }
            }
            Button("Cancel", role: .cancel) {
                decliningId = nil
            }
        } message: {
            Text("They can send another request with your invite code later.")
        }
    }

    private func load() async {
        loadFailed = !(await store.fetchTrainerJoinRequests())
        didLoad = true
    }

    /// The real card with placeholder data.
    private var requestSkeleton: some View {
        let placeholder = JoinRequestDTO(
            id: "placeholder", status: "pending", inviteCode: "", message: "Placeholder message from the trainee.",
            createdAt: "", updatedAt: nil, trainer: nil,
            trainee: JoinRequestTraineeSummary(id: "placeholder", name: "Trainee Name", avatarUrl: nil, email: nil)
        )
        return VStack(alignment: .leading, spacing: 12) {
            ForEach(0..<TTLoadTiming.placeholderRows(rowHeight: 170), id: \.self) { _ in
                requestRow(placeholder, skeleton: true)
            }
        }
        .ttSkeleton()
    }

    private var emptyCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("No pending requests")
                .font(TTFont.workSans(16, weight: .bold))
                .foregroundStyle(TTColor.ink)
            Text("When a trainee sends your invite code, their request shows up here.")
                .font(TTFont.body(14))
                .foregroundStyle(TTColor.inkMuted)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardFill)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func requestRow(_ request: JoinRequestDTO, skeleton: Bool = false) -> some View {
        let name = request.trainee?.name ?? "Trainee"
        let busy = busyId == request.id
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                TTAvatar(
                    name: name,
                    size: 48,
                    avatarUrl: request.trainee?.avatarUrl,
                    userId: request.trainee?.id
                )
                VStack(alignment: .leading, spacing: 4) {
                    Text(name)
                        .font(TTFont.workSans(16, weight: .bold))
                        .foregroundStyle(TTColor.ink)
                    Text(Self.relativeTime(from: request.createdAt))
                        .font(TTFont.caption(12))
                        .foregroundStyle(TTColor.inkMuted)
                }
                Spacer(minLength: 0)
            }
            if let message = request.message?.trimmingCharacters(in: .whitespacesAndNewlines), !message.isEmpty {
                Text(message)
                    .font(TTFont.body(14))
                    .foregroundStyle(TTColor.inkMuted)
            }
            HStack(spacing: 10) {
                Button {
                    decliningId = request.id
                    declineConfirm = true
                } label: {
                    Text("Decline")
                        .font(TTFont.workSans(14, weight: .bold))
                        .foregroundStyle(skeleton ? Color.primary : TTColor.danger)
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .background(skeleton ? Color.ttSkeletonFill : TTColor.danger.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(busy)

                Button {
                    Task { @MainActor in await accept(request) }
                } label: {
                    HStack(spacing: 6) {
                        if busy {
                            ProgressView()
                        } else {
                            Text("Accept")
                                .font(TTFont.workSans(14, weight: .bold))
                        }
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 40)
                    .background(skeleton ? Color.ttSkeletonFill : TTColor.actionOrange)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(busy)
            }
        }
        .padding(14)
        .background(cardFill)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    @MainActor
    private func accept(_ request: JoinRequestDTO) async {
        guard busyId == nil else { return }
        busyId = request.id
        defer { busyId = nil }
        let name = request.trainee?.name ?? "Trainee"
        do {
            try await store.acceptJoinRequest(id: request.id)
            toast = TTToastMessage(text: "\(name) added to your roster", style: .success)
        } catch {
            let detail = (error as? AppError)?.errorDescription ?? error.localizedDescription
            toast = TTToastMessage(text: detail, style: .error)
        }
    }

    @MainActor
    private func decline(id: String) async {
        guard busyId == nil else { return }
        busyId = id
        defer {
            busyId = nil
            decliningId = nil
        }
        do {
            try await store.rejectJoinRequest(id: id)
            toast = TTToastMessage(text: "Request declined", style: .success)
        } catch {
            let detail = (error as? AppError)?.errorDescription ?? error.localizedDescription
            toast = TTToastMessage(text: detail, style: .error)
        }
    }

    private static func relativeTime(from iso: String) -> String {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let basic = ISO8601DateFormatter()
        basic.formatOptions = [.withInternetDateTime]
        guard let date = fractional.date(from: iso) ?? basic.date(from: iso) else {
            return iso
        }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

#Preview {
    JoinRequestsView()
        .ttPreviewTrainer()
}
