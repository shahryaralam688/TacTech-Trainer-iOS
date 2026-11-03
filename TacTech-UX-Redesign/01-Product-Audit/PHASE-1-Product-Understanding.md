# TacTech — Phase 1: Existing Product Understanding

> **Scope of this document:** A factual map of how the existing iOS app works today, verified
> against the current `payment_integrated` source. No redesign, no opinions — those come in
> Phase 2 (Audit) onward. Everything here is read-only research; no app source was modified.

---

## 1. What TacTech is

**TacTech** is a native iOS (SwiftUI) fitness app with **two fixed roles chosen at signup**:

- **Trainee** — trains via an AI-generated plan *or* under a human trainer; tracks workouts,
  nutrition, form, and progress.
- **Trainer (Coach)** — builds workout plans, manages a roster of trainees, assigns plans,
  reviews performance/form, and markets a public coaching profile.

- **Brand:** text wordmark "TacTech" (no logo image). Purple brand (`#8621EB`, `TTPurple.p80`),
  **Work Sans** custom font, deliberately "soft" type weights (nothing heavier than Medium renders).
- **Design system** is mature and centralized (`TTTheme`, `TTComponents`, `TTCards`, `TTTabBar`…):
  8pt spacing grid, defined radii, SF-Symbol-based icon library (`SandowIcons`), floating notched
  tab bar with a center **Liquid FAB** menu.
- **Localization:** 6 languages (en, ar, es, fr, hi, zh-Hans), ~808 keys.
- **Push notifications ARE wired** at the app layer (`PushNotificationDelegate`,
  `NotificationStore.requestAuthorizationAndRegister`) — contrary to the brief's assumption that
  push is unconfigured. What's missing is the committed APNs entitlement/provisioning, not the UI.

---

## 2. App launch & gating flow

Driven by `App/AppRootView.swift` as a single state machine on `AppStore` flags:

```
Splash (1.4s + session restore)
  └─ hasCompletedWelcome?  ── no ─► WelcomeOnboardingView (6-page carousel, one-time)
                               └─ yes ─► WelcomeView ─► Login / Signup
                                                             └─ Signup = 2 steps:
                                                                 Step 1 account → Step 2 RoleSelection
                                                                 (trainee may paste an invite code here)
  └─ session exists?
        └─ assessmentCompleted?  ── no ─► per-role Assessment flow (HARD first-run gate)
                                     └─ yes ─► TraineeRootView / TrainerRootView
```

**Gates, in order:** (1) `hasCompletedWelcome` carousel, (2) auth, (3) role selection (inside signup),
(4) `assessmentCompleted` — a hard first-run assessment before *either* root view.

**Notable findings:**
- **Role is set server-side at signup** (`store.signup(role:)`), not switchable later. ✔ matches brief.
- `PostLoginBridgeView` (a "welcome back / first setup" interstitial) exists but is **dead code** —
  only referenced by its own `#Preview`, never in the live path.
- `ProfileCompletionFlowView` exists but is **NOT a launch gate** — it is reachable only from
  Account Settings. So profile completion is genuinely un-enforced today (brief item **H** confirmed).
- Assessment flag truth is server-backed (`serverAssessmentCompleted`) with a local per-user
  UserDefaults fallback.

---

## 3. Trainee experience

**Tabs** (`TraineeRootView`): **Home · Workout · Nutrition · Profile**, plus center Liquid FAB →
AI Coach chat / Coach (human) chat.

