# TacTech iOS — COMPLETE backend integration prompt (one shot)

Copy everything below into an iOS agent / engineer. Pair with `docs/BACKEND_PROMPT_CHAT_AI_WEBRTC.md` (backend contracts). Backend is assumed **already shipping** on FastAPI.

---

You are a senior iOS/SwiftUI engineer on **TacTech** (trainer + trainee fitness app).

Wire the app to the **existing production FastAPI backend**. Do **NOT** redesign UI. Do **NOT** invent mock-only APIs. Prefer additive changes. Match existing patterns: `JSONDecoder.tactech` / `JSONEncoder.tactech`, Bearer JWT, absolute media URLs, camelCase JSON, ISO-8601 dates.

If a screen already has UI (AI Coach, trainer↔trainee chat, support), **keep the look**; replace local/mock data with real networking + realtime.

Repo paths (work here):
- `TacTech/Data/APIClient.swift`, `APIConfig.swift`, `AppStore.swift`
- `TacTech/Data/CoachAPI.swift`, `CoachStore.swift`
- `TacTech/Models/CoachModels.swift`
- `TacTech/Features/Coach/*` (`AICoachView`, `CoachVoiceCallView`, …)
- `TacTech/Features/Trainer/TrainerTraineeChatView.swift` (**local mock today**)
- `TacTech/Features/Authentication/HelpCenterViews.swift` (**support live chat UI — local/mock**)
- `TacTech/Features/Trainer/TrainerRootView.swift`, `TraineeRootView.swift` (AI + trainee chat entry)

Commit + push to `main` when the integration slice is done (user preference).

---

## 0) Auth & errors (global)

- Every protected call: `Authorization: Bearer <accessToken>` from `TokenStore`
- On **401**: refresh via existing `POST /auth/refresh`, retry **once**, then clear tokens / logout if still failing
- Prefer **one shared** refresh + retry helper (today `APIClient` and `CoachAPI` each have their own — consolidate or keep in sync; do not diverge behavior)
- Error body ALWAYS:
```json
{ "detail": "Human message for toast", "code": "RATE_LIMITED" }
```
- Map into existing `AppError`:
  - `401` → `.unauthorized`
  - `404` → `.notFound(detail)`
  - `429` or `code == "RATE_LIMITED"` → `.rateLimited(detail, retryAfter:)` using `Retry-After` header (clamp ~5…120s)
  - else → `.api(detail)` with UI-safe string (never raw stack traces)
- Always send existing ngrok skip header when using `APIConfig` (`ngrok-skip-browser-warning: true`) until production host is final
- Accept list envelopes: bare `[T]` **or** `{ items | data | results }` (see `CoachAPI.sendArray` / `APIClient` patterns)

### Codes to handle in UI (toast / inline banner)
`UNAUTHORIZED` · `FORBIDDEN` · `NOT_FOUND` · `VALIDATION_ERROR` · `RATE_LIMITED` · `PROVIDER_UNAVAILABLE` · `QUOTA_EXCEEDED` · `PAYLOAD_TOO_LARGE` · `UNSUPPORTED_MEDIA` · `CONVERSATION_CLOSED` · `RTC_FAILED` · `INTERNAL`

UX:
- Soft-fail non-critical bootstrap (`/coach/status`, memory sync) — never block empty chat chrome
- Hard-fail send actions with retry CTA where `CoachStore` / chat already supports pending retry
- Rate limit: show countdown using `rateLimitSecondsRemaining` pattern already in `CoachStore`

---

## 1) AI Coach — finish production wiring (trainer + trainee)

### Already present (verify end-to-end; fix gaps only)
| Client | Path |
|--------|------|
| `CoachAPI.status` | `GET /coach/status` |
| `CoachAPI.syncMemory` | `POST /coach/memory/sync` |
| `CoachAPI.listConversations` / `createConversation` | `/coach/conversations` |
| `CoachAPI.listMessages` | `GET /coach/conversations/{id}/messages` |
| `CoachAPI.chat` / `chatStream` | `POST /coach/chat` |
| `CoachAPI.chatImage` | `POST /coach/chat/image` multipart |
| `CoachAPI.voiceTurn` | `POST /coach/voice/turn` multipart |
| `CoachAPI.iceServers` / `createRtcSession` | `/coach/rtc/*` |

