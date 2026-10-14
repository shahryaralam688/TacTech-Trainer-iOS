import SwiftUI

struct TraineeProfileView: View {
    @Environment(AppStore.self) private var store

    /// When opened as a sheet from Home, show the back button.
    var showsBack: Bool = false

    @State private var invite = ""
    @State private var joinMessage = ""
    @State private var message: String?
    @State private var showFindCoaches = false
    @State private var toast: TTToastMessage?
    @State private var isSendingRequest = false
    @State private var cancelConfirm = false
    @State private var isCancelling = false

    private var initials: String {
        let parts = (store.currentUser?.name ?? "A").split(separator: " ")
        return parts.prefix(2).map { String($0.prefix(1)) }.joined()
    }

    private var todayIntake: Int {
        guard let trainee = store.currentTrainee else { return 0 }
        return Int(store.dailyMacros(for: trainee.id, on: Date()).calories)
    }

    private var hasActiveLink: Bool {
        guard let trainee = store.currentTrainee else { return false }
        return store.trainer(for: trainee) != nil
    }

    private var pending: JoinRequestDTO? {
        store.pendingJoinRequest?.isPending == true ? store.pendingJoinRequest : nil
    }

    private var metrics: [TTProfileMetric] {
        let age = store.savedAssessmentAge() ?? 18
        let weight = Int(store.currentTrainee?.weightKg ?? 0)
        return [
            TTProfileMetric(
                id: "age",
                icon: .calendar1,
                iconColor: Color(hex: 0xEF4444),
                value: "\(age)",
                unit: "yr",
                label: "Current Age"
            ),
            TTProfileMetric(
                id: "weight",
                icon: .weightScale,
                iconColor: Color(hex: 0x22C55E),
                value: "\(weight)",
                unit: "kg",
                label: "Weight"
            ),
            TTProfileMetric(
                id: "intake",
                icon: .fire1,
                iconColor: Color(hex: 0x3B82F6),
                value: "\(todayIntake)",
                unit: "kcal",
                label: "Daily Intake"
            )
        ]
    }

