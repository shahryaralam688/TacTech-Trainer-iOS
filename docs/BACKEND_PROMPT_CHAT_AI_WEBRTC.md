# Backend AI Prompt — TacTech Chat + AI Coach + WebRTC Voice

Copy everything below the line into your Backend AI / implementer. Do not invent parallel APIs that break the iOS client already shipping in `TacTech-Trainer-iOS`.

---

## ROLE

You are a senior backend engineer building production APIs for **TacTech**, an iOS fitness coaching app (trainer + trainee).

Stack preferences (match existing TacTech backend if present):
- FastAPI (or equivalent) + PostgreSQL + Redis
- JWT auth (access + refresh) — every coach/chat route requires `Authorization: Bearer <access>`
- Multi-tenant: scope **all** data by `userId` / org from JWT — never trust body IDs for ownership
- Absolute HTTPS URLs for media
- CamelCase JSON (iOS uses `JSONDecoder.tactech` / `JSONEncoder.tactech`)
- ISO-8601 dates

**Do not remove or rename** endpoints iOS already calls. Prefer additive endpoints. Return **full objects** after create/update so the client can upsert without extra GETs.

---

## PRODUCT CONTEXT (what already exists on iOS)

### A) AI Coach (trainer + trainee) — partially live
iOS `CoachAPI` / `CoachStore` / `AICoachView` already expect:

| Method | Path | Purpose |
|--------|------|---------|
| GET | `/coach/status` | Provider readiness |
| POST | `/coach/memory/sync` | RAG memory sync |
| GET | `/coach/conversations` | List threads |
| POST | `/coach/conversations` | Create thread |
| DELETE | `/coach/conversations/{id}` | Delete thread + messages (iOS drawer) |
| GET | `/coach/conversations/{id}/messages` | History |
| POST | `/coach/chat` | Text chat (`stream: true` → SSE) |
| POST | `/coach/chat/image` | Multipart image + optional caption |
| POST | `/coach/voice/turn` | Multipart push-to-talk turn |
| GET | `/coach/rtc/ice-servers` | ICE servers |
| POST | `/coach/rtc/sessions` | Create RTC session (+ optional `?conversationId=`) |

Audience:
- **Trainer AI**: plans, roster, cues, assign advice
- **Trainee AI**: workouts, form, nutrition
Both use the same `/coach/*` routes; role comes from JWT.

### B) Trainer ↔ Trainee human chat — UI only (local mock)
`TrainerTraineeChatView` is **local**. You must design + implement real messaging APIs + realtime (Socket.IO or WebSocket) so trainer and trainee can chat 1:1.

### C) Support / Help Center live chat — separate product
Already specified under `/support/*` in remaining API docs. Keep it **separate** from trainer↔trainee chat and from AI coach.

### D) Voice call UX on iOS today
`CoachVoiceCallView`:
1. `POST /coach/rtc/sessions`
2. Connect WebSocket to `signalingPath` with `?token=<accessToken>`
3. Expect WS `{"type":"joined"}`
4. Hold-to-talk still uses **`POST /coach/voice/turn`** (not continuous WebRTC media yet)
5. Optional WS `voice_hint` / `hangup`

**Your job:** implement the full backend so this works end-to-end, then upgrade WebRTC to real duplex voice (see Phase 2) without breaking Phase 1.

---

## GOALS (ship in order)

### Phase 1 — Must ship first (iOS can wire immediately)
1. Complete **AI Coach** HTTP + SSE + voice-turn + RTC session bootstrap + signaling WS
2. Complete **Trainer ↔ Trainee messaging** REST + realtime delivery
3. Push notifications hooks (message + AI optional)
4. Robust error model + rate limits + UX-friendly `detail` / `code`

### Phase 2 — Real WebRTC voice AI
5. Full duplex WebRTC audio to AI agent (OpenAI Realtime / Gemini Live / custom SFU)
6. Same conversation ID as text chat (shared history)
7. Graceful fallback to `/coach/voice/turn` if RTC fails

