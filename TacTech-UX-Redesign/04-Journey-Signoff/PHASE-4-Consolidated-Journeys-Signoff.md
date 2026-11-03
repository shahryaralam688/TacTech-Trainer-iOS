# TacTech — Phase 4: Consolidated User Journeys & Final Product Sign-off

> **Purpose:** a single, end-to-end, reviewer-facing consolidation of every Trainer and Trainee
> journey — the document to sign off before any screen is drawn.
> **Scope guard (strict):** no SwiftUI/source changes · no UI designs or prototypes · no `AppStore`
> or business-logic changes · no new features/permissions · native iOS navigation, existing branding,
> fixed roles, and all current capabilities preserved.
> **Legend:** 〔E〕 = existing functionality (works today) · 〔P〕 = proposed UX improvement (no new
> rule) · ⟮U#⟯ = depends on an unresolved decision (carried verbatim from Phase 3).
> **State tags inline:** ∅ empty · ⏳ loading · ⌛ pending · ✅ success · ⚠ error.

---

## 0. How to read the sign-off

Each journey is one table: **Step → Entry point(s) → Destination → State(s) → E/P → Rules & U#**.
Every row names its *primary* door and any *secondary* doors, and ends at a concrete destination
(screen, sheet, alert, or inline surface). Proposed rows change **navigation, copy, or state
presentation only** — the governing business rule is always the existing one, cited in the last column.

The sign-off question for each journey: *"Is this the experience we commit to build in Phase 5?"*

---

# PART A — TRAINEE JOURNEYS

## A1. First run → first value (self-training, no coach) 〔E path, 〔P polish〕

| # | Step | Entry point(s) | Destination | States | E/P | Rules / U# |
|---|------|----------------|-------------|--------|-----|------------|
| 1 | Launch | App icon | Splash → gate machine | ⏳ splash 1.4s + session restore | E | `AppRootView` gates |
| 2 | Welcome | first launch only (`hasCompletedWelcome=false`) | WelcomeOnboarding carousel | — | E | one-time |
| 3 | Create account | "Create account" | SignupView (step 1 of 2) | ⚠ validation inline | E | — |
| 4 | Choose role | Signup step 2 | RoleSelection = **Trainee** (skip invite) | — | E | role server-set, **not switchable** |
| 5 | Assessment | hard first-run gate | FitnessAssessment (18 steps) | ⌛ "Continue later" draft | E | required set `{0,1,4,6,7,9,10,11,13}` unchanged |
| 5p | Assessment framing | — | same steps, **3 labelled phases + consistent Skip + on-tap permission rationale** | ∅ per optional step | **P** | display/labelling only (Phase 3 §7.2) |
| 6 | Land on Home | after submit | TraineeDashboardView | ∅ getStartedCard | E | `submitAssessment` |
| 7 | Build plan | Home **"Build my plan"** (primary); Workout empty CTA (secondary) | AssessmentReviewSheet → generate | ⏳ "Generating…" · ✅ notice · ⚠ paywall/conflict inline | E | `canShowSoloAIGenerate` (trainee, `!hasLinkedTrainer`, structuredPlanJson, no assigned plan) |
| 8 | See plan | after generate | WorkoutHubView | ✅ plan-change notice | E | `generateAIProgram` horizon 7 |
| 9 | Train | session hero → "Start" | ActiveWorkoutView → GuidedWorkoutFlow | ⏳ ensureSession · ✅ complete sheet · ⚠ local-log fallback | E | one-set-at-a-time + rest timer |
| 10 | Review | Home Progress / Progress sheet | TraineeProgressView | ∅ per-section empties | E | reads logs/formReports |

**Consolidation note:** the only proposed deltas here are **5p** (assessment framing) and the
entry-point unification for step 7 (Home + Workout lead to the *same* sheet). Nothing else changes.

## A2. First run → find & join a coach 〔E fallback + 〔P ideal〕 ⟮U1,U4⟯