### Tasks
1. **Confirm models** in `CoachModels.swift` decode live backend (add optional fields additively: e.g. ICE `username` / `credential` on `CoachRtcIceServer` without breaking STUN-only).
2. **Multi-chat**: replace local-only session list in `AICoachView` with real `listConversations` / `createConversation` / switch thread → `listMessages`. Keep UI (drawer / “New chat”).
3. **SSE**: ensure `user` → `delta*` → `done` mapping stays correct; ignore unknown events; cancel Task on navigate-away.
4. **Image**: keep JPEG encode via `CoachImageEncoder`; surface `UNSUPPORTED_MEDIA` / `PAYLOAD_TOO_LARGE` cleanly.
5. **Voice PTT**: keep max ~30s recording; play `audioUrl` or on-device TTS fallback (already in `CoachStore`).
6. **Audience**: same `/coach/*` for trainer & trainee; JWT role selects persona server-side — no client prompt override.
7. **Empty state**: first send may create conversation server-side when `conversationId` is nil — keep that flow.
8. **No mock replies** when `chatConfigured == true`. If `usingMockFallback == true`, show subtle status chip only (existing UI).

### Out of scope for redesign
Do not restyle `AICoachView` / bubbles / composer. Fix scroll-to-bottom / open glitches only if regressions appear from networking.

---

## 2) AI WebRTC voice call

### Phase 1 (must work now — matches `CoachVoiceCallView`)
1. `POST /coach/rtc/sessions?conversationId=` via `CoachStore.createCallSession`
2. Connect `URLSessionWebSocketTask` to absolute `signalingPath` + `?token=<access>`
3. Handle: `joined`, `voice_hint`, `hangup`, `error`
4. Send: `voice_hint` after PTT, `hangup` on End
5. Media remains **`POST /coach/voice/turn`** (hold-to-talk)
6. Errors: show `detail` inline; on `RTC_FAILED` keep sheet usable for PTT if session object exists, or dismiss with toast

### Phase 2 (additive — only if backend signals readiness)
- Extend signaling for `offer` / `answer` / `ice`
- Use WebRTC (e.g. `WebRTC` SPM or AVSampleBuffer path agreed with backend)
- Mirror transcripts into same conversation
- **Fallback**: if peer connection fails → automatic Phase 1 PTT mode + `voice_hint` “Switched to hold-to-talk”
- Do not remove Phase 1 path

### ICE
Decode optional TURN creds when present:
```swift
struct CoachRtcIceServer: Codable {
  var urls: [String]
  var username: String?
  var credential: String?
}
```

---

## 3) Trainer ↔ Trainee human chat (replace local mock)

### Today
`TrainerTraineeChatView` + `TraineeChatStore` are **local** (fake reply). Entry: liquid FAB “Trainee chat” on trainer root.

### Target backend (from backend prompt)
| Method | Path |
|--------|------|
| GET | `/chat/threads` |
| POST | `/chat/threads` body `{ "peerUserId" }` |
| GET | `/chat/threads/{id}/messages?cursor=&limit=` |
| POST | `/chat/threads/{id}/messages` JSON or multipart |
| POST | `/chat/threads/{id}/read` body `{ "upToMessageId" }` |

Realtime: Socket.IO namespace `/chat` (preferred) **or** native WebSocket if backend documents it — **match what backend ships**. Prefer a small `ChatSocket` client wrapper.

### Implementation plan
1. Add `ChatModels.swift` + `ChatAPI` actor (mirror `CoachAPI` style: auth, refresh, multipart, error map).
2. Replace `TraineeChatStore` with `@Observable` store backed by API + socket upserts (by `id` / `clientId`).
3. Keep inbox + thread UI; bind to `peerName`, `unreadCount`, `lastMessagePreview`.
4. Optimistic send with `clientId` (UUID); reconcile on 201; mark failed + retry.
5. On open thread: fetch messages, `POST .../read`.
6. Typing: debounce emit `chat.typing`; show peer typing if event arrives.
7. **Trainee app**: add entry to chat with assigned trainer (Profile / home shortcut if a control already exists; otherwise additive entry near existing messaging affordances — **do not invent a new tab** unless one exists). If no trainee UI yet, add a minimal NavigationLink from trainee home/profile **using existing chrome**, same thread UI reused.
8. Roster enforcement: surface 403 `FORBIDDEN` as “You can’t message this athlete.”
9. Push: when `UNNotification` data `type=chat`, deep-link to thread id (hook into existing notification path if any; else TODO comment + basic handler).

### Remove
- Local mock delayed “Got it — thanks coach!” reply
- Seed fake messages in production builds (`#if DEBUG` seed optional only)

---

## 4) Support / Help Center live chat

### Today
`LiveChatView` in `HelpCenterViews.swift` is UI with local messages.

### Backend
| Method | Path |
|--------|------|
| GET | `/support/conversations` |
| POST | `/support/conversations` |
| GET | `/support/conversations/{id}/messages?after=` |
| POST | `/support/conversations/{id}/messages` JSON or multipart |

