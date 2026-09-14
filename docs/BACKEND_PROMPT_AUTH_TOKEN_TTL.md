# Backend prompt — confirm JWT / session token TTL (iOS keeps signing out)

Copy-paste this to the backend engineer / backend AI. Goal: confirm exact access + refresh token lifetimes and refresh behavior so iOS can stop unexpected sign-outs.

---

## Context (iOS today)

TacTech Trainer iOS does **not** hardcode a logout timer.

Flow:

1. Login / signup → save `accessToken` + `refreshToken` in Keychain (`TokenStore`).
2. Every authenticated API call sends `Authorization: Bearer <accessToken>`.
3. On **401**:
   - Call `POST /auth/refresh` with `{ "refreshToken": "..." }` **once**
   - Retry the original request once
   - If refresh fails → clear tokens → user sees login again (“Session expired”)
4. On cold start: if tokens exist, call `/me` (via session restore). If that fails after refresh → clear session.

iOS also parses optional `expiresIn` on login/refresh responses but **does not currently use it** for proactive refresh.

Base URL (dev): whatever is in `APIConfig` / ngrok staging.

Relevant routes iOS already uses:

- `POST /auth/login`
- `POST /auth/signup`
- `POST /auth/refresh`
- `POST /auth/logout`
- `GET /me` (and other Bearer routes)

---

## What we need you to confirm (answer every item)

### 1) Access token lifetime

- Exact TTL? (minutes / seconds)
- Env var / config name? (e.g. `ACCESS_TOKEN_EXPIRE_MINUTES`)
- Is it a JWT with `exp` claim?
- Sample login response: do you return `expiresIn` (seconds)? Exact JSON field name?

### 2) Refresh token lifetime

- Exact TTL? (days / hours)
- Env var / config name?
- JWT or opaque token?
- Does it also have `exp`?

### 3) Refresh behavior (`POST /auth/refresh`)

Confirm the contract iOS expects:

```http
POST /auth/refresh
Content-Type: application/json

{ "refreshToken": "<refresh>" }
```

Success (200) — which shape do you return?

**A)** Token pair:

```json
{
  "accessToken": "...",
  "refreshToken": "...",
  "expiresIn": 900
}
```

**B)** Full auth payload (same as login):

```json
{
  "accessToken": "...",
  "refreshToken": "...",
  "expiresIn": 900,
  "user": { "...": "..." }
}
```

Answer:

- Which shape is canonical?
- Is `refreshToken` always returned on refresh, or only when rotated?
- If refresh token is **not** rotated, iOS keeps the old refresh — is that OK?
- If refresh token **is** rotated, old refresh must be rejected — confirm rotation policy.

### 4) When does refresh return 401?

List all cases, e.g.:

- refresh expired
- refresh revoked (logout)
- refresh reused after rotation
- user disabled / deleted
- wrong token type (access sent as refresh)

### 5) Why iOS might sign out repeatedly

Please check staging logs for our test accounts and confirm if any of these are happening:

1. Access TTL very short (e.g. 1–5 min) **and** refresh failing
2. Refresh TTL also short
3. Refresh token rotation without returning the new refresh to the client
4. `/auth/refresh` returning 401 for valid refresh
5. Multiple devices / concurrent refresh invalidating each other
6. Logout endpoint revoking refresh while app still holds it
7. Clock skew / `exp` validation too strict

### 6) Recommended production values (tell us what you use / want)

Please fill:

| Token | Current staging | Current production | Recommended |
|-------|-----------------|--------------------|-------------|
| Access | ? | ? | e.g. 15–60 min |
| Refresh | ? | ? | e.g. 7–30 days |

### 7) Optional: proactive refresh

If you return `expiresIn`, should iOS refresh access ~60s before expiry instead of waiting for 401?

- Yes / No
- Exact field name + units (seconds?)

---

## Please reply with

1. Access TTL + config name  
2. Refresh TTL + config name  
3. Refresh response JSON example (real sample, secrets redacted)  
4. Rotation policy (yes/no + rules)  
5. Top reason from staging logs if users are bouncing to login  

Once confirmed, iOS can align (proactive refresh using `expiresIn` / JWT `exp`, better error surfacing, shared refresh lock across API clients).

---

## Acceptance

Backend reply includes concrete numbers (not “about 15 min”) and a sample `/auth/refresh` 200 body.
