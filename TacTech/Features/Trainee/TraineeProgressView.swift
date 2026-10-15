import SwiftUI
import Charts

struct TraineeProgressView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    /// Asset Canvas ≈ #F9EBFF — Form Studio wash matches the sheet.
    private let canvasHex = "F9EBFF"

    var body: some View {
        VStack(spacing: 0) {
            TTModalSheetHeader(title: "Progress", subtitle: "Improve", background: .white)

            ScrollView {
                Group {
                    if let trainee = store.currentTrainee {
                        progressBody(trainee)
                    } else {
                        emptyState
                    }
                }
                .padding(.horizontal, TTModalSheetChrome.horizontalPadding)
                .padding(.top, TTModalSheetChrome.contentTopPadding)
                .padding(.bottom, TTModalSheetChrome.contentBottomPadding)
            }
        }
        .ttScreenBackground()
        .ttHideSystemNavigationBar()
    }

    @ViewBuilder
    private func progressBody(_ trainee: TraineeProfile) -> some View {
        let logs = store.logs(for: trainee.id)
        let reports = store.formReports(for: trainee.id)
        let bestForm = reports.map(\.score).max()
        let totalMinutes = logs.reduce(0) { $0 + $1.durationMinutes }

        VStack(alignment: .leading, spacing: 18) {
            telemetryStrip(
                sessions: logs.count,
                bestForm: bestForm,
                minutes: totalMinutes
            )

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ProgressSignalCard(
                    code: "01",
                    label: "SESSIONS",
                    value: "\(logs.count)",
                    meta: "Completed",
                    icon: .sparkle1,
                    accent: TTColor.calorie
                )
                ProgressSignalCard(
                    code: "02",
                    label: "BEST FORM",
                    value: bestForm.map(String.init) ?? "—",
                    meta: "AI score",
                    icon: .heartEcg,
                    accent: TTColor.energy
                )
            }

            progressStage

            if !logs.isEmpty {
                loadChart(logs: logs)
            }

            historySection(title: "Workout history", code: "LOG", isEmpty: logs.isEmpty, empty: "No sessions logged yet") {
                ForEach(logs) { log in
                    ProgressHistoryRow(
                        title: store.plans.first { $0.id == log.planId }?.title ?? "Workout",
                        subtitle: log.completedAt.formatted(date: .abbreviated, time: .omitted),
                        trailing: "\(log.durationMinutes) min",
                        accent: TTColor.brand
                    )
                }
            }

            historySection(title: "Form history", code: "AI", isEmpty: reports.isEmpty, empty: "No form reports yet") {
                ForEach(reports) { report in
                    ProgressHistoryRow(
                        title: store.exercise(id: report.exerciseId)?.name ?? "Exercise",
                        subtitle: report.cues.isEmpty ? "AI form check" : report.cues.joined(separator: " · "),
                        trailing: "\(report.score)",
                        accent: TTColor.energy
                    )
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Text("SIGNAL OFFLINE")
                .font(TTFont.workSans(12, weight: .bold))
                .tracking(1.4)
                .foregroundStyle(TTColor.inkMuted)
            Text("Sign in as a trainee to track progress.")
                .font(TTFont.workSans(15, weight: .medium))
                .foregroundStyle(TTColor.ink)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }

    private func telemetryStrip(sessions: Int, bestForm: Int?, minutes: Int) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(TTColor.brand)
                .frame(width: 8, height: 8)
                .shadow(color: TTColor.brand.opacity(0.45), radius: 4)

            Text("TELEMETRY · LIVE")
                .font(TTFont.workSans(11, weight: .bold))
                .tracking(1.1)
                .foregroundStyle(TTColor.ink)

            Spacer(minLength: 0)

            Text("\(sessions) SES · \(minutes) MIN · FORM \(bestForm.map(String.init) ?? "—")")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(TTColor.inkMuted)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.72))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(TTColor.line.opacity(0.7), lineWidth: 1)
        )
    }

    private var progressStage: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("COACH STAGE")
                    .font(TTFont.workSans(11, weight: .bold))
                    .tracking(1.2)
                    .foregroundStyle(TTColor.inkMuted)
                Spacer()
                Text("WARMING UP")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(TTColor.brand)
            }

            ZStack {
                TTColor.canvas
                FormStudioWebView(
                    formStudioExerciseId: "warming_up",
                    presentation: .preview,
                    previewBackgroundHex: canvasHex
                )
                .allowsHitTesting(false)
            }
            .frame(height: 220)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(TTColor.line.opacity(0.85), lineWidth: 1)
            )
            .overlay(alignment: .topLeading) {
                Text("3D · MIXAMO")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(TTColor.ink.opacity(0.45))
                    .padding(10)
            }
        }
    }

    private func loadChart(logs: [WorkoutLog]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("SESSION LOAD")
                    .font(TTFont.workSans(11, weight: .bold))
                    .tracking(1.2)
                    .foregroundStyle(TTColor.inkMuted)
                Spacer()
                Text("MIN / DAY")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(TTColor.inkMuted)
            }

            Chart {
                ForEach(logs) { log in
                    LineMark(
                        x: .value("Date", log.completedAt),
                        y: .value("Minutes", log.durationMinutes)
                    )
                    .foregroundStyle(TTColor.brand)
                    .interpolationMethod(.catmullRom)

                    AreaMark(
                        x: .value("Date", log.completedAt),
                        y: .value("Minutes", log.durationMinutes)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [TTColor.brand.opacity(0.28), TTColor.brand.opacity(0.02)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .interpolationMethod(.catmullRom)

                    PointMark(
                        x: .value("Date", log.completedAt),
                        y: .value("Minutes", log.durationMinutes)
                    )
                    .foregroundStyle(TTColor.brand)
                }
            }
            .frame(height: 168)
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 4]))
                        .foregroundStyle(TTColor.line)
                    AxisValueLabel()
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(TTColor.inkMuted)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { _ in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 4]))
                        .foregroundStyle(TTColor.line)
                    AxisValueLabel()
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(TTColor.inkMuted)
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.white.opacity(0.78))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(TTColor.line.opacity(0.8), lineWidth: 1)
            )
        }
    }

    private func historySection<Content: View>(
        title: String,
        code: String,
        isEmpty: Bool,
        empty: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(code)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(TTColor.brand)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(TTColor.brand.opacity(0.12), in: Capsule())
                Text(title)
                    .font(TTFont.workSans(16, weight: .bold))
                    .foregroundStyle(TTColor.ink)
                Spacer()
            }

            if isEmpty {
                Text(empty)
                    .font(TTFont.workSans(13, weight: .medium))
                    .foregroundStyle(TTColor.inkMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(TTColor.line.opacity(0.8), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                    )
            } else {
                content()
            }
        }
    }
}

