# TacTech — Phase 5: Native iOS Screen Design

> **Source of truth:** Phase 3 v2 architecture + Phase 4 consolidated journeys.
> **These are design specifications, not SwiftUI.** No source/`AppStore`/backend/business-logic
> changes; no new permissions or capabilities; all existing features preserved. Native iOS only.
> **Delivered incrementally, one journey group per review.**

## Design groups (review order)

| Group | File | Journey | Status |
|-------|------|---------|--------|
| 1 | `GROUP-1-Trainee-Home.md` | Trainee Home + relationship surfaces | **▶ for review** |
| 2 | `GROUP-2-Trainee-Workout.md` | Workout Hub + Active Workout | pending G1 |
| 3 | `GROUP-3-Trainer-Home.md` | Trainer Home / triage | pending |
| 4 | `GROUP-4-Trainer-Plans.md` | Plans + Create Plan wizard | pending |
| 5 | `GROUP-5-Trainer-Trainees-Relationship.md` | Trainees, Join Requests, Join-a-coach | pending |
| 6 | `GROUP-6-Nutrition-Profile-Discovery-Notifications.md` | remaining features | pending |

## Shared design contract (applies to every group)

**Design system — use existing tokens verbatim (`TacTech/DesignSystem/TTTheme.swift`):**
- **Brand:** `TTColor.brand` = `#8621EB` (`TTPurple.p80`); palette `TTPurple.p10…p100`. Accent `TTColor.accent` (p80), `accentSoft` (p10). Workout flows use `TTColor.actionOrange` (existing).
- **Surfaces:** `canvas`, `surface`, `surfaceAlt`, dark header `TTPurple.p100`. **Every screen sets an explicit background.**
- **Ink:** `ink`, `inkMuted`, `inkSubtle`; on dark headers `inkOnDark` / `inkOnDarkMuted`.
- **Semantic:** `success`, `danger`, `info`; nutrition `protein/carbs/fat/calorie`; `sleep`, `heart`.
- **Type — Work Sans via `TTTypography`** (soft-weight policy: nothing renders heavier than Medium). Use the named styles (`heading*`, `text*`, `paragraph*`), never raw sizes.
- **Spacing — `TTSpace`** (8pt grid): screen margin `screen`=16; `fieldHeight`/`buttonHeight`=56, `heroButtonHeight`=64.
- **Radius — `TTRadius`**: card 16 (`md`), lg 22, pill 100, `button` 18, `buttonHero` 28, `header` 56.
- **Icons:** SF Symbols + the bundled **SandowIcons** library; sizes from `TTIconSize`.

**Reusable components to compose from (do not invent new ones unless noted):**
`TTHomeProfileHeader` (collapsing hero), `TTHomeWeekDatePicker`, `TTButton` (.primary/.secondary/.ghost),
`TTCard*` (`TTListTile`, `TTMetricCard`, `TTMediaActivityCard`, `TTCardBadge`, `TTCardActionButton`),
`TTChip`, `TTProgressRing`, `TTSectionHeader`, `TTEmptyState`/`TTHomeEmptyState`, `TTAlertBanner`
(tones warning/success/info/error/accent), `TTToastMessage`/`.ttToast`, `TTFloatingTabBar` + center FAB,
`TTModalSheetChrome` / `.ttTopRoundedSheet` for sheets, `TTProfileScreen` scaffold.

**Presentation vocabulary (HIG, existing patterns):**
`push` (NavigationStack) · `sheet` (`.ttTopRoundedSheet` / `.ttModalSheetPresentation`) ·
`fullScreenCover` (guided/immersive) · `inline` (state card, never a screen) ·
`confirmationDialog` (destructive/confirm) · `toast` (`TTToastMessage`).

**Accessibility & i18n (every screen):**
- 6 languages (en, ar, es, fr, hi, zh-Hans). **Arabic = full RTL:** mirror leading/trailing, chevrons,
  progress direction, and horizontal strips; keep numerals locale-correct. All strings via
  `Localizable.xcstrings` keys — **no hard-coded copy**; wireframe text shown in English is illustrative.
- Dynamic Type: type styles scale; min tap target 44×44; respect reduce-motion (FAB/collapse already do).
- Color contrast: body text uses `ink`/`inkMuted` on `canvas`/`surface`; never color-only state cues —
  pair with icon + label.

**Unresolved-decision defaults honored in every spec (U1–U6):**
U1 invite-code fallback is the built path · U2 AI-under-coach shows the **neutral** state only ·
U5 required assessment set unchanged, Age inconsistency flagged not decided · U6 never invent
entitlement/availability (show "Coming soon" unless an existing flag says upgradeable).
