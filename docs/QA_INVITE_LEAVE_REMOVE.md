# QA — Invite link + Leave / Remove

## Happy path
1. **Trainer** copies invite code (Profile / My Trainees).
2. **Trainee** Profile → Join → paste code → **Link trainer**.
3. Trainee **My Trainer** shows name; trainer roster lists them.
4. Assign a plan → trainee sees it on Workout.
5. **Unassign plan** → plan gone; **My Trainer** still linked.
6. **Trainee Leave trainer** → confirm → toast “Trainer removed”; My Trainer empty; Join card returns; trainer roster without them.
7. Re-link with same invite → works again.
8. Or: **Trainer Remove from roster** on trainee detail → confirm → detail dismisses; roster refreshed; trainee My Trainer empty.

## Errors
- Link while already linked → **409** toast shows server `detail` (unlink first).
- Network / API failure on Leave or Remove → error toast with `detail`.

## Must not change
- Chat with that peer still openable after leave/remove.
- Boost, AI paywall, Form Studio 3D, packages, notifications — untouched.
- Unassign ≠ Remove (relationship stays on Unassign only).
