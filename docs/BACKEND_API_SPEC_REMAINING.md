# TecTach Trainer iOS — Backend API Spec (Remaining + Alignment)

**Purpose:** Give this document to the Backend AI so remaining iOS features stop using UserDefaults-only storage and sync to the server.

**App:** TecTach Trainer iOS  
**Current base URL (dev):** `https://sheryl-biocellate-sympathizingly.ngrok-free.dev`  
**Auth:** Bearer access token (`Authorization: Bearer <accessToken>`)  
**Refresh:** `POST /auth/refresh` with `{ "refreshToken": "..." }`  
**JSON:** camelCase keys preferred (iOS already uses camelCase Codable)  
**Dates:** ISO-8601; day queries use `yyyy-MM-dd` (UTC) as `?on=`

---

## 0. Conventions (must follow)

### Headers
```
Authorization: Bearer <accessToken>
Content-Type: application/json
Accept: application/json
ngrok-skip-browser-warning: true   # only needed on ngrok
```

### Standard error shape
```json
{
  "detail": "Human readable message",
  "code": "OPTIONAL_MACHINE_CODE",
  "fields": { "email": "already registered" }
}
```

### HTTP status usage
| Code | Meaning |
|------|---------|
| 200 | OK with body |
| 201 | Created |
| 204 | OK empty body |
| 400 | Validation |
| 401 | Unauthorized / token expired |
| 403 | Forbidden for this role |
| 404 | Not found |
| 409 | Conflict |
| 413 | File too large |
| 422 | Unprocessable |

### Roles
- `trainer`
- `trainee`

---

## 1. Already implemented (DO NOT break — iOS already uses these)

Keep these exactly (or provide backward-compatible aliases).

| Method | Path | Used by |
|--------|------|---------|
| POST | `/auth/login` | Login |
| POST | `/auth/signup` | Signup |
| POST | `/auth/forgot-password` | Reset |
| POST | `/auth/logout` | Logout |
| POST | `/auth/refresh` | Token refresh |
| GET | `/me` | Session restore |
| GET | `/exercises` | Exercise catalog |
| GET | `/trainer/plans` | Plan list |
| POST | `/trainer/plans` | Create plan |
| POST | `/trainer/assignments` | Assign plan |
| GET | `/trainer/trainees` | My trainees |
| GET | `/trainer/trainees/{id}` | Trainee detail |
| GET | `/trainer/trainees/{id}/meals?on=` | Trainer view meals |
| GET | `/trainer/trainees/{id}/macros?on=` | Trainer macros |
| GET | `/trainer/trainees/{id}/logs` | Trainer view logs |
| GET | `/trainer/trainees/{id}/form-reports` | Form reports |
| GET | `/trainer/trainees/{id}/feedback` | Feedback list |
| POST | `/trainer/feedback` | Send feedback |
| POST | `/trainer/assessment` | Trainer assessment |
| POST | `/trainee/assessment` | Trainee assessment |
| POST | `/trainee/link` | Link via invite |
| GET | `/trainee/trainer` | Linked trainer |
| GET | `/trainee/assigned-plan` | Assigned plan |
| GET/POST | `/trainee/logs` | Workout logs |
| GET/POST | `/trainee/meals` | Meals |
| GET | `/trainee/macros?on=` | Macros |
| GET | `/trainee/feedback` | Feedback inbox |
| GET/POST | `/trainee/form-reports` | Form AI reports |
| GET | `/food/lookup?q=` | Food search |

### Existing create-plan body (already sent by iOS)
```json
{
  "title": "4-day strength",
  "focus": "Hypertrophy",
  "durationMinutes": 55,
  "level": "Intermediate",
  "daysPerWeek": 4,
  "notes": "optional",
  "exercises": [ /* flat list */ ],
  "days": [
    {
      "weekday": "monday",
      "startTime": "07:30",
      "title": "Lower",
      "focus": "Squat",
      "durationMinutes": 55,
      "location": "Gym",
      "warmup": "...",
      "cooldown": "...",
      "coachNotes": "...",
      "exercises": [
        {
          "exerciseId": "uuid",
          "sets": 4,
          "reps": 8,
          "restSeconds": 90,
          "recommendedWeightKg": 40,
          "tempo": "3-1-1-0",
          "rpe": 7.5,
          "notes": "cues",
          "side": "Both",
          "prescribedSets": [
            { "setNumber": 1, "reps": 8, "weightKg": 40, "rpe": 7.5 }
          ]
        }
      ]
    }
  ]
}
```