// MARK: - System tiles

private struct ProgressSignalCard: View {
    let code: String
    let label: String
    let value: String
    let meta: String
    let icon: SandowIcon
    let accent: Color

    @State private var pulse = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(code)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(TTColor.inkMuted)
                Spacer()
                Circle()
                    .fill(accent)
                    .frame(width: 6, height: 6)
                    .scaleEffect(pulse ? 1.25 : 1)
                    .opacity(pulse ? 1 : 0.65)
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 8)

            ZStack {
                accent.opacity(0.10)
                TTIcon(icon: icon, filled: true, size: 28)
                    .foregroundStyle(accent)
                    .scaleEffect(pulse ? 1.06 : 1)
            }
            .frame(height: 72)
            .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 4) {
                Text(value)
                    .font(.system(size: 28, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
                Text(label)
                    .font(TTFont.workSans(11, weight: .bold))
                    .tracking(0.8)
                    .foregroundStyle(.white.opacity(0.9))
                Text(meta)
                    .font(TTFont.workSans(12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.65))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(TTColor.ink)
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(TTColor.line.opacity(0.5), lineWidth: 1)
        )
        .onAppear {
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }
}

private struct ProgressHistoryRow: View {
    let title: String
    let subtitle: String
    let trailing: String
    let accent: Color

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(accent)
                .frame(width: 3, height: 36)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(TTFont.workSans(15, weight: .semibold))
                    .foregroundStyle(TTColor.ink)
                    .lineLimit(1)
                Text(subtitle)
                    .font(TTFont.workSans(12, weight: .medium))
                    .foregroundStyle(TTColor.inkMuted)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            Text(trailing)
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundStyle(accent)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.78))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(TTColor.line.opacity(0.75), lineWidth: 1)
        )
    }
}

#Preview("Trainee Progress") {
    NavigationStack {
        TraineeProgressView()
            .ttPreviewTrainee()
    }
}