---

## NON-GOALS
- Do not redesign iOS UI
- Do not replace JWT with a different auth for chat
- Do not merge support chat into coach or trainee chat
- Do not require GraphQL

---

# PART 1 — SHARED CONVENTIONS

## Auth
- All routes: Bearer JWT
- On 401: client refreshes via `POST /auth/refresh` then retries once
- Role claims: `trainer` | `trainee` (exact claim name as existing backend)

## Error response (ALWAYS use this shape)
```json
{
  "detail": "Human-readable message suitable for UI toast",
  "code": "RATE_LIMITED"
}
```
Allowed `code` values (extend only if needed):
- `UNAUTHORIZED`
- `FORBIDDEN`
- `NOT_FOUND`
- `VALIDATION_ERROR`
- `RATE_LIMITED`
- `PROVIDER_UNAVAILABLE`
- `QUOTA_EXCEEDED`
- `PAYLOAD_TOO_LARGE`
- `UNSUPPORTED_MEDIA`
- `CONVERSATION_CLOSED`
- `RTC_FAILED`
- `INTERNAL`

HTTP mapping:
- 400 validation / bad multipart
- 401 unauthorized
- 403 wrong role / not in roster relationship
- 404 missing resource
- 413 payload too large
- 415 unsupported media
- 429 rate limited — **must** send `Retry-After` seconds header
- 502/503 provider down → `PROVIDER_UNAVAILABLE`
- 500 unexpected

## Pagination (lists that can grow)
Prefer:
```json
{ "items": [ ... ], "nextCursor": "opaque-or-null" }
```
iOS currently also accepts bare arrays OR `{ items | data | results }`. Prefer `{ "items": [...] }` going forward; still support bare arrays for coach routes already coded.

## Idempotency
- Accept optional `Idempotency-Key` header on message create / chat send
- Same key + same user → return same response (no duplicate messages)

## Observability
- Request id header echo: `X-Request-Id`
- Log conversationId, userId, modality, latency, provider errors (no raw PII audio in logs)

---

# PART 2 — AI COACH (TRAINER + TRAINEE)

## Personas / system prompts (server-side)

### Trainer coach system
You are TacTech AI for a **personal trainer**. Help with:
- Writing / refining workout plans
- Trainee adherence & form cues
- Assignment strategy
- Professional, concise, actionable tone
Never invent medical diagnoses. Prefer questions when data is missing.

### Trainee coach system
You are TacTech AI for an **athlete / trainee**. Help with:
- Today’s workout explanation
- Form tips
- Nutrition ideas aligned to their plan/logs when available
- Motivation without unsafe advice
Never invent medical diagnoses.

Inject **memory context** from `/coach/memory/sync` chunks (plans, logs, meals, profile) via RAG. Cite sources in `citations[]` when used.

## Data model (minimal)

```
CoachConversation
  id, userId, role ("trainer"|"trainee"), title, createdAt, updatedAt

CoachMessage
  id, conversationId, role ("user"|"assistant"|"system"),
  content, modality ("text"|"voice"|"image"),
  audioUrl?, imageUrl?, citations?, createdAt

CoachMemoryChunk
  id, userId, sourceType, sourceId?, content, embedding, updatedAt
```

## Endpoints — exact contracts iOS expects

### `GET /coach/status`
```json
{
  "provider": "openai",
  "chatConfigured": true,
  "usingMockFallback": false,
  "ttsProvider": "openai",
  "embedding": "text-embedding-3-small",
  "chatModel": "gpt-4.1-mini",
  "visionModel": "gpt-4.1-mini",
  "supportsImages": true
}
```
If keys missing: `chatConfigured: false`, still 200 (UI shows soft status).

