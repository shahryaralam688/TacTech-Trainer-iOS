# TacTech — Phase 3: UX Architecture & Navigation Maps

> **Scope:** architecture, information hierarchy, navigation maps, and state diagrams only.
> **No UI designs, no prototypes, no source/business-logic changes.** `AppStore` stays the single
> source of truth; everything below reads existing flags and invents no permissions.
> **HIG posture:** native iOS throughout — tab bars, `NavigationStack`, `.sheet`,
> `fullScreenCover`, `confirmationDialog`, collapsing headers, floating tab bar. Nothing here is
> change-for-the-sake-of-difference; every delta traces to a Phase 2 friction point.

> **Revision v2 (corrections applied):** assessment field classification re-anchored to the verified
> required set; AI-plan-after-leaving copy corrected (no restoration promised); trainer-dashboard
> loading made conditional (no caching assumed); Continue-Workout resume verified against existing
> session state with an explicit fallback. See the ✎v2 markers.

**How to read this doc.** Each proposed change carries a 5-line tag block:
`WHAT · WHY BETTER · SCREEN AFFECTED · WORK TYPE (UI / NAV / BACKEND) · MUST STAY INTACT.`
Diagrams are ASCII so they review in-place and diff cleanly.

---

## 0. Approved clarifications carried into this phase

- **A — Discovery→join:** design the ideal journey, but **trainer-ID join is a *conditional*
  backend capability**. Every join flow below has an **invite-code fallback** that works today.
- **B — AI plan on link:** **do not assume** retain/pause/replace. All AI-plan-under-coach states
  are **conditional branches** keyed on an unresolved flag `aiPlanOnLinkBehavior ∈ {retained,
  paused, replaced, unknown}`. Copy adapts; no behavior asserted.
- **C — Assessment:** classify each of the 18 fields as **Required-before-entry** vs
  **Progressive** by its *real dependency*. No required data removed; no assessment rule changed.

---

# PART 1 — INFORMATION ARCHITECTURE

## 1.1 Design principles (the spine of the IA)

1. **One task → one primary home.** Secondary doors are *shortcuts to the same destination*, never
   parallel features (fixes Phase 2 **J**).
2. **State is a first-class citizen.** Every relationship/plan state has a defined surface and a
   single obvious next action (fixes **B, N**).
3. **Progressive disclosure.** Show the next right thing, not every feature at once (brief §6).
4. **Native containers by default.** A state that is a sheet/alert/inline message is *not* a screen.
5. **Read, don't rule.** New surfaces read `AppStore` flags (`hasLinkedTrainer`, `assignedPlan`,
   `pendingJoinRequest`, `canShowSoloAIGenerate`, `activeWorkoutSession`, `aiCapabilities`).

## 1.2 Top-level IA (unchanged tab skeleton, clarified roles)

The **4-tab skeleton stays** for both roles (HIG: stable, flat, ≤5 tabs). We do **not** add or remove
tabs — we clarify what lives where and remove duplicate doors.

```
TRAINEE                               TRAINER
┌───────┬────────┬─────────┬───────┐  ┌───────┬───────┬──────────┬───────┐
│ Home  │ Workout│ Nutrition│Profile│  │ Home  │ Plans │ Trainees │Profile│
└───────┴────────┴─────────┴───────┘  └───────┴───────┴──────────┴───────┘
        └──── center FAB ────┘                 └──── center FAB ────┘
   AI Coach · Coach chat            AI Assist · Trainee chat · Create · Assign · Assignments
```

```
WHAT         Keep both 4-tab bars + center FAB; no structural tab changes.
WHY BETTER   Familiar, HIG-compliant, zero relearning; fixes are inside tabs, not to the shell.
SCREEN       TraineeRootView, TrainerRootView.
WORK TYPE    None (structure preserved).
MUST STAY    Tab set, order, icons, FAB menus.
```

## 1.3 Content ownership map (what each tab is *responsible* for)

