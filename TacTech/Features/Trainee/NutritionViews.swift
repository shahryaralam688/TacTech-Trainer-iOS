import AVFoundation
import Charts
import ImageIO
import PhotosUI
import SwiftUI
import Vision

// MARK: - Nutrition (Today · History) — rebuilt from Design/nutrition-prototype.html
// Phase 1: header, Today | History switch, search row, Today (ring, Planned, Eaten), add/edit sheet,
// goal sheet, "Food scan" sheet. History body and the camera/analyze flow come in the next phases.

private enum NutTab { case today, history }

private enum NutHistoryRange: Int, CaseIterable, Identifiable {
    case days = 0
    case weeks = 1
    case months = 2
    var id: Int { rawValue }
    var title: LocalizedStringKey {
        switch self {
        case .days: "Days"
        case .weeks: "Weeks"
        case .months: "Months"
        }
    }
    var apiPeriod: String {
        switch self {
        case .days: "day"
        case .weeks: "week"
        case .months: "month"
        }
    }
    var fetchDays: Int {
        switch self {
        case .days: 7
        case .weeks: 42
        case .months: 60
        }
    }
}

private struct NutPhotoDraft: Identifiable, Equatable {
    let id = UUID()
    let image: UIImage
    /// The photo is a nutrition label: go straight to on-device OCR instead of the meal-photo flow.
    var isLabel = false

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
}

/// Bottom panels. Opened with the prototype's timing (0.36 s in, 0.22 s out).
private enum NutPanelKind: Identifiable, Equatable {
    case add
    case addFood(FoodKnowledge)
    case addQuery(String)
    case photo(NutPhotoDraft)
    case edit(Meal)
    case goal
    case soon

    var id: String {
        switch self {
        case .add: "add"
        case .addFood(let food): "addFood-\(food.name)"
        case .addQuery(let q): "addQuery-\(q)"
        case .photo(let draft): "photo-\(draft.id.uuidString)"
        case .edit(let meal): "edit-\(meal.id)"
        case .goal: "goal"
        case .soon: "soon"
        }
    }
}

private enum NutStyle {
    static let charcoal = Color(red: 28 / 255, green: 28 / 255, blue: 30 / 255)
    static let field = Color(red: 244 / 255, green: 244 / 255, blue: 245 / 255)      // #F4F4F5
    static let track = Color(red: 238 / 255, green: 238 / 255, blue: 240 / 255)      // #EEEEF0
    static let mute = Color(red: 107 / 255, green: 107 / 255, blue: 112 / 255)       // #6B6B70
    static let line = Color(red: 239 / 255, green: 239 / 255, blue: 241 / 255)       // #EFEFF1
    static let accentText = Color(red: 194 / 255, green: 65 / 255, blue: 12 / 255)   // #C2410C
    static let danger = Color(red: 185 / 255, green: 28 / 255, blue: 28 / 255)       // #B91C1C
    static let orange = TTColor.actionOrange
    static let ease = Animation.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.3)
    static let sheetOpen = Animation.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.36)
    static let sheetClose = Animation.easeIn(duration: 0.22)
    /// Prototype: sticky bar block above the list (12 + 50 + 8 + 56 + 8).
    static let stickyHeight: CGFloat = 134
}

// MARK: - Scroll probe (search row shrinks on scroll down, returns on scroll up)

private struct NutScrollKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

private final class NutScrollTracker {
    var rest: CGFloat?
    var last: CGFloat = 0
    var lockUntil: Date = .distantPast
}

/// Reports the scroll distance. iOS 18+ uses the scroll geometry; iOS 17 falls back to a probe on the stack
/// (a geometry probe stops updating while scrolling from iOS 18 on).
private struct NutScrollWatcher: ViewModifier {
    let onChange: (CGFloat) -> Void
    @State private var rest: CGFloat?

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.onScrollGeometryChange(for: CGFloat.self) { geo in
                geo.contentOffset.y + geo.contentInsets.top
            } action: { _, y in
                onChange(y)
            }
        } else {
            content.onPreferenceChange(NutScrollKey.self) { minY in
                if rest == nil { rest = minY }
                onChange((rest ?? minY) - minY)
            }
        }
    }
}

// MARK: - Screen

