import SwiftUI

struct TrainerProfileView: View {
    @Environment(AppStore.self) private var store

    /// When opened as a sheet from Home, show the back button.
    var showsBack: Bool = false

    @State private var showPersonalInfo = false

    private var initials: String {
        let parts = (store.currentUser?.name ?? "T").split(separator: " ")
        return parts.prefix(2).map { String($0.prefix(1)) }.joined()
    }

    private var metrics: [TTProfileMetric] {
        let years = store.currentTrainer?.yearsExperience ?? 0
        let clients = store.currentTrainer.map { store.trainees(for: $0).count } ?? 0
        let age = store.savedAssessmentAge() ?? years + 22
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
                id: "exp",
                icon: .weightScale,
                iconColor: Color(hex: 0x22C55E),
                value: "\(years)",
                unit: "yrs",
                label: "Experience"
            ),
            TTProfileMetric(
                id: "clients",
                icon: .usersTwo,
                iconColor: Color(hex: 0x3B82F6),
                value: "\(clients)",
                unit: "",
                label: "Clients"
            )
        ]
    }

    /// Aggregate client form scores into a coach-facing weekly chart.
    private var scores: [TTSandowDayScore] {
        let first = store.currentTrainer.map { store.trainees(for: $0).first?.id }
        return store.weeklySandowScores(forTraineeId: first ?? nil)
    }

    var body: some View {
        TTProfileScreen(
            name: store.currentUser?.name ?? "Trainer",
            location: store.currentTrainer?.location?.nilIfBlank ?? "Add location",
            membership: store.currentTrainer?.specialty.nilIfBlank ?? "Coach",
            avatarAsset: TTAvatarCatalog.saved(for: store.session?.userId),
            initials: initials,
            scores: scores,
            metrics: metrics,
            showsBack: showsBack,
            onEdit: { showPersonalInfo = true }
        ) {
            inviteCard
        }
        .sheet(isPresented: $showPersonalInfo) {
            NavigationStack {
                PersonalInformationSettingsView()
            }
        }
    }

    private var inviteCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Trainee invite code")
                .font(TTFont.heading(16))
            Text(store.currentTrainer?.inviteCode ?? "—")
                .font(TTFont.display(28))
                .foregroundStyle(TTColor.actionOrange)
            Text("Share this code so a trainee can join your roster from signup or Profile.")
                .font(TTFont.body(13))
                .foregroundStyle(TTColor.inkMuted)
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

#Preview("Trainer Profile · Tab") {
    TrainerProfileView()
        .ttPreviewTrainer()
}

#Preview("Trainer Profile · Sheet") {
    TrainerProfileView(showsBack: true)
        .ttPreviewTrainer()
}