| Area | File | Behavior today |
|------|------|----------------|
| **Home** | `TraineeDashboardView` | Dark collapsing header; zones Today / Progress / Health&Support. Contextual Today CTA keyed off plan + session state. **"Build my plan"** appears only via `canShowSoloAIGenerate`. |
| **Workout hub** | `WorkoutHubView` | Plan overview, week picker, session hero; empty state when no plan. AI Edit/Regenerate/Delete block gated by `traineeCanEditDeleteAIPlan`. |
| **Active workout** | `ActiveWorkoutView` → `GuidedWorkoutFlow` | Overview/launcher that resumes-or-starts a session, then a one-set-at-a-time guided flow with rest timer, set logging, completion sheet. |
| **Assessment** | `FitnessAssessmentFlowView` (18 steps) | First-run gate; see §5. |
| **AI generate confirm** | `AssessmentReviewSheet` | "Update & Generate Plan" / "Skip update, generate with current data" → `generateAIProgram`. |
| **Coach discovery** | `FindCoachesView` → `CoachDetailView` | Search/filter/paginate public coaches; detail shows bio/packages/reviews. **Primary CTA is "Contact" → opens a chat.** |
| **Join a trainer** | `TraineeProfileView.joinRequestCard` | **Invite-code** form → `createJoinRequest(inviteCode:)`. Pending/syncing/linked states. |
| **Nutrition** | `NutritionViews` + `FoodScannerView` | Renders from pre-seeded `foodCatalog` immediately; silently refreshes the selected day. Scanner gated on `aiCapabilities.visionFood`. |
| **Progress** | `TraineeProgressView` | Read-only telemetry, history, form reports; per-section empty states. |

### The single most important business switch for trainees
`hasLinkedTrainer = currentTrainee.trainerId != nil`. When true:
- `canShowSoloAIGenerate` → **false** (solo "Build my plan" card disappears).
- `traineeCanEditDeleteAIPlan` → **false** (Edit/Regenerate/Delete vanish; server returns forbidden).
- The trainer's assigned plan becomes the source of truth and is **read-only** to the trainee.

There is **no in-app explanation** when these controls disappear (brief item **B** confirmed).

---

## 4. Trainer experience

**Tabs** (`TrainerRootView`): **Home · Plans · Trainees · Profile**, plus center Liquid FAB →
AI Assistant / Trainee chat / Create plan / Assign to trainee / Plan assignments.

| Area | File | Behavior today |
|------|------|----------------|
| **Home** | `TrainerDashboardView` | KPIs (Clients / Active plans / Form avg); join-requests banner; priority **action queue** (check-in → session today → assign plan → done); contextual empty/all-clear cards. |
| **Plans** | `WorkoutPlansView` | List + search; "+" opens Create Plan; detail has Modify/Delete/Assign/Unassign. |
| **Create plan** | `CreatePlanView` (3 steps) | Basics → Training days → Build sessions (per-day `SessionEditor`, exercise picker + reusable templates). "Continue later" supported. |
| **Trainees** | `MyTraineesView` | Invite-code banner, Join Requests entry w/ badge, search, roster rows → detail. |
| **Join requests** | `JoinRequestsView` | Accept / Decline list; clean empty state (no skeleton here). |
| **Trainee detail** | `TraineeDetailView` | Assign/Unassign plan (`store.assign`), performance (History/Analytics/Meals + Swift Charts), form reports, feedback, **Remove from roster** (distinct from Unassign). |
| **Profile / marketing** | `TrainerProfileView` + editor/packages/analytics/boost/verification | Public profile editor, coaching packages (display-only pricing), discovery analytics, Boost store. |

---

## 5. The fitness assessment (18 steps)

`FitnessAssessmentFlowView` — `total = 18`, indices 0–17:

`0 Goal · 1 Gender · 2 Weight · 3 Age · 4 Experience · 5 FitnessLevel · 6 Limitations · 7 Diet ·
8 Days/week · 9 ExercisePref · 10 Supplement y/n · 11 Supplement pick · 12 Calorie · 13 Sleep ·
14 BodyScan · 15 Voice · 16 TextAnalysis · 17 Avatar`

- **Required input** (`canContinue`): steps 0, 1, 4, 6, 7, 9, 10, 11, 13.
- **Already skippable:** Gender ("Prefer to skip"), Supplement pick (bypassed if "No"),
  **BodyScan / Voice / TextAnalysis** are optional (BodyScan & Voice have explicit "Skip for now").