| Tab | Owns (primary) | Hosts (secondary/shortcut) | Not here |
|-----|----------------|----------------------------|----------|
| **Trainee Home** | Today's one action; relationship status; nudges | Shortcuts to Workout/Nutrition/Find Coach | Deep plan editing |
| **Trainee Workout** | Active plan, session, live form | Resume live session (deep link target) | Coach discovery |
| **Trainee Nutrition** | Day log, macros, scanner | Manual meal, catalog search | Workout |
| **Trainee Profile** | Identity, **trainer relationship**, settings | Join fallback (invite code), completion | AI generate CTA (lives on Home/Workout) |
| **Trainer Home** | Day triage / action queue; requests banner | Shortcuts → Create/Assign (same sheets) | Deep trainee analytics |
| **Trainer Plans** | Plan library, create/edit | Assign (→ same assign sheet) | Roster mgmt |
| **Trainer Trainees** | Roster, requests, trainee detail | Assign/Unassign/Remove/Feedback | Plan authoring |
| **Trainer Profile** | Public coach profile, packages, boost, analytics | Verification, invite code | Trainee-facing features |

```
WHAT         Assign a single owner tab to each task; others become labelled shortcuts to it.
WHY BETTER   Kills "which door?" ambiguity (J); users learn tasks, not geography.
SCREEN       All roots + detail screens.
WORK TYPE    NAV (routing/labels); no logic change.
MUST STAY    Every existing capability stays reachable — only its canonical home is clarified.
```

---

# PART 2 — NAVIGATION MAPS

## 2.1 Trainee navigation map

```
TraineeRootView (tab bar)
│
├─ HOME (TraineeDashboardView)
│   ├─ Today zone → [contextual primary CTA] ──► (see §4.1 CTA resolver)
│   │     • no plan, solo-AI eligible ........→ AssessmentReviewSheet (generate)
│   │     • active session, dayId resolves ....→ ActiveWorkoutView for that day @ active exercise  ★NEW (E)
│   │     • active session, dayId nil/unresolved→ WorkoutHubView (fallback — today's behavior)
│   │     • plan, not started ................→ WorkoutHubView
│   │     • linked, no plan yet ..............→ Relationship status surface (B/N)
│   ├─ Relationship status card ────────────► TraineeProfile trainer section (deep link)
│   ├─ Progress zone → TraineeProgressView (sheet)
│   ├─ Completion nudge (dismissible) ───────► ProfileCompletionFlowView (existing)
│   ├─ Find a coach (contextual) ────────────► FindCoachesView (sheet)
│   └─ Notifications ────────────────────────► NotificationsInboxView (sheet)
│
├─ WORKOUT (WorkoutHubView)
│   ├─ Has plan → week picker → session hero → ActiveWorkoutView → GuidedWorkoutFlow
│   ├─ AI controls (Edit/Regenerate/Delete) — ONLY when traineeCanEditDeleteAIPlan
│   ├─ Linked & no AI controls → "Coach guides your training" explainer (B/N) ★NEW
│   └─ Empty → generate CTA (solo-AI) OR relationship explainer (linked)
│
├─ NUTRITION (NutritionView)
│   ├─ Day strip → per-day meals (inline loading affordance ★NEW, I)
│   ├─ Food search overlay · ManualMealView (sheet)
│   └─ FoodScannerView (sheet) → entitled | "Available on {tier}" | "Coming soon" (M)
│
└─ PROFILE (TraineeProfileView)
    ├─ Identity + metrics
    ├─ TRAINER RELATIONSHIP (single status component ★NEW, N) ──┐
    │     none → Find a coach / Have a code?                    │ states in §5
    │     pending → status + Cancel                              │
    │     linked → MyTrainerCard + Leave                         │
    ├─ Find coaches ─────────────► FindCoachesView ──► CoachDetailView
    │                                                   ├─ Contact (chat)         (L)
    │                                                   └─ Request to train ★NEW  (A/D)
    │                                                        ├─ if trainer-ID join → direct request
    │                                                        └─ else → invite-code fallback (prefilled if resolvable)
    └─ Settings / Account / ProfileCompletionFlowView
```

## 2.2 Trainer navigation map

