# Backend AI — Personal Info / Profile Setup APIs (copy-paste prompt)

You are a senior FastAPI backend engineer on **TacTech**.

## Mission

Ship **production** profile APIs that match what the **TacTech Trainer iOS** app already shows on:

**Account Settings → Personal Information**  
and the overlapping fields from **Account Settings → Profile Setup** (avatar, name, gender, location, height/weight for trainees).

Today iOS saves these **only in memory / UserDefaults**. There is **no live `/me/profile` call**. Implement the contract below so iOS can wire without inventing a second schema.

Do **not** break existing `GET /me`, login, signup, or role profiles.

---

## Auth & errors (global — mandatory)

Every route: `Authorization: Bearer <accessJWT>`.

Error body **always** (camelCase `code`, toast-safe `detail`):
```json
{ "detail": "Human-readable message for toast", "code": "VALIDATION" }
```

| HTTP | code | when |
|------|------|------|
| 401 | `UNAUTHORIZED` | missing/invalid/expired JWT |
| 403 | `FORBIDDEN` | authenticated but not allowed |
| 404 | `NOT_FOUND` | resource missing |
| 400 | `VALIDATION` | bad field / empty name / bad gender |
| 409 | `CONFLICT` | email already taken |
| 413 | `PAYLOAD_TOO_LARGE` | avatar > 5MB |
| 415 | `UNSUPPORTED_MEDIA` | avatar not jpeg/png/heic |
| 422 | `VALIDATION` | Pydantic-style field errors (still include `detail` + `code`) |
| 429 | `RATE_LIMITED` | include `Retry-After` seconds when possible |
| 500 | `INTERNAL` | unexpected |

JSON: **camelCase**. Dates: ISO-8601 UTC. Avatar URLs: **absolute** HTTPS.

---

## What iOS Personal Info actually edits

| UI field | API field | Notes |
|----------|-----------|--------|
| Full Name | `name` | required non-empty on save |
| Email | `email` | shown; allow update if unique, or reject with clear error |
| Password | via `POST /me/password` | **only if** new password non-empty; needs current OR treat empty as “no password change” |
| Weight | `weightKg` | **trainee only** (35…180); trainers omit |
| Gender | `gender` | one of: `Male`, `Female`, `Non-binary`, `Trans Female`, `Trans Male` |
| Location | `location` | string |
| Avatar catalog | `avatarAsset` | e.g. `Avatar_01_Color` (bundled Sandow catalog id) |
| Avatar custom photo | `POST /me/avatar` | multipart; returns `avatarUrl` |

**Removed from iOS:** Regular / Coach / Nutritionist chips. Do **not** require `accountType`. If column exists, ignore on PATCH or keep null.

Role (`trainer` | `trainee`) comes from JWT / user row — **never** changeable via Personal Info.

---

## 1) `GET /me/profile`

Load editable profile for the signed-in user.

```
GET /me/profile
Authorization: Bearer <accessJWT>
```

### Response **200**
```json
{
  "user": {
    "id": "u1",
    "name": "Alex Rivera",
    "email": "alex@tactech.app",
    "role": "trainee",
    "createdAt": "2026-01-01T00:00:00.000Z"
  },
  "profile": {
    "gender": "Male",
    "location": "Karachi",
    "heightCm": 178,
    "weightKg": 78.5,
    "avatarUrl": null,
    "avatarAsset": "Avatar_01_Color",
    "phone": null,
    "bio": null
  },
  "trainer": null,
  "trainee": {
    "id": "tp1",
    "userId": "u1",
    "trainerId": null,
    "goal": "",
    "heightCm": 178,
    "weightKg": 78.5,
    "dailyCalorieTarget": 2200,
    "gender": "Male",
    "location": "Karachi"
  },
  "assessmentCompleted": true,
  "onboardingCompleted": false
}
```

### Rules
- `trainer` **or** `trainee` populated based on role (other null).
- Prefer embedding `gender` / `location` / height / weight on the role profile **and** mirror under `profile` so iOS can read either.
- If only catalog avatar: `avatarAsset` set, `avatarUrl` null.
- If custom photo: `avatarUrl` absolute URL, `avatarAsset` null (or keep last catalog as fallback — document choice; iOS prefers URL when present).
- Include `assessmentCompleted` / `onboardingCompleted` (same meaning as `GET /me`).

### Errors
| Case | HTTP | code |
|------|------|------|
| No JWT | 401 | `UNAUTHORIZED` |
| User deleted | 404 | `NOT_FOUND` |

---

## 2) `PATCH /me/profile`

Partial update. **All fields optional**; only persist keys present in JSON.

```
PATCH /me/profile
Content-Type: application/json
```

### Request (iOS will send a subset)
```json
{
  "name": "Alex Rivera",
  "email": "alex@tactech.app",
  "gender": "Male",
  "location": "Karachi",
  "heightCm": 178,
  "weightKg": 78.5,
  "avatarAsset": "Avatar_01_Color"
}
```

### Field rules
| Field | Validation |
|-------|------------|
| `name` | trim; if present must be length ≥ 1 → else 400 `VALIDATION` “Enter your name.” |
| `email` | valid email; unique across users → else 409 `CONFLICT` “Email is already in use.” |
| `gender` | must be one of allowed strings above → else 400 |
| `location` | string, max 120 chars |
| `heightCm` | trainee: 140…210 int; trainer: ignore or allow null |
| `weightKg` | trainee: 35…180 number; trainer: ignore |
| `avatarAsset` | string catalog id; if set, clear custom `avatarUrl` **or** keep URL until DELETE — prefer: setting asset clears custom URL |