- **Permission-requesting:** BodyScan → **camera**, Voice → **microphone**, TextAnalysis → free text (no OS permission).
- **Finding:** the sensitive steps *are* technically skippable, but the skip affordances are weak /
  inconsistent and permissions are requested without a clear "why." (brief item **C** confirmed —
  partially; it's a clarity problem more than a missing-skip problem.)

---

## 6. Relationship & join-request model (verified against QA docs)

There is **no Swift enum** of relationship states — relationships are driven by **action strings**
through `handleRelationshipChanged` / `applyRelationshipChanged`:

- Linked ← `"linked" | "link" | "accepted"`
- Unlinked ← `"unlinked" | "unlink" | "ended" | "removed"`
- Reasons: `"trainee_left"` (trainer-side toast), `"trainer_removed"` (trainee-side toast).

Join request lifecycle (`JoinRequestDTO.status`): `pending → accepted | rejected | cancelled`.

Confirmed rules from `docs/QA_*`:
- One trainee ↔ one trainer at a time; re-request after reject/leave is allowed.
- **Unassigning a plan does NOT end the relationship.**
- Accept transitions trainee **pending → My Trainer in one step** (no empty-form flash).

---

## 7. Confirmed friction points (brief §5) — status after inspection

| # | Friction | Verified? | Key location |
|---|----------|-----------|--------------|
| A | Discovery & joining are disconnected | ✅ Yes — Find Coaches "Contact" only opens chat; joining is a separate invite-code form in Profile | `CoachDetailView` vs `TraineeProfileView` |
| B | AI plan disappears without explanation | ✅ Yes — no messaging when `hasLinkedTrainer` flips controls off | `AppStore.canShowSoloAIGenerate` |
| C | Assessment too long / weak skips | ⚠️ Partially — 18 steps; sensitive steps *are* skippable but affordances/rationale are weak | `FitnessAssessmentFlowView` |
| D | Browse & join should share trainer identity | ✅ Yes — join needs a manually-entered invite code even after viewing a coach | `CoachDetailView` |
| E | "Continue Workout" doesn't resume live session | ✅ **Confirmed** — Home's Continue Workout just opens `WorkoutHubView` overview; true resume is inside `ActiveWorkoutView` | `TraineeDashboardView:407/424` |
| F | Push notification UI states | ⚠️ Push *is* wired; notification types exist. Missing: provisioning + designed empty/permission states | `NotificationsInboxView`, `PushNotificationDelegate` |
| G | Join-request loading skeleton flash | ✅ **Confirmed, but on the DASHBOARD, not JoinRequestsView** — `TrainerDashboardView` shows `joinRequestsLoadingSkeleton` unconditionally until fetch resolves, flashing even when zero requests | `TrainerDashboardView:39-41, 500-518` |
| H | Profile completion not enforced | ✅ Yes — `ProfileCompletionFlowView` not a launch gate | `AppRootView` / `AccountSettingsView` |
| I | Nutrition cold-load | ⚠️ Minor — renders seed catalog instantly; only the selected day refreshes silently. No blocking spinner today | `NutritionViews` |

**Two corrections to the brief worth flagging now** (they change what Phase 5 should build):
1. **Push is already configured** in-app — treat Phase as *designing states*, not *enabling push*.
2. **The skeleton-flash (G) lives on the Trainer Dashboard**, not `JoinRequestsView` — that's where the fix belongs.

---

## 8. Architecture facts to respect in redesign

- Single `@Observable AppStore` is the source of truth; views are thin and read derived properties
  (`canShowSoloAIGenerate`, `traineeCanEditDeleteAIPlan`, `hasLinkedTrainer`, `assignedPlan(for:)`).
- Navigation is **native**: `NavigationStack`, `.sheet`, `fullScreenCover`, `confirmationDialog`,
  collapsing headers, floating tab bar. Redesign stays within these patterns.
- Relationship/plan/join events also arrive via **realtime** handlers — any new "explain the state"
  UI must read the same store flags, not invent new permissions (respects brief constraint B).

---

*End of Phase 1. Awaiting approval to proceed to Phase 2 (UX Audit & Friction Analysis).*