```
TrainerRootView (tab bar)
│
├─ HOME (TrainerDashboardView)
│   ├─ KPIs (Clients / Active plans / Form avg)
│   ├─ Join-requests banner — STABLE, no empty-flash ★FIX G (✎v2): show prior data if present;
│   │     skeleton ONLY when no data yet AND a fetch is in progress; stable empty state after a
│   │     successful empty response
│   │     tap → JoinRequestsView (sheet)
│   ├─ Action queue (check-in → session today → assign plan → done)
│   │     row tap → TraineeDetailView ; priority-2 → assign sheet (same sheet as everywhere)
│   └─ Quick actions → Create (→ Plans+sheet) / View trainees (→ Trainees tab)
│
├─ PLANS (WorkoutPlansView)
│   ├─ List + search → WorkoutPlanDetailView (Modify/Delete/Assign/Unassign)
│   └─ "+" → CreatePlanView (3-step) ── canonical create home
│
├─ TRAINEES (MyTraineesView)
│   ├─ Invite banner (copy code)
│   ├─ Join requests entry (badge) → JoinRequestsView
│   └─ Roster row → TraineeDetailView
│         ├─ Assign/Unassign (store.assign/unassign)
│         ├─ Performance: History / Analytics / Meals
│         ├─ Form reports · Feedback
│         └─ Remove from roster (distinct from Unassign)
│
└─ PROFILE (TrainerProfileView)
    ├─ Public profile editor · Packages · Boost · Analytics · Verification
    └─ Invite code

Center FAB (consolidated, §6): AI · Trainee chat · Create plan* · Assign* · Assignments*
   *routes to the SAME sheets as the tab doors — no parallel flows
```

```
WHAT         Document every destination; mark consolidated/new/fixed nodes (★).
WHY BETTER   Makes duplicate doors and missing state-surfaces visible; one destination per task.
SCREEN       All trainee + trainer screens.
WORK TYPE    NAV + a few UI-only new surfaces (explainer, status component, loading affordance).
MUST STAY    All listed destinations remain reachable; detail-screen capabilities unchanged.
```

---

# PART 3 — USER JOURNEYS

## 3.1 First-time user (FTU) journeys

### FTU-Trainee A — Self-training (no coach)
```
Splash → Welcome carousel → Signup(acct) → Role=Trainee (skip invite) →
Assessment (3 phases, §7) → Home (empty, solo-AI eligible) →
"Build my plan" → AssessmentReviewSheet → generate → Workout (plan) → first GuidedWorkoutFlow → Progress
```

### FTU-Trainee B — Find a coach
```
… Role=Trainee → Assessment → Home → Find a coach → FindCoachesView →
CoachDetailView → "Request to train" →
   (trainer-ID join)  → pending status                    ┐
   (fallback)         → invite-code sheet (prefill?) → pending status  ┘
→ [coach accepts] → linked → "Coach guides your training" → assigned plan → train
```

### FTU-Trainee C — Has a coach's invite code
```
… Signup → Role=Trainee → paste invite code at role step (existing) →
Assessment → Home → pending status (if request auto-created) OR Profile → enter code →
pending → accepted → assigned plan → train
```

### FTU-Trainer
```
Splash → Welcome → Signup(acct) → Role=Trainer →
Trainer Assessment (existing) → Trainer Home (empty roster) →
emptyRosterCard: "Invite your first trainee" (copy code) →
[request arrives] → stable requests banner → JoinRequestsView → Accept →
TraineeDetailView → Create plan (canonical) → Assign → track
```

## 3.2 Returning user (RU) journeys

### RU-Trainee — mid-program (the momentum path)
```
Open → Home Today zone resolves:
   active session, day resolves? → "Continue Workout" → ActiveWorkoutView for that day @ active exercise (E)
   active session, day unresolved → "Continue Workout" → WorkoutHubView (fallback)
   plan, today due  → "Start Today's Workout" → Workout hub → session
   linked, new plan → soft banner "New plan from {coach}" → Workout
   all done today   → "View today's workout" / "Go again"
```

### RU-Trainee — relationship change while away
```
Open → realtime/notification already applied → Home relationship card shows new state:
   accepted → "You're now training with {coach}" + next action
   rejected → "Request declined" → Find a coach / try code
   removed  → "You're training on your own again" → AI planning availability recalculated from current eligibility
(fixes silent state changes — B/F/N)
```

### RU-Trainer — daily triage
```
Open → Dashboard (no empty-flash: skeleton only when nothing to show yet AND a fetch is active) →
   pending requests? → banner → Accept/Decline
   action queue → highest-priority trainee → act (assign / check-in / view session)
   else → "You're clear for today"
```

```
WHAT         Explicit FTU + RU journeys per role incl. relationship-change-while-away.
WHY BETTER   Covers the moments Phase 2 flagged as silent (B, E, F, N); matches brief §6/§7.
SCREEN       Full flow across roots + details.
WORK TYPE    NAV + UI-only surfaces; no new rules.
MUST STAY    Role fixed at signup; assessment gate; one-trainer rule; AI-gated-by-trainer rule.
```

