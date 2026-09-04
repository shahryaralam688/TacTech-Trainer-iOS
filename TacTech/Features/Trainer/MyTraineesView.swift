import SwiftUI

// MARK: - My Trainees (Sandow / TacTech system design)

struct MyTraineesView: View {
    @Environment(AppStore.self) private var store
    @Namespace private var searchNS
    @State private var showSearch = false
    @State private var query = ""
    @State private var goalFilter: String?
    @State private var selectedTrainee: TraineeProfile?

    private let canvas = Color(white: 0.97)
    private let cardFill = Color(red: 243 / 255, green: 243 / 255, blue: 244 / 255)

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                trainerListHeader(
                    title: "My Trainees",
                    subtitle: "\(filtered.count) athletes",
                    trailingIcon: .userPlus
                ) {
                    UIPasteboard.general.string = store.currentTrainer?.inviteCode
                }

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 12) {
                        if let code = store.currentTrainer?.inviteCode {
                            inviteBanner(code: code)
                        }

                        TTSearchEntryPill(
                            placeholder: TTSearchCopy.trainees.pillPlaceholder,
                            query: displayQuery,
                            namespace: searchNS
                        ) {
                            showSearch = true
                        }

                        if filtered.isEmpty {
                            emptyCard
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
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 24)
                }
            }
            .background(canvas.ignoresSafeArea())
            .ttHideSystemNavigationBar()
            .navigationDestination(item: $selectedTrainee) { trainee in
                TraineeDetailView(trainee: trainee)
            }
            .ttSearchOverlay(
                isPresented: $showSearch,
                catalog: searchCatalog,
                namespace: searchNS,
                onOutcome: handleSearchOutcome
            )
        }
    }

    private var allTrainees: [TraineeProfile] {
        guard let trainer = store.currentTrainer else { return [] }
        return store.trainees(for: trainer)
    }

    private var searchCatalog: TTSearchCatalog {
        let names = Dictionary(uniqueKeysWithValues: allTrainees.map {
            ($0.id, store.user(forTrainee: $0)?.name ?? "Athlete")
        })
        let plansByTrainee = Dictionary(uniqueKeysWithValues: allTrainees.compactMap { trainee -> (String, String)? in
            guard let title = store.assignedPlan(for: trainee)?.title else { return nil }
            return (trainee.id, title)
        })
        let activeIds = Set(allTrainees.compactMap { trainee -> String? in
            store.logs(for: trainee.id).first != nil ? trainee.id : nil
        })
        return TTSearchCatalog.trainees(
            trainees: allTrainees,
            names: names,
            plansByTrainee: plansByTrainee,
            activeIds: activeIds,
            trainerId: store.currentTrainer?.id ?? "local",
            inviteCode: store.currentTrainer?.inviteCode
        )
    }

    private var displayQuery: String {
        if !query.isEmpty { return query }
        if let goalFilter { return goalFilter }
        return ""
    }

    private var filtered: [TraineeProfile] {
        var result = allTrainees
        if let goalFilter {
            result = result.filter { $0.goal.lowercased() == goalFilter.lowercased() }
        }
        guard !query.isEmpty else { return result }
        return result.filter {
            store.user(forTrainee: $0)?.name.localizedCaseInsensitiveContains(query) == true
                || $0.goal.localizedCaseInsensitiveContains(query)
        }
    }

    private func handleSearchOutcome(_ outcome: TTSearchOutcome) {
        switch outcome {
        case .item(let id):
            query = ""
            goalFilter = nil
            selectedTrainee = allTrainees.first { $0.id == id }
        case .category(let id):
            query = ""
            goalFilter = id
        case .offer:
            if let code = store.currentTrainer?.inviteCode {
                UIPasteboard.general.string = code
            }
        case .applyQuery(let q):
            goalFilter = nil
            query = q
        case .dismissed:
            break
        }
    }

    private func inviteBanner(code: String) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(TTColor.actionOrange.opacity(0.12))
                TTIcon(icon: .link4, filled: true, size: 18)
                    .foregroundStyle(TTColor.actionOrange)
            }
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 2) {
                Text("Invite code")
                    .font(TTFont.caption(12))
                    .foregroundStyle(TTColor.inkMuted)
                Text(code)
                    .font(TTFont.workSans(18, weight: .bold))
                    .foregroundStyle(TTColor.ink)
            }

            Spacer()

            Button {
                UIPasteboard.general.string = code
            } label: {
                Text("Copy")
                    .font(TTFont.workSans(13, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.black)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(cardFill)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func traineeRow(_ trainee: TraineeProfile) -> some View {
        let user = store.user(forTrainee: trainee)
        let plan = store.assignedPlan(for: trainee)
        let last = store.logs(for: trainee.id).first
        let active = last != nil

        return HStack(spacing: 12) {
            TTAvatar(name: user?.name ?? "T", size: 54)

            VStack(alignment: .leading, spacing: 4) {
                Text(user?.name ?? "Trainee")
                    .font(TTFont.workSans(16, weight: .bold))
                    .foregroundStyle(TTColor.ink)
                Text(plan?.title ?? "No plan assigned")
                    .font(TTFont.caption(12))
                    .foregroundStyle(TTColor.inkMuted)
                Text(trainee.goal)
                    .font(TTFont.caption(12))
                    .foregroundStyle(TTColor.inkSubtle)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 8) {
                Text(active ? "Active" : "Idle")
                    .font(TTFont.caption(11))
                    .fontWeight(.bold)
                    .foregroundStyle(active ? TTColor.success : TTColor.inkMuted)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background((active ? TTColor.success : TTColor.inkMuted).opacity(0.12))
                    .clipShape(Capsule())

                TTIcon(icon: .chevronRight, size: 14)
                    .foregroundStyle(TTColor.inkSubtle)
            }
        }
        .padding(14)
        .background(cardFill)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var emptyCard: some View {
        VStack(spacing: 12) {
            TTIcon(icon: .usersTwo, filled: true, size: 28)
                .foregroundStyle(TTColor.actionOrange)
            Text(query.isEmpty && goalFilter == nil ? "No trainees yet" : "No matches")
                .font(TTFont.workSans(17, weight: .bold))
            Text(
                query.isEmpty && goalFilter == nil
                    ? "Share your invite code so athletes can join your roster."
                    : "Try a different name."
            )
            .font(TTFont.body(14))
            .foregroundStyle(TTColor.inkMuted)
            .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(28)
        .background(cardFill)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

#Preview("My Trainees") {
    MyTraineesView()
        .ttPreviewTrainer()
}
