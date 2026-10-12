import SwiftUI

struct TrainerProfileView: View {
    @Environment(AppStore.self) private var store

    /// When opened as a sheet from Home, show the back button.
    var showsBack: Bool = false

    @State private var showPublicProfile = false
    @State private var showBoostStore = false
    @State private var showAnalytics = false
    @State private var showVerification = false
    @State private var showPackages = false

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

    var body: some View {
        TTProfileScreen(
            name: store.currentUser?.name ?? "Trainer",
            location: store.currentTrainer?.location?.nilIfBlank ?? "Add location",
            membership: store.currentTrainer?.specialty.nilIfBlank ?? "Coach",
            avatarAsset: store.displayAvatarAsset,
            avatarUrl: store.remoteAvatarURL,
            avatarUserId: store.session?.userId,
            initials: initials,
            metrics: metrics,
            showsBack: showsBack
        ) {
            VStack(alignment: .leading, spacing: 16) {
                publicProfileCard
                packagesCard
                verificationCard
                insightsCard
                boostCard
                inviteCard
            }
        }
        .sheet(isPresented: $showPublicProfile) {
            CoachPublicProfileEditorView()
                .ttModalSheetPresentation(dragIndicator: .hidden)
        }
        .sheet(isPresented: $showBoostStore) {
            TrainerBoostStoreView()
                .ttModalSheetPresentation(dragIndicator: .hidden)
        }
        .sheet(isPresented: $showAnalytics) {
            TrainerCoachAnalyticsView()
                .ttModalSheetPresentation(dragIndicator: .hidden)
        }
        .sheet(isPresented: $showVerification) {
            TrainerCoachVerificationView()
                .ttModalSheetPresentation(dragIndicator: .hidden)
        }
        .sheet(isPresented: $showPackages) {
            TrainerCoachPackagesView()
                .ttModalSheetPresentation(dragIndicator: .hidden)
        }
        .task {
            if store.session?.role == .trainer {
                await store.refreshMyBoost()
                // Recompute Sandow after Boost status resolves (boost vs roster mode).
                await store.loadSandowScore(period: store.sandowPeriod, force: true)
            }
        }
    }

    private var boostCard: some View {
        Button {
            showBoostStore = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(TTColor.actionOrange)
                    .frame(width: 40, height: 40)
                    .background(TTColor.actionOrange.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text("Get Featured")
                            .font(TTFont.heading(16))
                            .foregroundStyle(TTColor.ink)
                        if store.myBoost?.active == true || store.entitlements?.boost.active == true {
                            CoachBoostBadge()
                        }
                    }
                    Text(
                        (store.myBoost?.active == true || store.entitlements?.boost.active == true)
                            ? "You’re boosted — extend anytime."
                            : "Appear at the top of Find Coaches."
                    )
                        .font(TTFont.body(13))
                        .foregroundStyle(TTColor.inkMuted)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(TTColor.inkSubtle)
            }
            .padding(16)
            .background(Color(red: 243 / 255, green: 243 / 255, blue: 244 / 255))
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Get Featured Boost")
    }

    private var publicProfileCard: some View {
        Button {
            showPublicProfile = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "megaphone.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(TTColor.actionOrange)
                    .frame(width: 40, height: 40)
                    .background(TTColor.actionOrange.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    Text("Public profile")
                        .font(TTFont.heading(16))
                        .foregroundStyle(TTColor.ink)
                    Text("Get discovered by trainees in Find Coaches.")
                        .font(TTFont.body(13))
                        .foregroundStyle(TTColor.inkMuted)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(TTColor.inkSubtle)
            }
            .padding(16)
            .background(Color(red: 243 / 255, green: 243 / 255, blue: 244 / 255))
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var packagesCard: some View {
        Button {
            showPackages = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "shippingbox.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(TTColor.actionOrange)
                    .frame(width: 40, height: 40)
                    .background(TTColor.actionOrange.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    Text("Packages")
                        .font(TTFont.heading(16))
                        .foregroundStyle(TTColor.ink)
                    Text("List coaching offers trainees can inquire about.")
                        .font(TTFont.body(13))
                        .foregroundStyle(TTColor.inkMuted)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(TTColor.inkSubtle)
            }
            .padding(16)
            .background(Color(red: 243 / 255, green: 243 / 255, blue: 244 / 255))
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Manage Packages")
    }

    private var verificationCard: some View {
        Button {
            showVerification = true
        } label: {
            HStack(spacing: 12) {
                TTIcon(icon: .checkCircle, filled: true, size: 18)
                    .foregroundStyle(Color(hex: 0x2563EB))
                    .frame(width: 40, height: 40)
                    .background(Color(hex: 0x2563EB).opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    Text("Get verified")
                        .font(TTFont.heading(16))
                        .foregroundStyle(TTColor.ink)
                    Text("Free trust badge for your public coach profile.")
                        .font(TTFont.body(13))
                        .foregroundStyle(TTColor.inkMuted)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(TTColor.inkSubtle)
            }
            .padding(16)
            .background(Color(red: 243 / 255, green: 243 / 255, blue: 244 / 255))
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Coach Verification")
    }

    private var insightsCard: some View {
        Button {
            showAnalytics = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(TTColor.actionOrange)
                    .frame(width: 40, height: 40)
                    .background(TTColor.actionOrange.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    Text("Insights")
                        .font(TTFont.heading(16))
                        .foregroundStyle(TTColor.ink)
                    Text("Views, contacts, and Boost ROI from Find Coaches.")
                        .font(TTFont.body(13))
                        .foregroundStyle(TTColor.inkMuted)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(TTColor.inkSubtle)
            }
            .padding(16)
            .background(Color(red: 243 / 255, green: 243 / 255, blue: 244 / 255))
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Discovery Insights")
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
