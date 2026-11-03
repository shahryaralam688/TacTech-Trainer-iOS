# TacTech — Phase 2: UX Audit & Friction Analysis

> **Source of truth:** verified Phase 1 findings (`PHASE-1-Product-Understanding.md`).
> **Scope:** analysis only. No UI generated, no source or business logic modified.
> **Lens:** every issue is read from two perspectives — **first-time user (FTU)** and **returning user (RU)**.
>
> **Legend — fix type:**
> 🟦 **UI/UX-only** (copy, layout, state handling — no logic change) ·
> 🟨 **UI + store-flag read** (surface an existing `AppStore` flag; no new business rule) ·
> 🟥 **Needs product/business decision** (new rule or backend contract — flagged, not assumed).

---

## Part 1 — Problem taxonomy

Before the per-issue audit, a quick separation of concerns (brief instruction #7):

| Class | What it is | Examples here | Who owns it |
|-------|-----------|---------------|-------------|
| **Actual UX problems** | Confusion caused by UI, copy, navigation, or state presentation | A, B, D, E, G, H, and the cross-cutting issues J–N below | This redesign |
| **Technical / performance** | Latency, cold fetches, render timing | Nutrition day-refresh (I), assessment submit retry | Eng — design only *masks* with honest states |
| **Backend limitations** | Missing contract / provisioning | APNs provisioning (F), server forbid responses on AI edit when linked | Backend — design provides the *states*, not the fix |

**Guiding principle for the whole redesign:** *reduce cognitive load by making state legible.* Most
TacTech friction is not missing features — it's that the app changes what it offers (AI controls,
CTAs, join paths) **without telling the user why**. The fixes are overwhelmingly 🟦/🟨, not 🟥.

---

## Part 2 — Friction point deep-dive (brief §5 A–I)

Each issue: **Current behavior → Why users get confused (FTU/RU) → Recommended improvement →
Screens affected → Fix type.**

---

### A — Trainer discovery and joining are disconnected 🟨
**Current:** `FindCoachesView → CoachDetailView` primary CTA is **"Contact"**, which only opens a
chat thread (`store.contactCoach`). To actually join, the trainee must leave discovery, go to
**Profile → join card**, and type an **invite code** (`createJoinRequest(inviteCode:)`). Two
unrelated mental models for one goal.

**Why confused:**
- *FTU:* "I found a coach I like and messaged them — am I now their client? Why is nothing happening?" The chat implies a relationship that doesn't exist.
- *RU:* Knows joining needs a code but can't get it from the coach's profile — must ask in chat and copy-paste.

**Recommended:** Make the coach's identity carry the join action. On `CoachDetailView`, add a
**"Request to train with me"** action alongside Contact. Because the coach profile already resolves
a real trainer identity, the request can be created **against that trainer** rather than a typed code
— the invite-code form becomes the *fallback* ("Have a code instead?"), not the primary path.
Chat stays as "ask a question first."

**Screens:** `CoachDetailView`, `TraineeProfileView` (join card demoted to fallback), join-request status surface.

**Fix type:** 🟨 — needs a join-request-by-trainer-id entry point. If the backend's
`createJoinRequest` only accepts an invite code today, resolving coach→code is a 🟥 backend note
(see Part 5). The *UX* and the status states are UI-only.

---

### B — AI plan disappears without explanation 🟨 (highest-impact confusion)
**Current:** When `hasLinkedTrainer` becomes true, `canShowSoloAIGenerate` and
`traineeCanEditDeleteAIPlan` flip to false. The "Build my plan" card, and the Edit/Regenerate/Delete
block, silently vanish. The assigned plan becomes read-only. **No message explains any of this.**

**Why confused:**
- *FTU:* Just connected a coach, and the AI plan they built yesterday is gone / uneditable. Feels like data loss or a bug.
- *RU:* Knows a coach "takes over" but still can't tell *what happened to my old plan* or *when a new one is coming.*