---

## 2. NEW APIs required (priority order)

Implement in this order so iOS can migrate off UserDefaults.

---

### P0 — Profile & avatar (Personal Information screen)

#### `GET /me/profile`
Returns full editable profile for current user.

**Response 200**
```json
{
  "user": {
    "id": "u1",
    "name": "Alex Coach",
    "email": "alex@tactech.app",
    "role": "trainer",
    "createdAt": "2026-01-01T00:00:00Z"
  },
  "profile": {
    "gender": "Male",
    "location": "Karachi",
    "heightCm": 178,
    "weightKg": 78.5,
    "accountType": "Regular",
    "avatarUrl": "https://cdn.../avatars/u1.jpg",
    "avatarAsset": "Avatar_01_Color",
    "phone": "+92...",
    "bio": "optional"
  },
  "trainer": { "...existing TrainerProfile or null" },
  "trainee": { "...existing TraineeProfile or null" }
}
```

#### `PATCH /me/profile`
Update profile fields. All fields optional; send only changed ones.

**Request**
```json
{
  "name": "Alex Coach",
  "email": "alex@tactech.app",
  "gender": "Male",
  "location": "Karachi",
  "heightCm": 178,
  "weightKg": 78.5,
  "accountType": "Regular",
  "avatarAsset": "Avatar_01_Color",
  "phone": "+92...",
  "bio": "Strength coach"
}
```

**Response 200:** same shape as `GET /me/profile`

**Rules**
- If `email` changes → must be unique; may require re-verify later (optional).
- `avatarAsset` = bundled catalog id (`Avatar_01_Color` …). Mutually exclusive with custom upload preferred: if `avatarUrl` exists and no asset, show photo.

#### `POST /me/avatar` (multipart)
Upload custom profile photo from gallery/camera.

**Request:** `multipart/form-data`
- field `file`: image/jpeg or image/png (max 5MB)
- square crop preferred on client already

**Response 200**
```json
{
  "avatarUrl": "https://cdn.../avatars/u1.jpg",
  "avatarAsset": null
}
```

#### `DELETE /me/avatar`
Clear custom photo; fall back to catalog asset or initials.

#### `POST /me/password`
Change password (Personal Info password field).

**Request**
```json
{
  "currentPassword": "old",
  "newPassword": "newpass123"
}
```
**Response 204**

---

### P0 — Exercise templates (Create Plan templates)

Trainer saves reusable prescriptions per exercise.

#### `GET /trainer/exercise-templates?exerciseId={optional}`
**Response 200**
```json
[
  {
    "id": "t1",
    "exerciseId": "ex-back-squat",
    "trainerId": "tr1",
    "name": "Strength 5×5",
    "sets": 5,
    "reps": 5,
    "restSeconds": 180,
    "weightKg": 80,
    "tempo": "3-1-1-0",
    "rpe": 8,
    "howTo": "Brace hard…",
    "side": "Both",
    "setRows": [
      { "id": "s1", "setNumber": 1, "reps": 5, "weightKg": 80 }
    ],
    "updatedAt": "2026-09-01T12:00:00Z"
  }
]
```

#### `POST /trainer/exercise-templates`
**Request:** same object without requiring `id` / `trainerId` (server sets them)
**Response 201:** full template

#### `PATCH /trainer/exercise-templates/{id}`
Partial update of name / sets / rows / etc.
**Response 200:** full template

#### `DELETE /trainer/exercise-templates/{id}`
**Response 204**

**Auth:** trainer only; ownership check on trainerId.

---

### P0 — Plan update / delete (missing today)

