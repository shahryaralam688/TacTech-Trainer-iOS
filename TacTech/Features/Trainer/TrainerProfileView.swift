import SwiftUI

struct TrainerProfileView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    /// When opened as a sheet from Home, show the back button.
    var showsBack: Bool = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                TTDarkPageHeader(
                    title: "Profile",
                    showsBack: showsBack,
                    onBack: { dismiss() }
                )

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 20) {
                        profileCard
                        inviteCard

                        NavigationLink {
                            AccountSettingsView()
                        } label: {
                            HStack {
                                Image(systemName: "gearshape.fill")
                                Text("Account Settings & Help")
                                    .font(TTFont.textLG(.semibold))
                                Spacer()
                                Image(systemName: "chevron.right")
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                            .frame(height: 54)
                            .background(Color.black)
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    .padding(.bottom, 28)
                }
            }
            .background(Color.white.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
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
            if let gender = store.currentTrainer?.gender, !gender.isEmpty {
                labeled("Gender", gender)
            }
            if let location = store.currentTrainer?.location, !location.isEmpty {
                labeled("Location", location)
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

#Preview("Trainer Profile · Tab") {
    TrainerProfileView()
        .ttPreviewTrainer()
}

#Preview("Trainer Profile · Sheet") {
    TrainerProfileView(showsBack: true)
        .ttPreviewTrainer()
}