### Tasks
1. Wire Start Live Chat → `POST /support/conversations` (or GET open-or-create per backend).
2. Load history; poll **or** socket if backend provides (REST polling every 5–8s acceptable MVP if no support socket).
3. Send text / photo multipart; map `sender: user|support|system` to bubbles.
4. Same auth/error rules; keep Help Center visual design.

---

## 5) Shared networking hygiene

1. **Base URL**: `APIConfig.baseURL` — keep single source of truth.
2. Timeouts: chat/SSE/voice up to 120–180s (already on `CoachAPI`); normal REST ~30–60s.
3. Background: cancel streams on `onDisappear` / scene background where appropriate.
4. Media: only load absolute HTTPS `imageUrl` / `audioUrl` / `attachmentUrl`; never concatenate relative paths without a documented CDN base.
5. Logging: no tokens, no audio bytes in `print` / OSLog.
6. Thread-safety: keep API types as `actor`; UI stores `@MainActor`.

---

## 6) UX requirements (do not change business rules)

- Optimistic UI for human chat sends; streaming tokens for AI
- Empty inbox / empty AI: clear CTA (“Message a trainee”, “Ask TacTech AI”)
- Offline / transport errors: one banner + Retry — not silent fail
- Rate limit: disable send + countdown (AI already)
- Voice call: status labels already exist — keep (“Starting session…”, “Connected · hold to talk”, “Coach is thinking…”)
- Accessibility: retain button labels; don’t strip VoiceOver strings
- No new purple/glow redesign; use existing TT colors / Sandow icons

---

## 7) Files to add / touch (expected)

**Add**
- `TacTech/Data/ChatAPI.swift`
- `TacTech/Models/ChatModels.swift`
- `TacTech/Data/ChatStore.swift` (or evolve `TraineeChatStore`)
- `TacTech/Data/SupportChatAPI.swift` (or fold into `APIClient` if small)
- Optional: `TacTech/Data/ChatSocketClient.swift`

**Edit**
- `TrainerTraineeChatView.swift` — real store
- `HelpCenterViews.swift` / `LiveChatView` — real support API
- `AICoachView.swift` — real conversation list
- `CoachModels.swift` / `CoachVoiceCallView.swift` — ICE + Phase 2 hooks if ready
- `AppStore.swift` — only if session/logout must tear down sockets
- Trainee root/profile — chat entry if missing

**Do not**
- Rewrite tab bar / liquid FAB IA
- Delete coach SSE implementation to “simplify”
- Hardcode secrets

---

## 8) Acceptance checklist (iOS done when)

### AI
- [ ] Live `/coach/status` drives configured chip
- [ ] Conversations list + new chat + history from server
- [ ] SSE stream renders deltas; cancel works
- [ ] Image + voice turn succeed against prod
- [ ] 401 refresh once; 429 countdown
- [ ] RTC session + WS `joined` / `hangup`; PTT still works

### Trainer↔Trainee chat
- [ ] Inbox from `GET /chat/threads`
- [ ] Send/receive persists; second device / socket sees message
- [ ] Read receipts clear unread
- [ ] No mock auto-reply in Release
- [ ] 403 handled

### Support
- [ ] Start Live Chat creates/loads server conversation
- [ ] Messages round-trip; photo optional

### Quality
- [ ] No UI redesign regressions on Home / FAB / AI cover
- [ ] Build succeeds; commit + push

---

## 9) Implementation order

1. Shared error/401 parity between `APIClient` & `CoachAPI` (if needed)
2. AI multi-chat → real conversations (quick win; API exists)
3. Verify voice turn + RTC Phase 1 against prod; fix decode gaps
4. `ChatAPI` + replace `TrainerTraineeChatView` mock
5. Socket.IO / WS realtime for chat
6. Support live chat REST
7. Trainee-side thread entry
8. Phase 2 WebRTC only if backend ready
9. Push deep link for chat
10. Commit + push

---

## 10) Critical constraints

- **Do NOT redesign UI**
- **Do NOT invent mock-only APIs** for Release
- Prefer **additive** model fields
- Match backend field names from `docs/BACKEND_PROMPT_CHAT_AI_WEBRTC.md` and `docs/BACKEND_API_SPEC_REMAINING.md`
- Keep AI coach, trainer↔trainee chat, and support chat as **three separate** stacks
- Phase 1 voice = signaling + `/coach/voice/turn`; Phase 2 is additive fallback-safe
- Production-ready code only; environment via `APIConfig` / existing token store

When finished: summarize what was wired, any backend mismatches found, and push to `origin/main`.
