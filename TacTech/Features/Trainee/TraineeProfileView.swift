import SwiftUI

struct TraineeProfileView: View {
    @Environment(AppStore.self) private var store

    /// When opened as a sheet from Home, show the back button.
    var showsBack: Bool = false

    @State private var invite = ""
    @State private var message: String?
    @State private var showFindCoaches = false
    @State private var toast: TTToastMessage?
    @State private var isLinking = false

    private var initials: String {
        let parts = (store.currentUser?.name ?? "A").split(separator: " ")
        return parts.prefix(2).map { String($0.prefix(1)) }.joined()
    }

    private var todayIntake: Int {
        guard let trainee = store.currentTrainee else { return 0 }
        return Int(store.dailyMacros(for: trainee.id, on: Date()).calories)
    }

    private var hasLinkedTrainer: Bool {
        guard let trainee = store.currentTrainee else { return false }
        return store.trainer(for: trainee) != nil
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
                MyTrainerCard { toast = $0 }
                if !hasLinkedTrainer {
                    joinCard
                }
            }
        }
        .ttToast($toast, bottomInset: 28)
        .sheet(isPresented: $showFindCoaches) {
            FindCoachesView()
                .ttModalSheetPresentation(dragIndicator: .hidden)
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

    private var joinCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Join a trainer")
                .font(TTFont.heading(16))
            TTTextField(title: "Invite code", icon: "link", text: $invite)
            if let message {
                Text(message)
                    .font(TTFont.caption(12))
                    .foregroundStyle(TTColor.inkMuted)
            }
            TTButton(title: isLinking ? "Linking…" : "Link trainer", style: .secondary) {
                Task { await linkTrainer() }
            }
            .disabled(isLinking || invite.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(16)
        .background(Color(red: 243 / 255, green: 243 / 255, blue: 244 / 255))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    @MainActor
    private func linkTrainer() async {
        let code = invite.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else { return }
        isLinking = true
        defer { isLinking = false }
        do {
            try await store.linkTrainee(toInviteCode: code)
            message = "Trainer linked."
            invite = ""
            toast = TTToastMessage(text: "Trainer linked", style: .success)
        } catch {
            // 409 conflict (already linked) surfaces server `detail`.
            message = error.localizedDescription
            toast = TTToastMessage(text: error.localizedDescription, style: .error)
        }
    }
}

struct MyTrainerCard: View {
    @Environment(AppStore.self) private var store
    var onToast: ((TTToastMessage) -> Void)?

    @State private var leaveConfirm = false
    @State private var isLeaving = false

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
                        Text(linked.trainer.specialty)
                            .font(TTFont.body(13))
                            .foregroundStyle(TTColor.inkMuted)
                    }
                    Spacer(minLength: 0)
                }

                Button {
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
                Text("No trainer linked yet. Use an invite code below.")
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
                Task { await leaveTrainer() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            let name = linked?.user.name ?? "this trainer"
            Text("Stop coaching with \(name)? Your assigned plan will be cleared. Chat history stays.")
        }
    }

    @MainActor
    private func leaveTrainer() async {
        isLeaving = true
        defer { isLeaving = false }
        do {
            try await store.unlinkTrainer()
            onToast?(TTToastMessage(text: "Trainer removed", style: .success))
        } catch {
            onToast?(TTToastMessage(text: error.localizedDescription, style: .error))
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
