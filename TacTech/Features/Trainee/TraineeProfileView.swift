import SwiftUI

struct TraineeProfileView: View {
    @Environment(AppStore.self) private var store
    @State private var invite = ""
    @State private var message: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    TTScreenHeader(eyebrow: "Account", title: "Profile")
                    identity
                    MyTrainerCard()
                    joinCard
                    TTButton(title: "Sign out", style: .secondary) {
                        Task { await store.logout() }
                    }
                }
                .padding(20)
            }
            .ttScreenBackground()
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var identity: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                TTAvatar(name: store.currentUser?.name ?? "A", size: 68)
                VStack(alignment: .leading, spacing: 4) {
                    Text(store.currentUser?.name ?? "Trainee")
                        .font(TTFont.title(22))
                    Text(store.currentTrainee?.goal ?? "Training")
                        .font(TTFont.body(14))
                        .foregroundStyle(TTColor.inkMuted)
                }
            }
            HStack {
                labeled("Weight", "\(Int(store.currentTrainee?.weightKg ?? 0)) kg")
                labeled("Height", "\(store.currentTrainee?.heightCm ?? 0) cm")
                labeled("Target", "\(store.currentTrainee?.dailyCalorieTarget ?? 0)")
            }
        }
        .ttCard()
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
        .ttCard()
    }

    private func labeled(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(TTFont.caption(10))
                .foregroundStyle(TTColor.inkSubtle)
            Text(value)
                .font(TTFont.heading(14))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct MyTrainerCard: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TTSectionHeader(title: "My Trainer")
            if let trainee = store.currentTrainee, let trainer = store.trainer(for: trainee), let user = store.user(forTrainer: trainer) {
                HStack(spacing: 12) {
                    TTAvatar(name: user.name, size: 54)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(user.name)
                            .font(TTFont.heading(16))
                        Text(trainer.specialty)
                            .font(TTFont.caption(12))
                            .foregroundStyle(TTColor.inkMuted)
                    }
                }
                Text(trainer.bio)
                    .font(TTFont.body(14))
                    .foregroundStyle(TTColor.inkMuted)
                Text("\(trainer.yearsExperience) years coaching")
                    .font(TTFont.caption(12))
                    .foregroundStyle(TTColor.brand)
            } else {
                Text("You are not linked to a trainer yet. Use an invite code below.")
                    .font(TTFont.body(14))
                    .foregroundStyle(TTColor.inkMuted)
            }
        }
        .ttCard()
    }
}