### `POST /coach/memory/sync`
Rebuild / upsert embeddings for the current user.
```json
{ "chunkCount": 42, "userId": "u_123" }
```
Must be fast enough to call on chat open (or queue + return current count). Never hard-fail chat if sync fails — return 200 with last known count or 0.

### `GET /coach/conversations`
Array of:
```json
{
  "id": "c1",
  "title": "Form check",
  "role": "trainer",
  "createdAt": "2026-09-10T10:00:00Z",
  "updatedAt": "2026-09-10T11:00:00Z"
}
```
Sorted by `updatedAt` desc. Only current user’s threads.

### `POST /coach/conversations`
Empty body `{}` → create titled “New chat” (or localized equivalent).
Return full `CoachConversation`.

### `DELETE /coach/conversations/{id}`
**iOS already calls this** (`CoachAPI.deleteConversation` / drawer swipe + trash).

Hard-delete (or soft-delete + hide) the conversation **and all of its messages** for the authenticated user only.

**Auth:** Bearer JWT required.  
**Ownership:** `{id}` must belong to `userId` from JWT — otherwise **403** `{ "detail": "You can’t delete this chat.", "code": "FORBIDDEN" }`.  
**Missing / already deleted:** **404** `{ "detail": "Chat not found.", "code": "NOT_FOUND" }`  
(iOS treats 404 as success-ish / already gone — still prefer correct 404.)

**Response:**
- Preferred: **204 No Content** (empty body)
- Also accepted: **200** with `{ "id": "c1", "deleted": true }`

**Side effects (required):**
1. Delete or tombstone all `CoachMessage` rows for this conversation  
2. Remove / expire any stored media (image/audio) tied only to this conversation  
3. If an open RTC session is bound to this `conversationId`, hang up (`hangup`) and close it  
4. Do **not** delete other users’ data; do **not** affect trainer↔trainee `/chat/*` or `/support/*`

**Idempotency:** Second DELETE on same id → 404 (or 204 if you prefer soft idempotent delete — document which; iOS is fine with either).

### `GET /coach/conversations/{id}/messages`
Array of messages oldest→newest (or document reverse — iOS displays in array order; prefer chronological ascending).

Message:
```json
{
  "id": "m1",
  "conversationId": "c1",
  "role": "user",
  "content": "Check squat depth",
  "modality": "text",
  "audioUrl": null,
  "imageUrl": null,
  "citations": null,
  "createdAt": "2026-09-10T10:01:00Z"
}
```

### `POST /coach/chat` — text
Body:
```json
{
  "message": "Draft a 4-day upper/lower plan",
  "conversationId": "c1",
  "stream": false
}
```
Rules:
- If `conversationId` null/missing → create conversation, use it
- Persist user message + assistant message
- Update conversation `title` from first user message (truncate ~40 chars) if still “New chat”
- Non-stream (`stream: false` or omitted):
```json
{
  "conversation": { ... },
  "userMessage": { ... },
  "assistantMessage": { ... }
}
```

### Streaming (`stream: true`, `Accept: text/event-stream`)
Emit SSE lines `data: {json}\n\n` with events:

1. **user** (after persisting user msg)
```json
{
  "event": "user",
  "conversationId": "c1",
  "message": { ...userMessage }
}
```

2. **delta** (many)
```json
{ "event": "delta", "text": "partial token or chunk" }
```

3. **done**
```json
{
  "event": "done",
  "message": { ...assistantMessage },
  "citations": [ { "id": "...", "sourceType": "plan", "sourceId": "p1", "content": "...", "score": 0.82 } ]
}
```

Optional end: `data: [DONE]`

On stream failure mid-way: close connection; client shows retry. Prefer also emitting:
```json
{ "event": "error", "detail": "...", "code": "PROVIDER_UNAVAILABLE" }
```
(iOS may ignore unknown events — still persist nothing partial as final assistant unless you mark failed.)

