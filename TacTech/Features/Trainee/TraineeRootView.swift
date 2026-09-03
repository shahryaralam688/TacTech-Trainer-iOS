import SwiftUI

enum TraineeTab: Hashable {
    case home, workout, nutrition, progress, profile
}

struct TraineeRootView: View {
    @State private var tab: TraineeTab = .home

    var body: some View {
        TabView(selection: $tab) {
            TraineeDashboardView()
                .tabItem { Label("Home", systemImage: "house.fill") }
                .tag(TraineeTab.home)
            WorkoutHubView()
                .tabItem { Label("Workout", systemImage: "dumbbell.fill") }
                .tag(TraineeTab.workout)
            NutritionView()
                .tabItem { Label("Nutrition", systemImage: "fork.knife") }
                .tag(TraineeTab.nutrition)
            TraineeProgressView()
                .tabItem { Label("Progress", systemImage: "chart.dots.scatter") }
                .tag(TraineeTab.progress)
            TraineeProfileView()
                .tabItem { Label("Profile", systemImage: "person.crop.circle.fill") }
                .tag(TraineeTab.profile)
        }
        .tint(TTColor.accent)
    }
}