| # | Step | Entry point(s) | Destination | States | E/P | Rules / U# |
|---|------|----------------|-------------|--------|-----|------------|
| 1 | Discover | Home "Find a coach"; Profile "Find coaches" | FindCoachesView | ∅ "No coaches found" · ⏳ first-page spinner · ⚠ retry | E | search/filter/paginate |
| 2 | Inspect coach | tap row | CoachDetailView | ⏳ spinner · ⚠ "Coach not available" | E | `GET /coaches/{id}` |
| 3a | **Ask first** | "Contact" | chat thread | ✅ thread opens | E | `contactCoach` (chat only — not a relationship) |
| 3b | **Request to train** (primary ideal) | "Request to train with me" | join request **by coach identity** | ⌛ pending | **P** ⟮U1⟯ | needs `createJoinRequest(trainerId)`; **if unavailable → 3c** |
| 3c | **Invite-code fallback** (works today) | Profile join card; or 3b fallback | join request **by code** | ⌛ pending | E (⟮U4⟯ prefill) | `createJoinRequest(inviteCode:)`; code prefilled only if surfaced ⟮U4⟯ |
| 4 | Pending | after send | relationship status surface (Home + Profile) | ⌛ "Awaiting {coach}" + Cancel | **P**(surface) / E(state) | one trainee ↔ one trainer |
| 5 | Resolved | realtime/notification | status updates in place | ✅ accepted / ⚠ rejected (re-request allowed) | E | `handleJoinRequestRealtime` |
| 6 | Linked | on accept | "Coach guides your training" explainer | see A4 | **P**(explainer) | `hasLinkedTrainer` governs AI |

**Decision gate:** 3b is **conditional on ⟮U1⟯**. Until resolved, the committed path is **3c
(invite-code), which works today**; 3b is presented as the target once the backend confirms trainer-id
join. **No assumption is baked in.**

## A3. "Has a code already" (Journey C) 〔E〕

| # | Step | Entry point | Destination | States | E/P | Rules |
|---|------|-------------|-------------|--------|-----|-------|
| 1 | Enter code at signup | RoleSelection trainee invite field | stored on signup | — | E | `signup(inviteCode:)` |
| 2 | Or enter later | Profile join card | join request | ⌛ pending | E | `createJoinRequest(inviteCode:)` |
| 3 | Status | — | relationship surface | ⌛→✅/⚠ | E | — |
| 4 | Assigned plan | coach assigns | WorkoutHub (read-only plan) | ✅ "New plan from {coach}" | E | assigned plans read-only to trainee |

## A4. Trainee under a coach — the AI-plan transition 〔P explainer〕 ⟮U2⟯

The highest-impact proposed surface. **Governing rule unchanged:** `hasLinkedTrainer == true` gates
off solo AI generate + AI plan edit/delete. We only make it *legible*.

```
WHEN hasLinkedTrainer == true, Workout/Home/Profile show ONE explainer, copy chosen by ⟮U2⟯:
   retained → "Your AI plan is saved. {coach} now guides new training."
   paused   → "Your AI plan is paused while {coach} guides you."
   replaced → "{coach} now sets your plan."
   unknown  → "{coach} now guides your training."     ← DEFAULT until ⟮U2⟯ resolved
PLUS (all cases):
   assignedPlan == nil → ⌛ "Waiting for {coach} to assign your first plan."
   assignedPlan != nil → ✅ assigned plan (read-only) + "Assigned by {coach}."
ON leave (existing Leave flow):
   "After leaving your coach, AI planning availability is recalculated using your current eligibility."
   (NO restoration/retention of a prior AI plan promised.)
```

