# Backend AI — Live Notification Preferences + Push (copy-paste prompt)

You are a senior FastAPI backend engineer on **TacTech**.

## Mission

Make **Account Settings → Notifications** fully live end-to-end:

1. Persist preference toggles (iOS already calls these APIs).
2. Register APNs device tokens.
3. **Enforce** prefs when sending remote push / creating inbox rows.
4. Keep inbox + Socket `notification.created` working.

iOS **already ships** UI + client for prefs. Do **not** invent a parallel schema. Match camelCase exactly.

**Auth:** `Authorization: Bearer <accessJWT>`  
**JSON:** camelCase  
**Errors always:**
```json
{ "detail": "Human-readable toast text", "code": "VALIDATION_ERROR" }
```

| HTTP | code | when |
|------|------|------|
| 401 | `UNAUTHORIZED` | bad/missing JWT |
| 400 | `VALIDATION` / `VALIDATION_ERROR` | bad body |
| 404 | `NOT_FOUND` | missing resource |
| 500 | `INTERNAL` | unexpected |

---

## 1) Preference model (exact iOS fields)

Persist **per user** (defaults below if row missing):

```json
{
  "push": true,
  "aiCoach": false,
  "metrics": true,
  "vibrations": false,
  "sound": true,
  "appUpdate": true,
  "resources": false,
  "offersDevice": false,
  "chatMessages": true,
  "chatCalls": true
}
```

| Field | Meaning | Server must enforce |
|-------|---------|---------------------|
| `push` | Master remote-push switch | If `false` → **no APNs** of any type (inbox Socket/REST may still exist) |
| `chatMessages` | Human chat message alerts | If `false` → no push `type=chat` |
| `chatCalls` | Incoming video-call ring push | If `false` → no push `type=chat_call` |
| `aiCoach` | AI Coach alerts | If `false` → no AI coach push / optional no inbox type `ai_coach` |
| `metrics` | Progress / metrics / workout-style alerts | If `false` → no metrics/workout reminder push |
| `appUpdate` | App update notices | If `false` → no `app_update` push |
| `resources` | New resources content | If `false` → no `resources` push |
| `offersDevice` | Offers / promos | If `false` → no `offers` push |
| `vibrations` | Client UX preference | Store only (iOS applies locally) |
| `sound` | Client UX preference | Store only (iOS applies locally) |

Do **not** require `accountType` or role change.  
Do **not** drop `chatMessages` / `chatCalls` — iOS depends on them.

---

## 2) REST — preferences

### `GET /me/preferences/notifications`
**200** — full object (always all keys; fill defaults for missing columns).

### `PUT /me/preferences/notifications`
Replace / upsert full object (same shape).  
Partial also OK if you merge missing keys with defaults — but **response must return full object**.

**200** — saved object.

**Rules**
- Resolve user from JWT only.
- All values boolean.
- Idempotent.

---

## 3) REST — push tokens (already expected by iOS)

### `POST /me/push-tokens`
```json
{
  "token": "<apns device token hex or string>",
  "platform": "ios",
  "deviceName": "iPhone",
  "appVersion": "1.0.0"
}
```
**200**
```json
{
  "id": "pt1",
  "platform": "ios",
  "deviceName": "iPhone",
  "appVersion": "1.0.0",
  "createdAt": "2026-09-11T12:00:00.000Z",
  "updatedAt": "2026-09-11T12:00:00.000Z"
}
```
Upsert by `(userId, token)`.

### `DELETE /me/push-tokens`
```json
{ "token": "<same token>" }
```
**204** (or 200 `{ "deleted": true }`).

---

## 4) REST — inbox (keep / harden)

| Method | Path | Notes |
|--------|------|--------|
| GET | `/me/notifications?limit=&cursor=` | Newest first; `{ items, nextCursor?, unreadCount? }` |
| GET | `/me/notifications/unread-count` | `{ "unreadCount": N }` |
| POST | `/me/notifications/read` | `{ "notificationId": "…" }` or omit / null = mark all |

### Inbox item shape (Socket + REST)
```json
{
  "id": "n1",
  "type": "chat",
  "title": "Alex",
  "body": "See you at 6",
  "data": {
    "type": "chat",
    "threadId": "t1",
    "messageId": "m1"
  },
  "readAt": null,
  "createdAt": "2026-09-11T12:00:00.000Z"
}
```

`data` values should be strings (iOS flattens scalars).

