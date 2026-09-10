# Backend AI — Trainer↔Trainee Human Chat (copy-paste prompt)

You are a senior FastAPI backend engineer on **TacTech**.

## Context (read carefully)

iOS **already shipped** the trainer↔trainee chat UI (AI-chat chrome) with:

- Text messages  
- Photo + video attachments  
- Voice notes (≤60s m4a)  
- Live **video call UI shell** (local camera; waiting on your RTC)  
- Inbox + thread for **trainer** and **trainee**  
- Optimistic local store today — **not** wired to production APIs yet  

AI Coach (`/coach/*`) is a **separate** product surface. Do **not** reuse coach conversation tables for human chat.

This prompt is **only** for human 1:1 chat + media + live video call between trainer and trainee.

If any of these endpoints already exist, **audit + extend** them to match this contract exactly (camelCase JSON, absolute media URLs, JWT auth). Do not invent a parallel API.

---

## Goals

1. Persist 1:1 threads between roster-linked trainer ↔ trainee  
2. REST send/list/read for text + image + video + voice  
3. Realtime delivery (Socket.IO `/chat` preferred)  
4. Push when peer offline  
5. Live video call signaling + ICE/TURN (`/chat/rtc/*`) — **separate from** `/coach/rtc/*`  
6. Return UI-safe errors iOS can toast  

---

## Auth & errors (global)

Every route: `Authorization: Bearer <accessJWT>` (except WS may also accept `?token=`).

Error body **always**:
```json
{ "detail": "Human-readable message for toast", "code": "FORBIDDEN" }
```

| HTTP | code | when |
|------|------|------|
| 401 | `UNAUTHORIZED` | missing/invalid JWT |
| 403 | `FORBIDDEN` | not roster-linked / not thread participant |
| 404 | `NOT_FOUND` | thread/message missing |
| 400 | `VALIDATION` | empty message, bad multipart |
| 413 | `PAYLOAD_TOO_LARGE` | over size limits |
| 415 | `UNSUPPORTED_MEDIA` | bad MIME |
| 429 | `RATE_LIMITED` | include `Retry-After` seconds |
| 500 | `INTERNAL` | unexpected |

JSON: **camelCase**. Dates: ISO-8601 UTC. Media fields: **absolute** HTTPS URLs.

---

## Relationship rules (hard)

- Trainer may only chat with trainees **on their roster** (`trainee.trainerId` / assignment table).  
- Trainee may only chat with **their assigned trainer(s)**.  
- Otherwise → **403 `FORBIDDEN`**.  
- Every message/RTC action: caller must be a participant of that `threadId`.

---

## Data model

```
ChatThread
  id
  trainerUserId      // User.id of trainer
  traineeUserId      // User.id of trainee
  lastMessageAt
  lastMessagePreview // short string for inbox
  trainerUnreadCount
  traineeUnreadCount
  createdAt
  updatedAt
  UNIQUE(trainerUserId, traineeUserId)

ChatMessage
  id
  threadId
  senderUserId
  senderRole           // "trainer" | "trainee"
  kind                 // "text" | "attachment" | "call_event"
  text                 // nullable; caption for media; empty for pure voice/call
  attachmentUrl        // nullable absolute URL
  attachmentType       // null | "image" | "video" | "voice" | "file"
  durationSeconds      // nullable; voice/video
  callOutcome          // nullable; e.g. "Call · 02:14" | "Cancelled call"
  clientId             // nullable; client idempotency UUID
  createdAt
  readAt               // nullable

ChatRtcSession (optional table)
  id
  threadId
  createdByUserId
  status               // "active" | "ended"
  createdAt
  endedAt
```

Storage: S3/R2/GCS (or existing TacTech object store). Serve via CDN or signed absolute URLs.

---

## Attachment limits

| Type | Max size | MIME (accept) | Notes |
|------|----------|---------------|--------|
| image | 8 MB | jpeg, png, heic, webp | |
| video | 50 MB | mp4, mov, quicktime | form clips |
| voice | 5 MB / 60 s | audio/mp4, audio/m4a, audio/aac | AAC voice notes |
| file | 15 MB | optional pdf/doc | nice-to-have |

Reject oversize → 413. Bad type → 415 with clear `detail`.

---

# REST API

Base path: `/chat`

## `GET /chat/threads`

Inbox for current user (trainer sees trainees; trainee sees trainer).

```json
{
  "items": [
    {
      "id": "t1",
      "peerUserId": "u_trainee",
      "peerName": "Alex",
      "peerAvatarUrl": "https://cdn.example.com/a.jpg",
      "lastMessagePreview": "🎤 Voice note · 12s",
      "lastMessageAt": "2026-09-10T16:00:00Z",
      "unreadCount": 2,
      "peerRole": "trainee"
    }
  ]
}
```

Rules:
- Sort by `lastMessageAt` desc (nulls last).  
- Prefer hide threads with **zero messages** (document if you show them).  
- `unreadCount` is for **current** user side only.