**Recommended:** A persistent, honest **"Your coach is now guiding your training"** explainer that
reads the same store flags (no new permissions — respects brief constraint). It must answer the four
questions the brief lists:
1. *Why* AI generation is off — "Your coach now sets your plan."
2. *What happened to the old plan* — kept/visible vs replaced (state-driven).
3. *What's next* — "Waiting for {coach} to assign your first plan" (pending) vs "Your coach assigned {plan}".
4. *How to go back* — "Leaving your coach returns AI planning" (links to existing Leave flow).

**Screens:** `WorkoutHubView` (empty + plan states), `TraineeDashboardView` Today zone, `TraineeProfileView` trainer section.

**Fix type:** 🟨 — pure presentation of existing `hasLinkedTrainer` / `assignedPlan` / `pendingJoinRequest` flags.

---

### C — Fitness assessment is long; skips are weak 🟦
**Current:** 18 steps. Sensitive steps (BodyScan/Voice/Text) *are* skippable but the affordances are
inconsistent, and camera/mic permission is requested with no rationale.

**Why confused:**
- *FTU:* 18 steps before seeing the app = high abandon risk; being asked for camera/mic with no "why" reads as invasive, prompts a decline, then a dead-looking step.
- *RU:* (assessment is first-run only; re-entry is via `AssessmentReviewSheet`, which is already a focused edit form — not the 18-step gauntlet) — low RU impact.

**Recommended (no data removed — brief constraint):**
- **Group the 18 steps into labelled phases** ("About you" · "Your training" · "Fine-tune (optional)") so progress feels like 3 chunks, not 18.
- **Chunk-level progress** + "Step 3 of 3 · optional" labeling for the 14–16 sensitive block.
- **Consistent "Skip" affordance** on every optional step, same placement/wording.
- **One-line rationale** on each sensitive step ("Used to tailor form coaching — optional") and
  request the OS permission **only on tap**, not on step entry.
- Keep **"Continue later"** (already exists) visible.

**Screens:** `FitnessAssessmentFlowView`, `FitnessAssessmentSteps`.
**Fix type:** 🟦 — grouping/labels/copy/skip placement; required-step set unchanged.

---

### D — Browse & join should share trainer identity 🟨
Same root cause as **A** (re-enter invite code after viewing a coach). Treated as one workstream
with A: the coach profile is the identity; the join request should originate from it. Not a separate
fix — consolidated into A to avoid duplicate entry points (see cross-cutting **J**).

---

### E — "Continue Workout" does not resume the live session 🟦
**Current:** Home's Continue Workout CTA (`TraineeDashboardView:407/424`) sets `showWorkouts = true`
→ opens `WorkoutHubView` **overview**. The actual live resume (`GuidedWorkoutFlow` at the right set)
lives inside `ActiveWorkoutView`, computed from `completedExerciseCount`.

**Why confused:**
- *RU (primary):* Taps "Continue Workout" mid-session expecting the rest timer / next set; instead lands on a plan overview and must re-navigate (hub → day → Start → Continue). Breaks momentum during a workout — the worst moment to add taps.
- *FTU:* Rarely sees this (needs an in-progress session).

**Recommended:** When `store.activeWorkoutSession != nil`, Continue Workout should deep-link
**straight into `ActiveWorkoutView`/`GuidedWorkoutFlow` at the active exercise index**, bypassing the
hub overview. Keep "See My Workouts" / "Start Today's Workout" → hub for the no-session cases.
Label discipline: "Continue" resumes live; "View/Start" opens the hub.

**Screens:** `TraineeDashboardView` Today CTA → `ActiveWorkoutView`.
**Fix type:** 🟦 — navigation target change; the resume logic already exists in `ensureSession`.

---

### F — Background notification states 🟨 + 🟥(provisioning only)
**Corrected from Phase 1:** push *is* wired (`PushNotificationDelegate`,
`requestAuthorizationAndRegister`); notification **types already exist**
(`join_request`, `join_request_accepted/rejected/cancelled`, plan assignment, chat/call, pro). What's
missing is **(a) designed in-app states** and **(b)** committed APNs provisioning (backend/eng).