struct NutritionView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var tab: NutTab = .today
    @State private var panel: NutPanelKind?
    @State private var searchMinimized = false
    @State private var tracker = NutScrollTracker()
    @State private var toast: TTToastMessage?

    /// Load state for today's list (view-local, see CLAUDE.md loading rules).
    @State private var isLoadingDay = true
    @State private var dayLoadFailed = false
    @State private var didLoadToday = false

    @State private var historyRange: NutHistoryRange = .days
    @State private var selectedBucketIndex: Int? = nil
    @State private var barsGrown = false
    @State private var isLoadingHistory = false
    @State private var showHistorySkeleton = false
    @State private var historyLoadFailed = false
    @State private var summaryByPeriod: [NutHistoryRange: MealSummaryResponse] = [:]
    @State private var cachedHistoryBuckets: [NutHistoryBucket] = []
    @State private var loadedHistoryDays = 0

    @State private var showCamera = false
    @State private var showPhotoLibrary = false
    @State private var capturedPhoto: UIImage?
    @State private var libraryItem: PhotosPickerItem?
    @State private var pendingPhotoPanel: NutPanelKind?
    /// The next photo from the header scanner is a nutrition label.
    @State private var labelScanPending = false

    @Namespace private var searchNS
    @State private var showSearch = false

    private let canvas = Color.white

    var body: some View {
        NavigationStack {
          ScrollViewReader { proxy in
            TTCollapsingHeaderScreen(
                sheetFill: canvas,
                headerBackground: NutStyle.charcoal,
                topRadius: { _ in TTSheetChrome.pageTopRadius },
                pinsBelowCollapsedHeader: true,
                topAnchorID: "nutTop",
                onRefresh: {
                    invalidateHistoryCache()
                    await loadToday()
                    if tab == .history { await loadHistory() }
                },
                header: { progress in header(progress: progress) }
            ) {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                    Section {
                        Group {
                            switch tab {
                            case .today: todayBody
                            case .history: historyBody
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 120)
                    } header: {
                        stickyBar
                    }
                }
                // Measured on the stack itself (a probe inside the lazy content is dropped once it scrolls away).
                .background(scrollProbe)
            }
            // Today and History are different lengths: always start the other tab at the top (a kept scroll
            // position showed only the bottom of the list, which looked like the logs were gone).
            .onChange(of: tab) { _, _ in
                searchMinimized = false
                proxy.scrollTo("nutTop", anchor: .top)
            }
          }
            .modifier(NutScrollWatcher { handleScroll(y: $0) })
            .background(NutStyle.charcoal.ignoresSafeArea(edges: .top))
            .toolbar(.hidden, for: .navigationBar)
            .ttSyncRootTabBarWithNavigationDepth()
            .ttToast($toast)
            .task(id: traineeId) { await loadToday() }
            .task { await store.refreshFrequentMeals() }
            .onChange(of: traineeId) { _, _ in
                invalidateHistoryCache()
            }
            .onChange(of: store.meals.count) { _, _ in
                if tab == .history {
                    recomputeHistoryBuckets()
                }
            }
            // A meal saved from Home (or the + menu): the History summaries are out of date.
            .onReceive(NotificationCenter.default.publisher(for: .ttMealSaved)) { _ in
                invalidateHistoryCache()
            }
            .sheet(isPresented: $showCamera, onDismiss: {
                if let pending = pendingPhotoPanel {
                    pendingPhotoPanel = nil
                    openPanel(pending)
                }
            }) {
                CameraImagePicker(image: $capturedPhoto)
                    .ignoresSafeArea()
            }
            .photosPicker(isPresented: $showPhotoLibrary, selection: $libraryItem, matching: .images)
            .onChange(of: capturedPhoto) { _, newValue in
                guard let image = newValue else { return }
                capturedPhoto = nil
                let next = NutPanelKind.photo(NutPhotoDraft(image: image, isLabel: labelScanPending))
                labelScanPending = false
                if showCamera {
                    pendingPhotoPanel = next
                } else {
                    openPanel(next)
                }
            }
            .onChange(of: libraryItem) { _, item in
                guard let item else { return }
                Task {
                    defer { libraryItem = nil }
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        let next = NutPanelKind.photo(NutPhotoDraft(image: image, isLabel: labelScanPending))
                        labelScanPending = false
                        if showPhotoLibrary {
                            pendingPhotoPanel = next
                        } else {
                            openPanel(next)
                        }
                    }
                }
            }
            .onChange(of: showPhotoLibrary) { _, presented in
                if !presented, let pending = pendingPhotoPanel {
                    pendingPhotoPanel = nil
                    openPanel(pending)
                }
            }
            .ttSearchOverlay(
                isPresented: $showSearch,
                catalog: searchCatalog,
                namespace: searchNS,
                refined: true,
                onOutcome: handleSearchOutcome
            )
            .fullScreenCover(item: $panel) { kind in
                NutritionPanelHost { close in
                    panelContent(kind, close: close)
                }
                .presentationBackground(.clear)
            }
        }
    }

    // MARK: Header ("Nutrition" + label scanner)

    private func header(progress: CGFloat) -> some View {
        let p = min(1, max(0, progress))
        return HStack(alignment: .center) {
            Text("Nutrition")
                .font(TTFont.workSans(26 - 7 * p, weight: .medium))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            Menu {
                Button { labelScanPending = true; openMealCameraOrFallback() } label: { Text("Take photo") }
                Button { labelScanPending = true; showPhotoLibrary = true } label: { Text("Choose photo") }
            } label: {
                TTIcon(icon: .scan1, size: 22 - 2 * p)
                    .foregroundStyle(.white)
                    .frame(width: 44 - 4 * p, height: 44 - 4 * p)
                    .background(Color(white: 0.17))
                    .clipShape(RoundedRectangle(cornerRadius: 14 - 2 * p, style: .continuous))
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Scan nutrition label")
        }
        .padding(.horizontal, TTSpace.screen)
        .padding(.top, 14 - 4 * p)
        .padding(.bottom, 20 - 8 * p)
        .frame(maxWidth: .infinity, minHeight: TTDarkPageHeader.compactHeight + (TTDarkPageHeader.cardHeight - TTDarkPageHeader.compactHeight) * (1 - p), alignment: .bottomLeading)
        .background {
            Rectangle().fill(NutStyle.charcoal).ignoresSafeArea(edges: .top)
        }
    }

    // MARK: Sticky bar (Today | History + search row)

    private var stickyBar: some View {
        VStack(spacing: 8) {
            tabSwitch
            searchRow
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(Color.white)
        .frame(maxWidth: .infinity)
        // The slot keeps its full height so the list below never jumps when the search row shrinks.
        .frame(height: NutStyle.stickyHeight, alignment: .top)
    }

    private var tabSwitch: some View {
        HStack(spacing: 0) {
            tabButton("Today", .today)
            tabButton("History", .history)
        }
        .padding(3)
        .background(alignment: .leading) {
            GeometryReader { geo in
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white)
                    .shadow(color: .black.opacity(0.16), radius: 1.5, y: 1)
                    .frame(width: (geo.size.width - 6) / 2, height: geo.size.height - 6)
                    .offset(x: 3 + (tab == .history ? (geo.size.width - 6) / 2 : 0), y: 3)
                    .animation(reduceMotion ? nil : NutStyle.ease, value: tab)
            }
        }
        .background(NutStyle.track)
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        .accessibilityElement(children: .contain)
    }

    private func tabButton(_ title: LocalizedStringKey, _ value: NutTab) -> some View {
        Button {
            guard tab != value else { return }
            tab = value
        } label: {
            Text(title)
                .font(TTFont.workSans(15, weight: tab == value ? .semibold : .medium))
                .foregroundStyle(tab == value ? Color(white: 0.07) : Color(red: 85 / 255, green: 85 / 255, blue: 91 / 255))
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(tab == value ? .isSelected : [])
    }

    private var searchRow: some View {
        HStack(spacing: 8) {
            TTSearchEntryPill(
                placeholder: String(localized: "Add food or drink"),
                namespace: searchNS
            ) {
                showSearch = true
            }

            Button {
                openMealCameraOrFallback()
            } label: {
                TTIcon(icon: .camera1, size: 20)
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .background(NutStyle.orange)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add food photo")
        }
        .frame(height: searchMinimized ? 0 : 48, alignment: .top)
        .opacity(searchMinimized ? 0 : 1)
        .clipped()
        .allowsHitTesting(!searchMinimized)
        .accessibilityHidden(searchMinimized)
        .animation(reduceMotion ? nil : .timingCurve(0.2, 0.8, 0.2, 1, duration: 0.28), value: searchMinimized)
    }

    private func openMealCameraOrFallback() {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            showPhotoLibrary = true
            return
        }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            showCamera = true
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    if granted {
                        showCamera = true
                    } else {
                        toast = TTToastMessage(text: "Camera access is off — choose a photo from your library.", style: .error)
                        showPhotoLibrary = true
                    }
                }
            }
        case .denied, .restricted:
            toast = TTToastMessage(text: "Camera access is off — choose a photo from your library.", style: .error)
            showPhotoLibrary = true
        @unknown default:
            showPhotoLibrary = true
        }
    }

    private var scrollProbe: some View {
        Color.clear
            .frame(height: 0)
            .background(GeometryReader { geo in
                Color.clear.preference(key: NutScrollKey.self, value: geo.frame(in: .scrollView).minY)
            })
            .accessibilityHidden(true)
    }

    /// `y` = how far the list has scrolled up (0 at rest, negative while pulling down).
    private func handleScroll(y: CGFloat) {
        let t = tracker
        let dy = y - t.last
        t.last = y
        guard Date() >= t.lockUntil else { return }
        if y > 70, dy > 3, !searchMinimized {
            searchMinimized = true
            t.lockUntil = Date().addingTimeInterval(0.4)
        } else if (dy < -6 || y <= 10), searchMinimized {
            searchMinimized = false
            t.lockUntil = Date().addingTimeInterval(0.4)
        }
    }

    // MARK: Today

    private var traineeId: String? { store.currentTrainee?.id }
    private var goal: Int { store.currentTrainee?.dailyCalorieTarget ?? 0 }

    private var todaysMeals: [Meal] {
        guard let traineeId else { return [] }
        return store.meals(for: traineeId, on: Date())
    }

    private var planned: [Meal] { todaysMeals.filter(\.isPlanned).sorted { $0.eatenAt < $1.eatenAt } }
    private var eaten: [Meal] { todaysMeals.filter { !$0.isPlanned }.sorted { $0.eatenAt > $1.eatenAt } }

    private var hasData: Bool { !todaysMeals.isEmpty || didLoadToday }

    private static let placeholder = Meal(
        id: "placeholder", traineeId: "", name: "Meal name", eatenAt: Date(timeIntervalSince1970: 0),
        portionGrams: 0, macros: MacroEstimate(calories: 0, protein: 0, carbs: 0, fat: 0),
        source: "", isEstimate: false
    )

    @ViewBuilder
    private var todayBody: some View {
        if dayLoadFailed, hasData, !todaysMeals.isEmpty {
            TTStaleNotice { Task { await loadToday() } }
                .padding(.bottom, 8)
        }
        TTLoadGate(
            isLoading: !didLoadToday || isLoadingDay,
            hasData: !todaysMeals.isEmpty,
            loadingLabel: "Loading your meals"
        ) {
            VStack(alignment: .leading, spacing: 0) {
                todayCard(eaten: [], planned: [])
                listsSection(planned: [Self.placeholder], eaten: [Self.placeholder, Self.placeholder])
            }
            .ttSkeleton()
        } content: {
            if dayLoadFailed, todaysMeals.isEmpty {
                TTLoadError(title: "Couldn’t load your meals") { Task { await loadToday() } }
                    .padding(.top, 24)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    todayCard(eaten: eaten, planned: planned)
                    listsSection(planned: planned, eaten: eaten)
                }
            }
        }
    }

    private func todayCard(eaten: [Meal], planned: [Meal]) -> some View {
        let e = eaten.reduce(0) { $0 + $1.macros.calories }
        let pl = planned.reduce(0) { $0 + $1.macros.calories }
        let prot = eaten.reduce(0.0) { $0 + $1.macros.protein }
        let carb = eaten.reduce(0.0) { $0 + $1.macros.carbs }
        let fat = eaten.reduce(0.0) { $0 + $1.macros.fat }
        let g = goal
        let pe = g > 0 ? min(1, Double(e) / Double(g)) : 0
        let pp = g > 0 ? min(1, Double(e + pl) / Double(g)) : 0
        let left = max(0, g - e)
        // TODO: the backend has no protein/carbs/fat targets (only the calorie goal). The bars show each macro's
        // share of the grams eaten instead of "x / target".
        let macroSum = max(prot + carb + fat, 0.0001)

        return ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: 0) {
                Text("TODAY")
                    .font(TTFont.workSans(12, weight: .semibold))
                    .tracking(1.7)
                    .opacity(0.9)
                HStack(spacing: 16) {
                    NutRing(eaten: pe, planned: pp, reduceMotion: reduceMotion)
                        .frame(width: 104, height: 104)
                    VStack(alignment: .leading, spacing: 2) {
                        if g > 0 {
                            Text("\(left) kcal left")
                                .font(TTFont.workSans(26, weight: .semibold))
                                .minimumScaleFactor(0.7)
                                .lineLimit(1)
                        } else {
                            Text("\(e) kcal eaten")
                                .font(TTFont.workSans(26, weight: .semibold))
                                .minimumScaleFactor(0.7)
                                .lineLimit(1)
                        }
                        summaryLine(eaten: e, planned: pl, goal: g)
                            .font(TTFont.workSans(13, weight: .regular))
                            .opacity(0.95)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.top, 8)
                HStack(spacing: 10) {
                    macroBar("Protein", value: prot, share: prot / macroSum)
                    macroBar("Carbs", value: carb, share: carb / macroSum)
                    macroBar("Fat", value: fat, share: fat / macroSum)
                }
                .padding(.top, 14)
            }
            .foregroundStyle(.white)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)

            Button { openPanel(.goal) } label: {
                TTIcon(icon: .gear1, size: 20)
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(Color.white.opacity(0.2))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(10)
            .accessibilityLabel("Change calorie goal")
        }
        .background(NutStyle.orange)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .padding(.top, 10)
    }

    private func summaryLine(eaten: Int, planned: Int, goal: Int) -> Text {
        var t = Text("\(eaten) eaten")
        if planned > 0 { t = t + Text(verbatim: " · ") + Text("+\(planned) planned") }
        if goal > 0 { t = t + Text(verbatim: " · ") + Text("goal \(goal)") }
        return t
    }

    private func macroBar(_ title: LocalizedStringKey, value: Double, share: Double) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(title)
                Spacer(minLength: 2)
                Text(verbatim: "\(Int(value.rounded())) g")
            }
            .font(TTFont.workSans(12, weight: .regular))
            .monospacedDigit()
            .opacity(0.95)
            Capsule()
                .fill(Color.white.opacity(0.28))
                .frame(height: 6)
                .overlay(alignment: .leading) {
                    GeometryReader { geo in
                        Capsule().fill(Color.white)
                            .frame(width: geo.size.width * min(1, max(0, share)))
                            .animation(reduceMotion ? nil : .timingCurve(0.2, 0.8, 0.2, 1, duration: 0.5), value: share)
                    }
                }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private func listsSection(planned: [Meal], eaten: [Meal]) -> some View {
        let pl = planned.reduce(0) { $0 + $1.macros.calories }
        let e = eaten.reduce(0) { $0 + $1.macros.calories }
        return VStack(alignment: .leading, spacing: 0) {
            sectionTitle("Planned", trailing: pl > 0 ? Text("+\(pl) kcal") : nil)
            if planned.isEmpty {
                Text("Nothing planned. Use search, then choose Plan it.")
                    .font(TTFont.body(14)).foregroundStyle(NutStyle.mute)
                    .padding(.horizontal, 2).padding(.bottom, 10)
            } else {
                ForEach(Array(planned.enumerated()), id: \.element.id) { i, meal in
                    entryRow(meal, first: i == 0)
                }
            }
            sectionTitle("Eaten today", trailing: Text("\(e) kcal"))
            if eaten.isEmpty {
                Text("Nothing logged yet.")
                    .font(TTFont.body(14)).foregroundStyle(NutStyle.mute)
                    .padding(.horizontal, 2).padding(.bottom, 10)
            } else {
                ForEach(Array(eaten.enumerated()), id: \.element.id) { i, meal in
                    entryRow(meal, first: i == 0)
                }
            }
        }
    }

    private func sectionTitle(_ title: LocalizedStringKey, trailing: Text?) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(TTFont.workSans(20, weight: .semibold))
                .foregroundStyle(TTColor.ink)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            if let trailing {
                trailing
                    .font(TTFont.workSans(14, weight: .medium))
                    .foregroundStyle(NutStyle.mute)
            }
        }
        .padding(.top, 18)
        .padding(.horizontal, 2)
        .padding(.bottom, 8)
    }

    private func entryRow(_ meal: Meal, first: Bool) -> some View {
        let isPlanned = meal.isPlanned
        let time = meal.eatenAt.formatted(date: .omitted, time: .shortened)
        let detail = meal.detail ?? (meal.portionGrams > 0 ? "\(Int(meal.portionGrams)) g" : "")
        return HStack(spacing: 0) {
            Button {
                if meal.id != "placeholder" { openPanel(.edit(meal)) }
            } label: {
                HStack(spacing: 10) {
                    NutTile(name: meal.name, kind: meal.kind, planned: isPlanned, hasPhoto: meal.photoUrl != nil)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(verbatim: meal.name)
                            .font(TTFont.workSans(16, weight: .semibold))
                            .foregroundStyle(TTColor.ink)
                            .lineLimit(1)
                        Text(verbatim: [detail, (isPlanned ? "\(String(localized: "Planned")) " : "") + time]
                            .filter { !$0.isEmpty }.joined(separator: " · "))
                            .font(TTFont.workSans(13, weight: .regular))
                            .foregroundStyle(NutStyle.mute)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    Group {
                        if meal.macros.calories == 0, meal.source == "custom" {
                            Text(verbatim: "— kcal")
                        } else {
                            Text("\(meal.macros.calories) kcal")
                        }
                    }
                    .font(TTFont.workSans(14, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(TTColor.ink)
                }
                .padding(.vertical, 6)
                .frame(minHeight: 64)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Edit \(meal.name)"))
            .accessibilityValue(Text(verbatim: "\(meal.macros.calories) kcal, \(time)"))

            if isPlanned {
                Button { Task { await markEaten(meal) } } label: {
                    Circle()
                        .stroke(NutStyle.orange, lineWidth: 2)
                        .background(Circle().fill(Color.white))
                        .frame(width: 44, height: 44)
                        .overlay { TTIcon(icon: .check, size: 20).foregroundStyle(NutStyle.orange) }
                }
                .buttonStyle(.plain)
                .padding(.leading, 4)
                .accessibilityLabel(Text("Mark \(meal.name) as eaten"))
            }
        }
        .overlay(alignment: .top) {
            if !first { Rectangle().fill(NutStyle.line).frame(height: 1) }
        }
    }

    private struct NutHistoryBucket: Identifiable {
        let id: String
        let shortLabel: String
        let title: String
        let daysLogged: Int
        let avgCalories: Int
        let totalCalories: Int
        let daysOverGoal: Int
        let avgProtein: Double
        let avgCarbs: Double
        let avgFat: Double
        let meals: [Meal]
    }

    private func recomputeHistoryBuckets() {
        cachedHistoryBuckets = computeHistoryBuckets()
    }

    private func invalidateHistoryCache() {
        summaryByPeriod.removeAll()
        loadedHistoryDays = 0
        cachedHistoryBuckets = []
        historyLoadFailed = false
        if tab == .history {
            recomputeHistoryBuckets()
        }
    }

    private func computeHistoryBuckets() -> [NutHistoryBucket] {
        if let remoteBuckets = summaryByPeriod[historyRange]?.buckets, !remoteBuckets.isEmpty {
            return remoteBuckets.enumerated().map { idx, b in
                let meals = (b.meals ?? []).filter { !$0.isPlanned }.sorted { $0.eatenAt > $1.eatenAt }
                let avg = b.avgCalories ?? b.totalCalories ?? 0
                let total = b.totalCalories ?? (avg * max(1, b.daysLogged ?? 1))
                return NutHistoryBucket(
                    id: "remote-\(historyRange.rawValue)-\(idx)",
                    shortLabel: b.label,
                    title: b.title ?? b.label,
                    daysLogged: b.daysLogged ?? (meals.isEmpty ? 0 : 1),
                    avgCalories: avg,
                    totalCalories: total,
                    daysOverGoal: b.daysOverGoal ?? 0,
                    avgProtein: b.avgProtein ?? meals.reduce(0.0) { $0 + $1.macros.protein },
                    avgCarbs: b.avgCarbs ?? meals.reduce(0.0) { $0 + $1.macros.carbs },
                    avgFat: b.avgFat ?? meals.reduce(0.0) { $0 + $1.macros.fat },
                    meals: meals
                )
            }
        }
        guard let id = traineeId else { return [] }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let allEaten = store.meals.filter { $0.traineeId == id && !$0.isPlanned }

        switch historyRange {
        case .days:
            return (0..<7).reversed().compactMap { offset -> NutHistoryBucket? in
                guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
                let dayMeals = allEaten.filter { calendar.isDate($0.eatenAt, inSameDayAs: date) }
                    .sorted { $0.eatenAt > $1.eatenAt }
                let kcal = dayMeals.reduce(0) { $0 + $1.macros.calories }
                let p = dayMeals.reduce(0.0) { $0 + $1.macros.protein }
                let c = dayMeals.reduce(0.0) { $0 + $1.macros.carbs }
                let f = dayMeals.reduce(0.0) { $0 + $1.macros.fat }
                let short = offset == 0 ? String(localized: "Today") : date.formatted(.dateTime.weekday(.abbreviated))
                let title: String
                if offset == 0 {
                    title = String(localized: "Today so far")
                } else if offset == 1 {
                    title = String(localized: "Yesterday, ") + date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
                } else {
                    title = date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
                }
                return NutHistoryBucket(
                    id: "day-\(offset)",
                    shortLabel: short,
                    title: title,
                    daysLogged: dayMeals.isEmpty ? 0 : 1,
                    avgCalories: kcal,
                    totalCalories: kcal,
                    daysOverGoal: (goal > 0 && kcal > goal) ? 1 : 0,
                    avgProtein: p,
                    avgCarbs: c,
                    avgFat: f,
                    meals: dayMeals
                )
            }

        case .weeks:
            let startOfThisWeek = calendar.dateInterval(of: .weekOfYear, for: today)?.start ?? today
            return (0..<6).reversed().compactMap { weekOffset -> NutHistoryBucket? in
                guard let weekStart = calendar.date(byAdding: .weekOfYear, value: -weekOffset, to: startOfThisWeek),
                      let weekEnd = calendar.date(byAdding: .day, value: 6, to: weekStart) else { return nil }
                let weekMeals = allEaten.filter { $0.eatenAt >= weekStart && $0.eatenAt <= min(Date(), calendar.date(bySettingHour: 23, minute: 59, second: 59, of: weekEnd) ?? weekEnd) }
                let byDay = Dictionary(grouping: weekMeals) { calendar.startOfDay(for: $0.eatenAt) }
                let dayTotals = byDay.values.map { meals in
                    (
                        kcal: meals.reduce(0) { $0 + $1.macros.calories },
                        p: meals.reduce(0.0) { $0 + $1.macros.protein },
                        c: meals.reduce(0.0) { $0 + $1.macros.carbs },
                        f: meals.reduce(0.0) { $0 + $1.macros.fat }
                    )
                }
                let logged = dayTotals.count
                let totalKcal = dayTotals.reduce(0) { $0 + $1.kcal }
                let avgKcal = logged > 0 ? totalKcal / logged : 0
                let over = goal > 0 ? dayTotals.filter { $0.kcal > goal }.count : 0
                let short = weekOffset == 0 ? String(localized: "This wk") : weekStart.formatted(.dateTime.day().month(.abbreviated))
                let title = weekOffset == 0
                    ? "\(weekStart.formatted(.dateTime.weekday(.abbreviated).day())) – \(String(localized: "today"))"
                    : "\(weekStart.formatted(.dateTime.day().month(.abbreviated))) – \(weekEnd.formatted(.dateTime.day().month(.abbreviated)))"
                return NutHistoryBucket(
                    id: "wk-\(weekOffset)",
                    shortLabel: short,
                    title: title,
                    daysLogged: logged,
                    avgCalories: avgKcal,
                    totalCalories: totalKcal,
                    daysOverGoal: over,
                    avgProtein: logged > 0 ? dayTotals.reduce(0) { $0 + $1.p } / Double(logged) : 0,
                    avgCarbs: logged > 0 ? dayTotals.reduce(0) { $0 + $1.c } / Double(logged) : 0,
                    avgFat: logged > 0 ? dayTotals.reduce(0) { $0 + $1.f } / Double(logged) : 0,
                    meals: weekMeals
                )
            }

        case .months:
            let startOfThisMonth = calendar.dateInterval(of: .month, for: today)?.start ?? today
            return (0..<6).reversed().compactMap { monthOffset -> NutHistoryBucket? in
                guard let monthStart = calendar.date(byAdding: .month, value: -monthOffset, to: startOfThisMonth),
                      let monthInterval = calendar.dateInterval(of: .month, for: monthStart) else { return nil }
                let monthMeals = allEaten.filter { $0.eatenAt >= monthInterval.start && $0.eatenAt < monthInterval.end }
                let byDay = Dictionary(grouping: monthMeals) { calendar.startOfDay(for: $0.eatenAt) }
                let dayTotals = byDay.values.map { meals in
                    (
                        kcal: meals.reduce(0) { $0 + $1.macros.calories },
                        p: meals.reduce(0.0) { $0 + $1.macros.protein },
                        c: meals.reduce(0.0) { $0 + $1.macros.carbs },
                        f: meals.reduce(0.0) { $0 + $1.macros.fat }
                    )
                }
                let logged = dayTotals.count
                let totalKcal = dayTotals.reduce(0) { $0 + $1.kcal }
                let avgKcal = logged > 0 ? totalKcal / logged : 0
                let over = goal > 0 ? dayTotals.filter { $0.kcal > goal }.count : 0
                let short = monthStart.formatted(.dateTime.month(.abbreviated))
                let title = monthOffset == 0
                    ? "\(monthStart.formatted(.dateTime.month(.wide))) \(String(localized: "so far"))"
                    : monthStart.formatted(.dateTime.month(.wide).year())
                return NutHistoryBucket(
                    id: "mo-\(monthOffset)",
                    shortLabel: short,
                    title: title,
                    daysLogged: logged,
                    avgCalories: avgKcal,
                    totalCalories: totalKcal,
                    daysOverGoal: over,
                    avgProtein: logged > 0 ? dayTotals.reduce(0) { $0 + $1.p } / Double(logged) : 0,
                    avgCarbs: logged > 0 ? dayTotals.reduce(0) { $0 + $1.c } / Double(logged) : 0,
                    avgFat: logged > 0 ? dayTotals.reduce(0) { $0 + $1.f } / Double(logged) : 0,
                    meals: monthMeals
                )
            }
        }
    }

    private var historyBody: some View {
        let buckets = cachedHistoryBuckets
        let activeIndex = min(selectedBucketIndex ?? max(0, buckets.count - 1), max(0, buckets.count - 1))
        let selected = buckets.isEmpty ? nil : buckets[activeIndex]
        let nonZero = buckets.filter { $0.avgCalories > 0 }
        let avgAll = nonZero.isEmpty ? 0 : nonZero.reduce(0) { $0 + $1.avgCalories } / nonZero.count
        let onTarget = goal > 0 ? buckets.filter { $0.avgCalories > 0 && $0.avgCalories <= goal }.count : 0
        let highest = buckets.max(by: { $0.avgCalories < $1.avgCalories })

        return VStack(alignment: .leading, spacing: 10) {
            if showHistorySkeleton && buckets.allSatisfy({ $0.meals.isEmpty && $0.avgCalories == 0 }) {
                VStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .fill(NutStyle.orange.opacity(0.25))
                        .frame(height: 310)
                    HStack(spacing: 8) {
                        ForEach(0..<3, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(NutStyle.field)
                                .frame(height: 68)
                        }
                    }
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(NutStyle.field)
                        .frame(height: 150)
                }
                .redacted(reason: .placeholder)
                .padding(.top, 10)
            } else if historyLoadFailed && buckets.allSatisfy({ $0.meals.isEmpty && $0.avgCalories == 0 }) {
                TTLoadError(
                    title: "Couldn’t load history",
                    message: "Check your connection and try again."
                ) {
                    Task { await loadHistory() }
                }
                .padding(.top, 24)
            } else if let selected {
                historyHeroCard(buckets: buckets, selectedIndex: activeIndex, selected: selected)
                historyStatsRow(
                    avgKcal: avgAll,
                    onTargetText: "\(onTarget) of \(max(1, nonZero.count))",
                    highestLabel: highest?.avgCalories ?? 0 > 0 ? (highest?.shortLabel ?? "—") : "—"
                )
                historyDetailCard(selected: selected)
            }
        }
        .task(id: historyRange) {
            barsGrown = false
            await loadHistory()
            withAnimation(reduceMotion ? nil : .timingCurve(0.2, 0.8, 0.2, 1, duration: 0.7)) {
                barsGrown = true
            }
        }
    }

    private func historyHeroCard(buckets: [NutHistoryBucket], selectedIndex: Int, selected: NutHistoryBucket) -> some View {
        let maxBar = max(Double(max(goal, 1)) * 1.25, Double(buckets.map(\.avgCalories).max() ?? 0) * 1.12)
        let goalRatio = goal > 0 ? min(1.0, Double(goal) / maxBar) : 0
        let diff = selected.avgCalories - goal
        let isOver = goal > 0 && diff > 0

        return VStack(alignment: .leading, spacing: 0) {
            // Sliding Days | Weeks | Months pill switch
            HStack(spacing: 0) {
                ForEach(NutHistoryRange.allCases) { range in
                    Button {
                        guard historyRange != range else { return }
                        selectedBucketIndex = nil
                        barsGrown = false
                        withAnimation(reduceMotion ? nil : NutStyle.ease) {
                            historyRange = range
                        }
                    } label: {
                        Text(range.title)
                            .font(TTFont.workSans(14, weight: .semibold))
                            .foregroundStyle(historyRange == range ? NutStyle.accentText : .white)
                            .frame(maxWidth: .infinity, minHeight: 40)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(3)
            .background(alignment: .leading) {
                GeometryReader { geo in
                    Capsule()
                        .fill(Color.white)
                        .frame(width: (geo.size.width - 6) / 3, height: geo.size.height - 6)
                        .offset(x: 3 + CGFloat(historyRange.rawValue) * ((geo.size.width - 6) / 3), y: 3)
                        .animation(reduceMotion ? nil : NutStyle.ease, value: historyRange)
                }
            }
            .background(Color.white.opacity(0.22))
            .clipShape(Capsule())

            Text(verbatim: selected.title)
                .font(TTFont.workSans(13, weight: .medium))
                .foregroundStyle(.white.opacity(0.95))
                .padding(.top, 12)

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                NutCountUpText(
                    target: selected.avgCalories,
                    suffix: historyRange == .days ? " kcal" : " kcal / day",
                    reduceMotion: reduceMotion
                )
                .font(TTFont.workSans(34, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(.white)
            }
            .padding(.top, 2)

            if goal > 0 {
                Text(isOver
                     ? "\(diff.formatted()) kcal over goal"
                     : "\(abs(diff).formatted()) kcal under goal")
                    .font(TTFont.workSans(12, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(isOver ? NutStyle.charcoal : Color.white.opacity(0.22))
                    .clipShape(Capsule())
                    .padding(.top, 4)
            }

            // Interactive animated bars + dashed goal line
            ZStack(alignment: .bottom) {
                if goal > 0 {
                    GeometryReader { geo in
                        let barAreaHeight = geo.size.height - 24
                        let yOffset = barAreaHeight * (1 - goalRatio)
                        ZStack(alignment: .topTrailing) {
                            Path { path in
                                path.move(to: CGPoint(x: 0, y: 0))
                                path.addLine(to: CGPoint(x: geo.size.width, y: 0))
                            }
                            .stroke(Color.white.opacity(0.75), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                            .frame(height: 2)

                            Text("Goal \(goal.formatted())")
                                .font(TTFont.workSans(11, weight: .medium))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(NutStyle.orange)
                                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                .offset(y: -16)
                        }
                        .offset(y: yOffset)
                    }
                    .allowsHitTesting(false)
                }

                HStack(alignment: .bottom, spacing: 6) {
                    ForEach(Array(buckets.enumerated()), id: \.element.id) { index, bucket in
                        let isSelected = index == selectedIndex
                        let over = goal > 0 && bucket.avgCalories > goal
                        let ratio = maxBar > 0 ? min(1.0, Double(bucket.avgCalories) / maxBar) : 0
                        Button {
                            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
                                selectedBucketIndex = index
                            }
                        } label: {
                            VStack(spacing: 4) {
                                GeometryReader { barGeo in
                                    let targetH = max(bucket.avgCalories > 0 ? 6 : 0, barGeo.size.height * ratio)
                                    VStack {
                                        Spacer(minLength: 0)
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .fill(over ? NutStyle.charcoal : Color.white)
                                            .opacity(isSelected ? 1.0 : (over ? 0.6 : 0.5))
                                            .frame(maxWidth: 36)
                                            .frame(height: barsGrown ? targetH : 0)
                                            .animation(
                                                reduceMotion ? nil : .timingCurve(0.2, 0.8, 0.2, 1, duration: 0.7).delay(Double(index) * 0.045),
                                                value: barsGrown
                                            )
                                    }
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                }
                                .frame(height: 140)

                                Text(verbatim: bucket.shortLabel)
                                    .font(TTFont.workSans(11, weight: isSelected ? .semibold : .regular))
                                    .foregroundStyle(isSelected ? .white : .white.opacity(0.85))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.75)
                                    .frame(height: 20)
                            }
                            .frame(maxWidth: .infinity)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(height: 164)
            .padding(.top, 12)
        }
        .padding(14)
        .background(NutStyle.orange)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .padding(.top, 10)
    }

    private func historyStatsRow(avgKcal: Int, onTargetText: String, highestLabel: String) -> some View {
        HStack(spacing: 8) {
            historyStatTile(value: avgKcal.formatted(), label: "average kcal")
            historyStatTile(value: onTargetText, label: "on target")
            historyStatTile(value: highestLabel, label: "highest")
        }
    }

    private func historyStatTile(value: String, label: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: value)
                .font(TTFont.workSans(18, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(TTColor.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(label)
                .font(TTFont.workSans(12, weight: .regular))
                .foregroundStyle(NutStyle.mute)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(NutStyle.field)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func historyDetailCard(selected: NutHistoryBucket) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if historyRange == .days {
                Text("What you ate")
                    .font(TTFont.workSans(13, weight: .medium))
                    .foregroundStyle(NutStyle.mute)
                if selected.meals.isEmpty {
                    Text("Nothing logged yet.")
                        .font(TTFont.body(14))
                        .foregroundStyle(NutStyle.mute)
                        .padding(.vertical, 4)
                } else {
                    ForEach(Array(selected.meals.enumerated()), id: \.element.id) { idx, meal in
                        entryRow(meal, first: idx == 0)
                    }
                }
            } else {
                Text("Total \(selected.totalCalories.formatted()) kcal · \(selected.daysLogged) days logged · over goal on \(selected.daysOverGoal) of \(selected.daysLogged) days")
                    .font(TTFont.workSans(13, weight: .regular))
                    .foregroundStyle(NutStyle.mute)
                Text("Average per day")
                    .font(TTFont.workSans(13, weight: .medium))
                    .foregroundStyle(NutStyle.mute)
                    .padding(.top, 4)
                HStack(spacing: 10) {
                    historyMacroBar("Protein", value: selected.avgProtein, share: selected.avgProtein / 120)
                    historyMacroBar("Carbs", value: selected.avgCarbs, share: selected.avgCarbs / 170)
                    historyMacroBar("Fat", value: selected.avgFat, share: selected.avgFat / 55)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(NutStyle.field)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: selected.id)
    }

    private func historyMacroBar(_ title: LocalizedStringKey, value: Double, share: Double) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(title)
                Spacer(minLength: 2)
                Text(verbatim: "\(Int(value.rounded())) g").monospacedDigit()
            }
            .font(TTFont.workSans(12, weight: .medium))
            .foregroundStyle(TTColor.ink)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(red: 228 / 255, green: 228 / 255, blue: 231 / 255))
                    Capsule().fill(NutStyle.orange)
                        .frame(width: geo.size.width * min(1, max(0, share)))
                        .animation(reduceMotion ? nil : .timingCurve(0.2, 0.8, 0.2, 1, duration: 0.5), value: value)
                }
            }
            .frame(height: 6)
        }
    }

    private func loadHistory() async {
        guard let id = traineeId else {
            recomputeHistoryBuckets()
            return
        }
        let range = historyRange
        if summaryByPeriod[range] != nil {
            recomputeHistoryBuckets()
            return
        }

        isLoadingHistory = true
        historyLoadFailed = false
        var skeletonShownAt: Date?
        let skeletonTask = Task {
            try? await Task.sleep(nanoseconds: 200_000_000)
            if !Task.isCancelled && isLoadingHistory {
                skeletonShownAt = Date()
                showHistorySkeleton = true
            }
        }
        defer {
            skeletonTask.cancel()
            isLoadingHistory = false
            showHistorySkeleton = false
        }

        var hadSuccess = false
        if let summary = await store.fetchMealSummary(period: range.apiPeriod),
           !(summary.buckets ?? []).isEmpty {
            if !Task.isCancelled {
                summaryByPeriod[range] = summary
                hadSuccess = true
            }
        } else {
            let targetDays = range.fetchDays
            if loadedHistoryDays < targetDays {
                let calendar = Calendar.current
                let today = calendar.startOfDay(for: Date())
                let start = loadedHistoryDays
                let anyOk = await withTaskGroup(of: Bool.self) { group in
                    for offset in start..<targetDays {
                        guard let dayStart = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
                        let queryDate = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: dayStart) ?? dayStart
                        group.addTask {
                            await store.refreshDay(for: id, on: queryDate)
                        }
                    }
                    var ok = false
                    for await result in group where result { ok = true }
                    return ok
                }
                if !Task.isCancelled {
                    if anyOk {
                        loadedHistoryDays = max(loadedHistoryDays, targetDays)
                        hadSuccess = true
                    }
                }
            } else {
                hadSuccess = true
            }
        }

        if let shownAt = skeletonShownAt {
            let elapsed = Date().timeIntervalSince(shownAt)
            if elapsed < 0.4 {
                try? await Task.sleep(nanoseconds: UInt64((0.4 - elapsed) * 1_000_000_000))
            }
        }
        if !Task.isCancelled {
            recomputeHistoryBuckets()
            if !hadSuccess && cachedHistoryBuckets.allSatisfy({ $0.meals.isEmpty && $0.avgCalories == 0 }) {
                historyLoadFailed = true
            }
        }
    }

    // MARK: Data

    private func loadToday() async {
        guard let id = traineeId else { isLoadingDay = false; return }
        isLoadingDay = true
        dayLoadFailed = false
        let ok = await store.refreshDay(for: id, on: Date())
        if Task.isCancelled { return }
        dayLoadFailed = !ok
        if ok { didLoadToday = true }
        isLoadingDay = false
    }

    private func markEaten(_ meal: Meal) async {
        let previous = meal
        do {
            // The server sets the eaten time to now.
            let updated = try await store.updateMeal(meal, changes: UpdateMealBody(status: "eaten"))
            invalidateHistoryCache()
            let time = updated.eatenAt.formatted(date: .omitted, time: .shortened)
            toast = TTToastMessage(
                text: String(format: String(localized: "%@ eaten · %@"), updated.name, time),
                style: .success,
                action: TTToastAction(title: String(localized: "Undo")) {
                    Task { await self.revert(previous) }
                }
            )
            UIAccessibility.post(notification: .announcement, argument: toast?.text)
        } catch {
            toast = errorToast(error, fallback: "Couldn’t save entry")
        }
    }

    private func revert(_ meal: Meal) async {
        do {
            try await store.updateMeal(meal, changes: UpdateMealBody(eatenAt: meal.eatenAt, status: meal.status ?? "eaten"))
            invalidateHistoryCache()
        } catch {
            toast = errorToast(error, fallback: "Couldn’t save entry")
        }
    }

    private func delete(_ meal: Meal) async {
        do {
            try await store.deleteMeal(meal)
            invalidateHistoryCache()
            toast = TTToastMessage(
                text: String(format: String(localized: "Deleted %@"), meal.name),
                style: .success,
                action: TTToastAction(title: String(localized: "Undo")) {
                    Task { await self.restore(meal) }
                }
            )
            UIAccessibility.post(notification: .announcement, argument: toast?.text)
        } catch {
            toast = errorToast(error, fallback: "Couldn’t delete entry")
        }
    }

    private func restore(_ meal: Meal) async {
        do {
            try await store.saveMeal(meal)
            invalidateHistoryCache()
        } catch {
            toast = errorToast(error, fallback: "Couldn’t save entry")
        }
    }

    private func errorToast(_ error: Error, fallback: String) -> TTToastMessage {
        let detail = error.localizedDescription
        return TTToastMessage(text: detail.isEmpty ? String(localized: String.LocalizationValue(fallback)) : detail, style: .error)
    }

    // MARK: Search

    private var searchCatalog: TTSearchCatalog {
        let drinksCount = store.foodCatalog.filter { NutKind.infer(name: $0.name, keywords: $0.keywords) == .drink }.count
        let piecesCount = store.foodCatalog.filter { NutKind.infer(name: $0.name, keywords: $0.keywords) == .piece }.count
        let platesCount = store.foodCatalog.filter { NutKind.infer(name: $0.name, keywords: $0.keywords) == .plate }.count
        let categories: [(id: String, name: String, count: Int, icon: SandowIcon)] = [
            (id: "plate", name: String(localized: "Meals"), count: platesCount, icon: .forkKnife),
            (id: "piece", name: String(localized: "Snacks"), count: piecesCount, icon: .apple),
            (id: "drink", name: String(localized: "Drinks"), count: drinksCount, icon: .coffee)
        ]
        return TTSearchCatalog.foods(
            catalog: store.foodCatalog,
            categories: categories,
            scopeId: "nutrition",
            offerTitle: String(localized: "Add custom food"),
            offerSubtitle: String(localized: "Log calories, protein, carbs and fat")
        )
    }

    private func handleSearchOutcome(_ outcome: TTSearchOutcome) {
        switch outcome {
        case .item(let id):
            if let food = store.foodCatalog.first(where: { $0.name == id }) {
                openPanel(.addFood(food))
            } else {
                openPanel(.addQuery(id))
            }
        case .category:
            openPanel(.add)
        case .offer:
            openPanel(.add)
        case .applyQuery(let q):
            openPanel(.addQuery(q))
        case .dismissed:
            break
        }
    }

    // MARK: Panels

    private func openPanel(_ kind: NutPanelKind) {
        var t = Transaction(animation: nil)
        t.disablesAnimations = true
        withTransaction(t) { panel = kind }
    }

    @ViewBuilder
    private func panelContent(_ kind: NutPanelKind, close: @escaping (_ after: (() -> Void)?) -> Void) -> some View {
        switch kind {
        case .add:
            NutritionEntryContent(editing: nil, close: close, onSaved: { toast = $0; invalidateHistoryCache() }, onDelete: { _ in })
        case .addFood(let food):
            NutritionEntryContent(editing: nil, initialFood: food, close: close, onSaved: { toast = $0; invalidateHistoryCache() }, onDelete: { _ in })
        case .addQuery(let initialQuery):
            NutritionEntryContent(editing: nil, initialQuery: initialQuery, close: close, onSaved: { toast = $0; invalidateHistoryCache() }, onDelete: { _ in })
        case .photo(let photoDraft):
            NutCaptureContent(
                firstPhoto: photoDraft.image,
                startsWithLabelScan: photoDraft.isLabel,
                close: close,
                onSaved: { toast = $0; invalidateHistoryCache() },
                onSearch: { close { openPanel(.add) } }
            )
        case .edit(let meal):
            NutritionEntryContent(editing: meal, close: close, onSaved: { toast = $0; invalidateHistoryCache() }, onDelete: { m in Task { await delete(m) } })
        case .goal:
            NutritionGoalContent(close: close, onSaved: { toast = $0; invalidateHistoryCache() })
        case .soon:
            NutritionSoonContent(close: close)
        }
    }
}

// MARK: - Pieces

private struct NutRing: View {
    let eaten: Double
    let planned: Double
    let reduceMotion: Bool

    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.25), style: StrokeStyle(lineWidth: 10, lineCap: .round))
            Circle().trim(from: 0, to: planned)
                .stroke(Color.white.opacity(0.55), style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Circle().trim(from: 0, to: eaten)
                .stroke(Color.white, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 1) {
                Text("\(Int((eaten * 100).rounded()))%")
                    .font(TTFont.workSans(22, weight: .bold))
                    .monospacedDigit()
                Text("of goal")
                    .font(TTFont.workSans(11, weight: .regular))
                    .opacity(0.9)
            }
            .foregroundStyle(.white)
        }
        .padding(5)
        .animation(reduceMotion ? nil : .timingCurve(0.2, 0.8, 0.2, 1, duration: 0.5), value: eaten)
        .animation(reduceMotion ? nil : .timingCurve(0.2, 0.8, 0.2, 1, duration: 0.5), value: planned)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(Int((eaten * 100).rounded()))% of goal"))
    }
}

private struct NutCountUpText: View {
    let target: Int
    let suffix: String
    let reduceMotion: Bool

    @State private var displayed: Int = 0
    @State private var animTask: Task<Void, Never>?

    var body: some View {
        Text(verbatim: "\(displayed.formatted())\(suffix)")
            .onAppear { animate(to: target) }
            .onChange(of: target) { _, newValue in animate(to: newValue) }
            .onDisappear { animTask?.cancel() }
    }

    private func animate(to end: Int) {
        animTask?.cancel()
        if reduceMotion {
            displayed = end
            return
        }
        let start = 0
        let duration: TimeInterval = 0.55
        let startTime = Date()
        animTask = Task {
            while !Task.isCancelled {
                let elapsed = Date().timeIntervalSince(startTime)
                let t = min(1.0, elapsed / duration)
                let eased = 1.0 - pow(1.0 - t, 3.0)
                let val = Int((Double(start) + Double(end - start) * eased).rounded())
                await MainActor.run { displayed = val }
                if t >= 1.0 { break }
                try? await Task.sleep(nanoseconds: 16_000_000)
            }
        }
    }
}

/// Letter tile (42 pt). Colour follows the stored kind; neutral when the kind is unknown.
private struct NutTile: View {
    let name: String
    let kind: String?
    let planned: Bool
    let hasPhoto: Bool

    private var colors: (Color, Color) {
        switch kind {
        case "drink": (Color(red: 227 / 255, green: 240 / 255, blue: 1), Color(red: 30 / 255, green: 64 / 255, blue: 175 / 255))
        case "piece": (Color(red: 1, green: 244 / 255, blue: 204 / 255), Color(red: 138 / 255, green: 109 / 255, blue: 0))
        case "plate": (Color(red: 228 / 255, green: 245 / 255, blue: 233 / 255), Color(red: 22 / 255, green: 101 / 255, blue: 52 / 255))
        default: (Color(red: 237 / 255, green: 237 / 255, blue: 240 / 255), Color(white: 0.27))
        }
    }

    var body: some View {
        Text(verbatim: String(name.prefix(1)).uppercased())
            .font(TTFont.workSans(16, weight: .semibold))
            .foregroundStyle(colors.1)
            .frame(width: 42, height: 42)
            .background(colors.0)
            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay {
                if planned {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .strokeBorder(TTColor.actionOrange, style: StrokeStyle(lineWidth: 2, dash: [4, 3]))
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if hasPhoto {
                    Circle().fill(Color.black).frame(width: 16, height: 16)
                        .overlay(Circle().stroke(Color.white, lineWidth: 2))
                        .offset(x: 3, y: 3)
                }
            }
            .accessibilityHidden(true)
    }
}

// MARK: - Panel host (0.36 s in, 0.22 s out, covers the tab bar)

private struct NutritionPanelHost<Content: View>: View {
    @ViewBuilder var content: (_ close: @escaping (_ after: (() -> Void)?) -> Void) -> Content

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false
    @State private var contentHeight: CGFloat = 400
    @State private var dragOffset: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            let maxHeight = geo.size.height * 0.92
            let sheetHeight = min(contentHeight, maxHeight - 23)
            let isScrollable = contentHeight > maxHeight - 23
            let dismissDrag = DragGesture(minimumDistance: 8, coordinateSpace: .global)
                .onChanged { value in
                    guard value.translation.height > 0,
                          abs(value.translation.height) > abs(value.translation.width) else { return }
                    dragOffset = value.translation.height
                }
                .onEnded { value in
                    if value.translation.height > 90 || value.predictedEndTranslation.height > 160 {
                        close(nil)
                    } else {
                        withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.85)) {
                            dragOffset = 0
                        }
                    }
                }
            let dimOpacity = shown ? max(0, 0.45 * (1 - Double(dragOffset / max(200, sheetHeight)))) : 0
            ZStack(alignment: .bottom) {
                Color.black.opacity(dimOpacity)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { close(nil) }
                    .accessibilityHidden(true)

                VStack(spacing: 0) {
                    Capsule().fill(Color(red: 212 / 255, green: 212 / 255, blue: 216 / 255))
                        .frame(width: 40, height: 5)
                        .padding(.top, 10).padding(.bottom, 12)
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                        .gesture(dismissDrag)
                        .accessibilityHidden(true)
                    ScrollView(showsIndicators: false) {
                        content { after in close(after) }
                            .padding(.horizontal, 18)
                            .padding(.bottom, 24)
                            .background(GeometryReader { g in
                                Color.clear
                                    .onAppear { contentHeight = g.size.height }
                                    .onChange(of: g.size.height) { _, h in contentHeight = h }
                            })
                    }
                    .scrollBounceBehavior(.basedOnSize)
                    .scrollDismissesKeyboard(.interactively)
                    .frame(height: sheetHeight)
                    .simultaneousGesture(dismissDrag, including: isScrollable ? .subviews : .all)
                }
                .frame(maxWidth: .infinity)
                .background(
                    UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28)
                        .fill(Color.white)
                        .ignoresSafeArea(edges: .bottom)
                )
                .offset(y: shown ? dragOffset : geo.size.height)
                .accessibilityAddTraits(.isModal)
            }
        }
        .onAppear {
            withAnimation(reduceMotion ? nil : NutStyle.sheetOpen) { shown = true }
        }
    }

    private func close(_ after: (() -> Void)?) {
        guard shown else { return }
        withAnimation(reduceMotion ? nil : NutStyle.sheetClose) { shown = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + (reduceMotion ? 0 : 0.23)) {
            var t = Transaction(animation: nil)
            t.disablesAnimations = true
            withTransaction(t) { dismiss() }
            after?()
        }
    }
}