---

## `POST /chat/threads`

Find-or-create 1:1 thread.

Request:
```json
{ "peerUserId": "u_trainee" }
```

Response **200** (exists) or **201** (created): full thread inbox-shaped object including `id`.

Rules:
- Validate roster relationship → else 403.  
- Idempotent on `(trainerUserId, traineeUserId)`.

**Important for iOS:** Trainer roster uses `TraineeProfile.id` in the UI today. Accept **either**:
- `peerUserId` = User.id, **or**
- also accept `peerTraineeProfileId` / `peerTrainerProfileId` as optional alternate fields  

…and resolve to the correct User.id server-side. Document which field is canonical. Prefer:

```json
{ "peerUserId": "..." }
```

If iOS sends profile ids by mistake, return 400 with `detail` explaining it must be User.id — **or** accept profile id and resolve (preferred for fewer client bugs).

---

## `GET /chat/threads/{id}/messages?cursor=&limit=50`

```json
{
  "items": [
    {
      "id": "m1",
      "threadId": "t1",
      "senderUserId": "u1",
      "senderRole": "trainee",
      "kind": "text",
      "text": "Hey coach",
      "attachmentUrl": null,
      "attachmentType": null,
      "durationSeconds": null,
      "callOutcome": null,
      "clientId": null,
      "createdAt": "2026-09-10T16:00:00Z",
      "readAt": null
    }
  ],
  "nextCursor": null
}
```

Cursor semantics: **older-than** message id (paginate upward through history). Default page = newest 50. Non-participant → 403.

---

## `POST /chat/threads/{id}/messages`

### A) JSON text
```json
{
  "text": "See you at 5",
  "clientId": "uuid-from-ios"
}
```

### B) Multipart (media)
Fields:
- `text` — optional caption  
- `file` — binary  
- `attachmentType` — optional `image`|`video`|`voice`|`file` (sniff MIME if missing)  
- `durationSeconds` — optional number (voice/video)  
- `clientId` — optional  
- `kind` — optional; default `attachment` when file present  

### C) Call event (JSON)
```json
{
  "kind": "call_event",
  "callOutcome": "Call · 02:14",
  "clientId": "uuid"
}
```

Response **201**: full message object (same shape as list items).

Rules:
1. Empty text **and** no file **and** not `call_event` → 400.  
2. Max text 4000 chars.  
3. If `clientId` already exists for this thread+sender → return the **existing** message (idempotent).  
4. Persist → update thread preview/unread → emit Socket → push if peer offline.  
5. Preview helpers:
   - text → truncated text  
   - image → `📷 Photo` (+ caption if any)  
   - video → `🎬 Video`  
   - voice → `🎤 Voice note` (+ duration)  
   - call_event → `callOutcome` or `📞 Call`

---

## `POST /chat/threads/{id}/read`

```json
{ "upToMessageId": "m9" }
```

- Mark peer→me messages `readAt=now` up to that id.  
- Reset current user’s unread on thread.  
- Emit `chat.read` to peer.  
- Response 200: `{ "threadId", "upToMessageId", "unreadCount": 0 }`

---

## `DELETE /chat/threads/{id}/messages/{messageId}` (optional v1.1)

Soft-delete own message only. Emit `chat.message.updated`. Skip if time-boxed; not required for iOS day-1.

---

# Realtime — Socket.IO namespace `/chat`

Auth: JWT in `auth.token` **or** `Authorization` on handshake. Reject + disconnect if invalid.

### Client → server
| Event | Payload |
|-------|---------|
| `chat.join` | `{ "threadId" }` |
| `chat.leave` | `{ "threadId" }` |
| `chat.typing` | `{ "threadId", "isTyping": true }` |

### Server → client
| Event | Payload |
|-------|---------|
| `chat.message` | full message object |
| `chat.thread.updated` | inbox row fields for that thread |
| `chat.read` | `{ "threadId", "upToMessageId", "readerUserId" }` |
| `chat.typing` | `{ "threadId", "userId", "isTyping" }` |
| `chat.call.incoming` | `{ "threadId", "sessionId", "fromUserId", "fromName" }` |
| `chat.call.ended` | `{ "threadId", "sessionId", "reason" }` |

Guarantees:
- **Persist first, then emit**  
- Client reconciles by `id` / `clientId`  
- On reconnect: client refetches threads + messages after last known id  

If Socket.IO is blocked for some reason, document a native WebSocket equivalent with the **same event names/payloads** — do not make iOS guess.

---

# Live video call — `/chat/rtc/*`

**Do not** overload `/coach/rtc`. Human calls are peer-to-peer (trainer↔trainee), not AI.

## `GET /chat/rtc/ice-servers`
```json
{
  "iceServers": [
    { "urls": ["stun:stun.l.google.com:19302"] },
    {
      "urls": ["turn:turn.example.com:3478"],
      "username": "…",
      "credential": "…"
    }
  ]
}
```
TURN credentials must be **short-lived**.

