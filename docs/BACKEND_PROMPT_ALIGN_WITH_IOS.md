# Backend AI Prompt — Align TacTech API with iOS App

**Copy-paste this entire document to the Backend AI.**

---

You are a senior FastAPI engineer on **TacTech** (trainer/trainee gym app).

## Mission

Make the **backend the single source of truth** for everything the **TacTech Trainer iOS** app shows.  
iOS currently still uses **UserDefaults / mocks** for several screens even though many routes already exist in OpenAPI. Your job:

1. **Do not break** endpoints iOS already calls in production.
2. **Harden / complete** the routes iOS is about to wire (profile, templates, plans edit/delete, support, content, prefs, feedback).
3. **Add missing fields** iOS needs on `/me` so assessment/onboarding gates work without local flags.
4. Keep **Socket.IO + push** working for chat messages and video-call rings.

**iOS app:** TacTech Trainer iOS (`com.tactech.trainer.shahryar`)  
**Dev base URL:** `https://sheryl-biocellate-sympathizingly.ngrok-free.dev`  
**Auth:** `Authorization: Bearer <accessToken>`  
**JSON:** camelCase  
**Dates:** ISO-8601; day queries `?on=yyyy-MM-dd`

---

## 0. Product model (must match iOS)

- Roles: `trainer` | `trainee`
- Every user has `User.id` (canonical for chat `peerUserId`)
- Trainer has `TrainerProfile` + `inviteCode`
- Trainee has `TraineeProfile` + optional `trainerId` + `dailyCalorieTarget`
- Human chat is `/chat/*` (NOT `/coach/*`)
- AI coach is `/coach/*`
- Notifications inbox is `/me/notifications*`
- Push tokens are `/me/push-tokens` with `platform: "ios"`

---

## 1. DO NOT BREAK — iOS already live on these

Keep paths, auth, and camelCase bodies stable (or add aliases).

### Auth / session
- `POST /auth/signup`, `/auth/login`, `/auth/forgot-password`, `/auth/logout`, `/auth/refresh`
- `GET /me` (must keep working; see §2 for **new required fields**)

### Trainer domain
- `GET/POST /trainer/plans`
- `POST /trainer/assignments`
- `GET /trainer/trainees`, `GET /trainer/trainees/{id}`
- `GET /trainer/trainees/{id}/meals?on=`, `/macros?on=`, `/logs`, `/form-reports`, `/feedback`
- `POST /trainer/feedback`
- `POST /trainer/assessment`

### Trainee domain
- `POST /trainee/assessment`
- `POST /trainee/link`, `GET /trainee/trainer`
- `GET /trainee/assigned-plan`
- `POST /trainee/logs`
- `GET/POST /trainee/meals`, `GET /trainee/macros?on=`
- `POST /trainee/form-reports`
- `GET /food/lookup?q=` (and/or `/trainee/food/lookup`)
- `GET /exercises`

### AI Coach
- `/coach/status`, conversations CRUD, `/coach/chat` (SSE), `/coach/chat/image`, `/coach/voice/turn`, `/coach/memory/sync`, `/coach/rtc/*`

### Human chat + calls
- `/chat/threads`, messages (JSON + multipart), `/read`
- Socket.IO `/socket.io/` with auth `{ token }` on `/` and `/chat`
- Events: `chat.message`, `chat.thread.updated`, `chat.read`, `chat.typing`, `chat.call.incoming`, `chat.call.ended`
- `POST /chat/rtc/sessions`, `GET /chat/rtc/incoming`, signaling WS
- Personal room `user:{userId}` so call ring works **outside** chat UI

### Notifications (already wired on iOS)
- `GET /me/notifications`, `POST /me/notifications/read`, `GET /me/notifications/unread-count`
- `GET/PUT /me/preferences/notifications` (include `push`, `chatMessages`, `chatCalls`, …)
- `POST/GET/DELETE /me/push-tokens`
- Socket event `notification.created` → AppNotification shape
- Push data: `{ type:"chat", threadId, messageId }` and `{ type:"chat_call", threadId, sessionId, fromUserId, fromName, signalingPath? }`

---

## 2. CRITICAL — extend `GET /me` for iOS gates

iOS uses local UserDefaults today because `/me` does not clearly return assessment/onboarding completion.

**Required on `GET /me` (and login/signup auth payload if convenient):**

```json
{
  "user": { "id": "...", "name": "...", "email": "...", "role": "trainer|trainee", "createdAt": "..." },
  "trainer": { /* or null */ },
  "trainee": { /* or null */ },
  "assessmentCompleted": true,
  "onboardingCompleted": true
}
```

Rules:
- `assessmentCompleted` = true after successful `POST /trainee/assessment` or `POST /trainer/assessment` for that user.
- `onboardingCompleted` = true after profile essentials saved (name + role profile fields; avatar optional).
- Returning users on a **new device** must skip assessment when `assessmentCompleted` is true (no UserDefaults).
- Keep backward compatible: if old clients ignore new fields, fine.

Also ensure assessment POST responses persist server-side and flip these flags.

---

## 3. Confirm & harden — routes iOS will wire next (many already in OpenAPI)

Treat these as **contract tests**. Return 401 without token. camelCase only.

### 3.1 Profile / avatar / password (Settings → Personal Information)

| Method | Path | Notes |
|--------|------|--------|
| GET | `/me/profile` | `FullProfileOut`: user + editable profile + trainer/trainee |
| PATCH | `/me/profile` | `UpdateProfileRequest`: name, email, gender, location, heightCm, weightKg, accountType, avatarAsset, phone, bio |
| PATCH | `/me/trainee` | Include `dailyCalorieTarget`, goal, heightCm, weightKg (nutrition screen) |
| PATCH | `/me/trainer` | specialty, yearsExperience, bio |
| POST | `/me/avatar` | multipart image → returns `avatarUrl` |
| DELETE | `/me/avatar` | clear avatar |
| POST | `/me/password` | `{ "currentPassword", "newPassword" }` |

