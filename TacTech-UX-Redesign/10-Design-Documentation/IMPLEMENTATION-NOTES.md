# TacTech UX Redesign — Implementation Notes (for future SwiftUI work)

> Build-time requirements and tracked assumptions that **cannot be verified from static mockups**
> and must be honored when the designs are implemented. No source is changed by this document.

## Tracked requirements (apply to every screen, every group)

### R1 — Dynamic Type (TRACKED REQUIREMENT, not an assumption)
All user-facing text **must** use scalable text — `TTTypography`/`TTFont` styles that resolve to
SwiftUI `Font` built on the system text-style scale (e.g. relative to `.body`, `.headline`, etc.),
**never fixed non-scaling point sizes**. The static HTML mockups use fixed px for fidelity only; they
do **not** demonstrate Dynamic Type and must not be read as a spec for fixed sizes.
- Every label, button title, metric, and caption scales with the user's Dynamic Type setting.
- Layouts must reflow (wrap, grow vertically) at the larger accessibility sizes — Today cards, CTAs,
  metric wells, and tab labels included. No CTA truncation at AX sizes.
- Verify against the existing `TTFont.workSans(_:weight:)` usage; if any call site uses a fixed size
  that does not scale, that is a build defect to fix, not a design intent.
- **Status: open / to verify at implementation.** Owner: iOS eng.

