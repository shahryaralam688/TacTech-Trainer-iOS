# QA — Invite link + Leave / Remove

## Happy path
1. **Trainer** copies invite code (Profile / My Trainees).
2. **Trainee** Profile → Join → paste code → **Link trainer**.
3. Trainee **My Trainer** shows name; trainer roster lists them.
4. Assign a plan → trainee sees it on Workout.
5. **Unassign plan** → plan gone; **My Trainer** still linked.
6. **Trainee Leave trainer** → confirm → toast “Trainer removed”; **My Trainer empty within ~1s**; Join card returns; trainer roster without them.
7. Re-link with same invite → works again.
8. Or: **Trainer Remove from roster** on trainee detail → confirm → success toast → detail dismisses; roster refreshed; trainee My Trainer empty.

## Errors
- Link while already linked → **409** toast shows server `detail` (unlink first).
- Network / API failure on Leave or Remove → **red toast** with server `detail` (never silent).
- Leave when already unlinked (**404**) → clear stale UI + toast “Trainer removed” (treated as success).
- DEBUG: failed unlink/remove prints HTTP kind + `detail` to console.

## Live sync (two sims, both foreground — no force-quit)
1. Linked pair; both on home/dashboard.
2. **Trainee Leave** → trainer roster loses them live; optional “{name} left your roster”.
3. Re-link via Accept; then **Trainer Remove** → trainee My Trainer clears live; optional “You’ve been removed…”.
4. **Unassign plan** → neither side loses relationship; no `relationship_ended`.
5. Chat still opens after leave/remove. Join Accept still live-updates trainee.
6. Airplane on peer → action → later reconnect/foreground → state corrects.

## Must not change
- Chat with that peer still openable after leave/remove.
- Boost, AI paywall, Form Studio 3D, packages, notifications — untouched.
- Unassign ≠ Remove (relationship stays on Unassign only).