## `POST /chat/rtc/sessions`
```json
{ "threadId": "t1" }
```
Response 201:
```json
{
  "id": "rtc_h1",
  "threadId": "t1",
  "signalingPath": "wss://api.example.com/chat/rtc/sessions/rtc_h1/signal",
  "iceServers": [ /* same shape as above */ ],
  "createdAt": "2026-09-10T16:05:00Z"
}
```

Rules:
- Caller must be thread participant.  
- Notify peer via Socket `chat.call.incoming`.  
- One active session per thread (new call ends previous with `hangup`).  
- Max call length e.g. 60 minutes; idle timeout e.g. 90s with no media/signaling → end.

## Signaling WebSocket
`GET {signalingPath}?token=<accessJWT>`

Messages (JSON):

| type | direction | payload |
|------|-----------|---------|
| `joined` | server→both | `{ "type":"joined", "sessionId", "userId" }` |
| `offer` | peer↔peer via server | `{ "type":"offer", "sdp":"..." }` |
| `answer` | peer↔peer | `{ "type":"answer", "sdp":"..." }` |
| `ice-candidate` | peer↔peer | `{ "type":"ice-candidate", "candidate":{…} }` |
| `hangup` | either | `{ "type":"hangup", "reason":"ended"|"declined"|"failed"|"timeout" }` |
| `error` | server | `{ "type":"error", "detail":"…", "code":"…" }` |

Relay SDP/ICE between the two participants only. Validate JWT on connect; close if not a participant.

After hangup: emit `chat.call.ended`; optionally auto-insert a `call_event` message into the thread (or let client POST one — prefer **server** insert so both sides see it).

---

# Push notifications

When peer is **not** connected to `/chat`:

- Title: sender display name  
- Body: `lastMessagePreview`  
- Data: `{ "type":"chat", "threadId":"t1", "messageId":"m1" }`  

For incoming call:
- Data: `{ "type":"chat_call", "threadId":"t1", "sessionId":"rtc_h1" }`  
- High priority / VoIP if you already have CallKit hooks; otherwise standard push is OK for v1.

Respect notification preference flags when those exist.

---

# Rate limits (suggested)

| Action | Limit |
|--------|-------|
| POST message | 60 / min / user |
| Multipart media | 20 / min / user |
| Create RTC session | 10 / min / user |
| Typing events | debounce server-side; drop floods |

---

# Workflows (acceptance)

### W1 — Text DM
1. Trainer `POST /chat/threads` with trainee  
2. `POST .../messages` JSON text  
3. Trainee gets Socket `chat.message` (+ push if offline)  
4. Trainee opens → `POST .../read` → trainer gets `chat.read`

### W2 — Photo / video / voice
1. Multipart upload  
2. Absolute `attachmentUrl` in response  
3. Peer can download/play  
4. Inbox preview uses emoji prefix rules above

### W3 — Video call
1. A: `POST /chat/rtc/sessions`  
2. B: receives `chat.call.incoming` (+ push)  
3. Both connect signaling WS → `joined`  
4. Exchange offer/answer/ICE  
5. Media flows (WebRTC client-side)  
6. Hangup → `call_event` in thread history

### W4 — Security
1. Non-roster peer → 403 on thread create  
2. Non-participant cannot list messages / join WS / create RTC  
3. Bad JWT → 401 / WS close

---

# Implementation order

1. Models + migrations (`ChatThread`, `ChatMessage`)  
2. Roster guard helper  
3. `GET/POST /chat/threads`  
4. `GET/POST messages` (JSON text first)  
5. Multipart image → then video → voice  
6. `POST .../read`  
7. Socket.IO `/chat` events  
8. Push hooks  
9. `/chat/rtc/ice-servers` + sessions + signaling relay  
10. Call event persistence + incoming-call push  

---

# Deliverables

1. OpenAPI or route list matching this doc  
2. Example curl for: create thread, text, image multipart, voice multipart, read, RTC create  
3. Confirm Socket.IO path + auth method  
4. Staging base URL + test trainer/trainee accounts that are roster-linked  
5. Short note: which id iOS must send as `peerUserId` (User.id vs profile id)  

---

# Out of scope

- AI Coach `/coach/*` (already separate)  
- Support `/support/*` (keep separate)  
- Group chats  
- Message edit/reactions (later)  
- Call recording (default OFF)

---

# Done when

- [ ] Trainer and trainee can exchange text in <1s realtime on staging  
- [ ] Image, video, voice round-trip with absolute URLs  
- [ ] Unread + read receipts correct  
- [ ] Non-roster blocked with 403  
- [ ] Video call: session + signaling + ICE works between two devices  
- [ ] Hangup writes a call event both sides can see in history  
- [ ] All errors use `{ detail, code }`  
- [ ] You reply with staging URL + sample JWTs / test accounts so iOS can wire `ChatAPI`

---

**Reply format:** summarize what you implemented, any deviations, and the exact base URL + auth header format for iOS.