---

# PART 4 — CTA / STATE RESOLVERS (decision logic, read-only)

## 4.1 Trainee Home "Today" CTA resolver (documents existing + the E fix)
```
IF activeWorkoutSession != nil
      → "Continue Workout":
          IF activeWorkoutSession.dayId resolves to a day in the current plan
             → deep-link ActiveWorkoutView for THAT day  (reuses existing ensureSession +
               activeExerciseIndex; resumes at exercise granularity)            ★NEW target (E)
          ELSE (dayId nil / not found)
             → WorkoutHubView  (today's behavior — safe fallback, no new resume rule)
ELSE IF assignedPlan(for:) == nil AND canShowSoloAIGenerate
      → "Build my plan"     → AssessmentReviewSheet
ELSE IF assignedPlan != nil AND !hasCompletedTodayWorkout
      → "Start Today's Workout" → WorkoutHubView
ELSE IF assignedPlan != nil AND hasCompletedTodayWorkout
      → "View today's workout" + ghost "Go again" → WorkoutHubView
ELSE IF hasLinkedTrainer AND assignedPlan == nil
      → Relationship explainer: "Waiting for {coach} to assign your plan"  ★NEW (B/N)
ELSE (no plan, not solo-AI eligible, no trainer)
      → "Link a coach to get workouts" → Find a coach
```
> **✎v2 — resume verified against source.** `activeWorkoutSession` (`WorkoutSession`, APIClient.swift:436)
> carries `planId`, `dayId?`, and logged `sets[]`. The resume point is computed by the existing
> `activeExerciseIndex` (WorkoutHubView.swift:917) — the first exercise whose working sets aren't all
> logged — and `GuidedWorkoutFlow` already starts at that index (`guidedStartIndex = activeExerciseIndex`).
> So safe resume is possible **at exercise granularity, on the condition** that the session's `dayId`
> is resolved to a day in the current plan and passed to `ActiveWorkoutView(plan:day:)`. When `dayId`
> is `nil` or doesn't resolve, the correct day can't be guaranteed → **fall back to `WorkoutHubView`**.
> This introduces **no new session-resume business rule** — it only changes the Home CTA's navigation
> target and reuses `ensureSession` / `activeExerciseIndex` exactly as they work today.

## 4.2 AI-plan-under-coach resolver (clarification B — conditional, nothing assumed)
```
WHEN hasLinkedTrainer == true, Workout/Home show ONE of:
  aiPlanOnLinkBehavior == retained → "Your AI plan is saved. {coach} now guides new training."
  aiPlanOnLinkBehavior == paused   → "Your AI plan is paused while {coach} guides you."
  aiPlanOnLinkBehavior == replaced → "{coach} now sets your plan."
  aiPlanOnLinkBehavior == unknown  → neutral: "{coach} now guides your training."  ← default until confirmed
Plus, in all cases:
  • assignedPlan == nil → "Waiting for {coach} to assign your first plan."
  • assignedPlan != nil → show assigned plan (read-only) + "Assigned by {coach}".
  • Always (on Leave): "After leaving your coach, AI planning availability is recalculated using
    your current eligibility." → existing Leave flow.  ✎v2 (no restoration/retention promised)
```
```
WHAT         A conditional explainer whose copy is selected by an unresolved behavior flag.
WHY BETTER   Ends silent disappearance (B) without asserting a behavior we haven't confirmed.
SCREEN       WorkoutHubView, TraineeDashboardView, TraineeProfileView.
WORK TYPE    UI-only (reads hasLinkedTrainer/assignedPlan); the behavior flag is BACKEND-unresolved.
MUST STAY    hasLinkedTrainer still governs availability; assigned plans read-only; leaving
             RECALCULATES AI eligibility from current state (no restoration of a prior plan promised).
```

---

# PART 5 — TRAINER RELATIONSHIP STATE DIAGRAM

Derived from `handleRelationshipChanged` action strings + `JoinRequestDTO.status`. **No new states.**