### `POST /coach/chat/image` — multipart
Fields:
- `image` (file) required — jpeg/png/webp, max ~8MB server-side (iOS sends ≤5MB JPEG)
- `message` optional caption
- `conversation_id` optional

Response:
```json
{
  "conversation": { ... },
  "userMessage": { "modality": "image", "imageUrl": "https://...", "content": "caption or empty" },
  "assistantMessage": { ... },
  "imageAnalysis": "optional short vision summary"
}
```

### `POST /coach/voice/turn` — multipart (Phase 1 voice)
Fields:
- `audio` (file) m4a/aac/wav/webm
- `speak` = `true`|`false` (default true)
- `conversation_id` optional

Pipeline:
1. STT → transcript
2. Same LLM path as text chat (with modality voice)
3. Persist user msg (`modality: voice`, content = transcript) + assistant msg
4. If `speak=true`: TTS → upload → `audioUrl`

Response:
```json
{
  "conversation": { ... },
  "transcript": "How is my form?",
  "userMessage": { ... },
  "assistantMessage": { ... },
  "audioUrl": "https://.../reply.m4a"
}
```
If TTS fails: still 200 with `audioUrl: null` (iOS falls back to on-device TTS).

### Rate limits (AI)
Per user sliding window, e.g.:
- Chat: 30/min
- Image: 10/min
- Voice turn: 20/min
- RTC session create: 10/min

429 + `Retry-After` + `code: RATE_LIMITED` + friendly `detail`.

### UX rules for AI responses
- Prefer short paragraphs + bullets for plans
- Never dump raw JSON to the user
- If memory empty: ask 1 clarifying question instead of hallucinating roster data
- Soft refusal for medical/emergency topics with “see a professional”
- Streaming first token < 1.5s p50 when provider healthy

---

# PART 3 — AI VOICE + WEBRTC WORKFLOW

## Phase 1 (match current iOS) — “Call shell + push-to-talk”

### `GET /coach/rtc/ice-servers`
```json
[
  { "urls": ["stun:stun.l.google.com:19302"] },
  { "urls": ["turn:turn.tactech.example:3478"], "username": "...", "credential": "..." }
]
```
Note: iOS `CoachRtcIceServer` currently only decodes `urls: [String]`.  
**Additive:** you MAY include `username` / `credential` fields; update iOS later. For Phase 1, STUN-only is OK if TURN not ready — document limitation on cellular.

### `POST /coach/rtc/sessions?conversationId=optional`
Creates a session bound to user (+ conversation if provided).

Response (`CoachRtcSession`):
```json
{
  "id": "rtc_abc",
  "conversationId": "c1",
  "status": "open",
  "iceServers": [ { "urls": ["stun:stun.l.google.com:19302"] } ],
  "signalingPath": "wss://api.example.com/coach/rtc/sessions/rtc_abc/signal",
  "createdAt": "2026-09-10T12:00:00Z"
}
```
`signalingPath` must be absolute `wss://...` (or `ws://` only in local dev).

### Signaling WebSocket
Client connects: `signalingPath?token=<accessJWT>`

Server messages (JSON text frames):
| type | when | payload |
|------|------|---------|
| `joined` | auth OK + session open | `{ "type":"joined", "sessionId":"..." }` |
| `voice_hint` | optional coach tip | `{ "type":"voice_hint", "text":"..." }` |
| `hangup` | session ended | `{ "type":"hangup", "reason":"user\|timeout\|error" }` |
| `error` | recoverable/fatal | `{ "type":"error", "detail":"...", "code":"RTC_FAILED" }` |

Client → server:
| type | purpose |
|------|---------|
| `voice_hint` | iOS sends after PTT finish (can no-op server-side) |
| `hangup` | end session |
| `ping` | keepalive → reply `pong` |

Session timeout: idle 5 min → send `hangup` and close.

**Phase 1 media:** audio still via `/coach/voice/turn`. Signaling proves presence + future upgrade path.

