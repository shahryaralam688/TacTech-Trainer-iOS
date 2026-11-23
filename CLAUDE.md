# TacTech Trainer iOS — instructions for Claude

**Read this file before changing anything in this project.** The rules in "Working rules" apply to every task unless the owner explicitly says otherwise in that message.

## What this app is

TacTech is an iOS fitness-coaching app with two roles in one binary:

- **Trainer:** manages trainees, builds and assigns workout plans, chats with trainees, uses an AI Coach.
- **Trainee:** follows an assigned plan, logs workouts and nutrition, tracks progress, chats with their trainer, uses an AI Coach.

Stack: SwiftUI, iOS 17+, portrait only, Swift 5 language mode, no third-party package manager (code in `Vendor/`). The Xcode project is generated from `project.yml` (XcodeGen layout, sources = the `TacTech/` folder, so new files are picked up automatically).

## Project map

| Path | What lives there |
|---|---|
| `TacTech/App`, `TacTechApp.swift` | App entry, root routing between auth / trainer / trainee |
| `TacTech/Features/Trainer` | Home (`TrainerDashboardView`), Plans (`WorkoutPlansView`, `CreatePlanView`), `TraineeDetailView`, `MyTraineesView` (roster, now opened as a sheet from Chat), root tabs (`TrainerRootView`) |
| `TacTech/Features/Trainee` | Trainee tabs: Home, Workout, Nutrition, Progress (`TraineeRootView`) |
| `TacTech/Features/Chat` | `HumanPeerChatView` (the one chat screen, used full-screen and as the trainer Chat tab), calls, bubbles, composer |
| `TacTech/Features/Coach` | AI Coach screens |
| `TacTech/Features/Authentication`, `Notifications` | Sign-in, onboarding, settings, help, notification inbox |
| `TacTech/DesignSystem` | All shared UI (`TT*` components): tab bar, toasts, sheets, headers, search, cards, `SandowIcons`, theme tokens in `TTTheme.swift` |
| `TacTech/Data` | `AppStore` (single app-wide observable store), `APIClient`, chat/AI/notification stores, `APIConfig` (server URL) |
| `TacTech/Models` | Plain data models (`WorkoutPlan`, `PlanDay`, `WorkoutLog`, `TraineeProfile`, …) |
| `TacTech/Resources/Localizable.xcstrings` | All localized strings (6 languages) |
| `docs/` | Backend prompts/specs and `I18N.md` |
| `TacTech-UX-Redesign/` | Design/UX reference documents (read-only reference) |

Trainer root tabs: Home · Plans · Chat · Profile, plus a centre **+** button that opens a quick-actions menu (AI, create plan, assign, assignments). Trainee root tabs: Home · Workout · Nutrition · Progress.

## Working rules (the owner's standing instructions)

1. **UI/UX and wording only, unless told otherwise.** Do **not** change architecture, models, `AppStore`, `APIClient`, API calls, auth, or business logic. If a UX goal seems to need one of those, stop and ask.
2. **Never invent data.** If something is not in the existing data, show a neutral placeholder and leave a `// TODO:` that says what data is missing. Do not guess (for example workout titles from weekdays).
3. **Reuse before creating.** Use existing `TT*` components, tokens (`TTColor`, `TTFont`, `TTSpace`) and sheet presentation (`.ttModalSheetPresentation()`). New parameters on existing views must be **optional with defaults** so existing callers keep working. Don't add dependencies.
4. **Work in small steps.** Do one step, build, report briefly, then **stop and wait**. Do the next phase only when the owner says so ("go 3", "go home", "commit"). Don't continue ahead.
5. **Do not commit or push unless the owner says "commit".** Never push unless explicitly told. Commit only the files you changed for that task; leave other modified files alone.
6. **Report format:** short, with `file:line` references, what changed, and what was **not** verified. Say plainly when something is untested.
7. **Don't touch unrelated screens or remove existing functionality.** Preserve the existing look unless the task is a redesign.
8. **Read-only means read-only.** When asked to "check", "tell me why" or "report only", make no edits.

## UX standards to hold to