**Why confused:**
- *FTU:* No in-context ask — the OS permission prompt can appear cold, or never, so users miss request/accept events.
- *RU:* Relationship/plan changes happen silently in-app; the inbox has types but the *moments* (request received, accepted, plan assigned) aren't surfaced where the user is looking.

**Recommended (design deliverables, not push enablement):**
- **In-context permission priming** before the OS prompt (explain value, then ask) — reuse the existing auth trigger points.
- **Designed inbox states:** empty, unread badge, grouped by type, per-item + clear-all (logic exists).
- **In-app event surfaces** for the five events the brief lists, driven by the existing realtime handlers (`handleJoinRequestRealtime`, `handleRelationshipChanged`, `handlePlanAssignmentChanged`): toast + a home banner/badge, not a modal.

**Screens:** `NotificationsInboxView`, trainee/trainer Home banners, permission-priming sheet.
**Fix type:** 🟨 for states; 🟥 for APNs provisioning (Part 5).

---

### G — Join-request loading skeleton flash 🟦
**Corrected from Phase 1:** the flash is on **`TrainerDashboardView`**, not `JoinRequestsView`.
`isLoadingJoinRequests` starts `true` in `.task` and shows `joinRequestsLoadingSkeleton`
unconditionally until the fetch resolves — so even **zero** pending requests flash a skeleton, then
collapse to nothing.

**Why confused:**
- *RU:* Dashboard "jumps" on every open — a skeleton for something that turns out to be empty reads as a glitch and draws the eye to a non-event.
- *FTU:* First dashboard open looks unstable.

**Recommended:** Only show the skeleton when there is a *reason* to expect content — e.g. gate the
skeleton on "no cached value yet AND a fetch in flight," and when the resolved result is empty,
render **nothing** (or a stable slot) with no intermediate placeholder. Prefer showing last-known
cached count immediately, refreshing in place.

**Screens:** `TrainerDashboardView` join-requests area.
**Fix type:** 🟦 — state-gating of an existing skeleton; no new data.

---

### H — Profile completion not enforced / inconsistent 🟦
**Current:** `ProfileCompletionFlowView` exists but is **not a launch gate** (only reachable from
Account Settings). Completion is effectively optional and invisible.

**Why confused:**
- *FTU:* Never prompted to finish a profile; later hits features that assume profile data (coach discovery visibility, trainer public profile) with no guidance.
- *RU:* No sense of "what's left" — no progress signal.

**Recommended (lightweight, non-blocking — brief constraint):** a **progressive completion nudge**,
not a gate: a dismissible "Complete your profile (2 of 5)" card on Home that routes into the
*existing* `ProfileCompletionFlowView`, surfaced contextually (e.g. a trainer publishing a public
profile). Never block root access.

**Screens:** trainee/trainer Home, `ProfileCompletionFlowView` (reused), Profile tab.
**Fix type:** 🟦 — a nudge card + progress read; no new gate, no forced flow.

---

### I — Nutrition first-load 🟦 (minor)
**Corrected from Phase 1:** no blocking cold-load — `NutritionView` renders the seeded `foodCatalog`
immediately; only the **selected day's meals** refresh silently via `refreshDay`.

**Why confused:** *RU:* on day switch, logged meals can pop in a beat late with no indication, so a
day can momentarily look empty.

**Recommended:** a quiet per-day loading affordance (inline shimmer on the meals list only, or a
"Updating…" chip), and an honest empty-vs-loading distinction so a loading day never reads as "no
meals logged." Do **not** try to fix fetch latency with visuals (brief constraint).

**Screens:** `NutritionViews` meals section.
**Fix type:** 🟦.

---

## Part 3 — Cross-cutting issues (found beyond the brief's list)

These emerged from the Phase 1 map and compound cognitive load across screens.