## Phase 2 — Real WebRTC duplex voice AI

Extend signaling (backward compatible):

Client → server:
```json
{ "type": "offer", "sdp": "..." }
{ "type": "ice", "candidate": { ... } }
{ "type": "answer", "sdp": "..." }
```

Server → client: same `offer` / `answer` / `ice` as needed for the chosen architecture.

### Recommended architecture (pick one; document choice)

**Option A — Provider Realtime (preferred MVP quality)**  
- Server creates provider realtime session (OpenAI Realtime / similar)  
- Server acts as signaling bridge OR returns ephemeral client secret  
- Audio: WebRTC or provider WebSocket audio  
- Transcripts + assistant text mirrored into same `CoachConversation` as `modality: voice` messages in near-realtime  

**Option B — SFU / Media server**  
- Client ↔ mediasoup/livekit ↔ AI worker  
- Worker STT streaming → LLM → TTS streaming back  

### Phase 2 UX requirements
- States: connecting → listening → thinking → speaking → reconnecting → ended  
- Push `voice_hint` for “Listening…”, “Coach speaking…”  
- Barge-in: user speech cancels TTS when possible  
- Network drop: auto-reconnect ≤ 2 attempts, then `hangup` with `code: RTC_FAILED` and instruct client to fall back to PTT `/coach/voice/turn`  
- Persist transcript turns into conversation history so text chat and call share context  
- Max call length e.g. 15 minutes; warn at 14 via `voice_hint`

### Security
- Short-lived TURN credentials (time-limited)  
- Signaling JWT validated on connect; reject + close if invalid  
- One active RTC session per user (creating new closes previous with `hangup`)  
- Do not log raw audio; retain encrypted object storage only if product requires call recordings (default OFF)

---

# PART 4 — TRAINER ↔ TRAINEE HUMAN CHAT

## Relationship rules
- Trainer may only chat with trainees on their roster
- Trainee may only chat with their assigned trainer(s)
- 403 `FORBIDDEN` otherwise

## Data model

```
ChatThread
  id, trainerUserId, traineeUserId, lastMessageAt, lastMessagePreview,
  trainerUnreadCount, traineeUnreadCount, createdAt, updatedAt

ChatMessage
  id, threadId, senderUserId, senderRole ("trainer"|"trainee"),
  text?, attachmentUrl?, attachmentType? ("image"|"file"|"video"|"voice"),
  durationSeconds? (voice/video),
  clientId? (idempotency), createdAt, readAt?

Call / system messages (optional):
  kind?: "text"|"attachment"|"call_event"
  callOutcome?: string  // e.g. "Call · 02:14"
```

### Attachments (extended)
| Type | Max | Notes |
|------|-----|--------|
| image | 8MB | jpeg/png/heic |
| video | 50MB | mp4/mov — form clips |
| voice | 5MB / 60s | m4a AAC voice notes |
| file | 15MB | generic docs (optional) |

### Live video call (trainer↔trainee)
Separate from AI `/coach/rtc/*`.

```
POST /chat/rtc/sessions
  { "threadId": "t1" }
→ { "sessionId", "signalingUrl", "iceServers": [...] }

WebSocket signaling (same TURN/ICE pattern as coach RTC Phase 2):
  offer / answer / ice-candidate / hangup / joined
```

iOS ships a video-call UI shell now; wire WebRTC media when this lands.

## REST API (new — iOS will adopt)

### `GET /chat/threads`
Current user’s inbox.
```json
{
  "items": [
    {
      "id": "t1",
      "peerUserId": "u_trainee",
      "peerName": "Alex",
      "peerAvatarUrl": "https://...",
      "lastMessagePreview": "Ready when you are",
      "lastMessageAt": "2026-09-10T09:00:00Z",
      "unreadCount": 2,
      "peerRole": "trainee"
    }
  ]
}
```

