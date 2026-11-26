import AVFoundation
import Charts
import ImageIO
import PhotosUI
import SwiftUI
import Vision

// MARK: - Nutrition (Today · History) — rebuilt from Design/nutrition-prototype.html
// Phase 1: header, Today | History switch, search row, Today (ring, Planned, Eaten), add/edit sheet,
// goal sheet, "Food scan" sheet. History body and the camera/analyze flow come in the next phases.

enum NutTab { case today, history }

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

enum NutStyle {
    static let charcoal = TTColor.charcoal
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
}

// MARK: - Screen

struct NutritionView: View {
    @Environment(AppStore.self) var store
    @Environment(\.accessibilityReduceMotion) var reduceMotion

    @State var tab: NutTab = .today
    @State private var panel: NutPanelKind?
    @State private var toast: TTToastMessage?

    /// Load state for today's list (view-local, see CLAUDE.md loading rules).
    @State private var isLoadingDay = true
    @State private var dayLoadFailed = false
    @State private var didLoadToday = false

    @State var historyRange: NutHistoryRange = .days
    @State var selectedBucketIndex: Int? = nil
    @State var barsGrown = false
    @State var isLoadingHistory = false
    @State var showHistorySkeleton = false
    @State var historyLoadFailed = false
    @State var summaryByPeriod: [NutHistoryRange: MealSummaryResponse] = [:]
    @State var cachedHistoryBuckets: [NutHistoryBucket] = []
    @State var loadedHistoryDays = 0

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
                            case .today:
                                VStack(alignment: .leading, spacing: 0) {
                                    // Scrolls with the list and glides under the pinned Today | History bar.
                                    searchRow
                                        .padding(.top, 4)
                                        .padding(.bottom, 12)
                                    todayBody
                                }
                            case .history: historyBody
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, tab == .history ? 144 : 120)
                    } header: {
                        stickyBar
                    }
                }
            }
            // Today and History are different lengths: always start the other tab at the top (a kept scroll
            // position showed only the bottom of the list, which looked like the logs were gone).
            .onChange(of: tab) { _, _ in
                proxy.scrollTo("nutTop", anchor: .top)
            }
          }
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

    // MARK: Sticky bar (Today | History only)

    private var stickyBar: some View {
        tabSwitch
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(Color.white)
        .frame(maxWidth: .infinity)
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
        .frame(height: 48)
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

    // MARK: Today

    var traineeId: String? { store.currentTrainee?.id }
    var goal: Int { store.currentTrainee?.dailyCalorieTarget ?? 0 }

    private var todaysMeals: [Meal] {
        guard let traineeId else { return [] }
        return store.meals(for: traineeId, on: Date())
    }

    private var planned: [Meal] { todaysMeals.filter(\.isPlanned).sorted { $0.eatenAt < $1.eatenAt } }
    private var eaten: [Meal] { todaysMeals.filter { !$0.isPlanned }.sorted { $0.eatenAt > $1.eatenAt } }

    private var hasData: Bool { !todaysMeals.isEmpty || didLoadToday }

    static let placeholder = Meal(
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

    func entryRow(_ meal: Meal, first: Bool) -> some View {
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

struct NutCountUpText: View {
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
struct NutTile: View {
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

func nutPanelButton(_ title: LocalizedStringKey, style: NutPanelButtonStyle, loading: Bool = false, action: @escaping () -> Void) -> some View {
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

enum NutPanelButtonStyle { case primary, ghost, danger }

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

// MARK: - Add / edit sheet

// MARK: Kinds, sizes and the draft

enum NutKind: String {
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

/// Wrapping row for chips (a second line at large text sizes).
struct NutFlow: Layout {
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

struct NutNutrition {
    var kcal = 0.0
    var p = 0.0
    var c = 0.0
    var f = 0.0
    var fiber = 0.0

    func scaled(_ k: Double) -> NutNutrition {
        NutNutrition(kcal: kcal * k, p: p * k, c: c * k, f: f * k, fiber: fiber * k)
    }
}

#Preview("Nutrition Home") {
    NutritionView()
        .ttPreviewTrainee()
}