private func nutPanelButton(_ title: LocalizedStringKey, style: NutPanelButtonStyle, loading: Bool = false, action: @escaping () -> Void) -> some View {
    Button(action: action) {
        HStack(spacing: 10) {
            if loading { ProgressView().tint(.white) }
            Text(title).font(TTFont.workSans(17, weight: style == .primary ? .semibold : .medium))
        }
        .frame(maxWidth: .infinity, minHeight: style == .primary ? 54 : 48)
        .foregroundStyle(style == .primary ? Color.white : (style == .danger ? NutStyle.danger : Color(white: 0.27)))
        .background(style == .primary ? Color.black : Color.clear)
        .clipShape(Capsule())
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
}

private enum NutPanelButtonStyle { case primary, ghost, danger }

// MARK: - Soon sheet

private struct NutritionSoonContent: View {
    let close: (_ after: (() -> Void)?) -> Void

    var body: some View {
        VStack(spacing: 0) {
            TTIcon(icon: .scan1, size: 30)
                .foregroundStyle(NutStyle.orange)
                .frame(width: 64, height: 64)
                .background(Color(red: 1, green: 241 / 255, blue: 230 / 255))
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .padding(.top, 6).padding(.bottom, 10)
                .accessibilityHidden(true)
            Text("Food scan")
                .font(TTFont.workSans(20, weight: .bold))
                .foregroundStyle(TTColor.ink)
                .accessibilityAddTraits(.isHeader)
            Text("Upcoming feature. Soon you will scan your food with the camera and AI will tell you everything about it.")
                .font(TTFont.body(14))
                .foregroundStyle(NutStyle.mute)
                .multilineTextAlignment(.center)
                .padding(.top, 2).padding(.bottom, 10)
            nutPanelButton("Got it", style: .primary) { close(nil) }
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Goal sheet

private struct NutritionGoalContent: View {
    @Environment(AppStore.self) private var store
    let close: (_ after: (() -> Void)?) -> Void
    let onSaved: (TTToastMessage) -> Void

    @State private var value = 2100
    @State private var saving = false
    @State private var errorText: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Daily calorie goal")
                .font(TTFont.workSans(20, weight: .bold)).foregroundStyle(TTColor.ink)
                .accessibilityAddTraits(.isHeader)
            Text("Changing it updates your ring and what is left.")
                .font(TTFont.body(14)).foregroundStyle(NutStyle.mute)
                .padding(.top, 2).padding(.bottom, 10)
            HStack(spacing: 18) {
                roundButton("−", label: "Lower by 50") { value = max(1200, value - 50) }
                Text("\(value) kcal")
                    .font(TTFont.workSans(34, weight: .semibold))
                    .monospacedDigit()
                    .frame(minWidth: 130)
                    .minimumScaleFactor(0.7)
                roundButton("+", label: "Raise by 50") { value = min(4000, value + 50) }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            if let errorText {
                Text(verbatim: errorText).font(TTFont.body(13)).foregroundStyle(NutStyle.danger).padding(.bottom, 4)
            }
            nutPanelButton("Save goal", style: .primary, loading: saving) { save() }
                .disabled(saving)
            nutPanelButton("Cancel", style: .ghost) { close(nil) }
                .disabled(saving)
        }
        .onAppear { value = (store.currentTrainee?.dailyCalorieTarget ?? 0) > 0 ? (store.currentTrainee?.dailyCalorieTarget ?? 2100) : 2100 }
    }

    private func roundButton(_ glyph: String, label: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(verbatim: glyph).font(TTFont.workSans(26, weight: .regular))
                .foregroundStyle(TTColor.ink)
                .frame(width: 52, height: 52)
                .overlay(Circle().stroke(Color(red: 212 / 255, green: 212 / 255, blue: 216 / 255), lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func save() {
        guard !saving else { return }
        saving = true
        errorText = nil
        let target = value
        Task {
            do {
                try await store.saveDailyCalorieTarget(target)
                saving = false
                close {
                    onSaved(TTToastMessage(text: String(format: String(localized: "Goal saved: %lld kcal"), target), style: .success))
                }
            } catch {
                saving = false
                errorText = error.localizedDescription.isEmpty ? String(localized: "Couldn’t save goal") : error.localizedDescription
            }
        }
    }
}

// MARK: - Add / edit sheet

// MARK: Kinds, sizes and the draft

private enum NutKind: String {
    case drink, piece, plate

    /// From the food's name and keywords (the catalog has no category). Default: plate.
    static func infer(name: String, keywords: [String] = []) -> NutKind {
        let blob = ([name] + keywords).joined(separator: " ").lowercased()
        let drinks = ["shake", "smoothie", "juice", "milk", "coffee", "latte", "tea", "water", "soda", "cola", "drink", "lemonade"]
        let pieces = ["banana", "apple", "egg", "orange", "avocado", "pear", "peach", "mango", "cookie", "date"]
        if drinks.contains(where: { blob.contains($0) }) { return .drink }
        if pieces.contains(where: { blob.contains($0) }) { return .piece }
        return .plate
    }
}

/// Size steps. The stored `detail` always uses these English tokens so an edit can rebuild the options.
private struct NutSize {
    let token: String
    let title: LocalizedStringKey
    let factor: Double
    static let piece = [
        NutSize(token: "Small", title: "Small", factor: 0.85),
        NutSize(token: "Medium", title: "Medium", factor: 1),
        NutSize(token: "Large", title: "Large", factor: 1.15)
    ]
    static let plate = [
        NutSize(token: "Small", title: "Small", factor: 0.75),
        NutSize(token: "Regular", title: "Regular", factor: 1),
        NutSize(token: "Large", title: "Large", factor: 1.3)
    ]
}

private enum NutPhotoCategory: String, CaseIterable, Identifiable {
    case meal, snack, drink
    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .meal: "Meal"
        case .snack: "Snack"
        case .drink: "Drink"
        }
    }

    var kind: NutKind {
        switch self {
        case .meal: .plate
        case .snack: .piece
        case .drink: .drink
        }
    }

    func defaultMealType(at date: Date) -> TTMealType {
        switch self {
        case .snack:
            return .snack
        case .meal, .drink:
            let suggested = TTMealType.suggested(at: date)
            return suggested == .snack ? .lunch : suggested
        }
    }
}

private struct NutDraft {
    var name: String
    var kind: NutKind
    var mealType: TTMealType
    var notes = ""
    /// Per gram (or ml) values the portion is multiplied with.
    var perUnit: (kcal: Double, p: Double, c: Double, f: Double)
    var status: String        // "eaten" | "planned"
    var time: Date
    var timeTouched = false
    var isCustom = false
    var customKcal = ""
    var customProtein = ""
    var customCarbs = ""
    var customFat = ""
    // drink
    var ml: Double = 250
    // piece
    var count = 1
    // piece / plate size index; nil = keep `storedPortion` (an old entry whose detail can't be read)
    var size: Int? = nil
    var storedPortion: Double?

    // TODO: the backend has no grams-per-piece or grams-per-plate. A medium piece is treated as 100 g and a regular
    // plate as 250 g (the sizes then scale that). A drink is treated as 1 ml = 1 g.
    static let pieceBase = 100.0
    static let plateBase = 250.0

    var portion: Double {
        switch kind {
        case .drink: return ml
        case .piece:
            guard let size else { return storedPortion ?? Self.pieceBase }
            return Double(count) * NutSize.piece[size].factor * Self.pieceBase
        case .plate:
            guard let size else { return storedPortion ?? Self.plateBase }
            return NutSize.plate[size].factor * Self.plateBase
        }
    }

    var detail: String {
        switch kind {
        case .drink: return "\(Int(ml)) ml"
        case .piece:
            guard let size else { return "\(Int(portion.rounded())) g" }
            return "\(count) × \(NutSize.piece[size].token)"
        case .plate:
            guard let size else { return "\(Int(portion.rounded())) g" }
            return "\(NutSize.plate[size].token) portion"
        }
    }

    /// A custom food uses the calories and macros the person typed; empty stays 0 ("— kcal", not counted).
    var macros: MacroEstimate {
        if isCustom {
            return MacroEstimate(
                calories: Int(customKcal.trimmingCharacters(in: .whitespaces)) ?? 0,
                protein: Double(customProtein.trimmingCharacters(in: .whitespaces)) ?? 0,
                carbs: Double(customCarbs.trimmingCharacters(in: .whitespaces)) ?? 0,
                fat: Double(customFat.trimmingCharacters(in: .whitespaces)) ?? 0
            )
        }
        let g = portion
        return MacroEstimate(
            calories: Int((perUnit.kcal * g).rounded()),
            protein: (perUnit.p * g * 10).rounded() / 10,
            carbs: (perUnit.c * g * 10).rounded() / 10,
            fat: (perUnit.f * g * 10).rounded() / 10
        )
    }

    static func new(
        name: String,
        kind: NutKind,
        mealType: TTMealType? = nil,
        perUnit: (kcal: Double, p: Double, c: Double, f: Double),
        custom: Bool,
        time: Date
    ) -> NutDraft {
        var d = NutDraft(
            name: name,
            kind: kind,
            mealType: mealType ?? TTMealType.suggested(at: time),
            perUnit: perUnit,
            status: "eaten",
            time: time,
            isCustom: custom
        )
        d.size = kind == .piece ? 1 : (kind == .plate ? 1 : nil)
        return d
    }

    /// Rebuilds the options of a saved entry from its kind and detail.
    static func from(meal: Meal) -> NutDraft {
        let g = max(meal.portionGrams, 1)
        let kind = NutKind(rawValue: meal.kind ?? "") ?? NutKind.infer(name: meal.name)
        let mealType = TTMealType(rawValue: meal.mealType ?? "") ?? TTMealType.suggested(at: meal.eatenAt)
        var d = NutDraft(
            name: meal.name, kind: kind, mealType: mealType, notes: meal.notes ?? "",
            perUnit: (Double(meal.macros.calories) / g, meal.macros.protein / g, meal.macros.carbs / g, meal.macros.fat / g),
            status: meal.isPlanned ? "planned" : "eaten", time: meal.eatenAt,
            isCustom: meal.source == "custom"
        )
        if d.isCustom {
            if meal.macros.calories > 0 { d.customKcal = String(meal.macros.calories) }
            if meal.macros.protein > 0 { d.customProtein = Self.formatMacroInput(meal.macros.protein) }
            if meal.macros.carbs > 0 { d.customCarbs = Self.formatMacroInput(meal.macros.carbs) }
            if meal.macros.fat > 0 { d.customFat = Self.formatMacroInput(meal.macros.fat) }
        }
        let detail = meal.detail ?? ""
        switch kind {
        case .drink:
            d.ml = meal.portionGrams > 0 ? meal.portionGrams : 250
            if let n = Int(detail.split(separator: " ").first ?? ""), detail.hasSuffix("ml") || detail.hasSuffix("g") { d.ml = Double(n) }
        case .piece:
            let parts = detail.components(separatedBy: " × ")
            if parts.count == 2, let n = Int(parts[0]), (1...6).contains(n),
               let i = NutSize.piece.firstIndex(where: { $0.token == parts[1] }) {
                d.count = n; d.size = i
            } else { d.storedPortion = meal.portionGrams > 0 ? meal.portionGrams : nil }
        case .plate:
            if detail.hasSuffix(" portion"),
               let i = NutSize.plate.firstIndex(where: { $0.token == String(detail.dropLast(" portion".count)) }) {
                d.size = i
            } else { d.storedPortion = meal.portionGrams > 0 ? meal.portionGrams : nil }
        }
        return d
    }

    private static func formatMacroInput(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(format: "%.1f", value)
    }
}

private struct NutritionEntryContent: View {
    @Environment(AppStore.self) private var store
    let editing: Meal?
    var initialPhoto: UIImage? = nil
    var initialFood: FoodKnowledge? = nil
    var initialQuery: String? = nil
    let close: (_ after: (() -> Void)?) -> Void
    let onSaved: (TTToastMessage) -> Void
    let onDelete: (Meal) -> Void

    @State private var query = ""
    @State private var remote: FoodKnowledge?
    @State private var searchTask: Task<Void, Never>?
    @State private var draft: NutDraft?
    /// A frequent meal with its foods opens the Meal Tray directly.
    @State private var trayItems: [NutTrayItem]?
    @State private var activePhoto: UIImage?
    @State private var photoCategory: NutPhotoCategory = .meal
    @State private var showRetakeCamera = false
    @State private var showRetakeLibrary = false
    @State private var retakeLibraryItem: PhotosPickerItem?
    @State private var saving = false
    @State private var errorText: String?
    @FocusState private var searchFocused: Bool

    /// Time the sheet opened ("Now"). Eaten entries can't be later; planned entries start after it.
    @State private var now = Date()

    var body: some View {
        Group {
            if let trayItems {
                NutMealTrayContent(items: trayItems, mealTag: nil, source: "log", heroPhoto: nil, close: close, onSaved: onSaved)
            } else if draft == nil {
                chooser
            } else {
                details
            }
        }
        .onAppear {
            now = Date()
            if activePhoto == nil { activePhoto = initialPhoto }
            if let editing, draft == nil {
                draft = NutDraft.from(meal: editing)
            } else if let initialFood, draft == nil {
                pick(Self.option(from: initialFood))
            } else if let initialQuery, query.isEmpty {
                query = initialQuery
            }
        }
        .sheet(isPresented: $showRetakeCamera) {
            CameraImagePicker(image: $activePhoto)
                .ignoresSafeArea()
        }
        .photosPicker(isPresented: $showRetakeLibrary, selection: $retakeLibraryItem, matching: .images)
        .onChange(of: retakeLibraryItem) { _, item in
            guard let item else { return }
            Task {
                defer { retakeLibraryItem = nil }
                if let data = try? await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    activePhoto = image
                }
            }
        }
    }

    // MARK: Step 1 — choose

    private struct Option: Identifiable {
        let id: String
        let name: String
        let perUnit: (kcal: Double, p: Double, c: Double, f: Double)
        let kind: NutKind
        let subtitle: String
        var custom = false
    }

    private var options: [Option] {
        let t = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var foods = store.foodCatalog
        if let remote, !foods.contains(where: { $0.name == remote.name }) { foods.insert(remote, at: 0) }
        if t.isEmpty {
            // Recent: the trainee's own latest entries (real per-gram values), then nothing invented.
            var seen = Set<String>()
            var out: [Option] = []
            for m in store.meals.sorted(by: { $0.eatenAt > $1.eatenAt }) where m.traineeId == store.currentTrainee?.id && m.portionGrams > 0 && m.source != "custom" {
                guard seen.insert(m.name.lowercased()).inserted else { continue }
                out.append(Option(
                    id: "recent-\(m.id)", name: m.name,
                    perUnit: (Double(m.macros.calories) / m.portionGrams, m.macros.protein / m.portionGrams, m.macros.carbs / m.portionGrams, m.macros.fat / m.portionGrams),
                    kind: NutKind(rawValue: m.kind ?? "") ?? NutKind.infer(name: m.name),
                    subtitle: String(format: String(localized: "%lld kcal per 100 g"), Int((Double(m.macros.calories) / m.portionGrams * 100).rounded()))
                ))
                if out.count >= 8 { break }
            }
            if !out.isEmpty { return out }
            return foods.prefix(12).map(Self.option(from:))
        }
        return foods.filter { f in
            f.name.lowercased().contains(t) || f.keywords.contains { $0.lowercased().contains(t) }
        }.map(Self.option(from:))
    }

    private static func option(from f: FoodKnowledge) -> Option {
        Option(
            id: "food-\(f.name)", name: f.name,
            perUnit: (Double(f.per100g.calories) / 100, f.per100g.protein / 100, f.per100g.carbs / 100, f.per100g.fat / 100),
            kind: NutKind.infer(name: f.name, keywords: f.keywords),
            subtitle: String(format: String(localized: "%lld kcal per 100 g"), f.per100g.calories)
        )
    }

    private var chooser: some View {
        let list = options
        let typed = !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return VStack(alignment: .leading, spacing: 0) {
            Text("Add food or drink")
                .font(TTFont.workSans(20, weight: .bold)).foregroundStyle(TTColor.ink)
                .accessibilityAddTraits(.isHeader)
            Text("Saved with today's date and time.")
                .font(TTFont.body(14)).foregroundStyle(NutStyle.mute)
                .padding(.top, 2).padding(.bottom, 10)
            if let activePhoto {
                photoBanner(activePhoto)
                    .padding(.bottom, 12)
            }
            TextField("Search foods and drinks", text: $query)
                .font(TTFont.body(16))
                .padding(.horizontal, 14)
                .frame(height: 48)
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(searchFocused ? NutStyle.orange : Color(red: 228 / 255, green: 228 / 255, blue: 231 / 255), lineWidth: 1.5))
                .focused($searchFocused)
                .submitLabel(.search)
                .padding(.vertical, 4)
                .onChange(of: query) { _, value in
                    remote = nil
                    searchTask?.cancel()
                    let q = value.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard q.count >= 2 else { return }
                    searchTask = Task {
                        try? await Task.sleep(nanoseconds: 250_000_000)
                        guard !Task.isCancelled else { return }
                        let found = await store.searchFood(query: q)
                        if !Task.isCancelled && query.trimmingCharacters(in: .whitespacesAndNewlines) == q {
                            remote = found
                        }
                    }
                }
                .accessibilityLabel("Search foods and drinks")
            if !typed, editing == nil, !store.frequentMeals.isEmpty {
                Text("FREQUENT")
                    .font(TTFont.workSans(12, weight: .semibold))
                    .tracking(1.4)
                    .foregroundStyle(NutStyle.mute)
                    .padding(.top, 12).padding(.bottom, 6).padding(.horizontal, 2)
                ForEach(Array(store.frequentMeals.prefix(5).enumerated()), id: \.element.id) { i, meal in
                    chooserRow(
                        name: meal.name,
                        subtitle: frequentSubtitle(meal),
                        kind: meal.kind,
                        first: i == 0,
                        trailing: "\(Int((meal.calories ?? 0).rounded())) kcal"
                    ) { pickFrequent(meal) }
                }
            }
            Text(typed ? "RESULTS" : (list.first?.id.hasPrefix("recent-") == true ? "RECENT" : "SUGGESTED"))
                .font(TTFont.workSans(12, weight: .semibold))
                .tracking(1.4)
                .foregroundStyle(NutStyle.mute)
                .padding(.top, 12).padding(.bottom, 6).padding(.horizontal, 2)
            if list.isEmpty {
                Text("No match. Add it as a custom food in the app.")
                    .font(TTFont.body(14)).foregroundStyle(NutStyle.mute)
                    .padding(.horizontal, 2).padding(.bottom, 10)
                // TODO: the prototype only shows the text above; without this row a food that isn't in the list
                // could not be logged at all (the old sheet allowed any name).
                let typedName = query.trimmingCharacters(in: .whitespacesAndNewlines)
                chooserRow(name: typedName, subtitle: String(localized: "Custom food"), kind: nil, first: true) {
                    pick(Option(id: "custom", name: typedName, perUnit: (0, 0, 0, 0), kind: NutKind.infer(name: typedName), subtitle: "", custom: true))
                }
            } else {
                ForEach(Array(list.enumerated()), id: \.element.id) { i, option in
                    chooserRow(name: option.name, subtitle: option.subtitle, kind: option.kind.rawValue, first: i == 0) { pick(option) }
                }
            }
        }
        .onAppear { searchFocused = false }
    }

    private func photoBanner(_ image: UIImage) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 60, height: 60)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    Text("Food photo attached")
                        .font(TTFont.workSans(15, weight: .semibold))
                        .foregroundStyle(TTColor.ink)
                    HStack(spacing: 8) {
                        if UIImagePickerController.isSourceTypeAvailable(.camera) {
                            Button("Retake") { showRetakeCamera = true }
                                .font(TTFont.workSans(12, weight: .semibold))
                                .foregroundStyle(NutStyle.orange)
                                .buttonStyle(.plain)
                        }
                        Button("Library") { showRetakeLibrary = true }
                            .font(TTFont.workSans(12, weight: .semibold))
                            .foregroundStyle(NutStyle.mute)
                            .buttonStyle(.plain)
                    }
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 6) {
                ForEach(NutPhotoCategory.allCases) { cat in
                    let on = photoCategory == cat
                    Button {
                        photoCategory = cat
                    } label: {
                        Text(cat.title)
                            .font(TTFont.workSans(13, weight: .semibold))
                            .foregroundStyle(on ? .white : TTColor.ink)
                            .frame(maxWidth: .infinity, minHeight: 36)
                            .background(on ? NutStyle.orange : Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }

            nutPanelButton("Continue with photo", style: .primary) {
                continueWithPhoto()
            }
        }
        .padding(12)
        .background(NutStyle.field)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func continueWithPhoto() {
        searchFocused = false
        let typed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let defaultName: String
        switch photoCategory {
        case .meal: defaultName = String(localized: "Meal")
        case .snack: defaultName = String(localized: "Snack")
        case .drink: defaultName = String(localized: "Drink")
        }
        let name = typed.isEmpty ? defaultName : typed
        draft = NutDraft.new(
            name: name,
            kind: photoCategory.kind,
            mealType: photoCategory.defaultMealType(at: now),
            perUnit: (0, 0, 0, 0),
            custom: true,
            time: now
        )
    }

    private func frequentSubtitle(_ meal: FrequentMeal) -> String {
        var parts: [String] = []
        if let detail = meal.detail?.trimmingCharacters(in: .whitespacesAndNewlines), !detail.isEmpty { parts.append(detail) }
        if let count = meal.count { parts.append(String(format: String(localized: "Logged %lld×"), count)) }
        return parts.joined(separator: " · ")
    }

    /// 1-tap repeat: the foods open in the Meal Tray; a meal without foods opens the entry sheet filled in.
    private func pickFrequent(_ m: FrequentMeal) {
        searchFocused = false
        if let items = m.mealItems, !items.isEmpty {
            trayItems = items.map { NutTrayBuilder.item(from: $0) }
            return
        }
        let meal = Meal(
            id: UUID().uuidString, traineeId: store.currentTrainee?.id ?? "", name: m.name, eatenAt: now,
            portionGrams: max(m.portionGrams ?? 0, 1),
            macros: MacroEstimate(calories: Int((m.calories ?? 0).rounded()), protein: m.proteinG ?? 0, carbs: m.carbsG ?? 0, fat: m.fatG ?? 0),
            source: "log", isEstimate: true, status: "eaten", kind: m.kind, detail: m.detail
        )
        draft = NutDraft.from(meal: meal)
    }

    private func chooserRow(name: String, subtitle: String, kind: String?, first: Bool, trailing: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                NutTile(name: name, kind: kind, planned: false, hasPhoto: false)
                VStack(alignment: .leading, spacing: 0) {
                    Text(verbatim: name).font(TTFont.workSans(15, weight: .semibold)).foregroundStyle(TTColor.ink).lineLimit(1)
                    Text(verbatim: subtitle).font(TTFont.workSans(12, weight: .regular)).foregroundStyle(NutStyle.mute).lineLimit(1)
                }
                Spacer(minLength: 0)
                if let trailing {
                    Text(verbatim: trailing)
                        .font(TTFont.workSans(14, weight: .semibold)).monospacedDigit()
                        .foregroundStyle(TTColor.ink)
                }
            }
            .frame(minHeight: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .top) { if !first { Rectangle().fill(NutStyle.line).frame(height: 1) } }
    }

    private func pick(_ option: Option) {
        searchFocused = false
        let mealType: TTMealType = activePhoto != nil
            ? photoCategory.defaultMealType(at: now)
            : TTMealType.suggested(at: now)
        draft = NutDraft.new(
            name: option.name,
            kind: option.kind,
            mealType: mealType,
            perUnit: option.perUnit,
            custom: option.custom,
            time: now
        )
    }

    // MARK: Step 2 — details (options follow the kind)

    private var details: some View {
        let d = draft!
        let m = d.macros
        let ate = d.status == "eaten"
        let endOfDay = Calendar.current.date(bySettingHour: 23, minute: 59, second: 0, of: now) ?? now
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                if let activePhoto {
                    Image(uiImage: activePhoto)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 56, height: 56)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                } else if let photoUrl = editing?.photoUrl {
                    TTMealPhoto(urlString: photoUrl)
                        .frame(width: 56, height: 56)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                } else {
                    NutTile(name: d.name, kind: d.kind.rawValue, planned: false, hasPhoto: false)
                        .scaleEffect(56.0 / 42.0).frame(width: 56, height: 56)
                }
                VStack(alignment: .leading, spacing: 0) {
                    Text(verbatim: d.name.isEmpty ? String(localized: "Meal") : d.name)
                        .font(TTFont.workSans(20, weight: .bold))
                        .foregroundStyle(TTColor.ink)
                        .lineLimit(2)
                    Text(editing == nil ? "Chosen by you" : "Editing entry")
                        .font(TTFont.workSans(13, weight: .medium))
                        .foregroundStyle(NutStyle.mute)
                }
                Spacer(minLength: 0)
            }
            .padding(.top, 2).padding(.bottom, 4)

            if d.isCustom && editing == nil {
                customNameField
                kindOptions(d)
            }

            switch d.kind {
            case .drink: drinkOptions(d)
            case .piece: pieceOptions(d)
            case .plate: plateOptions(d)
            }

            mealTypeOptions(d)

            if d.isCustom { customNutrition(d) }

            notesField

            estimate(m)

            HStack(spacing: 0) {
                seg("Ate it", on: ate) { setStatus("eaten") }
                seg("Plan it", on: !ate) { setStatus("planned") }
            }
            .padding(3)
            .background(NutStyle.track)
            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
            .padding(.vertical, 6)

            HStack {
                Text(verbatim: (sameMinute(d.time, now) ? "\(String(localized: "Now")) · " : "") + d.time.formatted(date: .omitted, time: .shortened))
                    .font(TTFont.workSans(16, weight: .semibold)).monospacedDigit()
                Spacer(minLength: 8)
                HStack(spacing: 12) {
                    roundStep("−", label: "15 minutes earlier") { shiftTime(-15, ate: ate, endOfDay: endOfDay) }
                    roundStep("+", label: "15 minutes later") { shiftTime(15, ate: ate, endOfDay: endOfDay) }
                }
            }
            .padding(.vertical, 6)

            if let errorText {
                Text(verbatim: errorText).font(TTFont.body(13)).foregroundStyle(NutStyle.danger).padding(.top, 4)
            }
            nutPanelButton(saving ? "Saving…" : (editing != nil ? "Save changes" : (ate ? "Save" : "Save plan")), style: .primary, loading: saving) { save() }
                .disabled(saving)
                .padding(.top, 10)
            if let editing {
                nutPanelButton("Delete entry", style: .danger) { close { onDelete(editing) } }
                    .disabled(saving)
            } else {
                nutPanelButton("Cancel", style: .ghost) { close(nil) }
                    .disabled(saving)
            }
        }
    }

    private var customNameField: some View {
        VStack(alignment: .leading, spacing: 0) {
            label("NAME")
            TextField("e.g. Milk, Chicken Bowl, Apple", text: Binding(
                get: { draft?.name ?? "" },
                set: { draft?.name = $0 }
            ))
            .font(TTFont.body(15))
            .padding(.horizontal, 14)
            .frame(height: 44)
            .background(NutStyle.field)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private func kindOptions(_ d: NutDraft) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            label("TYPE")
            chipRow {
                chip(Text("Meal"), on: d.kind == .plate) {
                    draft?.kind = .plate
                    draft?.size = 1
                }
                chip(Text("Snack"), on: d.kind == .piece) {
                    draft?.kind = .piece
                    draft?.size = 1
                    draft?.mealType = .snack
                }
                chip(Text("Drink"), on: d.kind == .drink) {
                    draft?.kind = .drink
                    draft?.size = nil
                }
            }
        }
    }

    private func mealTypeOptions(_ d: NutDraft) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            label("MEAL")
            chipRow {
                ForEach(TTMealType.allCases) { type in
                    chip(Text(type.title), on: d.mealType == type) {
                        draft?.mealType = type
                    }
                }
            }
        }
    }

    private var notesField: some View {
        VStack(alignment: .leading, spacing: 0) {
            label("NOTES")
            TextField("Optional details (e.g. low-fat milk, homemade)", text: Binding(
                get: { draft?.notes ?? "" },
                set: { draft?.notes = $0 }
            ))
            .font(TTFont.body(14))
            .padding(.horizontal, 14)
            .frame(height: 42)
            .background(NutStyle.field)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private func drinkOptions(_ d: NutDraft) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            label("AMOUNT")
            chipRow {
                ForEach([("Glass", 250.0), ("Cup", 200.0), ("Bottle", 500.0)], id: \.0) { name, v in
                    chip(Text(LocalizedStringKey(name)) + Text(verbatim: " · \(Int(v)) ml"), on: d.ml == v) { draft?.ml = v }
                }
            }
            HStack(spacing: 12) {
                roundStep("−", label: "Less") { draft?.ml = max(50, d.ml - 50) }
                Text(verbatim: "\(Int(d.ml)) ml")
                    .font(TTFont.workSans(20, weight: .semibold)).monospacedDigit()
                    .frame(minWidth: 96)
                roundStep("+", label: "More") { draft?.ml = min(1000, d.ml + 50) }
            }
            .padding(.vertical, 6)
        }
    }

    private func pieceOptions(_ d: NutDraft) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            label("HOW MANY")
            HStack(spacing: 12) {
                roundStep("−", label: "Fewer") { draft?.count = max(1, d.count - 1) }
                Text(verbatim: "\(d.count)")
                    .font(TTFont.workSans(20, weight: .semibold)).monospacedDigit()
                    .frame(minWidth: 96)
                roundStep("+", label: "More") { draft?.count = min(6, d.count + 1) }
            }
            .padding(.vertical, 6)
            label("SIZE")
            chipRow {
                ForEach(Array(NutSize.piece.enumerated()), id: \.offset) { i, s in
                    chip(Text(s.title), on: d.size == i) { draft?.size = i }
                }
            }
        }
    }

    private func plateOptions(_ d: NutDraft) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            label("PORTION")
            chipRow {
                ForEach(Array(NutSize.plate.enumerated()), id: \.offset) { i, s in
                    chip(Text(s.title), on: d.size == i) { draft?.size = i }
                }
            }
        }
    }

    private func customNutrition(_ d: NutDraft) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            label("CALORIES & MACROS (OPTIONAL)")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                macroInputField(
                    title: "Calories",
                    unit: "kcal",
                    text: Binding(
                        get: { draft?.customKcal ?? "" },
                        set: { draft?.customKcal = $0.filter(\.isNumber) }
                    ),
                    decimal: false
                )
                macroInputField(
                    title: "Protein",
                    unit: "g",
                    text: Binding(
                        get: { draft?.customProtein ?? "" },
                        set: { draft?.customProtein = sanitizeDecimal($0) }
                    ),
                    decimal: true
                )
                macroInputField(
                    title: "Carbs",
                    unit: "g",
                    text: Binding(
                        get: { draft?.customCarbs ?? "" },
                        set: { draft?.customCarbs = sanitizeDecimal($0) }
                    ),
                    decimal: true
                )
                macroInputField(
                    title: "Fat",
                    unit: "g",
                    text: Binding(
                        get: { draft?.customFat ?? "" },
                        set: { draft?.customFat = sanitizeDecimal($0) }
                    ),
                    decimal: true
                )
            }
        }
    }

    private func macroInputField(title: LocalizedStringKey, unit: String, text: Binding<String>, decimal: Bool) -> some View {
        HStack(spacing: 6) {
            TextField(title, text: text)
                .keyboardType(decimal ? .decimalPad : .numberPad)
                .font(TTFont.workSans(15, weight: .semibold))
            Text(verbatim: unit)
                .font(TTFont.workSans(12, weight: .regular))
                .foregroundStyle(NutStyle.mute)
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 44)
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color(red: 228 / 255, green: 228 / 255, blue: 231 / 255), lineWidth: 1.5)
        )
    }

    private func sanitizeDecimal(_ input: String) -> String {
        var seenDot = false
        return String(input.filter { ch in
            if ch.isNumber { return true }
            if ch == "." && !seenDot { seenDot = true; return true }
            return false
        })
    }

    private func chipRow<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        // Wraps to a second line at large text sizes.
        NutFlow(spacing: 8) { content() }
    }

    private func chip(_ title: Text, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            title
                .font(TTFont.workSans(14, weight: .medium))
                .foregroundStyle(on ? Color.white : TTColor.ink)
                .padding(.horizontal, 14).frame(minHeight: 44)
                .background(on ? Color.black : Color.white)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(on ? Color.black : Color(red: 228 / 255, green: 228 / 255, blue: 231 / 255), lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func label(_ text: LocalizedStringKey) -> some View {
        Text(text).font(TTFont.workSans(12, weight: .semibold)).tracking(1.4).foregroundStyle(NutStyle.mute)
            .padding(.top, 12).padding(.bottom, 6).padding(.horizontal, 2)
    }

    private func roundStep(_ glyph: String, label: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(verbatim: glyph).font(TTFont.workSans(22, weight: .regular)).foregroundStyle(TTColor.ink)
                .frame(width: 44, height: 44)
                .overlay(Circle().stroke(Color(red: 212 / 255, green: 212 / 255, blue: 216 / 255), lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func seg(_ title: LocalizedStringKey, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(TTFont.workSans(15, weight: on ? .semibold : .medium))
                .foregroundStyle(on ? Color(white: 0.07) : Color(red: 85 / 255, green: 85 / 255, blue: 91 / 255))
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(on ? Color.white : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .shadow(color: on ? .black.opacity(0.16) : .clear, radius: 1.5, y: 1)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func estimate(_ m: MacroEstimate) -> some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 0) {
                if m.calories > 0 {
                    Text("\(m.calories) kcal").font(TTFont.workSans(18, weight: .bold)).monospacedDigit()
                } else {
                    Text(verbatim: "— kcal").font(TTFont.workSans(18, weight: .bold))
                }
                Text("Estimate").font(TTFont.workSans(13, weight: .regular).italic()).foregroundStyle(NutStyle.mute)
            }
            Spacer(minLength: 4)
            macroCell("Protein", m.protein)
            macroCell("Carbs", m.carbs)
            macroCell("Fat", m.fat)
        }
        .foregroundStyle(TTColor.ink)
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(NutStyle.field)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.top, 10).padding(.bottom, 2)
        .accessibilityElement(children: .combine)
    }

    private func macroCell(_ title: LocalizedStringKey, _ value: Double) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(TTFont.workSans(12, weight: .regular)).foregroundStyle(Color(white: 0.27))
            Text(verbatim: "\(value.formatted(.number.precision(.fractionLength(0...1)))) g")
                .font(TTFont.workSans(15, weight: .bold)).monospacedDigit()
        }
    }

    private func sameMinute(_ a: Date, _ b: Date) -> Bool {
        Calendar.current.isDate(a, equalTo: b, toGranularity: .minute)
    }

    private func setStatus(_ status: String) {
        guard var d = draft else { return }
        d.status = status
        if status == "planned", d.time <= now { d.time = now.addingTimeInterval(78 * 60) }
        if status == "eaten", d.time > now { d.time = now }
        // Never past the end of today (planned entries are for later today only).
        if let end = Calendar.current.date(bySettingHour: 23, minute: 59, second: 0, of: now), d.time > end { d.time = end }
        d.timeTouched = true
        draft = d
    }

    private func shiftTime(_ minutes: Int, ate: Bool, endOfDay: Date) {
        guard var d = draft else { return }
        var t = d.time.addingTimeInterval(Double(minutes) * 60)
        if ate { t = min(now, t) } else { t = min(endOfDay, max(now.addingTimeInterval(15 * 60), t)) }
        d.time = t
        d.timeTouched = true
        draft = d
    }

    // MARK: Save

    private func save() {
        guard let d = draft, !saving else { return }
        saving = true
        errorText = nil
        let macros = d.macros
        Task {
            do {
                var savedName = d.name
                var savedTime = d.time
                if let editing {
                    var body = UpdateMealBody(portionGrams: d.portion, macros: macros, status: d.status, kind: d.kind.rawValue, detail: d.detail)
                    if d.timeTouched || d.status == "planned" { body.eatenAt = d.time }
                    let updated = try await store.updateMeal(editing, changes: body)
                    savedName = updated.name; savedTime = updated.eatenAt
                } else {
                    let trimmedName = d.name.trimmingCharacters(in: .whitespacesAndNewlines)
                    let finalName = trimmedName.isEmpty ? String(localized: "Meal") : trimmedName
                    let trimmedNotes = d.notes.trimmingCharacters(in: .whitespacesAndNewlines)
                    let meal = Meal(
                        id: UUID().uuidString, traineeId: store.currentTrainee?.id ?? "", name: finalName,
                        eatenAt: d.time, portionGrams: d.portion, macros: macros,
                        source: d.isCustom ? "custom" : "log", isEstimate: true,
                        mealType: d.mealType.rawValue,
                        notes: trimmedNotes.isEmpty ? nil : trimmedNotes,
                        status: d.status, kind: d.kind.rawValue, detail: d.detail
                    )
                    // "Eaten now" leaves the time to the server; a chosen or planned time is sent.
                    try await store.saveMeal(meal, photo: activePhoto, sendsEatenAt: d.status == "planned" || d.timeTouched)
                    savedName = finalName
                }
                saving = false
                let time = savedTime.formatted(date: .omitted, time: .shortened)
                let text = d.status == "planned"
                    ? String(format: String(localized: "%@ planned · %@"), savedName, time)
                    : String(format: String(localized: "%@ saved · %@"), savedName, time)
                close {
                    onSaved(TTToastMessage(text: text, style: .success))
                    UIAccessibility.post(notification: .announcement, argument: text)
                }
            } catch {
                // Inputs stay as they are so the person can try again.
                saving = false
                errorText = error.localizedDescription.isEmpty ? String(localized: "Couldn’t save entry") : error.localizedDescription
            }
        }
    }
}