### J — Duplicate / competing entry points 🟦
Several actions have 2–3 doors, which forces users to learn the app's geography instead of its tasks:
- **Create plan (trainer):** Plans tab "+" **and** Liquid FAB "Create workout plan" **and** dashboard quick action.
- **Assign plan (trainer):** `TraineeDetailView` assign card, `WorkoutPlanDetailView` assign card, Liquid FAB "Assign", dashboard priority-2 card.
- **AI generate (trainee):** Home "Build my plan", WorkoutHub empty CTA, WorkoutHub "Regenerate".
- **Join a trainer (trainee):** Profile join card (today) + (proposed) coach profile.

**Recommendation:** keep **one primary, obvious** entry per task and let the others be *contextual
shortcuts that lead to the same sheet*, with consistent labels. Don't delete doors users rely on —
unify their **destination and wording** so they don't feel like different features. The Liquid FAB
should be the "quick action from anywhere" layer, not a parallel universe.
**Fix type:** 🟦 — routing + label consolidation.

### K — Terminology drift 🟦
"Trainer" vs "Coach" are used interchangeably (role is `.trainer`; discovery is "Find **Coaches**";
packages/boost are "Coach" features). "Plan" vs "Program" vs "Week" also mix
(`generateAIProgram` → notice "AI week ready"; plans are "Workout Plans"). **Recommendation:** pick
one user-facing term per concept (suggest **Coach** for the person, **Plan** for the artifact, **Week**
only for an AI 7-day horizon) and apply via the localization catalog. 🟦 copy-only.

### L — "Contact" vs "Request" ambiguity 🟦
Tied to A/D: a chat ("Contact") and a roster relationship ("Request") look equally weighty on the
coach profile, but mean very different commitments. Needs clear visual hierarchy and copy that states
the consequence of each. 🟦.

### M — Unexplained disabled / "Coming soon" states 🟦
Food Scanner and Live Form show "Coming soon" when `aiCapabilities.visionFood/visionPose` are off,
but it's unclear whether that's *per-account entitlement* or *not-built-yet*. Users can't tell if
upgrading/acting unlocks it. **Recommendation:** distinguish "Available on {tier}" (actionable →
paywall) from "Coming soon" (not yet shipped). 🟦/🟨 (reads entitlement flags).

### N — Relationship state is legible to code but not to users 🟨
There's no user-facing map of "where am I" across: no trainer → request pending → accepted → linked →
left/removed. Each state exists in the store but is shown ad hoc. **Recommendation:** a single,
consistent **trainer-relationship status component** (one for trainee, one for trainer) that renders
the current state + the one obvious next action, reused on Home + Profile. Ties A, B, F, N together.
🟨 — reads existing flags.

---

## Part 4 — Prioritized problem list

Ranked by **(user impact × frequency) ÷ effort**, FTU and RU weighted.

| Rank | Issue | Severity | Who hits it | Fix type | Effort |
|------|-------|----------|-------------|----------|--------|
| **P0** | **B** — AI plan vanishes unexplained | 🔴 Critical | Every trainee who links a coach | 🟨 | Low–Med |
| **P0** | **E** — Continue Workout doesn't resume | 🔴 Critical | Every mid-workout RU | 🟦 | Low |
| **P1** | **A/D/L** — Discovery↔join disconnect | 🟠 High | Every trainee seeking a coach | 🟨 | Med |
| **P1** | **C** — Assessment length/skip clarity | 🟠 High | Every new trainee (abandon risk) | 🟦 | Med |
| **P1** | **N** — Relationship state not legible | 🟠 High | Trainees + trainers in any link state | 🟨 | Med |
| **P2** | **G** — Dashboard skeleton flash | 🟡 Med | Every trainer, every open | 🟦 | Low |
| **P2** | **J** — Duplicate entry points | 🟡 Med | Both roles, ongoing | 🟦 | Med |
| **P2** | **F** — Notification states/priming | 🟡 Med | Both roles | 🟨 (+🟥 provisioning) | Med |
| **P3** | **H** — Profile completion nudge | 🟢 Low | New users | 🟦 | Low |
| **P3** | **K** — Terminology drift | 🟢 Low | Everyone (subtle) | 🟦 | Low |
| **P3** | **M** — Disabled/"coming soon" clarity | 🟢 Low | Trainees on AI features | 🟦/🟨 | Low |
| **P3** | **I** — Nutrition per-day loading | 🟢 Low | Trainees switching days | 🟦 | Low |

