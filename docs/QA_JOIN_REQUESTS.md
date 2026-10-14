# QA — Join requests (invite → pending → accept/reject)

## Files touched
- `TacTech/Data/APIClient.swift` — join-request models + endpoints
- `TacTech/Data/AppStore.swift` — pending/list state + create/cancel/accept/reject
- `TacTech/Features/Trainee/TraineeProfileView.swift` — States A/B/C
- `TacTech/Features/Trainer/JoinRequestsView.swift` — Accept / Decline list
- `TacTech/Features/Trainer/MyTraineesView.swift` — Requests entry + badge
- `TacTech/Features/Trainer/TrainerDashboardView.swift` — pending card
- `TacTech/Features/Trainer/TrainerRootView.swift` / `TraineeRootView.swift` — deep links
- `TacTech/Data/NotificationStore.swift` — tap routing + socket refresh
- `TacTech/DesignSystem/TTAlertBanner.swift` — join_request tones
- `TacTech/Features/Authentication/AuthFlowView.swift` — TACT-MAYA wording
- Leave / Remove kept for **active** links only

## Checklist
1. Trainee **Send request** → Pending UI; trainer roster does **not** show them yet.
2. Trainer inbox gets `join_request`; **Requests** list shows row.
3. **Accept** → trainee My Trainer linked; Leave available; roster has them; plan assign works.
4. **Decline** → trainee not on roster; trainee can send again.
5. **Cancel request** → join form returns; trainer list cleared.
6. Already linked → Send request → **409** toast (`detail`).
7. Leave then re-request same code → pending → Accept works.
8. Unassign plan does **not** clear My Trainer.
9. Chat still opens after leave/remove/reject.
10. Boost / AI / Form Studio untouched.