```
                 ┌───────────────┐
                 │  NO TRAINER   │◄───────────────────────────┐
                 │ (solo-AI on)  │                            │
                 └──────┬────────┘                            │
        request (trainer-ID or invite code)                  │
                        ▼                                     │
                 ┌───────────────┐   cancel (trainee)         │
                 │   PENDING     ├────────────────────────────┤
                 │ (awaiting)    │                            │
                 └──┬─────────┬──┘                            │
         accept ▲   │         │  reject                       │
    (trainer)   │   │         ▼                               │
                │   │   ┌───────────┐  re-request allowed      │
                │   │   │ REJECTED  ├──────────────────────────┤
                │   │   └───────────┘                          │
                ▼   │                                          │
         ┌───────────────┐                                     │
         │   LINKED      │  trainee "Leave"  (reason=trainee_left)
         │ (coach guides)│──────────────────────────────────► │
         │ AI gated off  │  trainer "Remove" (reason=trainer_removed)
         └──────┬────────┘──────────────────────────────────► ┘
                │
   within LINKED (relationship persists):
     • plan Assigned / Unassigned  ── Unassign does NOT end relationship (hard rule)
     • plan Edited by trainer → read-only refresh for trainee
```

Mapping to code (read-only reference):
- `linked ← "linked"|"link"|"accepted"` · `unlinked ← "unlinked"|"unlink"|"ended"|"removed"`
- reasons `trainee_left` / `trainer_removed` drive the respective side's toast + status copy.

```
WHAT         Canonical relationship state machine users can be shown consistently (status component).
WHY BETTER   N — one legible model reused on Home + Profile; no more ad-hoc per-screen states.
SCREEN       TraineeProfileView, both Home screens, JoinRequestsView.
WORK TYPE    UI-only (renders existing store state).
MUST STAY    One-trainer rule; re-request after reject/leave; Unassign ≠ end relationship.
```

---

# PART 6 — WORKOUT PLAN LIFECYCLE DIAGRAMS

## 6.1 AI-generated plan (trainee, solo)
```
canShowSoloAIGenerate (trainee, !hasLinkedTrainer, structuredPlanJson, no assigned plan)
   │  "Build my plan" / "Regenerate"
   ▼
AssessmentReviewSheet ──(generateAIProgram, horizon 7d)──► AI WEEK PLAN (isAISource)
   │  editable: Edit / Regenerate / Delete  (traineeCanEditDeleteAIPlan == true)
   ▼
train in GuidedWorkoutFlow → logs → Progress
   │
   └─ IF a trainer links → AI edit/generate controls gate OFF → see §4.2 conditional states
```

## 6.2 Trainer-assigned plan
```
Trainer CreatePlanView (3-step) → Plan in library
   │  assign (store.assign planId→trainee)   [also via detail / FAB / dashboard — same sheet §6-FAB]
   ▼
ASSIGNED PLAN (read-only to trainee, badge "Assigned by {coach}")
   │  trainer Edit → trainee sees refreshed read-only plan
   │  trainer Unassign → plan removed, RELATIONSHIP PERSISTS
   ▼
trainee trains (same GuidedWorkoutFlow) → logs visible to trainer (History/Analytics)
```

## 6.3 The crossover (where B lives)
```
SOLO AI PLAN exists ──(trainer links)──► [aiPlanOnLinkBehavior: retained|paused|replaced|unknown]
                                             │
                        assigned plan arrives │
                                             ▼
                                   TRAINER-ASSIGNED PLAN governs
                                             │
                        trainee leaves coach │
                                             ▼
             AI planning availability RECALCULATED from current eligibility  ✎v2
             (no restoration or retention of a prior AI plan promised) — see §4.2
```
```
WHAT         Two plan lifecycles + their crossover, with the unresolved behavior isolated to one node.
WHY BETTER   Makes the "my plan changed" moment explicit and designable (B).
SCREEN       WorkoutHubView, CreatePlanView, TraineeDetailView.
WORK TYPE    UI-only; crossover behavior is BACKEND-unresolved (B).
MUST STAY    isAISource gating; read-only assigned plans; horizon-7 AI week; Unassign ≠ unlink.
```

---

# PART 7 — ONBOARDING & ASSESSMENT ARCHITECTURE

## 7.1 Field classification (clarification C — by real dependency, nothing removed)

**✎v2 — corrected to match the verified required set `{0, 1, 4, 6, 7, 9, 10, 11, 13}` exactly.**
No field is reclassified in this phase. Fields outside the required set are marked as *candidates*
for progressive capture that each **require explicit product approval** before any change.