**Headline:** the two P0s and all P1s are achievable **without new business rules** — they are
presentation, navigation, and copy. Only notification *provisioning* (F) and possibly
*join-by-coach-identity* (A) touch the backend contract.

---

## Part 5 — What requires a business/backend decision (🟥)

Explicitly separated so design never silently invents a rule (brief constraints):

1. **Join-by-coach-identity (A/D):** does `createJoinRequest` accept a trainer id, or only an invite
   code? If code-only, either (a) backend resolves coach→code, or (b) design keeps code entry but
   pre-fills/retrieves it from the coach profile. **Decision needed before Phase 5 builds the flow.**
2. **APNs provisioning (F):** committing the push entitlement/certs is eng, not design. Design will
   deliver the in-app states regardless.
3. **"Old AI plan" retention on linking (B):** does an existing solo AI plan *remain visible/read-only*
   after a coach links, or is it replaced? Phase 1 shows the assigned plan takes over; the exact
   retention behavior determines copy ("your plan is paused" vs "replaced"). **Confirm the actual
   server behavior before finalizing B's copy.**

---

## Part 6 — Current vs proposed journeys (summary; full maps in Phase 3)

> Phase 3 will produce the detailed navigation maps. These are the *intended deltas* Phase 2 recommends.

**Trainee — find & join a coach**
- *Current:* Discover coach → **Contact (chat only)** → leave → Profile → type invite code → pending → … (two models, manual code).
- *Proposed:* Discover coach → **Request to train with me (from the profile)** → clear pending status component → accepted → assigned plan. Chat and invite-code become secondary paths. *(Resolves A, D, L, N.)*

**Trainee — AI plan under a coach**
- *Current:* AI controls silently disappear on link; no explanation.
- *Proposed:* AI controls give way to a **"Your coach guides your training"** explainer with status + next action; Leave restores AI. *(Resolves B, N.)*

**Trainee — resume a workout**
- *Current:* Continue Workout → hub overview → day → Start → Continue (4 hops).
- *Proposed:* Continue Workout → **live session at the active set** (1 hop). *(Resolves E.)*

**Trainee — first run**
- *Current:* 18 ungrouped steps, weak skips, cold permission prompts.
- *Proposed:* 3 labelled phases, consistent skips, rationale + on-tap permission, "continue later". *(Resolves C.)*

**Trainer — triage the day**
- *Current:* Dashboard skeleton flash even when empty; create/assign scattered across many doors.
- *Proposed:* Stable dashboard (cached count, no empty-flash); one primary create/assign path with contextual shortcuts to the same sheet. *(Resolves G, J.)*

---

## Part 7 — Must remain unchanged (hard constraints)

Carried from Phase 1 + brief; the redesign must preserve all of these:

- **Two fixed roles**, chosen at signup, server-set, **not switchable**.
- **One trainee ↔ one trainer** at a time; re-request after reject/leave allowed.
- **Unassigning a plan does NOT end the relationship** (distinct from Remove from roster).
- **`hasLinkedTrainer` governs AI availability** — we *explain* it, we do **not** change the rule.
- **Assigned (trainer) plans are read-only to the trainee**; AI plans editable only when no trainer.
- All existing features preserved: AI generate, live form correction, 3D form demos, food scanner,
  nutrition tracking, coaching packages/boost/analytics/verification, chat & calls, feedback, form reports.
- **Native iOS patterns only** — NavigationStack, sheets, fullScreenCover, confirmationDialog,
  collapsing headers, floating tab bar; no web/Android/Material paradigms.
- **`AppStore` remains the single source of truth** — new UI reads existing flags, invents no permissions.
- Existing brand (purple / Work Sans / soft weights) and the 6-language localization preserved.

---

*End of Phase 2. Awaiting review & approval before Phase 3 (UX Architecture & navigation maps).
No designs or code will be produced until approved.*