| State | Entry/trigger | Destination/surface | E/P | Rules / U# |
|-------|---------------|---------------------|-----|------------|
| Just linked, no plan | accept event | ⌛ explainer on Home + Workout | **P** | reads `hasLinkedTrainer`, `assignedPlan` |
| Plan assigned | assignment event | ✅ read-only plan, "Assigned by {coach}" | E(plan)/**P**(label) | read-only rule |
| Wants AI back | Profile → Leave | confirmation dialog → recalculated eligibility | E(flow)/**P**(copy) | ⟮U2⟯ — no behavior asserted |

**Must-not-change:** we do **not** change when AI appears/disappears; we add explanation only. ⟮U2⟯
stays open — copy defaults to neutral "unknown" until product confirms retain/pause/replace.

## A5. Returning trainee — resume a workout 〔P target + 〔E fallback〕 (friction E)

| # | Step | Entry point | Destination | States | E/P | Rules / notes |
|---|------|-------------|-------------|--------|-----|---------------|
| 1 | Open | app | Home Today CTA resolver | — | E | reads `activeWorkoutSession` etc. |
| 2a | Resume (day resolves) | **"Continue Workout"** | ActiveWorkoutView for that day @ active exercise | ✅ resumes mid-session | **P** | reuses `ensureSession`+`activeExerciseIndex`; **verified** `WorkoutSession` carries `planId/dayId/sets` |
| 2b | Resume (dayId nil/unresolved) | "Continue Workout" | **WorkoutHubView (fallback)** | — | E | no new resume rule |
| 3 | Start today | "Start Today's Workout" | WorkoutHubView | — | E | `assignedPlan`, `!doneToday` |
| 4 | Done today | "View today's workout" / "Go again" | WorkoutHubView | ✅ done state | E | — |

**Guarantee:** resume is exercise-granularity and **only** when the session's day is resolvable;
otherwise the current hub behavior is preserved. No new business rule (Phase 3 §4.1 ✎v2).

## A6. Nutrition 〔E + 〔P honest loading〕 (friction I)

| # | Step | Entry point | Destination | States | E/P | Rules |
|---|------|-------------|-------------|--------|-----|-------|
| 1 | Open tab | Nutrition tab | NutritionView | renders seed/loaded catalog (no blocking spinner) | E | `foodCatalog` pre-seeded |
| 2 | Switch day | day strip | per-day meals | ⏳ **inline shimmer on meals only** · ∅ honest "no meals logged" ≠ loading | **P** | `refreshDay`; no latency "fix" via visuals |
| 3 | Log meal | search overlay / ManualMealView | add meal | ✅ added | E | — |
| 4 | Scan food | FoodScannerView | entitled → scan; else "Available on {tier}" / "Coming soon" | ∅ gated | E(gate)/**P**(copy) ⟮U6⟯ | `aiCapabilities.visionFood`; upgrade-vs-not-built per ⟮U6⟯ |

## A7. Trainee profile & relationship management 〔E + 〔P status component〕 (friction N)

| State | Entry | Surface | Next action | E/P | Rules |
|-------|-------|---------|-------------|-----|-------|
| No trainer | Profile | "Find a coach" / "Have a code?" | discover or enter code | E/**P**(fallback framing) | solo-AI on |
| Pending | Profile/Home | ⌛ status + Cancel | cancel or wait | **P**(unified) | `pendingJoinRequest` |
| Linked | Profile | MyTrainerCard + Leave | train / leave | E | one-trainer rule |
| Left/removed | event | ⚠/ℹ status | re-discover | E | `trainee_left`/`trainer_removed` |
| Profile incomplete | Home nudge | dismissible "Complete profile (n of m)" → ProfileCompletionFlowView | finish (non-blocking) | **P** | H — nudge, **never a gate** |

---

# PART B — TRAINER JOURNEYS

## B1. First run → first trainee 〔E + 〔P stable dashboard〕 (friction G, J)

| # | Step | Entry point(s) | Destination | States | E/P | Rules / U# |
|---|------|----------------|-------------|--------|-----|------------|
| 1 | Launch → role Trainer | Signup step 2 | Trainer Assessment | — | E | role server-set |
| 2 | Home | after assessment | TrainerDashboardView | ∅ emptyRosterCard (invite code + Copy) | E | — |
| 3 | Invite | emptyRosterCard / Trainees banner / Profile invite card | copy invite code | ✅ copied | E | — |
| 4 | Request arrives | realtime | join-requests banner | ⌛ **banner stable**: prior value if present; skeleton **only** when none-yet + fetch active; stable ∅ after empty success | **P** ⟮impl⟯ | `trainerJoinRequests` is non-optional `[]` → needs a "loaded ≥1" signal (Phase 3 §10 ✎v2) |
| 5 | Review | banner tap / Trainees → Requests | JoinRequestsView | ∅ "No pending requests" · ⌛ busy row · ⚠ retry | E | — |
| 6 | Accept / Decline | row actions | roster update / dialog | ✅ roster+ / declined | E | accept = pending→linked one step; re-request allowed |
| 7 | Build first plan | **Plans "+"** (canonical); FAB "Create"; Dashboard quick action | CreatePlanView (3-step) | ⌛ "Continue later" draft · ⚠ validation | E/**P**(one destination, friction J) | — |
| 8 | Assign | **TraineeDetail assign** (canonical); PlanDetail assign; FAB "Assign"; Dashboard priority-2 | PlanQuickAssignSheet | ✅ assign success | E/**P**(same sheet) | `store.assign` |
| 9 | Track | TraineeDetail performance | History/Analytics/Meals | ∅/⏳/⚠ per section | E | reads logs/analytics |

## B2. Returning trainer — daily triage 〔E + 〔P〕

| # | Step | Entry point | Destination | States | E/P | Rules |
|---|------|-------------|-------------|--------|-----|-------|
| 1 | Open | app | Dashboard | no empty-flash (B1-#4 rule) | **P** | — |
| 2 | Pending? | banner | JoinRequestsView | ⌛ rows | E | — |
| 3 | Act on queue | priority card (check-in→session→assign→done) | TraineeDetailView / assign sheet | ✅ | E | `actionQueue` priority model |
| 4 | Nothing urgent | — | "You're clear for today" | ∅ allClear | E | — |

## B3. Trainer plan lifecycle & roster management 〔E〕

| Action | Entry | Destination | States | E/P | Rules (hard) |
|--------|-------|-------------|--------|-----|--------------|
| Create | Plans "+" | CreatePlanView | wizard | E | — |
| Edit/Delete | WorkoutPlanDetail | modify / confirm dialog | ⚠ confirm | E | — |
| Assign | (one sheet, B1-#8) | PlanQuickAssignSheet | ✅ | E | — |
| **Unassign** | TraineeDetail / PlanDetail | confirm dialog | ✅ plan cleared | E | **Unassign ≠ end relationship** |
| **Remove from roster** | TraineeDetail removeCard | confirm → dismiss | ✅ removed | E | distinct from Unassign; `trainer_removed` |
| Feedback | TraineeDetail | send note | ✅ | E | `saveFeedback` |

## B4. Trainer public-coach / marketing 〔E〕

| Area | Entry | Destination | States | E/P | Rules |
|------|-------|-------------|--------|-----|-------|
| Public profile | Profile → publicProfileCard | CoachPublicProfileEditorView | ⏳ load · ⚠ error · "Visible in Find Coaches" toggle | E | `GET/PUT /me/coach-profile` |
| Packages | packagesCard | TrainerCoachPackagesView | ∅/⏳/⚠/forbidden/missingProfile | E | display-only pricing, no checkout |
| Analytics | insightsCard | TrainerCoachAnalyticsView | ∅ all-zero hint · ⚠ | E | discovery analytics |
| Boost | boostCard | TrainerBoostStoreView | badge when boosted | E | — |
| Verification | verificationCard | TrainerCoachVerificationView | — | E | — |

---

# PART C — SHARED / CROSS-ROLE JOURNEYS

## C1. Trainer-relationship state machine (both sides) 〔E states, 〔P one legible surface〕

```
NO TRAINER ──request(⟮U1⟯ id | code)──► PENDING ──accept──► LINKED ──leave/remove──► NO TRAINER
     ▲                                     │                 │ (AI gated off; assigned plan read-only)
     └──────── reject (re-request ok) ◄─────┘                 └ Unassign ≠ unlink (relationship persists)
```
Mapping (read-only): linked ← `linked|link|accepted` · unlinked ← `unlinked|unlink|ended|removed` ·
reasons `trainee_left` / `trainer_removed`. **No new states; one status component renders the current
one + its single obvious next action, reused on Home + Profile (trainee) and Dashboard (trainer).**

## C2. Notifications 〔E types/push wired, 〔P states + priming〕 ⟮U3⟯

| Event | In-app surface (proposed) | Existing hook | E/P | U# |
|-------|---------------------------|---------------|-----|-----|
| Permission | in-context priming **before** OS prompt | existing auth trigger points | **P** | ⟮U3⟯ provisioning is eng |
| New join request | banner/badge (trainer) | `handleJoinRequestRealtime` | **P**(surface) | — |
| Request accepted/rejected | status update + toast (trainee) | same | **P** | — |
| New plan assignment | soft "New plan from {coach}" | `handlePlanAssignmentChanged` | **P** | — |
| Relationship change | status component update | `handleRelationshipChanged` | **P** | — |
| Inbox | ∅ empty / unread badge / grouped / clear-all | NotificationsInboxView | E(logic)/**P**(states) | — |

Push *delivery* (⟮U3⟯ APNs provisioning) is a separate eng task; **design delivers the in-app states
regardless** and never asserts push is live.

---

# PART D — ENTRY-POINT → DESTINATION MATRIX (every door, consolidated)

| Task | Primary door | Secondary doors | Single destination | Change |
|------|--------------|-----------------|--------------------|--------|
| Trainee: build AI plan | Home "Build my plan" | Workout empty CTA, "Regenerate" | AssessmentReviewSheet | wording by state |
| Trainee: join coach | Coach profile "Request to train" ⟮U1⟯ | Profile "Have a code?" (E) | join request | id primary / code fallback |
| Trainee: resume workout | Home "Continue Workout" | Workout session hero | ActiveWorkoutView (or hub fallback) | target change (E) |
| Trainee: find coach | Home / Profile | — | FindCoachesView | — |
| Trainer: create plan | Plans "+" | FAB "Create", Dashboard quick action | CreatePlanView | one destination |
| Trainer: assign plan | TraineeDetail assign | PlanDetail, FAB, Dashboard priority-2 | PlanQuickAssignSheet | one sheet |
| Trainer: review requests | Dashboard banner | Trainees → Requests | JoinRequestsView | — |
| Both: AI / human chat | center FAB | — | AI chat / HumanPeerChat | — |

---

# PART E — EXISTING vs PROPOSED (one-glance ledger)

| Journey touchpoint | Existing 〔E〕 | Proposed 〔P〕 (no new rule) |
|--------------------|--------------|------------------------------|
| Assessment | 18 flat steps | 3 labelled phases, consistent skip + rationale (display only) |
| Coach join | invite-code in Profile + chat "Contact" | request-from-profile ⟮U1⟯ + code fallback + clear Contact-vs-Request hierarchy |
| AI under coach | silent disappearance | conditional explainer (status + next + how-to-leave), ⟮U2⟯ neutral default |
| Relationship state | ad-hoc per screen | one status component (same states) |
| Continue Workout | → hub overview | → live session for resolved day @ active exercise (fallback: hub) |
| Trainer dashboard | skeleton flash even when empty | prior data / skeleton-only-when-none+fetching / stable empty (⟮impl⟯ signal needed) |
| Duplicate doors | 2–3 per task | 1 canonical + shortcuts to same destination |
| Notifications | types + push wired, states absent | priming + designed inbox/event states (⟮U3⟯ provisioning separate) |
| Profile completion | invisible | non-blocking nudge |
| Nutrition day | silent late pop-in | inline per-day loading, honest empty≠loading |
| "Coming soon" | ambiguous | "Available on {tier}" vs "Coming soon" ⟮U6⟯ |

**Everything in 〔P〕 is navigation / copy / state-presentation only.** No 〔P〕 row changes a business
rule, adds a permission, or assumes a backend capability.

---

# PART F — CONTRADICTIONS, MISSING DEPENDENCIES & DECISIONS NEEDED

### F1. Unresolved dependencies (carried verbatim; none resolved in this phase)

| # | Decision | Blocks | Safe default in use |
|---|----------|--------|---------------------|
| U1 | `createJoinRequest` accepts trainer-id vs invite-code only | A2-3b | invite-code fallback (works today) |
| U2 | `aiPlanOnLinkBehavior` retain/pause/replace on link | A4 copy | `unknown` → neutral copy |
| U3 | APNs provisioning committed | C2 delivery | design states only; prime before OS prompt |
| U4 | coach invite code surfaced on profile (prefill) | A2-3c prefill | manual code entry |
| U5 | days/week (8) & sleep (13)… and (new ✎) weight(2)/age(3)/fitness(5)/calorie(12) required vs progressive | assessment | **keep exact required set `{0,1,4,6,7,9,10,11,13}`; all others candidates only** |
| U6 | scanner/live-form: upgrade vs not-built | A6/M copy | "Coming soon" unless entitlement says upgradeable |

### F2. One contradiction flagged for product (not resolved here)
**Age (step 3)** is **not** in the verified required set, yet `AssessmentReviewSheet` presents Age as
**read-only/locked** (implying it must be captured once and not re-edited). This is an internal
inconsistency in the *existing* app, surfaced for a product decision — **Phase 4 does not reclassify
Age**; it keeps the current required set and flags the reconciliation under U5.

### F3. Implementation dependency (not a business rule)
Trainer-dashboard "no empty-flash" (B1-#4 / C2 inbox) needs a way to distinguish "not loaded yet"
from "loaded, empty" — today `trainerJoinRequests: [JoinRequestDTO] = []` cannot. A "loaded ≥1" flag
or optional marker is required at build time. **Eng/Phase-5 note, invents no rule.**

### F4. No other contradictions found
All CTA resolvers, state tables, and journeys were checked against the same rule set: fixed roles ·
one trainee↔one trainer · Unassign ≠ unlink · `hasLinkedTrainer` governs AI · assigned plans
read-only · native containers · `AppStore` single source of truth. No new permission or capability
appears anywhere in Parts A–E.

---

# PART G — FINAL SIGN-OFF CHECKLIST

Preserved, verified across every journey above:

- [x] Two fixed roles, server-set at signup, **not switchable**.
- [x] One trainee ↔ one trainer; re-request after reject/leave allowed.
- [x] **Unassign ≠ end relationship**; Remove-from-roster is the distinct end action.
- [x] `hasLinkedTrainer` governs AI availability — **explained, never changed**.
- [x] Assigned (trainer) plans read-only to the trainee; AI plans editable only when no trainer.
- [x] No promise about a prior AI plan after leaving — eligibility **recalculated**, nothing restored.
- [x] Required assessment set `{0,1,4,6,7,9,10,11,13}` unchanged; phases are labelling only.
- [x] All features intact: AI generate, live form, 3D demos, scanner, nutrition, packages/boost/
      analytics/verification, chat/calls, feedback, form reports.
- [x] Native iOS only — tabs, NavigationStack, sheets, fullScreenCover, dialogs, collapsing headers, FAB.
- [x] `AppStore` single source of truth; new surfaces read existing flags, invent no permissions.
- [x] Brand (purple / Work Sans / soft weights) + 6-language localization preserved.
- [x] U1–U6 carried open with safe defaults; no backend capability or AI-on-link behavior assumed.

**Open items requiring your product decision before Phase 5 builds the dependent flow:** U1, U2, U3,
U4, U5 (incl. Age/F2), U6. Design can proceed on the documented safe defaults if you prefer to defer
any of them.

---

*End of Phase 4. Awaiting explicit approval. Phase 5 (screen design) will not begin until approved.*
