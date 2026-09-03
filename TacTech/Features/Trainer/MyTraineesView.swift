import SwiftUI

struct MyTraineesView: View {
    @Environment(AppStore.self) private var store
    @State private var query = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    TTScreenHeader(eyebrow: "Roster", title: "My Trainees")
                    searchField
                    if filtered.isEmpty {
                        TTEmptyState(icon: "person.2", title: "No trainees yet", message: "Share your invite code from Profile so athletes can join.")
                            .ttCard()
                    } else {
                        ForEach(filtered) { trainee in
                            NavigationLink {
                                TraineeDetailView(trainee: trainee)
                            } label: {
                                traineeRow(trainee)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(20)
            }
            .ttScreenBackground()
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var searchField: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(TTColor.inkMuted)
            TextField("Search trainees", text: $query)
                .font(TTFont.body(15))
        }
        .padding(.horizontal, 14)
        .frame(height: 48)
        .background(TTColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(TTColor.line, lineWidth: 1)
        )
    }

    private func traineeRow(_ trainee: TraineeProfile) -> some View {
        let user = store.user(forTrainee: trainee)
        let plan = store.assignedPlan(for: trainee)
        let last = store.logs(for: trainee.id).first
        return HStack(spacing: 12) {
            TTAvatar(name: user?.name ?? "T", size: 52)
            VStack(alignment: .leading, spacing: 4) {
                Text(user?.name ?? "Trainee")
                    .font(TTFont.heading(16))
                    .foregroundStyle(TTColor.ink)
                Text(plan?.title ?? "No plan assigned")
                    .font(TTFont.caption(12))
                    .foregroundStyle(TTColor.inkMuted)
                Text(trainee.goal)
                    .font(TTFont.caption(12))
                    .foregroundStyle(TTColor.inkSubtle)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(last == nil ? "Idle" : "Active")
                    .font(TTFont.caption(11))
                    .foregroundStyle(last == nil ? TTColor.inkMuted : TTColor.success)
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(TTColor.inkSubtle)
            }
        }
        .ttCard()
    }

    private var filtered: [TraineeProfile] {
        guard let trainer = store.currentTrainer else { return [] }
        let all = store.trainees(for: trainer)
        guard !query.isEmpty else { return all }
        return all.filter {
            store.user(forTrainee: $0)?.name.localizedCaseInsensitiveContains(query) == true
        }
    }
}

#Preview("My Trainees") {
    MyTraineesView()
        .ttPreviewTrainer()
}