/// Wrapping row for chips (a second line at large text sizes).
private struct NutFlow: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(width: proposal.width ?? .infinity, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(width: bounds.width, subviews: subviews)
        for (i, origin) in result.origins.enumerated() {
            subviews[i].place(at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y), proposal: .unspecified)
        }
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> (size: CGSize, origins: [CGPoint]) {
        var origins: [CGPoint] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxX: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            origins.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            maxX = max(maxX, x - spacing)
        }
        return (CGSize(width: maxX, height: y + rowHeight), origins)
    }
}

// MARK: - Meal photos: capture, AI disclosure, barcode and the meal tray

private enum NutTrust: String {
    case verifiedLabel = "verified_label"
    case databaseMatch = "database_match"
    case aiEstimate = "ai_estimate"

    init(raw: String?) { self = NutTrust(rawValue: raw ?? "") ?? .aiEstimate }

    var title: LocalizedStringKey {
        switch self {
        case .verifiedLabel: "Verified Label"
        case .databaseMatch: "Database Match"
        case .aiEstimate: "AI Estimate"
        }
    }

    var tint: Color {
        switch self {
        case .verifiedLabel: Color(red: 22 / 255, green: 101 / 255, blue: 52 / 255)
        case .databaseMatch: Color(red: 30 / 255, green: 64 / 255, blue: 175 / 255)
        case .aiEstimate: Color(red: 194 / 255, green: 65 / 255, blue: 12 / 255)
        }
    }
}