- Follow Apple HIG: 44×44pt minimum tap targets, safe areas, Dynamic Type friendly text, Reduce Motion respected (no motion when it's on), VoiceOver labels on every icon-only control.
- Prefer visible controls over hidden gestures (long-press, swipes) — gestures may exist as shortcuts, never as the only way.
- One clear primary action per screen/card; destructive actions are visually distinct, confirmed, and offer Undo where it's cheap.
- Never use two navigation styles in one stack: pushes go through one `navigationDestination(item:)` / `(isPresented:)` per stack; don't mix with closure `NavigationLink`s (this caused the "Modify does nothing" bug).
- RTL: Arabic is supported. Gestures and layouts must mirror (use leading/trailing, check `layoutDirection`).
- Every user-visible string must exist in `Localizable.xcstrings` for `en, ar, es, fr, hi, zh-Hans` (mark `needs_review` if not professionally translated — never leave empty). See `docs/I18N.md`.
- Use the product name **TacTech** (never "TecTach").

## Conventions and gotchas

- Tabs stay mounted; each has its own `NavigationStack`. The tab bar hides on pushed screens via `ttSyncRootTabBarWithNavigationDepth()` and `TTRootTabBarVisibleKey`. Embedded screens that need the bar hidden publish `.ttRootTabBarVisible(false)`.
- Swipe helpers (`ttSwipeBetweenTabs`, `ttEdgeSwipeBack`, `ttTabFade`) and the re-enabled iOS edge-swipe-back live in `DesignSystem/TTTabBarChrome.swift`.
- Toasts: `.ttToast($binding)`; `TTToastMessage` supports an optional action (e.g. **Undo**, stays 5 s).
- `PlanQuickAssignSheet` (in `WorkoutPlansView.swift`) is the **one** assign UI. Modes: default (plan + trainee pickers), trainee mode (`preselectedTraineeId`), plan mode (`preselectedPlanId`). The opener shows the toast after `onAssigned`.
- `WorkoutPlan` has **no created date** — "Newest/Oldest" sort relies on store order. `WorkoutLog` has **no plan-day id**. Don't fake either.
- `Localizable.xcstrings` must keep Xcode's exact formatting (`"key" : {` with a blank line inside empty entries). Edit it with a script that round-trips byte-for-byte; never re-dump it with default JSON formatting (that produces a 10,000-line diff).
- No test target exists yet. Verification today = build + run in the simulator.

## Build and run

```
xcodebuild -scheme TacTech -destination 'id=<simulator-udid>' -configuration Debug build
```

Bundle id `com.tactech.trainer.shahryar`. The simulator can be driven for screenshots (`xcrun simctl io <udid> screenshot`) but **tap/swipe automation is not installed** — say "not tested on device" instead of claiming an interaction works.

## Project audit (as of 2026-11-11)

**Verdict: not ready for production.** It builds clean (Release too; only Swift 6 concurrency warnings in `TTStackedSections`, `NotificationAPI`, `LocalizationController`).

### Blockers
1. **API server is a LAN address over HTTP:** `TacTech/Data/APIConfig.swift` → `http://192.168.18.32:8000`. Real users can't reach it; chat/call websockets use the same host. Needs an HTTPS production URL, set per build configuration (Debug/Release).
2. **App Transport Security** in `Info.plist` only has an exception for an old ngrok domain. Remove it and the ngrok header constants once a real HTTPS URL is in.
3. **No automated tests** (no test target). Nothing guards sign-in, plan create/assign/delete, or chat.
4. **Personal identity in release config:** bundle id `com.tactech.trainer.shahryar` and a personal signing team (`project.yml`). Needs the company id/team, app icon/version/privacy-policy/account-deletion review items before App Store submission.

### Should fix
- Two hard crashes: `fatalError` when the Form Studio web folder is missing (`FormStudioWebView.swift`), and an unused `required init` in `HumanCallView.swift`. Replace the first with an error screen.
- ~10 `TODO`s mark unfinished features (water tracking, offline banner, summary share, trainee unread count, timed-exercise unit). Hide or finish before launch.
- ~10 `print()` calls remain; "demo" strings/accounts exist (`demoHint` is DEBUG-only; others not reviewed).
- Translations added by AI (`needs_review`) for ar/es/fr/hi/zh-Hans need a native review.
- Large files: `WorkoutPlansView.swift` (~1,900 lines, holds several unrelated views), `AppStore.swift`, `HumanPeerChatView.swift`. Splitting them would help, but only as its own task.

### Unverified / open items
- Plan detail "Modify" button reported as doing nothing. Fixed structurally (one push style per stack) but **not confirmed on a device**.
- Tab slide transition and swipe-between-tabs/edge-swipe-back were built but **never exercised on a device**; a screenshot showed Plans content shifted sideways mid-transition (cause unconfirmed — see git history/discussion).
- Message → chat for a trainee with no thread yet relies on the chat store creating the thread; untested.
- Assign flow "Step 2" (plan mode in `PlanQuickAssignSheet` + single "Assign this plan" button on plan detail) is **not built**.
- Simulator test plan a–g (create plan → saved screen → assign paths, Modify) has **not been run**.

### Recommended order
1. Production URL + ATS cleanup, per-configuration. 2. Full manual pass on a real device against that server. 3. Replace crash points, hide placeholder features. 4. Basic tests for assign and plan CRUD. 5. Native translation review, then release checklist.

## Loading states and skeletons

Reference: the "Skeleton loading rules" prototype. Components live in `TacTech/DesignSystem/TTComponents.swift` (section "Loading states"). They are in an existing file on purpose: a new Swift file is not in the target of the tracked `.xcodeproj` until XcodeGen regenerates it (verified: the build fails with "cannot find in scope").

**Every screen that loads data has four states:** loading (skeleton), content, empty (what the screen is for + ONE action, `TTLoadEmpty`), error (calm text + **Try again**, `TTLoadError`; if stale content exists keep it and show `TTStaleNotice` above it instead).

**Use a skeleton when** the layout is known and the data comes from the network and takes more than ~0.2 s.
**Do NOT use one for:** data the store already has (show it, refresh quietly), button actions (inline spinner in the button), pull to refresh (system control), instant local content, tiny sections.

**Timing constants** (only in `TTLoadTiming`): `showDelay` 0.2 s, `minVisible` 0.4 s, `crossfade` 0.2 s, `pulsePeriod` 1.4 s, `maxPlaceholderRows` 6, `placeholderRows(rowHeight:)` = rows that fit the screen, at most 6.

**Build one, step by step**
1. Find the loading flag and whether the store already has data (`hasData`). If the store has no flag, add the smallest one (view `@State` first; a store change only if the failure is otherwise invisible, and say so).
2. Wrap the section in `TTLoadGate(isLoading:, hasData:, loadingLabel:)`. Skeleton = the REAL row/card rendered with placeholder data + `.ttSkeleton()`. Content = the real view, including its empty and error branches.
3. The first load must start from `isLoading == true` (for example `!didLoad || store.isLoading`), otherwise the empty state flashes before the load starts.
```swift
TTLoadGate(isLoading: !didLoad || store.isLoading, hasData: !store.items.isEmpty,
           loadingLabel: "Loading notifications") {
    VStack(spacing: 12) {
        ForEach(0..<TTLoadTiming.placeholderRows(rowHeight: 100), id: \.self) { _ in row(placeholder) }
    }.ttSkeleton()
} content: {
    if store.lastError != nil { TTLoadError(title: "Couldn’t load notifications") { Task { await store.refresh() } } }
    else { TTLoadEmpty(icon: .bell1, title: "No notifications yet", message: "…") }
}
```

**Layout-match rule:** same paddings, heights, radii and structure as the content, so nothing shifts. Prefer the real view with placeholder data. Check with simulator screenshots (skeleton vs content) using a temporary delay hook in a COPY of the project, never in the repo.
**Accessibility:** placeholders are hidden from VoiceOver; the gate gives one "Loading …" label and posts a layout-change announcement when content arrives. Localize the label and the error text.
**Performance:** one pulse per section (opacity only), no `GeometryReader` loops or per-frame scroll readers, no heavy work in `body`, never render skeleton rows that are off screen (the 6-row cap).
**Reduce Motion:** the pulse and the crossfade are off; placeholders are static.

**Review checklist (copy into every new screen)**
- [ ] Loading, content, empty and error states all exist
- [ ] No skeleton when the store already has data; no skeleton for loads under 0.2 s
- [ ] Skeleton is the real layout with placeholder data; screenshots compared
- [ ] Pull to refresh is the system control; buttons use an inline spinner
- [ ] Failed refresh keeps stale content with `TTStaleNotice`
- [ ] VoiceOver: one loading label, placeholders hidden; strings in `Localizable.xcstrings` (6 languages)
- [ ] Reduce Motion and dark mode checked