| # | Field | Current class (verified) | Notes / future-decision flag |
|---|-------|--------------------------|------------------------------|
| 0 | Goal | **Required** | In required set. |
| 1 | Gender | **Required** | In required set (has explicit "Prefer to skip" that writes empty + advances). |
| 2 | Weight | Not in required set | ⚠️ FUTURE DECISION — candidate for progressive capture; requires approval. |
| 3 | Age | Not in required set | ⚠️ FUTURE DECISION — note: AssessmentReviewSheet shows Age read-only/locked, implying a once-only capture; reconcile this before any move. Do **not** reclassify as required without a rule owner. |
| 4 | Experience | **Required** | In required set (auto-advances on answer). |
| 5 | Fitness level | Not in required set | ⚠️ FUTURE DECISION — candidate for progressive; requires approval. |
| 6 | Limitations | **Required** | In required set (safety). |
| 7 | Diet | **Required** | In required set. |
| 8 | Days/week | Not in required set | ⚠️ FUTURE DECISION — candidate for progressive; requires approval. |
| 9 | Exercise pref | **Required** | In required set. |
| 10 | Supplement y/n | **Required** | In required set. |
| 11 | Supplement pick | **Required** | In required set (bypassed only when y/n = No). |
| 12 | Calorie target | Not in required set | ⚠️ FUTURE DECISION — candidate for progressive; requires approval. |
| 13 | Sleep | **Required** | In required set. |
| 14 | Body scan (camera) | Optional (already skippable) | Explicit "Skip for now"; request camera permission **on tap** only. |
| 15 | Voice (mic) | Optional (already skippable) | Explicit "Skip for now"; request mic permission **on tap** only. |
| 16 | Text analysis | Optional (already skippable) | Free text; no OS permission. |
| 17 | Avatar | Optional | Cosmetic; captured at submit. |

**Authoritative required set (unchanged): steps 0, 1, 4, 6, 7, 9, 10, 11, 13.** Every "Not in
required set" row is a *candidate only*; the required set and all assessment business rules are
preserved exactly until a rule owner signs off (brief constraint). The 3-phase grouping in §7.2 is a
**display/labelling change only** — it does not move fields between steps or alter which are required.

## 7.2 Proposed phase grouping (no steps removed — grouping + labels only)
```
PHASE 1 · "About you"      → Goal, Gender, Weight, Age, Experience, Fitness level, Limitations
PHASE 2 · "Your training"  → Diet, Days/week, Exercise pref, Supplements(y/n→pick), Calorie, Sleep
PHASE 3 · "Fine-tune (optional)" → Body scan, Voice, Text, Avatar
          └ every step: consistent Skip · one-line rationale · OS permission on tap only
Chrome: 3-chunk progress ("Phase 2 of 3") · "Continue later" persists (existing)
```
```
WHAT         Group 18 steps into 3 labelled phases; classify fields; standardize skip + rationale.
WHY BETTER   C — feels like 3 chunks not 18; sensitive asks explained; abandon risk down.
SCREEN       FitnessAssessmentFlowView, FitnessAssessmentSteps.
WORK TYPE    UI-only (grouping/labels/copy/skip placement). No field removed, no rule changed.
MUST STAY    Required-input set (steps 0,1,4,6,7,9,10,11,13); submit→submitAssessment; first-run gate.
```

---

# PART 8 — ENTRY-POINT CONSOLIDATION STRATEGY (fixes J)

Principle: **one canonical home per task; all other doors route to the same sheet with the same label.**

| Task | Canonical home | Shortcuts (→ same destination) | Change |
|------|----------------|--------------------------------|--------|
| Create plan | Plans tab "+" → `CreatePlanView` | FAB "Create", Dashboard quick action | Point all at one sheet; unify label "Create plan" |
| Assign plan | `TraineeDetailView` assign card | `WorkoutPlanDetailView` assign, FAB "Assign", Dashboard priority-2 | One `PlanQuickAssignSheet`; consistent "Assign plan" |
| AI generate (trainee) | Home "Build my plan" | Workout empty CTA, "Regenerate" | Same `AssessmentReviewSheet`; "Build"/"Regenerate" wording by state |
| Join a coach | Coach profile "Request to train" | Profile "Have a code?" fallback | Primary = identity-based; code = fallback (A/D) |
| View trainees | Trainees tab | Dashboard "View trainees" | Shortcut only |