private struct NutNutrition {
    var kcal = 0.0
    var p = 0.0
    var c = 0.0
    var f = 0.0
    var fiber = 0.0

    func scaled(_ k: Double) -> NutNutrition {
        NutNutrition(kcal: kcal * k, p: p * k, c: c * k, f: f * k, fiber: fiber * k)
    }
}

private struct NutModifierOption {
    let token: String
    let title: LocalizedStringKey
    /// How the nutrition changes when this option is chosen (relative to the neutral option).
    let apply: (NutNutrition) -> NutNutrition
}

private enum NutModifierProfile: String {
    case curryOil = "curry_oil"
    case teaSugar = "tea_sugar"
    case milkType = "milk_type"

    var neutralIndex: Int { self == .curryOil ? 1 : 0 }

    var options: [NutModifierOption] {
        switch self {
        case .curryOil:
            return [
                NutModifierOption(token: "Kam Oil", title: "Kam Oil") { n in
                    var r = n; r.f = n.f * 0.85; r.kcal = n.kcal - n.f * 0.15 * 9; return r
                },
                NutModifierOption(token: "Normal", title: "Normal") { $0 },
                NutModifierOption(token: "Oily", title: "Oily") { n in
                    var r = n; r.f = n.f * 1.25; r.kcal = n.kcal + n.f * 0.25 * 9; return r
                }
            ]
        case .teaSugar:
            return [
                NutModifierOption(token: "No Sugar", title: "No Sugar") { $0 },
                NutModifierOption(token: "With Sugar", title: "With Sugar") { n in
                    var r = n; r.kcal = n.kcal + 32; r.c = n.c + 8; return r
                }
            ]
        case .milkType:
            // TODO: the backend gives no numbers for milk types. These ratios follow the prototype's example
            // values (whole 61 / semi-skimmed 46 / skimmed 34 kcal per 100 ml; fat 3.3 / 1.6 / 0.1 g).
            return [
                NutModifierOption(token: "Whole", title: "Whole") { $0 },
                NutModifierOption(token: "Semi-skimmed", title: "Semi-skimmed") { n in
                    var r = n; r.kcal = n.kcal * 0.75; r.f = n.f * 0.48; return r
                },
                NutModifierOption(token: "Skimmed", title: "Skimmed") { n in
                    var r = n; r.kcal = n.kcal * 0.56; r.f = n.f * 0.03; return r
                }
            ]
        }
    }