### Response **200**
Same shape as `GET /me/profile` (full fresh snapshot).

### Side effects
1. Update `User.name` / `User.email` when provided.
2. Update role profile (`TraineeProfile` / `TrainerProfile`) gender + location (+ height/weight for trainee).
3. If this completes “essentials” (name + gender + location; trainee also height/weight optional), set `onboardingCompleted = true` so Profile Setup gate clears server-side.
4. Do **not** change password here.

### Errors
| Case | HTTP | code | detail example |
|------|------|------|----------------|
| Bad gender | 400 | `VALIDATION` | `Gender is not valid.` |
| Empty name | 400 | `VALIDATION` | `Enter your name.` |
| Email taken | 409 | `CONFLICT` | `Email is already in use.` |
| Unauthorized | 401 | `UNAUTHORIZED` | `Please sign in again.` |

---

## 3) `POST /me/avatar` (custom photo)

```
POST /me/avatar
Content-Type: multipart/form-data
```

Form field: **`file`** (required) — `image/jpeg`, `image/png`, or `image/heic`  
Max size: **5 MB**

### Response **200**
```json
{
  "avatarUrl": "https://cdn.example.com/avatars/u1.jpg",
  "avatarAsset": null
}
```

### Behavior
1. Store on CDN/object storage; replace previous custom avatar.
2. Prefer clearing `avatarAsset` when custom upload succeeds (catalog no longer primary).
3. Return absolute URL.

### Errors
| Case | HTTP | code |
|------|------|------|
| Missing file | 400 | `VALIDATION` |
| Too large | 413 | `PAYLOAD_TOO_LARGE` |
| Bad MIME | 415 | `UNSUPPORTED_MEDIA` |

---

## 4) `DELETE /me/avatar`

```
DELETE /me/avatar
```

### Success
**204** empty body (preferred)  
or **200** `{ "cleared": true, "avatarAsset": "Avatar_01_Color" }`

Clears custom photo; fall back to last `avatarAsset` or default catalog / initials on client.

---

## 5) `POST /me/password`

Personal Info password field = **change password**, not signup.

```
POST /me/password
Content-Type: application/json
```

### Request
```json
{
  "currentPassword": "oldPass123",
  "newPassword": "newPass456"
}
```

### Rules
1. Verify `currentPassword` against hash → else **400** `VALIDATION` “Current password is incorrect.”
2. `newPassword` length ≥ 6 → else 400 “Password must be at least 6 characters.”
3. Optional: reject if new == current.
4. Hash with same algorithm as signup/login.
5. Do **not** rotate refresh tokens unless you already do on password change (if you rotate, document it).

### Success
**204** No Content

### Errors
| Case | HTTP | code |
|------|------|------|
| Wrong current | 400 | `VALIDATION` |
| Weak new | 400 | `VALIDATION` |
| No JWT | 401 | `UNAUTHORIZED` |

---

## 6) Keep `GET /me` consistent

After profile PATCH / avatar, a subsequent `GET /me` must reflect:
- updated `user.name` / `user.email`
- updated trainee/trainer height, weight, gender, location (if those columns exist)
- `onboardingCompleted` when essentials saved
- Prefer exposing `avatarUrl` on user or nested profile if iOS later reads `/me` only

Do not remove `assessmentCompleted` / `onboardingCompleted`.

---

## Idempotency & clarity

- PATCH is idempotent: same body twice → same 200 snapshot.
- Never return HTML error pages.
- Never return snake_case keys.
- Never nest errors under opaque shapes without `detail` + `code`.

Optional richer validation (still keep top-level `detail`/`code`):
```json
{
  "detail": "Fix the highlighted fields.",
  "code": "VALIDATION",
  "fields": {
    "email": "Email is already in use.",
    "weightKg": "Weight must be between 35 and 180."
  }
}
```

---

## Out of scope

- Changing `role` trainer ↔ trainee
- `accountType` Regular/Coach/Nutritionist (removed from iOS)
- OTP / 2FA (Security settings later)
- Deleting the account (`DELETE /me` separate)

---

## Acceptance checklist

- [ ] `GET /me/profile` returns user + profile + role profile + gate flags
- [ ] `PATCH /me/profile` updates name/email/gender/location/(trainee metrics)/avatarAsset
- [ ] Email conflict → **409 CONFLICT** with clear `detail`
- [ ] `POST /me/avatar` stores file, returns absolute `avatarUrl`
- [ ] `DELETE /me/avatar` clears custom photo
- [ ] `POST /me/password` checks current password; **204** on success
- [ ] All errors use `{ detail, code }`
- [ ] `GET /me` stays in sync after patch
- [ ] Saving essentials can set `onboardingCompleted: true`

---

## Suggested implement order

1. `GET /me/profile` + `PATCH /me/profile`  
2. `POST /me/avatar` + `DELETE /me/avatar`  
3. `POST /me/password`  
4. Align `GET /me` + `onboardingCompleted`  

When done, reply with:
1. Confirmed routes live  
2. One sample `GET /me/profile` JSON  
3. One sample `PATCH` request/response  
4. One sample error JSON for email conflict and wrong password  

iOS will then replace UserDefaults saves with these endpoints using the same field names.
