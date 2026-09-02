import SwiftUI

struct TrainerProfileView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    TTScreenHeader(eyebrow: "Account", title: "Profile")
                    profileCard
                    inviteCard
                    TTButton(title: "Sign out", style: .secondary) {
                        store.logout()
                    }
                }
                .padding(20)
            }
            .ttScreenBackground()
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var profileCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                TTAvatar(name: store.currentUser?.name ?? "T", size: 68)
                VStack(alignment: .leading, spacing: 4) {
                    Text(store.currentUser?.name ?? "Trainer")
                        .font(TTFont.title(22))
                    Text(store.currentTrainer?.specialty ?? "Coach")
                        .font(TTFont.body(14))
                        .foregroundStyle(TTColor.inkMuted)
                }
            }
            Text(store.currentTrainer?.bio ?? "")
                .font(TTFont.body(14))
                .foregroundStyle(TTColor.inkMuted)
            HStack {
                labeled("Experience", "\(store.currentTrainer?.yearsExperience ?? 0) yrs")
                labeled("Role", "Trainer")
                labeled("Clients", "\(store.currentTrainer.map { store.trainees(for: $0).count } ?? 0)")
            }
        }
        .ttCard()
    }

    private var inviteCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Trainee invite code")
                .font(TTFont.heading(16))
            Text(store.currentTrainer?.inviteCode ?? "—")
                .font(TTFont.display(28))
                .foregroundStyle(TTColor.brand)
            Text("Share this code so a trainee can join your roster from signup or Profile.")
                .font(TTFont.body(13))
                .foregroundStyle(TTColor.inkMuted)
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