    /// `base` was delivered with option `initial` already included; moving to `selected` changes it by the difference.
    func adjust(_ n: NutNutrition, selected: Int, initial: Int) -> NutNutrition {
        let opts = options
        guard opts.indices.contains(selected), opts.indices.contains(initial) else { return n }
        let a = opts[selected].apply(n)
        let b = opts[initial].apply(n)
        return NutNutrition(
            kcal: max(0, n.kcal + a.kcal - b.kcal),
            p: max(0, n.p + a.p - b.p),
            c: max(0, n.c + a.c - b.c),
            f: max(0, n.f + a.f - b.f),
            fiber: n.fiber
        )
    }
}

/// One food in the meal tray. All portion scaling runs locally (no extra backend calls).
private struct NutTrayItem: Identifiable {
    let id = UUID()
    var name: String
    var searchKey: String?
    var category: NutKind
    var baseGrams: Double
    /// Nutrition for `baseGrams`, as delivered.
    var base: NutNutrition
    var aiPortionLabel: String?
    var trust: NutTrust
    var confidence: Double?
    var alternatives: [String] = []
    var profile: NutModifierProfile?
    var initialModifier = 0
    var modifier = 0
    var plateSize = 1
    var pieceSize = 1
    var count = 1
    var ml = 250.0
    var portionTouched = false
    var expanded = false

    static let plateFactors: [Double] = [0.7, 1.0, 1.4]
    static let pieceFactors: [Double] = [0.85, 1.0, 1.15]
    static let plateTokens = ["Small", "Regular", "Large"]
    static let pieceTokens = ["Small", "Medium", "Large"]

    var grams: Double {
        switch category {
        case .drink: return ml
        case .piece: return baseGrams * Double(count) * Self.pieceFactors[pieceSize]
        case .plate: return baseGrams * Self.plateFactors[plateSize]
        }
    }

    var nutrition: NutNutrition {
        var n = base.scaled(baseGrams > 0 ? grams / baseGrams : 1)
        if let profile { n = profile.adjust(n, selected: modifier, initial: initialModifier) }
        return n
    }

    var needsReview: Bool { (confidence ?? 1) < 0.85 }

    var modifierLabel: String? { profile.map { $0.options[modifier].token } }

    private var useOwnLabel: Bool { portionTouched || (aiPortionLabel ?? "").isEmpty }

    /// English token stored with the meal (an edit can read it back).
    var portionLabelForSave: String {
        switch category {
        case .drink: return "\(Int(ml.rounded())) ml"
        case .piece: return useOwnLabel ? "\(count) × \(Self.pieceTokens[pieceSize])" : (aiPortionLabel ?? "")
        case .plate: return useOwnLabel ? Self.plateTokens[plateSize] : (aiPortionLabel ?? "")
        }
    }

    /// "~200 g" (or "250 ml" for a drink): the weight, written once.
    var weightText: String {
        let g = Int(grams.rounded())
        return category == .drink ? "\(g) ml" : "~\(g) g"
    }

    /// A label from the analysis, with any weight it already contains ("200g", "(~200 g)") removed.
    private func labelWithoutWeight(_ label: String) -> String {
        let stripped = label.replacingOccurrences(
            of: "[\\(\\[]?\\s*~?\\d+([.,]\\d+)?\\s*(g|gr|grams?|ml)\\b\\s*[\\)\\]]?",
            with: "", options: [.regularExpression, .caseInsensitive]
        )
        return stripped.trimmingCharacters(in: CharacterSet(charactersIn: " ·-–—,;:()[]"))
    }

    /// Localized summary for the collapsed card: "Regular · ~250 g". The weight appears once, never repeated.
    var portionSummary: String {
        func loc(_ token: String) -> String { String(localized: String.LocalizationValue(token)) }
        let label: String
        switch category {
        case .drink: return weightText
        case .piece: label = useOwnLabel ? "\(count) × \(loc(Self.pieceTokens[pieceSize]))" : labelWithoutWeight(aiPortionLabel ?? "")
        case .plate: label = useOwnLabel ? loc(Self.plateTokens[plateSize]) : labelWithoutWeight(aiPortionLabel ?? "")
        }
        return label.isEmpty ? weightText : "\(label) · \(weightText)"
    }

    var itemBody: MealItemBody {
        let n = nutrition
        func r1(_ v: Double) -> Double { (v * 10).rounded() / 10 }
        return MealItemBody(
            name: name, searchKey: searchKey, category: category.rawValue, grams: r1(grams),
            portionLabel: portionLabelForSave.isEmpty ? nil : portionLabelForSave,
            modifierLabel: modifierLabel,
            calories: Int(n.kcal.rounded()), proteinG: r1(n.p), carbsG: r1(n.c), fatG: r1(n.f),
            fiberG: n.fiber > 0 ? r1(n.fiber) : nil,
            trustSource: trust.rawValue, confidence: confidence
        )
    }
}