### `POST /chat/threads`
Find-or-create 1:1 thread.
```json
{ "peerUserId": "u_trainee" }
```
Response 200/201: full thread object (include `id`).

### `GET /chat/threads/{id}/messages?cursor=&limit=50`
```json
{
  "items": [
    {
      "id": "m1",
      "threadId": "t1",
      "senderUserId": "u1",
      "senderRole": "trainee",
      "text": "Hey coach",
      "attachmentUrl": null,
      "attachmentType": null,
      "createdAt": "2026-09-10T09:00:00Z",
      "readAt": null
    }
  ],
  "nextCursor": null
}
```
Return newest page with clear cursor semantics (document: cursor = older-than id).

### `POST /chat/threads/{id}/messages`
JSON:
```json
{ "text": "See you at 5", "clientId": "uuid-from-ios" }
```
OR multipart:
- `text` optional
- `file` optional (image / video / voice)
- `attachmentType` optional (`image`|`video`|`voice`|`file`) — server may also sniff MIME
- `durationSeconds` optional (voice/video)
- `clientId` optional

Response 201: full message.

Rules:
- Trim empty text without file → 400
- Max text 4000 chars
- Image max 8MB; video max 50MB; voice max 5MB / 60s
- Update thread preview + unread for peer
- Emit realtime event to peer
- Trigger push notification if peer not connected

### `POST /chat/threads/{id}/read`
```json
{ "upToMessageId": "m9" }
```
Marks messages as read; resets unread; emits `thread.read` to peer.

## Realtime (Socket.IO preferred to match product stack notes)

Namespace: `/chat`  
Auth: JWT in `auth.token` or `Authorization` on handshake.

Events server → client:
- `chat.message` — new message object
- `chat.message.updated` — rare edits (optional)
- `chat.thread.updated` — preview/unread changed
- `chat.read` — `{ threadId, upToMessageId, readerUserId }`
- `chat.typing` — `{ threadId, userId, isTyping }`

Events client → server:
- `chat.join` `{ threadId }`
- `chat.leave` `{ threadId }`
- `chat.typing` `{ threadId, isTyping }`

Delivery guarantees:
- Persist first, then emit
- Client reconciles by `id` / `clientId`
- On reconnect: client refetches threads + messages after last id

## Push
- Title: peer name  
- Body: message preview  
- Data: `{ "type":"chat", "threadId":"..." }`  
- Respect user notification prefs when those endpoints exist  

## UX requirements
- Optimistic send with `clientId`; replace on ack
- Failed send → retryable error with `detail`
- Typing indicators debounce 2s
- Unread badges accurate across devices
- Block empty threads spam: creating thread without message is OK, but inbox may hide until first message (choose one; document it — prefer show after first message)

---

# PART 5 — SUPPORT CHAT (keep separate)

Implement/confirm `/support/*` as already specified in remaining API docs. Do not reuse `/chat/*` tables without a `channel` discriminator if shared infra — product-wise keep APIs separate.

---

# PART 6 — WORKFLOWS (end-to-end)

## Workflow 1 — Trainer opens AI from + menu
1. iOS presents AI fullScreenCover  
2. `GET /coach/status` (soft)  
3. `GET /coach/conversations` + messages for latest  
4. Background `POST /coach/memory/sync`  
5. User sends text → `POST /coach/chat` stream  
6. UI shows deltas → done message + citations  

## Workflow 2 — Trainee AI image form check
1. Multipart `/coach/chat/image`  
2. Vision model + memory  
3. Return assistant tips + optional `imageAnalysis`  

## Workflow 3 — AI voice call (Phase 1)
1. `POST /coach/rtc/sessions?conversationId=`  
2. WS connect → `joined`  
3. Hold-to-talk → `/coach/voice/turn`  
4. Play `audioUrl` or device TTS  
5. `hangup`  