```
WHAT         Collapse duplicate doors to shortcuts that open one shared destination per task.
WHY BETTER   J — users learn tasks not geography; consistent labels reduce cognitive load.
SCREEN       Both roots, FAB menu, dashboards, detail screens.
WORK TYPE    NAV + copy. No capability removed — every door still works, just unified.
MUST STAY    FAB remains the "from anywhere" layer; all current actions remain reachable.
```

---

# PART 9 — SCREEN HIERARCHY & NAVIGATION DESTINATIONS

Container discipline (HIG): **screen** (push/tab) vs **sheet** (focused task) vs **alert/dialog**
(confirm) vs **inline** (state). Phase 2 **M**: a state is not a screen.

```
SCREENS (pushed / tabbed)                 SHEETS (.sheet / fullScreenCover)
  TraineeRoot / TrainerRoot tabs            AssessmentReviewSheet
  WorkoutHubView                            FindCoachesView, CoachDetailView (push within sheet)
  ActiveWorkoutView                         CreatePlanView, PlanQuickAssignSheet, PlanAssignmentsListSheet
  GuidedWorkoutFlow (fullScreenCover)       JoinRequestsView, NotificationsInboxView
  TraineeDetailView                         ProfileCompletionFlowView
  WorkoutPlanDetailView                     ManualMealView, FoodScannerView
                                            AI Coach chat / Human chat (fullScreenCover)
ALERTS / CONFIRMATION DIALOGS             INLINE STATES (not screens)
  Delete plan · Leave coach · Remove        Relationship status card, AI-under-coach explainer,
  trainee · Decline request · Unassign      completion nudge, empty/loading/error slots, "coming soon"
```
```
WHAT         Classify every destination into the correct native container.
WHY BETTER   Prevents inventing standalone screens for things that are sheets/alerts/inline (brief §8).
SCREEN       All.
WORK TYPE    NAV (container choice); no logic change.
MUST STAY    Existing presentation styles (collapsing headers, top-rounded sheets, FAB).
```

---

# PART 10 — STATE MATRIX (empty · loading · pending · active · completed · error)

| Screen | Empty | Loading | Pending | Active | Completed | Error |
|--------|-------|---------|---------|--------|-----------|-------|
| Trainee Home | getStartedCard | silent (renders from already-loaded store data; refresh is background) | relationship "pending" card | Today CTA (active session) | "done today" + Go again | soft toast |
| Workout Hub | generate CTA / coach explainer | pull-to-refresh | "waiting for plan" (linked) | session hero | plan-change notice | retry chip |
| Active workout | — | ensureSession | — | GuidedWorkoutFlow @ set | WorkoutCompleteSheet | local-log fallback + notice |
| Nutrition day | "no meals logged" | **inline per-day shimmer ★NEW (I)** | — | logged list | — | honest empty≠loading |
| Find coaches | "No coaches found" | spinner (first page) | — | list + pagination | — | retry |
| Coach detail | "Coach not available" | spinner | request pending badge | profile + Request/Contact | "Requested" | inline error |
| Trainer Dashboard | emptyRosterCard / stable empty after empty success | **skeleton only if no data yet + fetch active ★FIX (G)** | requests banner (prior value if present) | action queue | "clear for today" | toast |
| Join Requests | "No pending requests" | (no skeleton — safe) | request rows | — | accepted → roster | busy/retry |
| Create Plan | step empties | — | "Continue later" draft | wizard steps | "Save plan" | validation inline |
| Trainee Detail | "no plan" | perf loading | — | assigned summary | adherence/history | analytics error state |
| Notifications | empty inbox | load page | — | grouped unread | read | retry |

★ = the only two *new/changed* state behaviors (I inline loading, G skeleton-gating); all others are
documenting existing states so Phase 5 covers every one.

**✎v2 — loading-state info required from the existing implementation (G).** The desired three-way
behavior (prior data / skeleton-only-when-none-and-fetching / stable-empty-after-empty-success) needs
a distinction the dashboard does not express today:
- `TrainerDashboardView` currently drives the skeleton off a single `isLoadingJoinRequests` bool set
  `true` in `.task` and `false` after the fetch — so the skeleton shows unconditionally.
- `trainerJoinRequests` is a **non-optional `[]`**, so "not loaded yet" and "loaded, empty" are
  **indistinguishable**. That missing distinction is the root of the flash.
- To implement the desired behavior the view needs *either* a "has completed ≥1 fetch" flag **or** an
  optional/loaded-marker so empty-after-success renders the stable empty state while first-load shows
  the skeleton. **This is an implementation observation for Phase 5/eng, not a new business rule.**

