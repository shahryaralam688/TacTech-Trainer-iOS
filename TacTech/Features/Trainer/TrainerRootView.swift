import SwiftUI

enum TrainerTab: Hashable {
    case dashboard, trainees, plans, progress, profile
}

struct TrainerRootView: View {
    @State private var tab: TrainerTab = .dashboard

    var body: some View {
        TabView(selection: $tab) {
            TrainerDashboardView()
                .tabItem { Label("Home", systemImage: "square.grid.2x2.fill") }
                .tag(TrainerTab.dashboard)
            MyTraineesView()
                .tabItem { Label("Trainees", systemImage: "person.2.fill") }
                .tag(TrainerTab.trainees)
            WorkoutPlansView()
                .tabItem { Label("Plans", systemImage: "list.clipboard.fill") }
                .tag(TrainerTab.plans)
            TrainerProgressView()
                .tabItem { Label("Progress", systemImage: "chart.line.uptrend.xyaxis") }
                .tag(TrainerTab.progress)
            TrainerProfileView()
                .tabItem { Label("Profile", systemImage: "person.crop.circle.fill") }
                .tag(TrainerTab.profile)
        }
    }
}
