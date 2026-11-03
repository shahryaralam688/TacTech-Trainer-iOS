# Group 1 — Trainee Home (`TraineeDashboardView`)

> Design spec for the trainee's Home tab and its relationship surfaces. Build-ready layout + tokens,
> **not SwiftUI**. All behavior reads existing `AppStore` flags; no new rules/permissions.
> Wireframes are ASCII; English copy is illustrative (final copy via `Localizable.xcstrings`).

Presentation: **tab root** (`TraineeRootView` → Home). Container = `NavigationStack` with the existing
**collapsing dark hero** (`TTHomeProfileHeader`) over a top-rounded scrolling body on `TTColor.canvas`.
Center **FAB** (AI Coach / Coach chat) and `TTFloatingTabBar` persist. No structural change — this
screen keeps its zones (Today · Progress · Health & Support); the work is **state legibility + the two
fixes that touch Home (E resume target, N relationship surface) + the H completion nudge**.

---

## 1. Screen anatomy (shared skeleton)

```
┌─────────────────────────────────────────────┐  ← status bar (safe area)
│  ░░░  TTHomeProfileHeader (TTPurple.p100)  ░░│
│  Good morning,                      ◍ avatar │  greeting: text.textLG inkOnDarkMuted
│  Alex                               🔔 bell  │  name: heading.headingLG inkOnDark
│  ┌─ metric ─┬─ metric ─┬─ metric ─┐          │  TTHomeProfileMetric row (streak / today / wk)
│  │  5 day   │  320 kcal │  3/4 wk  │          │  bell = Notifications entry (badge if unread)
│  └──────────┴───────────┴──────────┘          │
╰──────────────────────────────────────────────╯  ← header collapses on scroll (existing math)
┌─────────────────────────────────────────────┐  ← body, TTColor.canvas, radius header(56) top
│  TODAY                                        │  TTSectionHeader (overline, inkSubtle)
│  ┌───────────────────────────────────────┐   │
│  │   [ TODAY CARD — state-driven, §2 ]    │   │  primary surface; variants below
│  └───────────────────────────────────────┘   │
│                                               │
│  PROGRESS                                     │  TTSectionHeader
│  ┌─ ring ─┐  ┌─ signal ─┐  ┌─ signal ─┐       │  TTProgressRing + TTMetricCard ×n
│  │  62%   │  │ sessions │  │ best form│       │  (only when hasMeaningfulActivity)
│  └────────┘  └──────────┘  └──────────┘       │
│                                               │
│  HEALTH & SUPPORT                             │  TTSectionHeader
│  ┌── coach / find-a-coach card (§3) ──────┐   │
│  ┌── diet snapshot · form insights ───────┐   │  TTHomeEmptyState when no data
│  [ Complete your profile (2 of 5)  ✕ ]        │  §4 nudge — dismissible, only if incomplete
└─────────────────────────────────────────────┘
        ⌂        🏋        🍎        ◍            ← TTFloatingTabBar + center FAB
```

Tokens: section gaps `TTSpace.s32`; card insets `TTSpace.s16`; card radius `TTRadius.md`(16);
card fill `TTColor.surface` with `TTShadow.card`. Screen margins `.ttScreenMargins()` (16).

---

## 2. TODAY card — the contextual CTA (state machine)

Single card, one primary action, resolved by the existing Phase 3 §4.1 resolver. Only **one** variant
shows at a time. Primary button = `TTButton(.primary)` (brand fill, `buttonHero` radius, height 56–64);
secondary = `TTButton(.ghost)`.

### 2a. ⌛ New trainee, no plan, solo-AI eligible → "Build my plan"
`canShowSoloAIGenerate == true`
```
┌───────────────────────────────────────┐
│  ✦  Start your training                │  heading.headingSM ink
│  Build a personalized AI plan from     │  paragraph.regular inkMuted
│  your assessment in seconds.           │
│  ┌─────────────────────────────────┐   │
│  │        Build my plan      →      │   │  TTButton(.primary), icon sparkles
│  └─────────────────────────────────┘   │
└───────────────────────────────────────┘
```
Tap → **sheet** `AssessmentReviewSheet` (`.ttTopRoundedSheet`). Icon: SF `sparkles` / Sandow AI mark.
Secondary door (Workout empty CTA) opens the **same** sheet.