```
WHAT         A complete per-screen state map across 6 state classes.
WHY BETTER   Ensures no state is skipped in design; isolates the 2 actual state fixes (G, I).
SCREEN       All.
WORK TYPE    UI-only (G gating, I inline affordance); rest is documentation of existing states.
MUST STAY    Existing success/error toasts, confirmation dialogs, local-log fallback behavior.
```

---

# PART 11 — CURRENT vs PROPOSED ARCHITECTURE (side-by-side)

| Dimension | Current | Proposed | Net |
|-----------|---------|----------|-----|
| Tab shells | 4+4 + FAB | **unchanged** | 0 relearn |
| Task entry points | 2–3 doors per task | 1 canonical + shortcuts to same sheet | −ambiguity (J) |
| Coach join | Chat (Contact) ⟂ invite code in Profile | Request-from-profile (ID) + code fallback | unified (A/D/L) |
| AI-under-coach | silent disappearance | conditional explainer (status + next + how-to-leave) | legible (B) |
| Relationship state | ad-hoc per screen | one status component, canonical state machine | legible (N) |
| Continue Workout | → hub overview (several hops) | → live session for resolved day @ active exercise (fallback: hub) | momentum (E) |
| Assessment | 18 flat steps, weak skips | 3 labelled phases, consistent skips + rationale | less abandon (C) |
| Trainer dashboard | skeleton flash even when empty | prior data if present; skeleton only when none + fetch active; stable empty after empty success | stable (G) |
| Notifications | types exist, states/priming absent | priming + designed inbox/event states | surfaced (F) |
| Profile completion | invisible, unenforced | non-blocking progressive nudge | guided (H) |
| Terminology | Trainer/Coach, Plan/Program/Week mixed | one term per concept via xcstrings | clarity (K) |
| Nutrition day | silent late pop-in | inline per-day loading | honest (I) |

**Everything in "Proposed" is UI/NAV except three isolated backend-dependent items (below).**

---

# PART 12 — UNRESOLVED BUSINESS / BACKEND DECISIONS

Carried forward; **must be answered before Phase 5 builds the dependent flow.** Until then, the
architecture above uses the conditional/fallback branches noted.

| # | Decision | Blocks | Default used here |
|---|----------|--------|-------------------|
| U1 | Does `createJoinRequest` accept a **trainer id**, or invite-code only? | A/D direct-join | Invite-code fallback (works today); ID join behind capability check |
| U2 | **`aiPlanOnLinkBehavior`** — retained / paused / replaced when a coach links? | B copy + §6.3 | `unknown` → neutral copy "coach now guides your training" |
| U3 | **APNs provisioning** (entitlement/certs) committed? | F live delivery | Design in-app states regardless; priming before OS prompt |
| U4 | Can a coach's **invite code be surfaced on their profile** (for prefill fallback)? | A fallback prefill | Manual code entry if not |
| U5 | Are **days/week (8)** and **sleep (13)** truly required pre-entry, or progressive? | C field move | Keep as-is (required) until rule owner confirms |
| U6 | Food scanner / live form: **entitlement upgrade** vs **not-yet-built**? | M copy ("Available on {tier}" vs "Coming soon") | Show "Coming soon" unless entitlement flag says upgradeable |

```
WHAT         Explicit register of every unresolved dependency + the safe default in use.
WHY BETTER   Guarantees design never silently invents a business rule (brief constraint).
SCREEN       Cross-cutting.
WORK TYPE    BACKEND/PRODUCT decisions; design proceeds on documented defaults.
MUST STAY    No rule assumed; AppStore remains source of truth.
```

---

## Appendix — Global "must remain intact" (unchanged from Phase 2 §7)
Two fixed roles (server-set, non-switchable) · one trainee↔one trainer · Unassign ≠ end relationship ·
`hasLinkedTrainer` governs AI (explained, not changed) · assigned plans read-only · all features
preserved (AI generate, live form, 3D demos, scanner, nutrition, packages/boost/analytics/verification,
chat/calls, feedback, form reports) · native iOS patterns only · `AppStore` single source of truth ·
brand (purple/Work Sans/soft weights) + 6-language localization.

---

*End of Phase 3. Awaiting review & approval before Phase 4 (consolidated journey presentation for
sign-off) / Phase 5 (screen design). No screens or prototypes will be produced until approved.*