**Done when:** iOS can drop UserDefaults for name/location/weight/avatar/password and calorie target survives reinstall.

### 3.2 Preferences

| Method | Path |
|--------|------|
| GET/PUT | `/me/preferences/notifications` |
| GET/PUT | `/me/preferences/language` → `{ languageCode, languageLabel, bilingual }` |
| GET/PUT | `/me/preferences/security` → `{ twoFactor, googleAuth, faceId, biometric }` |

Language codes used by iOS UI: `jp`, `us`, `uk`, `it`, `ar`, `cn`, `ru`.

### 3.3 App feedback

| Method | Path |
|--------|------|
| POST | `/me/app-feedback` |

Body:
```json
{
  "areas": ["Performance", "Bug", "Crashes", "Navigation"],
  "message": "optional",
  "appVersion": "1.0",
  "platform": "ios"
}
```
Response 201: `{ "id", "areas", "createdAt" }`

### 3.4 Exercise templates (trainer) — replace iOS UserDefaults

| Method | Path |
|--------|------|
| GET | `/trainer/exercise-templates` |
| POST | `/trainer/exercise-templates` |
| PATCH | `/trainer/exercise-templates/{id}` |
| DELETE | `/trainer/exercise-templates/{id}` |

Shape matches `ExerciseTemplateIn` / `ExerciseTemplateOut` (sets, reps, restSeconds, setRows, …).  
Scoped to authenticated trainer only.

### 3.5 Plans edit / delete / unassign

| Method | Path |
|--------|------|
| GET | `/trainer/plans/{id}` |
| PATCH | `/trainer/plans/{id}` | partial PlanBody |
| DELETE | `/trainer/plans/{id}` | soft-delete OK; clear active assignments |
| DELETE | `/trainer/assignments/{assignmentId}` | unassign |
| DELETE | `/trainer/assignments?planId=&traineeId=` | alternate |

iOS today only creates + assigns. These unlock plan management UI.

### 3.6 Support chat (Help Center) — kill iOS mock replies

| Method | Path |
|--------|------|
| GET | `/support/conversations` |
| POST | `/support/conversations` |
| GET | `/support/conversations/{id}/messages` |
| POST | `/support/conversations/{id}/messages` | `{ "text": "..." }` |

`SupportMessageOut.sender` = `"user"` | `"support"` (or `"agent"`).  
Optional: Socket/push later; REST poll is enough for v1.

### 3.7 Static content

| Method | Path |
|--------|------|
| GET | `/content/faq` | `[FaqItemOut]` |
| GET | `/content/about` | `AboutOut` |

---

## 4. Chat / calls / push (keep rock-solid)

### Incoming call (already required by iOS)
On `POST /chat/rtc/sessions`:
1. Return session `{ id, threadId, signalingPath, iceServers }`
2. Emit `chat.call.incoming` to callee personal room **immediately**
3. If callee offline Socket → high-priority push `type=chat_call`
4. On hangup/decline → `chat.call.ended` + clear from `GET /chat/rtc/incoming`

### Messages
- Offline peer → push `type=chat` + inbox row via `notification.created`
- Online peer → Socket `chat.message` (skip remote push if connected; still create inbox notification if that’s your model)

### Respect prefs
If `push`, `chatMessages`, or `chatCalls` is false → do not send that remote push type.

---

## 5. Nutrition / meals (small gaps)

Already have create/list/macros/lookup. Please also support when ready:

- Meal `PATCH` / `DELETE` by id (trainee owns meal)
- Persist `dailyCalorieTarget` via `PATCH /me/trainee` (required for iOS to stop memory-only target)

Optional later: server food catalog list; iOS currently falls back to bundled SeedData when lookup empty.

---

## 6. Out of scope for this prompt (do not block on these)

- Full WebRTC media SFU (iOS still needs peer connection client work)
- CallKit / VoIP push certs
- Android FCM (keep `platform` field ready)
- Replacing on-device Vision pose / food recognition (iOS keeps local ML; only stores results)

---

## 7. Acceptance checklist (Backend AI must verify)

- [ ] Fresh install + login: `GET /me` returns `assessmentCompleted` correctly (no UserDefaults)
- [ ] After assessment POST, flag flips; new device skips assessment
- [ ] `GET/PATCH /me/profile` + avatar upload round-trip
- [ ] `POST /me/password` works with current password check
- [ ] Language + security prefs GET/PUT persist
- [ ] `POST /me/app-feedback` stores row
- [ ] Exercise templates CRUD scoped to trainer
- [ ] Plan PATCH/DELETE + assignment DELETE work; trainee `assigned-plan` updates
- [ ] Support conversation create + message list/send (no fake client)
- [ ] FAQ + About return JSON (not empty)
- [ ] Call create → callee gets Socket and/or push + `/chat/rtc/incoming`
- [ ] Chat message → offline push `type=chat` + `notification.created`
- [ ] OpenAPI at `/openapi.json` matches reality
- [ ] Existing chat/coach/auth/trainer trainee paths still green

---

## 8. Reply format

When done, reply with:

1. List of endpoints **confirmed / fixed / newly added**
2. Exact sample JSON for `GET /me` (with assessment flags)
3. Sample for `GET /me/profile` and `POST /support/conversations/{id}/messages`
4. Any breaking changes (ideally none)
5. Notes for iOS team: which UserDefaults screens can now be deleted

**Priority order if time-boxed:**  
(1) `/me` assessment flags → (2) profile/avatar/password → (3) support chat → (4) templates + plan delete → (5) content + prefs + feedback → (6) call/push hardening.