### Socket
Emit to user’s personal room `user:{userId}`:

```text
Event: notification.created
Payload: <same AppNotification object>
```

---

## 5) Push send rules (this makes prefs “live”)

Before every APNs send for user U:

```
prefs = loadNotificationPreferences(U)
if prefs.push == false: SKIP_PUSH
else if pushType == "chat" and prefs.chatMessages == false: SKIP_PUSH
else if pushType == "chat_call" and prefs.chatCalls == false: SKIP_PUSH
else if pushType == "ai_coach" and prefs.aiCoach == false: SKIP_PUSH
else if pushType in ("metrics","workout") and prefs.metrics == false: SKIP_PUSH
else if pushType == "app_update" and prefs.appUpdate == false: SKIP_PUSH
else if pushType == "resources" and prefs.resources == false: SKIP_PUSH
else if pushType == "offers" and prefs.offersDevice == false: SKIP_PUSH
else: SEND to all active ios tokens for U
```

Still create **inbox row** + `notification.created` when product requires history (recommended for chat), even if push skipped — **except** if product policy says silent; default: **inbox yes, push gated**.

### Required push payloads iOS already handles

**Chat message (peer offline / background):**
```json
{
  "title": "<sender name>",
  "body": "<preview>",
  "data": {
    "type": "chat",
    "threadId": "t1",
    "messageId": "m1"
  }
}
```

**Incoming video call:**
```json
{
  "title": "<caller name>",
  "body": "Incoming video call",
  "data": {
    "type": "chat_call",
    "threadId": "t1",
    "sessionId": "rtc_…",
    "fromUserId": "…",
    "fromName": "…",
    "signalingPath": "wss://…/signal"
  }
}
```
Use **high priority** for `chat_call`.

**Optional types** (when you have product events):
- `ai_coach` — coach message / tip  
- `metrics` / `workout` — progress / workout reminder  
- `app_update`  
- `resources`  
- `offers`

---

## 6) When to fire (product wiring)

| Event | Inbox | Socket | Push (if prefs allow) |
|-------|-------|--------|------------------------|
| Human chat message to peer | yes | `notification.created` + `chat.message` | `type=chat` if peer not in active socket (or always if you prefer) |
| Incoming RTC session create | optional | `chat.call.incoming` | `type=chat_call` if peer offline/background |
| AI coach notable event | optional | optional | `ai_coach` |
| Workout / metrics reminder (cron or trainer action) | optional | optional | `metrics` |
| App update broadcast | optional | optional | `app_update` |
| New resource published | optional | optional | `resources` |
| Offer / promo | optional | optional | `offers` |

---

## 7) Profile Setup overlap (optional same sprint)

iOS Profile Setup still stores locally:
- Workout reminders → map to **`metrics`** (or add `workouts` later)
- Messages & feedback → map to **`chatMessages`**
- Progress updates → map to **`metrics`**

Preferred: when Profile Setup saves, iOS will later PUT preferences. For now backend only needs prefs + enforcement above.

---

## 8) Acceptance checklist

- [ ] `GET /me/preferences/notifications` returns all 10 booleans  
- [ ] `PUT` persists; re-GET matches  
- [ ] `POST/DELETE /me/push-tokens` upsert / remove  
- [ ] `push=false` → **zero** APNs for that user  
- [ ] `chatMessages=false` → no `type=chat` push; chat Socket still works  
- [ ] `chatCalls=false` → no `type=chat_call` push; Socket `chat.call.incoming` still OK when online  
- [ ] Chat offline path: inbox row + `notification.created` + gated push  
- [ ] Call offline path: gated high-priority `chat_call` push  
- [ ] Errors use `{ detail, code }`  

---

## 9) Implement order

1. Ensure prefs table + GET/PUT (include `chatMessages`, `chatCalls`)  
2. Token register/delete stable  
3. Central `shouldSendPush(userId, type)` helper used by chat + RTC + any jobs  
4. Verify chat + call push honor prefs  
5. Wire optional types (aiCoach, metrics, appUpdate, resources, offers) when those product events exist  

---

## Reply when done

1. Confirm routes live  
2. Sample GET prefs JSON  
3. Confirm push gate table (which pref blocks which `type`)  
4. One test: user sets `chatMessages=false`, peer sends message → no APNs, inbox still created (or document if inbox also suppressed)

iOS Notification Settings is already wired to these endpoints — backend enforcement is what makes toggles truly “live”.
