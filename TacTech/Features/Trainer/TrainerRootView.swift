import SwiftUI

enum TrainerTab: Hashable {
    case dashboard, plans, trainees, profile
}

struct TrainerRootView: View {
    @State private var tab: TrainerTab = .dashboard
    @State private var showQuickActions = false

    private let tabs: [TTTabBarItem<TrainerTab>] = [
        TTTabBarItem(.dashboard, icon: .house1, label: "Home"),
        TTTabBarItem(.plans, icon: .barbellDiagonal, label: "Plans"),
        TTTabBarItem(.trainees, icon: .usersTwo, label: "Trainees"),
        TTTabBarItem(.profile, icon: .user, label: "Profile")
    ]

    var body: some View {
        Group {
            switch tab {
            case .dashboard:
                TrainerDashboardView()
            case .plans:
                WorkoutPlansView()
            case .trainees:
                MyTraineesView()
            case .profile:
                TrainerProfileView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            TTFloatingTabBar(
                tabs: tabs,
                selection: $tab,
                onCenterTap: { showQuickActions = true }
            )
        }
        .ignoresSafeArea(.keyboard)
        .confirmationDialog("Quick action", isPresented: $showQuickActions, titleVisibility: .visible) {
            Button("My Trainees") { tab = .trainees }
            Button("Workout Plans") { tab = .plans }
            Button("Profile") { tab = .profile }
            Button("Cancel", role: .cancel) {}
        }
    }
}