    var body: some View {
        TTProfileScreen(
            name: store.currentUser?.name ?? "Trainee",
            location: store.currentTrainee?.location?.nilIfBlank ?? "Add location",
            membership: store.currentTrainee?.goal.nilIfBlank ?? "Basic Member",
            avatarAsset: store.displayAvatarAsset,
            avatarUrl: store.remoteAvatarURL,
            avatarUserId: store.session?.userId,
            initials: initials,
            metrics: metrics,
            showsBack: showsBack
        ) {
            VStack(alignment: .leading, spacing: 16) {
                findCoachesCard
                myTrainerSection
            }
        }
        .ttToast($toast)
        .sheet(isPresented: $showFindCoaches) {
            FindCoachesView()
                .ttModalSheetPresentation(dragIndicator: .hidden)
        }
        .task {
            await store.refreshTraineeJoinState()
        }
        .refreshable {
            await store.refreshTraineeJoinState()
        }
        .onReceive(NotificationCenter.default.publisher(for: .ttJoinRequestRealtime)) { note in
            let type = (note.userInfo?["type"] as? String) ?? ""
            Task { @MainActor in
                await store.handleJoinRequestRealtime(type: type)
                let lower = type.lowercased()
                if lower == "join_request_accepted" {
                    let linkedName = store.currentTrainee
                        .flatMap { store.trainer(for: $0) }
                        .flatMap { store.user(forTrainer: $0)?.name }
                        ?? "your trainer"
                    toast = TTToastMessage(text: "You’re linked with \(linkedName)", style: .success)
                } else if lower == "join_request_rejected" {
                    toast = TTToastMessage(text: "Request declined", style: .error)
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .ttOpenTraineeProfileJoin)) { _ in
            // Profile tab / sheet already here when opened from inbox.
            Task { await store.refreshTraineeJoinState() }
        }
        .confirmationDialog(
            "Cancel this request?",
            isPresented: $cancelConfirm,
            titleVisibility: .visible
        ) {
            Button("Cancel request", role: .destructive) {
                guard !isCancelling else { return }
                Task { @MainActor in await cancelPending() }
            }
            .disabled(isCancelling)
            Button("Keep waiting", role: .cancel) {}
        } message: {
            Text("You can send a new request with the same invite code later.")
        }
    }

    @ViewBuilder
    private var myTrainerSection: some View {
        if hasActiveLink {
            MyTrainerCard(toast: $toast)
        } else if let pending {
            pendingCard(pending)
        } else {
            joinRequestCard
        }
    }

    private var findCoachesCard: some View {
        Button {
            showFindCoaches = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "person.3.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(TTColor.actionOrange)
                    .frame(width: 40, height: 40)
                    .background(TTColor.actionOrange.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    Text("Find Coaches")
                        .font(TTFont.heading(16))
                        .foregroundStyle(TTColor.ink)
                    Text("Browse public trainers and start a chat.")
                        .font(TTFont.body(13))
                        .foregroundStyle(TTColor.inkMuted)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(TTColor.inkSubtle)
            }
            .padding(16)
            .background(Color(red: 243 / 255, green: 243 / 255, blue: 244 / 255))
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var joinRequestCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Request to join a trainer")
                .font(TTFont.heading(16))
            TTTextField(title: "Invite code", icon: "link", text: $invite)
            TTTextField(title: "Message (optional)", icon: "text.bubble", text: $joinMessage)
            if let message {
                Text(message)
                    .font(TTFont.caption(12))
                    .foregroundStyle(TTColor.inkMuted)
            }
            TTButton(title: isSendingRequest ? "Sending…" : "Send request", style: .secondary) {
                Task { await sendRequest() }
            }
            .disabled(isSendingRequest || invite.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(16)
        .background(Color(red: 243 / 255, green: 243 / 255, blue: 244 / 255))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func pendingCard(_ request: JoinRequestDTO) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("My Trainer")
                .font(TTFont.heading(16))
            HStack(spacing: 12) {
                TTAvatar(name: request.trainer?.name ?? "Trainer", size: 54)
                VStack(alignment: .leading, spacing: 4) {
                    Text(request.trainer?.name ?? "Trainer")
                        .font(TTFont.heading(16))
                    Text("Pending approval")
                        .font(TTFont.caption(12))
                        .fontWeight(.bold)
                        .foregroundStyle(TTColor.actionOrange)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(TTColor.actionOrange.opacity(0.12))
                        .clipShape(Capsule())
                }
                Spacer(minLength: 0)
            }
            if let note = request.message, !note.isEmpty {
                Text(note)
                    .font(TTFont.body(13))
                    .foregroundStyle(TTColor.inkMuted)
            }
            Button {
                cancelConfirm = true
            } label: {
                HStack(spacing: 8) {
                    if isCancelling {
                        ProgressView()
                    } else {
                        Text("Cancel request")
                            .font(TTFont.workSans(14, weight: .bold))
                    }
                }
                .foregroundStyle(TTColor.danger)
                .frame(maxWidth: .infinity)
                .frame(height: 42)
                .background(TTColor.danger.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(isCancelling)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(red: 243 / 255, green: 243 / 255, blue: 244 / 255))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    @MainActor
    private func sendRequest() async {
        let code = invite.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else { return }
        isSendingRequest = true
        defer { isSendingRequest = false }
        do {
            _ = try await store.createJoinRequest(inviteCode: code, message: joinMessage)
            message = nil
            invite = ""
            joinMessage = ""
            toast = TTToastMessage(text: "Request sent — waiting for approval", style: .success)
        } catch {
            let detail = (error as? AppError)?.errorDescription ?? error.localizedDescription
            message = detail
            toast = TTToastMessage(text: detail, style: .error)
        }
    }

    @MainActor
    private func cancelPending() async {
        guard let id = pending?.id else { return }
        guard !isCancelling else { return }
        isCancelling = true
        defer { isCancelling = false }
        do {
            try await store.cancelJoinRequest(id: id)
            toast = TTToastMessage(text: "Request cancelled", style: .success)
        } catch {
            let detail = (error as? AppError)?.errorDescription ?? error.localizedDescription
            toast = TTToastMessage(text: detail, style: .error)
        }
    }
}

struct MyTrainerCard: View {
    @Environment(AppStore.self) private var store
    @Binding var toast: TTToastMessage?

    @State private var leaveConfirm = false
    @State private var isLeaving = false
    @State private var confirmName = "this trainer"

    private var linked: (trainee: TraineeProfile, trainer: TrainerProfile, user: User)? {
        guard let trainee = store.currentTrainee,
              let trainer = store.trainer(for: trainee),
              let user = store.user(forTrainer: trainer) else { return nil }
        return (trainee, trainer, user)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("My Trainer")
                .font(TTFont.heading(16))
            if let linked {
                HStack(spacing: 12) {
                    TTAvatar(name: linked.user.name, size: 54)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(linked.user.name)
                            .font(TTFont.heading(16))
                        Text(linked.trainer.specialty.isEmpty ? "Linked coach" : linked.trainer.specialty)
                            .font(TTFont.body(13))
                            .foregroundStyle(TTColor.inkMuted)
                    }
                    Spacer(minLength: 0)
                }

                Button {
                    confirmName = linked.user.name
                    leaveConfirm = true
                } label: {
                    HStack(spacing: 8) {
                        if isLeaving {
                            ProgressView()
                        } else {
                            Text("Leave trainer")
                                .font(TTFont.workSans(14, weight: .bold))
                        }
                    }
                    .foregroundStyle(TTColor.danger)
                    .frame(maxWidth: .infinity)
                    .frame(height: 42)
                    .background(TTColor.danger.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(isLeaving)
                .accessibilityLabel("Leave trainer")
            } else {
                Text("No trainer linked yet.")
                    .font(TTFont.body(14))
                    .foregroundStyle(TTColor.inkMuted)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(red: 243 / 255, green: 243 / 255, blue: 244 / 255))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .confirmationDialog(
            "Leave this trainer?",
            isPresented: $leaveConfirm,
            titleVisibility: .visible
        ) {
            Button("Leave trainer", role: .destructive) {
                guard !isLeaving else { return }
                Task { @MainActor in
                    await leaveTrainer()
                }
            }
            .disabled(isLeaving)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Stop coaching with \(confirmName)? Your assigned plan will be cleared. Chat history stays.")
        }
    }

    @MainActor
    private func leaveTrainer() async {
        guard !isLeaving else { return }
        isLeaving = true
        defer { isLeaving = false }
        do {
            try await store.unlinkTrainer()
            toast = TTToastMessage(text: "Trainer removed", style: .success)
        } catch {
            let detail = (error as? AppError)?.errorDescription
                ?? error.localizedDescription
            toast = TTToastMessage(
                text: detail.isEmpty ? "Couldn't leave trainer" : detail,
                style: .error
            )
        }
    }
}

private extension String {
    var nilIfBlank: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}

#Preview("Trainee Profile · Tab") {
    TraineeProfileView()
        .ttPreviewTrainee()
}

#Preview("Trainee Profile · Sheet") {
    TraineeProfileView(showsBack: true)
        .ttPreviewTrainee()
}