#### `GET /trainer/plans/{id}`
Full plan detail.

#### `PATCH /trainer/plans/{id}`
Same body shape as create (`PlanBody`), partial allowed.
**Response 200:** updated plan

#### `DELETE /trainer/plans/{id}`
Also unassign or keep historical assignments (document choice). Prefer: soft-delete plan, clear active assignments.
**Response 204**

#### `DELETE /trainer/assignments/{assignmentId}` OR  
#### `DELETE /trainer/assignments?planId=&traineeId=`
Unassign plan from trainee.
**Response 204**

---

### P1 — Notification preferences

#### `GET /me/preferences/notifications`
**Response 200**
```json
{
  "push": true,
  "aiCoach": false,
  "metrics": true,
  "vibrations": false,
  "sound": true,
  "appUpdate": true,
  "resources": false,
  "offersDevice": false
}
```

#### `PUT /me/preferences/notifications`
Replace full object (same shape).
**Response 200:** saved object

---

### P1 — Security preferences

#### `GET /me/preferences/security`
```json
{
  "twoFactor": false,
  "googleAuth": false,
  "faceId": true,
  "biometric": true
}
```

#### `PUT /me/preferences/security`
Same shape.
**Notes for backend AI:**
- Storing flags is enough for v1.
- Real 2FA/TOTP can be phase 2 (`POST /me/security/2fa/enable` …).
- Face ID / biometric are device-side; server only stores user preference “allow biometric unlock”.

---

### P1 — Language preferences

#### `GET /me/preferences/language`
```json
{
  "languageCode": "jp",
  "languageLabel": "Japanese (JP)",
  "bilingual": true
}
```

#### `PUT /me/preferences/language`
Same shape.
Supported codes used by iOS UI: `jp`, `us`, `uk`, `it`, `ar`, `cn`, `ru`

---

### P1 — In-app feedback (Submit Feedback screen)

#### `POST /me/app-feedback`
**Request**
```json
{
  "areas": ["Performance", "Bug", "Crashes", "Navigation"],
  "message": "optional free text",
  "appVersion": "1.0",
  "platform": "ios"
}
```
**Response 201**
```json
{
  "id": "fb1",
  "areas": ["Bug"],
  "createdAt": "2026-09-05T00:00:00Z"
}
```

#### `GET /me/app-feedback` (optional admin later)
List current user’s submissions.

---

### P1 — Live Chat / Help Center

#### `GET /support/conversations`
Current user’s open conversation (create if none).
```json
{
  "id": "c1",
  "status": "open",
  "updatedAt": "..."
}
```

#### `GET /support/conversations/{id}/messages?after={optionalMessageId}`
```json
[
  {
    "id": "m1",
    "conversationId": "c1",
    "sender": "user",
    "text": "Profile picture bug",
    "attachmentUrl": null,
    "createdAt": "2026-09-05T10:00:00Z"
  },
  {
    "id": "m2",
    "sender": "support",
    "text": "Thanks — we’ll check.",
    "attachmentUrl": null,
    "createdAt": "2026-09-05T10:01:00Z"
  }
]
```
`sender`: `user` | `support` | `system`

#### `POST /support/conversations/{id}/messages`
**JSON**
```json
{ "text": "Hello" }
```
**OR multipart** for photo:
- `text` (optional)
- `file` (optional image)

**Response 201:** message object

#### `POST /support/conversations` 
Start new chat (Help Center → Start Live Chat).
**Response 201:** conversation

---

### P2 — Meal / log edits

#### `PATCH /trainee/meals/{id}`
#### `DELETE /trainee/meals/{id}`
#### `PATCH /trainee/logs/{id}`
#### `DELETE /trainee/logs/{id}`

Keep body shapes consistent with create models already used.

---

### P2 — Account lifecycle

#### `DELETE /me`
Close account (irreversible).
**Request**
```json
{ "password": "confirm-password" }
```
**Response 204**

#### `POST /me/export` (optional)
Data export request.

---

### P2 — Search recents (optional sync)

Not required for MVP. If wanted:

