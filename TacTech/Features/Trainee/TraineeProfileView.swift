import SwiftUI

struct TraineeProfileView: View {
    @Environment(AppStore.self) private var store

    /// When opened as a sheet from Home, show the back button.
    var showsBack: Bool = false

    @State private var invite = ""
    @State private var message: String?

    private var initials: String {
        let parts = (store.currentUser?.name ?? "A").split(separator: " ")
        return parts.prefix(2).map { String($0.prefix(1)) }.joined()
    }

    private var todayIntake: Int {
        guard let trainee = store.currentTrainee else { return 0 }
        return Int(store.dailyMacros(for: trainee.id, on: Date()).calories)
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
            avatarAsset: TTAvatarCatalog.saved(for: store.session?.userId),
            avatarUserId: store.session?.userId,
            initials: initials,
            scores: store.weeklySandowScores(),
            metrics: metrics,
            showsBack: showsBack
        ) {
            VStack(alignment: .leading, spacing: 16) {
                MyTrainerCard()
                joinCard
            }
        }
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
            TTButton(title: "Link trainer", style: .secondary) {
                Task {
                    do {
                        try await store.linkTrainee(toInviteCode: invite)
                        message = "Trainer linked."
                    } catch {
                        message = error.localizedDescription
                    }
                }
            }
        }
        .padding(16)
        .background(Color(red: 243 / 255, green: 243 / 255, blue: 244 / 255))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

struct MyTrainerCard: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("My Trainer")
                .font(TTFont.heading(16))
            if let trainee = store.currentTrainee, let trainer = store.trainer(for: trainee), let user = store.user(forTrainer: trainer) {
                HStack(spacing: 12) {
                    TTAvatar(name: user.name, size: 54)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(user.name)
                            .font(TTFont.heading(16))
                        Text(trainer.specialty)
                            .font(TTFont.body(13))
                            .foregroundStyle(TTColor.inkMuted)
                    }
                }
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
