import SwiftUI

enum TraineeTab: Hashable {
    case home, workout, nutrition, profile
}

struct TraineeRootView: View {
    @State private var tab: TraineeTab = .home
    @State private var showQuickActions = false

    private let tabs: [TTTabBarItem<TraineeTab>] = [
        TTTabBarItem(.home, icon: .house1, label: "Home"),
        TTTabBarItem(.workout, icon: .barbellDiagonal, label: "Workout"),
        TTTabBarItem(.nutrition, icon: .forkKnife, label: "Nutrition"),
        TTTabBarItem(.profile, icon: .user, label: "Profile")
    ]

    var body: some View {
        Group {
            switch tab {
            case .home:
                TraineeDashboardView()
            case .workout:
                WorkoutHubView()
            case .nutrition:
                NutritionView()
            case .profile:
                TraineeProfileView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            TTFloatingTabBar(
                tabs: tabs,
                selection: $tab,
                onCenterTap: { showQuickActions = true }
            )
            .padding(.horizontal, 18)
            .padding(.top, 4)
            .padding(.bottom, 6)
        }
        .ignoresSafeArea(.keyboard)
        .confirmationDialog("Quick action", isPresented: $showQuickActions, titleVisibility: .visible) {
            Button("Workouts") { tab = .workout }
            Button("Nutrition") { tab = .nutrition }
            Button("Profile") { tab = .profile }
            Button("Cancel", role: .cancel) {}
        }
    }
}