#### `GET /me/search-recents?scope=plans|trainees|foods`
#### `PUT /me/search-recents`
```json
{
  "scope": "plans",
  "items": ["4-day strength", "hypertrophy"]
}
```

---

### P2 — Static content (About Us / FAQ)

#### `GET /content/about`
```json
{
  "brandName": "TecTach",
  "tagline": "AI Fitness & Training Solution",
  "addressLines": ["578 Boolean Ave", "Turing St", "New York, NY"],
  "phones": ["+123-456-789", "+44-887-449"],
  "social": {
    "facebook": "https://...",
    "instagram": "https://...",
    "linkedin": "https://...",
    "youtube": "https://..."
  }
}
```

#### `GET /content/faq`
```json
[
  {
    "id": "what",
    "question": "What is TecTach?",
    "answer": "..."
  }
]
```

---

## 3. Auth rules matrix

| Endpoint group | trainer | trainee |
|----------------|---------|---------|
| `/me/*` | ✅ | ✅ |
| `/trainer/exercise-templates` | ✅ | ❌ 403 |
| `/trainer/plans` write | ✅ | ❌ |
| `/support/*` | ✅ | ✅ |
| `/me/app-feedback` | ✅ | ✅ |
| `/content/*` | ✅ public or auth | ✅ |

---

## 4. Migration notes for Backend AI

1. **Do not remove** existing routes iOS already calls.
2. Prefer **PATCH** for updates (iOS client already has `.patch` method stub).
3. Return **full objects** after create/update so iOS can upsert memory without extra GET.
4. For avatar: store file in S3/GCS/local uploads; return absolute HTTPS URL.
5. Multi-tenant: every resource scoped by `userId` / `trainerId` from JWT — never trust body IDs for ownership.
6. Idempotency: create plan / templates should accept client-generated UUIDs if provided (`id` field).
7. Assessments already POST — ensure 200 (not only 404 fallback) so iOS can drop local-only path later.

---

## 5. Acceptance checklist (backend done when)

- [ ] Profile GET/PATCH works; iOS Personal Info Save can call API
- [ ] Avatar multipart upload returns `avatarUrl`
- [ ] Exercise templates CRUD round-trips for a trainer
- [ ] Plan PATCH + DELETE work
- [ ] Notification / security / language preferences persist across reinstall (same user)
- [ ] App feedback stored server-side
- [ ] Live chat messages persist; second device sees history
- [ ] Existing login → create plan → assign → meal/log flows still green

---

## 6. Suggested implementation order for Backend AI

1. `PATCH /me/profile` + `POST /me/avatar`  
2. Exercise templates CRUD  
3. Plan PATCH/DELETE + unassign  
4. Preferences (notifications, security, language)  
5. App feedback  
6. Support chat  
7. Meal/log edit/delete + account delete  
8. Content endpoints  

---

## 7. Example OpenAPI-ish summary (new only)

```
PATCH  /me/profile
POST   /me/avatar
DELETE /me/avatar
POST   /me/password
GET    /me/profile

GET    /trainer/exercise-templates
POST   /trainer/exercise-templates
PATCH  /trainer/exercise-templates/{id}
DELETE /trainer/exercise-templates/{id}

GET    /trainer/plans/{id}
PATCH  /trainer/plans/{id}
DELETE /trainer/plans/{id}
DELETE /trainer/assignments

GET    /me/preferences/notifications
PUT    /me/preferences/notifications
GET    /me/preferences/security
PUT    /me/preferences/security
GET    /me/preferences/language
PUT    /me/preferences/language

POST   /me/app-feedback

POST   /support/conversations
GET    /support/conversations
GET    /support/conversations/{id}/messages
POST   /support/conversations/{id}/messages

PATCH  /trainee/meals/{id}
DELETE /trainee/meals/{id}
DELETE /me

GET    /content/about
GET    /content/faq
```

---

**End of spec.**  
After backend ships these, iOS will replace UserDefaults/@AppStorage writes with `APIClient` calls and keep local cache only as offline fallback.