private enum NutTrayBuilder {
    static func item(from a: AnalyzedMealItem) -> NutTrayItem {
        let category = NutKind(rawValue: a.category ?? "") ?? .plate
        let grams = max(a.grams ?? 0, 1)
        let name = (a.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        var item = NutTrayItem(
            name: name.isEmpty ? String(localized: "Food") : name,
            searchKey: a.searchKey,
            category: category,
            baseGrams: grams,
            base: NutNutrition(kcal: a.calories ?? 0, p: a.proteinG ?? 0, c: a.carbsG ?? 0, f: a.fatG ?? 0, fiber: a.fiberG ?? 0),
            aiPortionLabel: a.portionLabel,
            trust: NutTrust(raw: a.trustSource),
            confidence: a.confidence,
            alternatives: Array((a.alternatives ?? []).prefix(3))
        )
        if category == .drink { item.ml = grams }
        if let raw = a.modifierProfile, let profile = NutModifierProfile(rawValue: raw) {
            item.profile = profile
            let label = (a.modifierLabel ?? "").lowercased()
            let index = profile.options.firstIndex { !label.isEmpty && label.contains($0.token.lowercased()) } ?? profile.neutralIndex
            item.initialModifier = index
            item.modifier = index
        }
        return item
    }

    /// Barcode: per-100 g values scaled to the serving.
    static func item(from b: BarcodeMealItem) -> NutTrayItem? {
        let name = (b.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        let serving = max(b.servingGrams ?? 100, 1)
        let k = serving / 100
        var item = NutTrayItem(
            name: name,
            searchKey: b.barcode,
            category: NutKind(rawValue: b.category ?? "") ?? .plate,
            baseGrams: serving,
            base: NutNutrition(kcal: (b.caloriesPer100g ?? 0) * k, p: (b.proteinPer100g ?? 0) * k, c: (b.carbsPer100g ?? 0) * k, f: (b.fatPer100g ?? 0) * k),
            aiPortionLabel: String(localized: "Serving"),
            trust: .verifiedLabel,
            confidence: nil
        )
        if item.category == .drink { item.ml = serving }
        return item
    }

    /// A food picked from the list ("+ Add missing item", or an alternative that exists locally).
    static func item(from f: FoodKnowledge, grams overrideGrams: Double? = nil) -> NutTrayItem {
        let category = NutKind.infer(name: f.name, keywords: f.keywords)
        let grams = overrideGrams ?? (category == .piece ? NutDraft.pieceBase : (category == .drink ? 250 : NutDraft.plateBase))
        let k = grams / 100
        var item = NutTrayItem(
            name: f.name,
            searchKey: f.name.lowercased(),
            category: category,
            baseGrams: grams,
            base: NutNutrition(kcal: Double(f.per100g.calories) * k, p: f.per100g.protein * k, c: f.per100g.carbs * k, f: f.per100g.fat * k),
            aiPortionLabel: nil,
            trust: .databaseMatch,
            confidence: nil
        )
        if category == .drink { item.ml = grams }
        return item
    }
}

private func nutTrayChip(_ title: Text, on: Bool, action: @escaping () -> Void) -> some View {
    Button(action: action) {
        title
            .font(TTFont.workSans(14, weight: .medium))
            .foregroundStyle(on ? Color.white : TTColor.ink)
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .background(on ? Color.black : Color.white)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(on ? Color.black : Color(red: 228 / 255, green: 228 / 255, blue: 231 / 255), lineWidth: 1.5))
    }
    .buttonStyle(.plain)
    .accessibilityAddTraits(on ? .isSelected : [])
}

private func nutTrayRoundButton(_ glyph: String, label: LocalizedStringKey, action: @escaping () -> Void) -> some View {
    Button(action: action) {
        Text(verbatim: glyph).font(TTFont.workSans(22, weight: .regular)).foregroundStyle(TTColor.ink)
            .frame(width: 44, height: 44)
            .overlay(Circle().stroke(Color(red: 212 / 255, green: 212 / 255, blue: 216 / 255), lineWidth: 1))
            .contentShape(Circle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel(label)
}

/// One item card: collapsed by default, tap to adjust the portion.
private struct NutTrayCard: View {
    @Binding var item: NutTrayItem
    let onRemove: () -> Void
    let onAlternative: (String) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let n = item.nutrition
        let kcal = Int(n.kcal.rounded())
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 8) {
                Button {
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { item.expanded.toggle() }
                } label: {
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(verbatim: item.name)
                                .font(TTFont.workSans(16, weight: .semibold))
                                .foregroundStyle(TTColor.ink)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                            Text(verbatim: item.portionSummary)
                                .font(TTFont.workSans(13, weight: .regular))
                                .foregroundStyle(NutStyle.mute)
                            Text(item.trust.title)
                                .font(TTFont.workSans(11, weight: .semibold))
                                .foregroundStyle(item.trust.tint)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(item.trust.tint.opacity(0.12))
                                .clipShape(Capsule())
                        }
                        Spacer(minLength: 4)
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("\(kcal) kcal")
                                .font(TTFont.workSans(15, weight: .bold))
                                .monospacedDigit()
                                .foregroundStyle(TTColor.ink)
                            if !item.expanded {
                                Text("Tap to adjust")
                                    .font(TTFont.workSans(11, weight: .regular))
                                    .foregroundStyle(NutStyle.mute)
                            }
                        }
                        Image(systemName: "chevron.down")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(NutStyle.mute)
                            .rotationEffect(.degrees(item.expanded ? 180 : 0))
                            .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: item.expanded)
                            .accessibilityHidden(true)
                    }
                    .frame(minHeight: 56)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(verbatim: "\(item.name), \(item.portionSummary), \(kcal) kcal"))
                .accessibilityHint(Text("Adjust portion"))

                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(NutStyle.mute)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Remove \(item.name)"))
            }

            if item.needsReview, !item.alternatives.isEmpty {
                NutFlow(spacing: 8) {
                    ForEach(item.alternatives, id: \.self) { alt in
                        nutTrayChip(Text("Not it?") + Text(verbatim: " \(alt)"), on: false) { onAlternative(alt) }
                    }
                }
            }

            if item.expanded { controls }
        }
        .padding(12)
        .background(NutStyle.field)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(item.needsReview ? NutStyle.orange : Color.clear, lineWidth: 1.5)
        )
    }

    @ViewBuilder
    private var controls: some View {
        VStack(alignment: .leading, spacing: 10) {
            switch item.category {
            case .plate:
                NutFlow(spacing: 8) {
                    ForEach(0..<3, id: \.self) { i in
                        nutTrayChip(
                            Text(LocalizedStringKey(NutTrayItem.plateTokens[i])) + Text(verbatim: " · " + String(format: "%.1f×", NutTrayItem.plateFactors[i])),
                            on: item.plateSize == i
                        ) { item.plateSize = i; item.portionTouched = true }
                    }
                }
            case .piece:
                HStack(spacing: 12) {
                    nutTrayRoundButton("−", label: "Fewer") { item.count = max(1, item.count - 1); item.portionTouched = true }
                    Text(verbatim: "\(item.count)")
                        .font(TTFont.workSans(20, weight: .semibold)).monospacedDigit()
                        .frame(minWidth: 64)
                    nutTrayRoundButton("+", label: "More") { item.count = min(6, item.count + 1); item.portionTouched = true }
                }
                NutFlow(spacing: 8) {
                    ForEach(0..<3, id: \.self) { i in
                        nutTrayChip(Text(LocalizedStringKey(NutTrayItem.pieceTokens[i])), on: item.pieceSize == i) {
                            item.pieceSize = i; item.portionTouched = true
                        }
                    }
                }
            case .drink:
                NutFlow(spacing: 8) {
                    ForEach([("Glass", 250.0), ("Cup", 200.0), ("Bottle", 500.0)], id: \.0) { name, v in
                        nutTrayChip(Text(LocalizedStringKey(name)) + Text(verbatim: " \(Int(v))"), on: item.ml == v) {
                            item.ml = v; item.portionTouched = true
                        }
                    }
                }
                HStack(spacing: 12) {
                    nutTrayRoundButton("−", label: "Less") { item.ml = max(50, item.ml - 50); item.portionTouched = true }
                    Text(verbatim: "\(Int(item.ml)) ml")
                        .font(TTFont.workSans(20, weight: .semibold)).monospacedDigit()
                        .frame(minWidth: 96)
                    nutTrayRoundButton("+", label: "More") { item.ml = min(1000, item.ml + 50); item.portionTouched = true }
                }
            }

            if let profile = item.profile {
                NutFlow(spacing: 8) {
                    ForEach(Array(profile.options.enumerated()), id: \.offset) { i, option in
                        nutTrayChip(Text(option.title), on: item.modifier == i) { item.modifier = i }
                    }
                }
            }
        }
    }
}

/// Review screen: live totals, one card per food, status, time and save.
private struct NutMealTrayContent: View {
    @Environment(AppStore.self) private var store
    let source: String
    let heroPhoto: UIImage?
    let close: (_ after: (() -> Void)?) -> Void
    let onSaved: (TTToastMessage) -> Void

    @State private var items: [NutTrayItem]
    @State private var status = "eaten"
    @State private var now: Date
    @State private var time: Date
    @State private var timeTouched = false
    @State private var saving = false
    @State private var errorText: String?
    @State private var addingItem = false
    @State private var query = ""
    @State private var remote: FoodKnowledge?
    @State private var mealTag: String?
    @State private var showFix = false
    @State private var fixText = ""
    @State private var refining = false
    @State private var fixMessage: String?

    init(
        items: [NutTrayItem], mealTag: String?, source: String, heroPhoto: UIImage?,
        close: @escaping (_ after: (() -> Void)?) -> Void, onSaved: @escaping (TTToastMessage) -> Void
    ) {
        _items = State(initialValue: items)
        let opened = Date()
        _now = State(initialValue: opened)
        _time = State(initialValue: opened)
        _mealTag = State(initialValue: mealTag)
        self.source = source
        self.heroPhoto = heroPhoto
        self.close = close
        self.onSaved = onSaved
    }

    private var totals: NutNutrition {
        items.reduce(NutNutrition()) { acc, item in
            let n = item.nutrition
            return NutNutrition(kcal: acc.kcal + n.kcal, p: acc.p + n.p, c: acc.c + n.c, f: acc.f + n.f, fiber: acc.fiber + n.fiber)
        }
    }

    private var goal: Int { store.currentTrainee?.dailyCalorieTarget ?? 0 }

    private var eatenKcalToday: Int {
        guard let id = store.currentTrainee?.id else { return 0 }
        return store.meals(for: id, on: Date()).filter { !$0.isPlanned }.reduce(0) { $0 + $1.macros.calories }
    }