## Workflow 4 — AI voice call (Phase 2)
1. Same session create  
2. SDP/ICE exchange  
3. Continuous STT/LLM/TTS  
4. Mirror transcripts into conversation  
5. On RTC failure → client falls back to Phase 1 PTT  

## Workflow 5 — Trainer messages trainee
1. `POST /chat/threads` with trainee user id  
2. `POST .../messages`  
3. Trainee receives Socket `chat.message` + push  
4. Trainee opens thread → `POST .../read`  

## Workflow 6 — Trainee replies
Mirror of 5 with role reversed; trainer unread increments.

---

# PART 7 — ACCEPTANCE CHECKLIST

### AI Coach
- [ ] Status returns configured flags without crashing when provider missing  
- [ ] Create conversation + list + messages round-trip  
- [ ] `DELETE /coach/conversations/{id}` removes thread + messages; iOS drawer delete stays gone after relaunch  
- [ ] Non-stream chat returns full conversation + both messages  
- [ ] SSE stream emits `user` → `delta*` → `done`  
- [ ] Image multipart works; HEIC rejection returns clear 415/`UNSUPPORTED_MEDIA`  
- [ ] Voice turn returns transcript + messages; TTS optional  
- [ ] 429 includes `Retry-After`  
- [ ] Trainer vs trainee system prompts differ by JWT role  
- [ ] Memory sync does not block chat usability  

### RTC
- [ ] Session create returns absolute `signalingPath` + iceServers  
- [ ] WS auth via token works; bad token closes  
- [ ] `joined` then `hangup` lifecycle works  
- [ ] Idle timeout hangup  
- [ ] Phase 2: offer/answer/ice documented and tested on iOS simulator + device  

### Trainer↔Trainee chat
- [ ] Roster enforcement 403  
- [ ] Find-or-create thread idempotent  
- [ ] Messages persist; second device sees history  
- [ ] Realtime delivery < 1s on good network  
- [ ] Read receipts clear unread  
- [ ] Attachment upload returns absolute URL  

### Quality / UX
- [ ] Every error has UI-safe `detail`  
- [ ] No stack traces in client payloads  
- [ ] p50 text first-token < 1.5s (provider healthy)  
- [ ] Load test: 100 concurrent SSE chats without dropped events  

---

# PART 8 — IMPLEMENTATION ORDER FOR YOU (BACKEND AI)

1. Error envelope + rate limit middleware  
2. Coach conversations + messages CRUD  
3. `/coach/chat` non-stream then SSE  
4. Memory sync + RAG injection  
5. Image + voice turn  
6. RTC sessions + signaling WS (Phase 1)  
7. `/chat/*` REST + Socket.IO  
8. Push hooks  
9. WebRTC Phase 2 duplex voice  
10. Hardening: quotas, TURN creds, abuse controls  

---

# PART 9 — DELIVERABLES

Produce:
1. OpenAPI (YAML) for all new/updated routes  
2. DB migration SQL  
3. Sequence diagrams (text is fine) for: SSE chat, voice turn, RTC Phase 1, RTC Phase 2, trainer-trainee message  
4. Env var list (`OPENAI_API_KEY`, `TURN_*`, `REDIS_URL`, …) — **no secrets in repo**  
5. Short “iOS integration notes” listing any field additions beyond current Swift models  

---

## CRITICAL CONSTRAINTS (read again)

- Match existing iOS `CoachAPI` paths and response field names (`conversationId`, `audioUrl`, `chatConfigured`, SSE `event` values `user|delta|done`).  
- CamelCase JSON.  
- Full objects on write.  
- JWT multi-tenant scoping.  
- Separate: **AI coach** vs **trainer↔trainee chat** vs **support chat**.  
- Phase 1 voice call must work with signaling + `/coach/voice/turn` before Phase 2 media.  
- Prefer excellent error `detail` strings — they show directly in iOS UI.  

Build production-ready code only. No mock-only endpoints unless `usingMockFallback: true` is explicitly returned from `/coach/status` for local/dev.