### R2 — Contrast (verified in mockups, keep at build)
- Body/caption text ≥ 4.5:1; decorative & navigational icons ≥ 3:1.
- Mockups use `TTColor.inkMuted` (#6B6B70, ~5:1) for muted text, chevrons, and inactive tab items;
  active = brand `#8621EB`. Do not reintroduce the lighter #C4C4CA/#9A9AA0 greys for text or chevrons.
- White text only on brand purple (`#8621EB`) or darker — never on light orange.

### R3 — Meaning never by color alone
Every state cue pairs color with an icon + text label (e.g. in-progress = orange dot **and** "IN
PROGRESS" text; pending = clock icon **and** "Request pending"). Keep this in implementation.

### R4 — RTL / 6 languages
All strings via `Localizable.xcstrings` (en, ar, es, fr, hi, zh-Hans). Arabic = full RTL: mirror
leading/trailing, chevrons, progress direction, and horizontal strips; locale-correct numerals.
Illustrative English copy in mockups is not final.

### R5 — No invented data at build
Every rendered number/label must bind to a verified `AppStore` property (see each group's per-frame
annotations). Items marked ⚠️ NEEDS VERIFICATION (e.g. Trainee Home State 8 "plan finished/expired")
require a product/backend decision before they can be built — they have no data source today.

## Per-group build flags

### Group 1 — Trainee Home
- State 8 (plan finished/expired): **blocked** — `WorkoutPlan` has no completion/expiry field. Needs
  a product decision (new derivation or model field) before implementation.
- Rest day (State 7): rest is **implicit** (`session(on:) == nil`); copy must not imply a stored rest flag.
- `FormReport.score` has no declared range; treat as the app does (÷100 for progress, clamp 1–99 for
  health) — do not assert a 0–100 bound in new code without confirming the backend contract.

### Group 2 — Workout Hub + Active Workout

**W-1 — OPEN PRODUCT ITEM: no logged-vs-prescribed set capture (impacts stats integrity).**
`GuidedWorkoutFlow.logSet()` (WorkoutHubView.swift:1244-1275) writes `reps: set.reps` and
`weightKg = set.weightKg ?? item.recommendedWeightKg ?? 0` — i.e. it records the **prescribed** set,
not what the trainee actually performed. There is **no `TextField`/`Stepper`/edit affordance** in the
guided flow (verified by grep). Consequence: `WorkoutLog.totalVolumeKg`, workout history, and anything
derived from logged sets reflect the plan, not reality. This is a **product gap**, not a visual one.
- Decision needed: add an actual-reps/weight capture step to the guided flow (and the matching
  backend field semantics) — or explicitly accept "prescribed = logged" as intended.
- Until decided, mockups show the source-faithful "Done logs the prescribed set" behavior and do **not**
  invent an editor. Owner: product + iOS eng. Status: **open.**

**W-2 — PENDING DECISION: rest "Skip rest / +30s" control.**
`restScreen` auto-advances at 0 with **no manual skip** today (:1397). A skip/extend control was
considered and **removed from the Group-2 approval round** because it changes behavior. If adopted it's
a new control requiring sign-off; re-present separately. Status: **pending.**

**Badge copy decision:** source logic is `canMutateAI ? "AI" : "Trainer"` (WorkoutHubView:211). A locked
AI plan therefore shows "Trainer" today. Mockup (State 3) proposes "Read-only" for clarity — confirm
desired badge copy for the AI-plan-after-linking case before build. Status: open.

### Group 3 — Trainer Home
**W-3 — Dashboard join-requests skeleton flash (friction G).** `joinRequestsLoadingSkeleton`
(TrainerDashboardView.swift:500) is shown off `isLoadingJoinRequests`, set true in `.task` and cleared
after the fetch (:39-41, 85-89) — so it flashes even when 0 requests resolve. Fix needs a way to tell
"not loaded yet" from "loaded, empty": `trainerJoinRequests` is a non-optional `[]` and can't. Add a
"has completed ≥1 fetch" flag (or optional marker); then show the skeleton only when (no prior value AND
fetch active) and render a stable empty afterward. Implementation observation, no business rule. Status: open.

- **Header chips accessibility (R4):** the dashboard header metric chips are shown in mockups with emoji
  (👥 Trainees, ★ Coach) for fidelity. In build they use `TTHomeProfileMetric` with real `SandowIcons`
  (`.usersTwo`, `.starFull`) — each icon-only chip needs a proper `accessibilityLabel`, and no meaning
  may rest on the emoji/icon alone (R3/R4). Do not ship emoji as the only chip content.

### Group 4 — Trainer Plans + Create Plan
**W-4 — "Continue later" does not persist a draft (misleading label).** In `CreatePlanView`, the
"Continue later" footer button opens `confirmationDialog("Continue later?")` whose message is
*"This plan isn't saved yet. You can start again anytime from Plans."* (new) / *"Unsaved edits will be
discarded."* (editing), and the confirm action is `dismiss()` — **the in-progress plan is discarded, not
saved** (CreatePlanView.swift:152-165, 257). The label implies draft persistence that doesn't exist.
Decision: either rename the control (e.g. "Discard") or actually implement draft saving. Until decided,
mockups show the real discard copy. Status: open (product/copy).

- Wizard primary CTA is `Color.black` (:249), not orange — matched in mockups. Progress track is orange.
- Plan-list meta chips and card icons are emoji in mockups for fidelity; build uses SandowIcons
  (`.alarm`, `.calendar1`, `.kettlebell`, `.clipboard`, `.barbellDiagonal`) + accessibilityLabels (R4).

### Group 5 — Trainees + Join a Coach
**W-5 — roster "Active/Idle" badge has no recency window.** `traineeRow` computes
`active = store.logs(for: trainee.id).first != nil` (MyTraineesView.swift:256), and `logs(for:)` returns
*all* of a trainee's logs unfiltered (AppStore.swift:1312). So "Active" = ever-logged, "Idle" = never
logged — it does not reflect recent engagement; a long-idle trainee still shows "Active". Decision:
either redefine the badge with a recency cutoff (e.g. logged in last 7 days) or relabel it
("Started" / "Not started") so it isn't mistaken for a recency signal. The real recency triage lives in
the dashboard action queue ("N days without a log"). Status: open (product).

- Invite-banner "Copy" button is `Color.black` (MyTraineesView:244) — matched in mockups.
- State 6 "Request declined. You can request another coach." is proposed copy for the existing `message`
  slot — confirm the final localized string at build.

*(Later groups append their own flags here.)*