    private var endOfDay: Date {
        Calendar.current.date(bySettingHour: 23, minute: 59, second: 0, of: now) ?? now
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Review your meal")
                .font(TTFont.workSans(20, weight: .bold)).foregroundStyle(TTColor.ink)
                .accessibilityAddTraits(.isHeader)
                .padding(.bottom, 10)

            summaryCard

            VStack(spacing: 10) {
                ForEach($items) { $item in
                    NutTrayCard(
                        item: $item,
                        onRemove: { remove(item.id) },
                        onAlternative: { alt in applyAlternative(item.id, alt) }
                    )
                }
            }
            .padding(.top, 12)

            if items.isEmpty {
                Text("Add an item to save this meal.")
                    .font(TTFont.body(14)).foregroundStyle(NutStyle.mute)
                    .padding(.top, 8)
            }

            addMissingItem

            HStack(spacing: 0) {
                seg("Ate it", on: status == "eaten") { setStatus("eaten") }
                seg("Plan it", on: status == "planned") { setStatus("planned") }
            }
            .padding(3)
            .background(NutStyle.track)
            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
            .padding(.top, 14).padding(.bottom, 6)

            HStack {
                Text(verbatim: (Calendar.current.isDate(time, equalTo: now, toGranularity: .minute) ? "\(String(localized: "Now")) · " : "")
                     + time.formatted(date: .omitted, time: .shortened))
                    .font(TTFont.workSans(16, weight: .semibold)).monospacedDigit()
                Spacer(minLength: 8)
                HStack(spacing: 12) {
                    nutTrayRoundButton("−", label: "15 minutes earlier") { shiftTime(-15) }
                    nutTrayRoundButton("+", label: "15 minutes later") { shiftTime(15) }
                }
            }
            .padding(.vertical, 6)

            if let errorText {
                Text(verbatim: errorText).font(TTFont.body(13)).foregroundStyle(NutStyle.danger).padding(.top, 4)
            }

            nutPanelButton(saving ? "Saving…" : "Save meal", style: .primary, loading: saving) { save() }
                .disabled(saving || items.isEmpty)
                .opacity(items.isEmpty ? 0.4 : 1)
                .padding(.top, 10)
            nutPanelButton("Cancel", style: .ghost) { close(nil) }
                .disabled(saving)
                .padding(.bottom, 12)
        }
    }

    // MARK: Summary

    private var summaryCard: some View {
        let t = totals
        let kcal = Int(t.kcal.rounded())
        let left = goal - eatenKcalToday - kcal
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(kcal) kcal")
                    .font(TTFont.workSans(30, weight: .bold)).monospacedDigit()
                    .foregroundStyle(TTColor.ink)
                    .minimumScaleFactor(0.7).lineLimit(1)
                Spacer(minLength: 4)
                if let tag = mealTag?.trimmingCharacters(in: .whitespacesAndNewlines), !tag.isEmpty {
                    Text(verbatim: tag)
                        .font(TTFont.workSans(12, weight: .semibold))
                        .foregroundStyle(NutStyle.accentText)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(NutStyle.orange.opacity(0.12))
                        .clipShape(Capsule())
                        .lineLimit(1)
                }
            }
            HStack(spacing: 8) {
                macroCell("Protein", t.p)
                macroCell("Carbs", t.c)
                macroCell("Fat", t.f)
            }
            if goal > 0 {
                Text("\(max(0, left)) kcal left after this meal")
                    .font(TTFont.workSans(13, weight: .medium))
                    .foregroundStyle(left < 0 ? NutStyle.danger : NutStyle.mute)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(NutStyle.field)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func macroCell(_ title: LocalizedStringKey, _ value: Double) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(TTFont.workSans(12, weight: .regular)).foregroundStyle(Color(white: 0.27))
            Text(verbatim: "\(value.formatted(.number.precision(.fractionLength(0...1)))) g")
                .font(TTFont.workSans(15, weight: .bold)).monospacedDigit().foregroundStyle(TTColor.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Add missing item

    private var results: [FoodKnowledge] {
        let t = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var foods = store.foodCatalog
        if let remote, !foods.contains(where: { $0.name == remote.name }) { foods.insert(remote, at: 0) }
        guard !t.isEmpty else { return Array(foods.prefix(6)) }
        return foods.filter { f in
            f.name.lowercased().contains(t) || f.keywords.contains { $0.lowercased().contains(t) }
        }
    }

    private var addMissingItem: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Button {
                    addingItem.toggle()
                    if addingItem { showFix = false }
                } label: {
                    Text("+ Add missing item")
                        .font(TTFont.workSans(15, weight: .semibold))
                        .foregroundStyle(NutStyle.accentText)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Spacer(minLength: 4)

                Button {
                    showFix.toggle()
                    if showFix { addingItem = false }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles").font(.system(size: 14, weight: .semibold))
                        Text("Fix with AI").font(TTFont.workSans(15, weight: .semibold))
                    }
                    .foregroundStyle(NutStyle.accentText)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(showFix ? .isSelected : [])
            }
            if addingItem { searchBlock }
            if showFix { fixBlock }
        }
        .padding(.top, 6)
    }

    private var searchBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("Search foods and drinks", text: $query)
                .font(TTFont.body(16))
                .padding(.horizontal, 14)
                .frame(height: 48)
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color(red: 228 / 255, green: 228 / 255, blue: 231 / 255), lineWidth: 1.5))
                .onChange(of: query) { _, value in
                    remote = nil
                    let q = value.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard q.count >= 2 else { return }
                    Task {
                        let found = await store.searchFood(query: q)
                        if query.trimmingCharacters(in: .whitespacesAndNewlines) == q { remote = found }
                    }
                }
            ForEach(results, id: \.name) { food in
                Button {
                    items.append(NutTrayBuilder.item(from: food))
                    addingItem = false; query = ""; remote = nil
                } label: {
                    HStack {
                        Text(verbatim: food.name).font(TTFont.workSans(15, weight: .semibold)).foregroundStyle(TTColor.ink)
                        Spacer(minLength: 4)
                        Text(verbatim: String(format: String(localized: "%lld kcal per 100 g"), food.per100g.calories))
                            .font(TTFont.workSans(12, weight: .regular)).foregroundStyle(NutStyle.mute)
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 4)
    }

    /// "Fix with AI": a short instruction, sent with the tray's current items.
    private var fixBlock: some View {
        let trimmed = fixText.trimmingCharacters(in: .whitespacesAndNewlines)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                TextField("e.g. It's mutton not chicken, add 1 roti", text: $fixText, axis: .vertical)
                    .lineLimit(1...3)
                    .font(TTFont.body(15))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .frame(minHeight: 44)
                    .background(NutStyle.field)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .disabled(refining)
                    .accessibilityLabel(Text("Fix with AI"))
                Button { refine() } label: {
                    HStack(spacing: 6) {
                        if refining { ProgressView().tint(.white) }
                        Text("Update").font(TTFont.workSans(15, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .frame(minHeight: 44)
                    .background(Color.black)
                    .clipShape(Capsule())
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(refining || trimmed.isEmpty)
                .opacity(trimmed.isEmpty && !refining ? 0.4 : 1)
            }
            if let fixMessage {
                Text(verbatim: fixMessage)
                    .font(TTFont.body(13)).foregroundStyle(NutStyle.mute)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.top, 4)
    }

    private func refine() {
        let instruction = fixText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !refining, !instruction.isEmpty else { return }
        refining = true
        fixMessage = nil
        let bodies = items.map(\.itemBody)
        let fallback = String(localized: "Couldn’t update right now — you can still edit items below.")
        Task {
            do {
                let response = try await store.refineMeal(items: bodies, instruction: instruction)
                let refined = (response.items ?? []).map { NutTrayBuilder.item(from: $0) }
                if (response.isFood ?? true), !refined.isEmpty {
                    // Only the items change: Ate it | Plan it and the chosen time stay as they are.
                    items = refined
                    if let tag = response.mealTag?.trimmingCharacters(in: .whitespacesAndNewlines), !tag.isEmpty { mealTag = tag }
                    fixText = ""
                    showFix = false
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } else {
                    let message = (response.message ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    fixMessage = message.isEmpty ? fallback : message
                }
            } catch {
                fixMessage = fallback
            }
            refining = false
        }
    }

    // MARK: Actions

    private func remove(_ id: UUID) {
        items.removeAll { $0.id == id }
    }

    /// "Not it?" — rename, and use the local food list for numbers when there is a match (no backend call).
    private func applyAlternative(_ id: UUID, _ alt: String) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        var item = items[index]
        item.name = alt
        item.searchKey = alt.lowercased()
        item.confidence = 1
        item.alternatives = []
        if let food = store.lookupFood(query: alt) {
            let grams = item.grams
            let k = grams / 100
            item.base = NutNutrition(kcal: Double(food.per100g.calories) * k, p: food.per100g.protein * k, c: food.per100g.carbs * k, f: food.per100g.fat * k)
            item.baseGrams = max(grams, 1)
            item.trust = .databaseMatch
            item.profile = nil
        }
        items[index] = item
    }

    private func seg(_ title: LocalizedStringKey, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(TTFont.workSans(15, weight: on ? .semibold : .medium))
                .foregroundStyle(on ? Color(white: 0.07) : Color(red: 85 / 255, green: 85 / 255, blue: 91 / 255))
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(on ? Color.white : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .shadow(color: on ? .black.opacity(0.16) : .clear, radius: 1.5, y: 1)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func setStatus(_ newStatus: String) {
        status = newStatus
        if newStatus == "planned", time <= now { time = now.addingTimeInterval(78 * 60) }
        if newStatus == "eaten", time > now { time = now }
        if time > endOfDay { time = endOfDay }
        timeTouched = true
    }

    private func shiftTime(_ minutes: Int) {
        var t = time.addingTimeInterval(Double(minutes) * 60)
        if status == "eaten" { t = min(now, t) } else { t = min(endOfDay, max(now.addingTimeInterval(15 * 60), t)) }
        time = t
        timeTouched = true
    }

    private func save() {
        guard !saving, !items.isEmpty else { return }
        saving = true
        errorText = nil
        let t = totals
        func r1(_ v: Double) -> Double { (v * 10).rounded() / 10 }
        let names = items.map(\.name).joined(separator: ", ")
        let name = names.count > 60 ? String(names.prefix(57)) + "…" : names
        // Same kind of text as manual entries ("~200 g", "250 ml"); several items: "3 items". The meal tag stays in the tray.
        let detail = items.count == 1
            ? items[0].weightText
            : String(format: String(localized: "%lld items"), items.count)
        let meal = Meal(
            id: UUID().uuidString,
            traineeId: store.currentTrainee?.id ?? "",
            name: name,
            eatenAt: time,
            portionGrams: max(1, items.reduce(0) { $0 + $1.grams }),
            macros: MacroEstimate(calories: Int(t.kcal.rounded()), protein: r1(t.p), carbs: r1(t.c), fat: r1(t.f)),
            source: source,
            isEstimate: items.contains { $0.trust != .verifiedLabel },
            status: status,
            kind: items.count == 1 ? items[0].category.rawValue : NutKind.plate.rawValue,
            detail: detail.isEmpty ? nil : detail
        )
        let bodies = items.map(\.itemBody)
        let hero = heroPhoto
        let sendTime = status == "planned" || timeTouched
        Task {
            do {
                // Uploads the first photo (if any), then saves the meal with its items; the Today list refreshes.
                try await store.saveMeal(meal, photo: hero, sendsEatenAt: sendTime, items: bodies)
                saving = false
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                let timeText = time.formatted(date: .omitted, time: .shortened)
                let text = status == "planned"
                    ? String(format: String(localized: "%@ planned · %@"), name, timeText)
                    : String(format: String(localized: "%@ saved · %@"), name, timeText)
                close {
                    onSaved(TTToastMessage(text: text, style: .success))
                    UIAccessibility.post(notification: .announcement, argument: text)
                }
            } catch {
                // Everything stays as it is so the person can try again.
                saving = false
                errorText = error.localizedDescription.isEmpty ? String(localized: "Couldn’t save entry") : error.localizedDescription
            }
        }
    }
}

// MARK: Barcode (on device)

private extension CGImagePropertyOrientation {
    init(_ o: UIImage.Orientation) {
        switch o {
        case .up: self = .up
        case .upMirrored: self = .upMirrored
        case .down: self = .down
        case .downMirrored: self = .downMirrored
        case .left: self = .left
        case .leftMirrored: self = .leftMirrored
        case .right: self = .right
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}

private enum NutBarcode {
    /// The first barcode in the image (Apple Vision, no network).
    static func detect(in image: UIImage) async -> String? {
        guard let cg = image.cgImage else { return nil }
        let orientation = CGImagePropertyOrientation(image.imageOrientation)
        return await Task.detached(priority: .userInitiated) { () -> String? in
            let request = VNDetectBarcodesRequest()
            let handler = VNImageRequestHandler(cgImage: cg, orientation: orientation, options: [:])
            do { try handler.perform([request]) } catch { return nil }
            return request.results?.compactMap { $0.payloadStringValue }.first { !$0.isEmpty }
        }.value
    }
}

// MARK: Nutrition label OCR (on device)

private enum NutLabelOCR {
    /// All text Vision can read from a label photo, one line per row. Runs off the main actor.
    static func recognize(in image: UIImage) async -> String {
        guard let cg = image.cgImage else { return "" }
        let orientation = CGImagePropertyOrientation(image.imageOrientation)
        return await Task.detached(priority: .userInitiated) { () -> String in
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            let handler = VNImageRequestHandler(cgImage: cg, orientation: orientation, options: [:])
            do { try handler.perform([request]) } catch { return "" }
            let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
            return lines.joined(separator: "\n")
        }.value
    }
}

// MARK: Capture panel: photos → (barcode fast path) → disclosure → analyze → tray

private struct NutCaptureContent: View {
    @Environment(AppStore.self) private var store
    let firstPhoto: UIImage
    /// Optional: the first photo is a nutrition label, so run label OCR right away.
    var startsWithLabelScan = false
    let close: (_ after: (() -> Void)?) -> Void
    let onSaved: (TTToastMessage) -> Void
    let onSearch: () -> Void

    private enum Phase: Equatable {
        case checkingBarcode, collecting, disclosure, analyzing, readingLabel, notFound(String), tray
    }

    private static let disclosureKey = "nutrition.aiPhotoDisclosureAccepted"

    @State private var photos: [UIImage] = []
    @State private var phase: Phase = .checkingBarcode
    @State private var trayItems: [NutTrayItem] = []
    @State private var trayTag: String?
    @State private var traySource = "photo"
    @State private var analysisTask: Task<Void, Never>?
    @State private var showCamera = false
    @State private var showLibrary = false
    @State private var cameraImage: UIImage?
    @State private var libraryItem: PhotosPickerItem?
    @State private var cameraMessage: String?
    /// The next picked photo is a nutrition label (OCR), not a meal photo.
    @State private var pickingLabel = false
    /// A barcode was read but is not in the database: the not-found screen offers "Scan nutrition label".
    @State private var barcodeMissed = false
    /// Optional one-line note for the analysis ("zero sugar", "air fried"). Never required.
    @State private var hint = ""

    var body: some View {
        Group {
            switch phase {
            case .checkingBarcode: busy("Checking barcode…")
            case .collecting: collecting
            case .disclosure: disclosure
            case .analyzing: analyzing
            case .readingLabel: readingLabel
            case .notFound(let message): notFound(message)
            case .tray:
                NutMealTrayContent(items: trayItems, mealTag: trayTag, source: traySource, heroPhoto: photos.first, close: close, onSaved: onSaved)
            }
        }
        .task { await start() }
        .fullScreenCover(isPresented: $showCamera) {
            CameraImagePicker(image: $cameraImage).ignoresSafeArea()
        }
        .photosPicker(isPresented: $showLibrary, selection: $libraryItem, matching: .images)
        .onChange(of: cameraImage) { _, image in
            guard let image else { return }
            cameraImage = nil
            handlePicked(image)
        }
        .onChange(of: libraryItem) { _, item in
            guard let item else { return }
            Task {
                defer { libraryItem = nil }
                if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                    handlePicked(image)
                }
            }
        }
        .onDisappear { analysisTask?.cancel() }
    }

    // MARK: Phases

    private func busy(_ title: LocalizedStringKey) -> some View {
        VStack(spacing: 14) {
            ProgressView()
            Text(title)
                .font(TTFont.workSans(16, weight: .semibold)).foregroundStyle(TTColor.ink)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .accessibilityElement(children: .combine)
    }

    private var analyzing: some View {
        VStack(spacing: 10) {
            busy("Looking at your photo…")
            nutPanelButton("Cancel", style: .ghost) {
                analysisTask?.cancel()
                phase = .collecting
            }
        }
    }

    private var readingLabel: some View {
        VStack(spacing: 10) {
            busy("Reading the label…")
            nutPanelButton("Cancel", style: .ghost) {
                analysisTask?.cancel()
                phase = .collecting
            }
        }
    }

    /// "Scan nutrition label": take or pick a photo of the label; the text is read on the device.
    private func labelScanMenu() -> some View {
        Menu {
            Button { pickingLabel = true; openCamera() } label: { Text("Take photo") }
            Button { pickingLabel = true; showLibrary = true } label: { Text("Choose photo") }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "text.viewfinder").font(.system(size: 15, weight: .semibold))
                Text("Scan nutrition label").font(TTFont.workSans(15, weight: .semibold))
            }
            .foregroundStyle(NutStyle.accentText)
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
        }
    }

    private var collecting: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Add photos")
                .font(TTFont.workSans(20, weight: .bold)).foregroundStyle(TTColor.ink)
                .accessibilityAddTraits(.isHeader)
            Text("Add up to 5 photos of the same meal.")
                .font(TTFont.body(14)).foregroundStyle(NutStyle.mute)
                .padding(.top, 2).padding(.bottom, 8)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(Array(photos.enumerated()), id: \.offset) { index, image in
                        ZStack(alignment: .topTrailing) {
                            Image(uiImage: image)
                                .resizable().scaledToFill()
                                .frame(width: 84, height: 84)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .accessibilityLabel(Text("Meal photo"))
                            Button { photos.remove(at: index) } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(.white)
                                    .frame(width: 22, height: 22)
                                    .background(Color.black.opacity(0.75))
                                    .clipShape(Circle())
                                    .frame(width: 44, height: 44)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(Text("Remove photo"))
                            .offset(x: 14, y: -14)
                        }
                        .frame(width: 84, height: 84)
                    }
                    if photos.count < 5 { addTile }
                }
                .padding(.top, 14).padding(.trailing, 16).padding(.bottom, 6)
            }

            if let cameraMessage {
                Text(verbatim: cameraMessage).font(TTFont.body(13)).foregroundStyle(NutStyle.mute).padding(.bottom, 6)
            }

            TextField("Optional note (e.g. zero sugar, air fried, chicken)", text: $hint)
                .font(TTFont.body(15))
                .lineLimit(1)
                .submitLabel(.done)
                .padding(.horizontal, 14)
                .frame(minHeight: 44)
                .background(NutStyle.field)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .padding(.top, 8)
                .onChange(of: hint) { _, value in
                    if value.count > 200 { hint = String(value.prefix(200)) }
                }
                .accessibilityLabel(Text("Optional note"))

            nutPanelButton("Analyze", style: .primary) { analyze() }
                .disabled(photos.isEmpty)
                .opacity(photos.isEmpty ? 0.4 : 1)
                .padding(.top, 8)
            labelScanMenu()
            nutPanelButton("Cancel", style: .ghost) { close(nil) }
        }
    }

    private var addTile: some View {
        Menu {
            Button { openCamera() } label: { Text("Take photo") }
            Button { showLibrary = true } label: { Text("Choose photo") }
        } label: {
            VStack(spacing: 4) {
                TTIcon(icon: .camera1, size: 20)
                Text("+ Add photo")
                    .font(TTFont.workSans(12, weight: .semibold))
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(NutStyle.accentText)
            .frame(width: 84, height: 84)
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(NutStyle.orange, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
            )
        }
        .accessibilityLabel(Text("Add photo"))
    }

    private var disclosure: some View {
        VStack(spacing: 0) {
            TTIcon(icon: .camera1, size: 28)
                .foregroundStyle(NutStyle.orange)
                .frame(width: 64, height: 64)
                .background(Color(red: 1, green: 241 / 255, blue: 230 / 255))
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .padding(.top, 6).padding(.bottom, 10)
                .accessibilityHidden(true)
            Text("AI photo analysis")
                .font(TTFont.workSans(20, weight: .bold)).foregroundStyle(TTColor.ink)
                .accessibilityAddTraits(.isHeader)
            Text("Meal photos are analyzed by AI to estimate calories and macros. Photos are not used to train AI models.")
                .font(TTFont.body(14)).foregroundStyle(NutStyle.mute)
                .multilineTextAlignment(.center)
                .padding(.top, 2).padding(.bottom, 10)
            nutPanelButton("Continue", style: .primary) {
                UserDefaults.standard.set(true, forKey: Self.disclosureKey)
                runAnalysis()
            }
            nutPanelButton("Cancel", style: .ghost) { phase = .collecting }
        }
        .frame(maxWidth: .infinity)
    }

    private func notFound(_ message: String) -> some View {
        VStack(spacing: 10) {
            TTIcon(icon: .infoCircle, size: 28)
                .foregroundStyle(TTColor.inkMuted)
                .padding(.top, 6)
                .accessibilityHidden(true)
            Text(verbatim: message)
                .font(TTFont.body(15)).foregroundStyle(TTColor.ink)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8).padding(.bottom, 6)
            nutPanelButton("Search", style: .primary) { onSearch() }
            if barcodeMissed { labelScanMenu() }
            nutPanelButton("Retake", style: .ghost) {
                photos = []
                phase = .collecting
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Actions

    private func start() async {
        guard photos.isEmpty else { return }
        if startsWithLabelScan {
            scanLabel(firstPhoto)
            return
        }
        photos = [firstPhoto]
        // On-device barcode fast path: a found barcode costs no AI call.
        guard let code = await NutBarcode.detect(in: firstPhoto) else {
            phase = .collecting
            return
        }
        phase = .checkingBarcode
        do {
            let response = try await store.lookupBarcode(code)
            if response.found == true, let item = response.item, let tray = NutTrayBuilder.item(from: item) {
                trayItems = [tray]
                trayTag = nil
                traySource = "barcode"
                phase = .tray
            } else {
                barcodeMissed = true
                phase = .notFound(String(localized: "Barcode not found — take a photo of the food or search."))
            }
        } catch {
            phase = .notFound(String(localized: "Couldn’t analyze right now. Check your connection, or search for the food instead."))
        }
    }

    private func handlePicked(_ image: UIImage) {
        if pickingLabel {
            pickingLabel = false
            scanLabel(image)
        } else {
            addPhoto(image)
        }
    }

    /// Label photo → text on the device (Vision) → `parse-label` → Meal Tray with a Verified Label item.
    private func scanLabel(_ image: UIImage) {
        phase = .readingLabel
        analysisTask?.cancel()
        analysisTask = Task {
            let text = await NutLabelOCR.recognize(in: image)
            if Task.isCancelled { return }
            guard text.trimmingCharacters(in: .whitespacesAndNewlines).count >= 10 else {
                phase = .notFound(String(localized: "Couldn’t read this label — retake the photo or search."))
                return
            }
            do {
                let response = try await store.parseNutritionLabel(ocrText: text)
                if Task.isCancelled { return }
                if response.found == true, let item = response.item, let tray = NutTrayBuilder.item(from: item) {
                    trayItems = [tray]
                    trayTag = nil
                    traySource = "label"
                    phase = .tray
                } else {
                    phase = .notFound(String(localized: "Couldn’t read this label — retake the photo or search."))
                }
            } catch {
                if Task.isCancelled { return }
                phase = .notFound(String(localized: "Couldn’t analyze right now. Check your connection, or search for the food instead."))
            }
        }
    }

    private func addPhoto(_ image: UIImage) {
        guard photos.count < 5 else { return }
        photos.append(image)
        if phase != .collecting { phase = .collecting }
    }

    private func openCamera() {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else { showLibrary = true; return }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            showCamera = true
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    if granted {
                        showCamera = true
                    } else {
                        cameraMessage = String(localized: "Camera access is off — choose a photo from your library.")
                        showLibrary = true
                    }
                }
            }
        default:
            cameraMessage = String(localized: "Camera access is off — choose a photo from your library.")
            showLibrary = true
        }
    }

    private func analyze() {
        guard !photos.isEmpty else { return }
        // First cloud analysis: one-time AI disclosure (App Store guideline 5.1.2).
        if UserDefaults.standard.bool(forKey: Self.disclosureKey) {
            runAnalysis()
        } else {
            phase = .disclosure
        }
    }

    private func runAnalysis() {
        phase = .analyzing
        analysisTask?.cancel()
        let images = photos
        let note = hint
        analysisTask = Task {
            do {
                let result = try await store.analyzeMealPhotos(images, hint: note)
                if Task.isCancelled { return }
                let mapped = (result.items ?? []).map { NutTrayBuilder.item(from: $0) }
                if result.isFood == false || mapped.isEmpty {
                    let message = (result.message ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    phase = .notFound(message.isEmpty ? String(localized: "We couldn’t recognise a meal in this photo.") : message)
                    return
                }
                trayItems = mapped
                trayTag = result.mealTag
                traySource = "photo"
                phase = .tray
            } catch {
                if Task.isCancelled { return }
                phase = .notFound(String(localized: "Couldn’t analyze right now. Check your connection, or search for the food instead."))
            }
        }
    }
}

extension Notification.Name {
    /// A meal was saved outside the Nutrition screen (Home, + menu).
    static let ttMealSaved = Notification.Name("ttMealSaved")
}

/// Home and the + menu: the same Add photos → barcode / AI → Review your meal flow as Nutrition, in a normal sheet.
struct TTMealPhotoFlowSheet: View {
    @Environment(\.dismiss) private var dismiss
    let image: UIImage
    var onSaved: (TTToastMessage) -> Void
    /// "Search" on the not-found screen: called after this sheet has closed.
    var onSearch: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 0) {
            Capsule().fill(Color(red: 212 / 255, green: 212 / 255, blue: 216 / 255))
                .frame(width: 40, height: 5).padding(.top, 8).padding(.bottom, 10)
                .accessibilityHidden(true)
            ScrollView {
                NutCaptureContent(
                    firstPhoto: image,
                    close: { after in dismiss(); after?() },
                    onSaved: { toast in
                        NotificationCenter.default.post(name: .ttMealSaved, object: nil)
                        onSaved(toast)
                    },
                    onSearch: {
                        dismiss()
                        if let onSearch {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { onSearch() }
                        }
                    }
                )
                .padding(.horizontal, 18)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .background(Color.white.ignoresSafeArea())
    }
}

// MARK: - Compatibility: other screens open the add sheet as a normal sheet (centre "+" menu)

struct ManualMealView: View {
    @Environment(\.dismiss) private var dismiss
    let day: Date
    var prefillName: String? = nil
    var initialPhoto: UIImage? = nil
    var onSaved: ((TTToastMessage) -> Void)? = nil

    var body: some View {
        VStack(spacing: 0) {
            Capsule().fill(Color(red: 212 / 255, green: 212 / 255, blue: 216 / 255))
                .frame(width: 40, height: 5).padding(.top, 8).padding(.bottom, 10)
            ScrollView {
                NutritionEntryContent(
                    editing: nil,
                    initialPhoto: initialPhoto,
                    initialQuery: prefillName,
                    close: { after in dismiss(); after?() },
                    onSaved: { toast in onSaved?(toast) },
                    onDelete: { _ in }
                )
                    .padding(.horizontal, 18)
                    .padding(.bottom, 24)
            }
        }
        .background(Color.white.ignoresSafeArea())
    }
}

#Preview("Nutrition Home") {
    NutritionView()
        .ttPreviewTrainee()
}