### 2b. ✅ Active session live, day resolves → "Continue Workout" (friction E)
`activeWorkoutSession != nil` AND `dayId` resolves to a plan day
```
┌───────────────────────────────────────┐
│  ● In progress · Push Day              │  TTCardBadge tone=accent, inkMuted meta
│  Exercise 3 of 6 · Bench Press         │  text.textMD ink  (from activeExerciseIndex)
│  ┌─────────────────────────────────┐   │
│  │     Continue Workout    ▸        │   │  TTButton(.primary), SF arrow.right.circle.fill
│  └─────────────────────────────────┘   │
└───────────────────────────────────────┘
```
Tap → **push** (or fullScreenCover, matching current guided launch) `ActiveWorkoutView(plan:day:)`
for the **resolved** day → resumes at `activeExerciseIndex`. **Fallback 2b′:** if `dayId` nil/unresolved,
same button label but destination = `WorkoutHubView` (today's behavior). No new resume rule.

### 2c. Plan exists, not done today → "Start Today's Workout"
```
┌───────────────────────────────────────┐
│  Today · Upper Body                    │  text.textMD ink
│  6 exercises · ~45 min                 │  paragraph.caption inkSubtle
│  ┌─────────────────────────────────┐   │
│  │     Start Today's Workout        │   │  TTButton(.primary)
│  └─────────────────────────────────┘   │
└───────────────────────────────────────┘
```
Tap → **sheet** `WorkoutHubView`. (If no session yet, label "See My Workouts" per resolver.)

### 2d. ✅ Done today → "View today's workout" + ghost "Go again"
```
┌───────────────────────────────────────┐
│  ✓ Completed today · nice work         │  success icon + text.textMD ink
│  ┌───────────────┐ ┌───────────────┐   │
│  │ View workout  │ │   Go again     │   │  .secondary + .ghost
│  └───────────────┘ └───────────────┘   │
└───────────────────────────────────────┘
```
Both → `WorkoutHubView`.

### 2e. ⌛ Linked coach, no plan yet → relationship explainer (friction B/N, U2 neutral)
`hasLinkedTrainer == true` AND `assignedPlan == nil`
```
┌───────────────────────────────────────┐
│  👤  Coach Maya guides your training    │  heading.headingSM ink  (U2 NEUTRAL copy only)
│  Waiting for Maya to assign your first  │  paragraph.regular inkMuted
│  plan. You'll be notified when it's     │
│  ready.                                 │
│  ┌─────────────────────────────────┐   │
│  │     View coach             →      │   │  TTButton(.secondary) → Profile trainer section
│  └─────────────────────────────────┘   │
└───────────────────────────────────────┘
```
Uses `TTAlertBanner` tone=`info` inline styling. **No AI-generate CTA here** (gated off, correctly).
U2: shows only the neutral "guides your training" line — no retain/pause/replace claim.

### 2f. No plan, not solo-AI eligible, no trainer → "Link a coach to get workouts"
```
┌───────────────────────────────────────┐
│  Get a workout plan                    │
│  Train with AI or link a coach to get  │  paragraph.regular inkMuted
│  started.                              │
│  ┌─────────────────────────────────┐   │
│  │        Find a coach        →      │   │  TTButton(.primary) → FindCoaches sheet
│  └─────────────────────────────────┘   │
└───────────────────────────────────────┘
```

---

## 3. Relationship surface on Home (friction N — one legible component)

A compact mirror of the Profile relationship component (full version in Group 5). On Home it appears
in **Health & Support** as a single row-card driven by the same state machine (Phase 4 §C1):

| State | Card copy (neutral) | Action → | Tone |
|-------|---------------------|----------|------|
| No trainer | "Train with a coach" | Find a coach → FindCoaches sheet | accent |
| ⌛ Pending | "Request sent to {coach}" | View status → Profile | info |
| Linked | "Coached by {coach}" | Message / View → chat / Profile | success |
| ⚠ Rejected | "Request declined" | Try another coach | warning |
| Removed/left | "Training on your own" | Explore coaches | info |

`TTListTile` with leading avatar/icon, title + subtitle, trailing chevron. RTL: chevron + avatar mirror.
No color-only cues — each pairs an SF Symbol (`person.crop.circle`, `clock`, `checkmark.seal`,
`xmark.circle`, `figure.walk`).

---

## 4. Profile completion nudge (friction H — non-blocking)

Dismissible card, **never a gate**. Shows only when profile incomplete; routes to existing
`ProfileCompletionFlowView` (sheet).
```
┌───────────────────────────────────────┐
│ ◗ Complete your profile      2 of 5  ✕ │  TTProgressRing mini + text.textSM; ✕ dismiss
│ ▓▓▓▓▓▓░░░░░░░░░░                        │  progress bar, TTColor.brand fill
└───────────────────────────────────────┘
```
Tap → **sheet** `ProfileCompletionFlowView`. ✕ → dismiss for session (no persistence rule invented).
Placement: bottom of Health & Support, below the fold — unobtrusive.

---

## 5. Full state coverage (empty · loading · pending · active · completed · error)

| State | Trigger | Home surface | Presentation | Component |
|-------|---------|--------------|--------------|-----------|
| ∅ Empty (new user) | no plan/logs/trainer/meals | `getStartedCard`: "Log a meal" / "Find a coach" | inline | `TTHomeEmptyState` |
| ⏳ Loading | first appear, refresh tasks | **silent** — render already-loaded store data; no blocking spinner | inline | — (background refresh) |
| ⌛ Pending | `pendingJoinRequest != nil` | §3 pending card | inline | `TTListTile`/`TTAlertBanner` |
| ● Active | `activeWorkoutSession != nil` | §2b Continue card | inline | card + `TTButton` |
| ✅ Completed | `hasCompletedTodayWorkout` | §2d done card | inline | card |
| ⚠ Error | refresh/action failure | soft `TTToastMessage` (non-blocking), content stays | toast `.ttToast` | `TTToastBanner` |

Loading note: Home intentionally has **no full-screen spinner** — it shows the last-loaded state and
refreshes silently (matches current behavior; honest, no skeleton flash). Any hard failure surfaces as
a dismissible toast, never an error screen.

---

## 6. Navigation & presentation map (this screen's destinations)

| Trigger | Destination | Presentation |
|---------|-------------|--------------|
| Bell icon | `NotificationsInboxView` | sheet |
| Build my plan / Workout empty | `AssessmentReviewSheet` | sheet (`.ttTopRoundedSheet`) |
| Continue Workout (day resolves) | `ActiveWorkoutView` | push / fullScreenCover (match guided) |
| Continue Workout (unresolved) · Start · View · Go again | `WorkoutHubView` | sheet |
| Find a coach | `FindCoachesView` | sheet |
| View coach / relationship | Profile trainer section | tab switch / push |
| Complete profile | `ProfileCompletionFlowView` | sheet |
| Center FAB | AI Coach chat / Human coach chat | fullScreenCover |

---

## 7. RTL / localization specifics (Arabic + 5 others)

- Greeting + name left-aligned (LTR) / right-aligned (RTL); metric row mirrors order.
- All CTA chevrons/arrows flip (`→` becomes `←`); progress bars fill from trailing edge in RTL.
- "2 of 5" uses locale numerals; "Exercise 3 of 6" likewise.
- Coach name interpolated via localized format string (`"relationship.coached_by %@"`), never concatenated.
- Dynamic Type: Today card grows vertically; buttons keep 56–64 height, text wraps (no truncation of CTAs).

---

## 8. What stays exactly as-is (no redesign-for-novelty)

- Zone order (Today · Progress · Health & Support), collapsing hero, FAB, tab bar — unchanged.
- Progress ring, metric cards, diet/form snapshots — same components, same data sources.
- Every existing entry point remains; we only unify destinations/labels and add the §2e/§3/§4 surfaces.

---

### Open items touching this screen (carried, not decided)
- **U2** — §2e/§3 copy is the neutral default; swap to retain/pause/replace strings only on product sign-off.
- **U5/Age** — not surfaced on Home; no action here.
- Completion nudge dismiss persistence (session-only shown) — confirm desired persistence in Phase 6 if needed (no rule invented now).

*End of Group 1. Awaiting review before Group 2 (Trainee Workout Hub + Active Workout).*
